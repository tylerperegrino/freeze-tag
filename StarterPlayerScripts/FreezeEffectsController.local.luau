-- FreezeEffectsController: draws the ice cube around frozen characters.
-- Runs on each client so the animation is perfectly smooth (tweens run every frame
-- locally instead of being replicated from the server at a lower rate).
-- The server decides who is frozen and tags them "Frozen"; this only draws it.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.FreezeConfig)

-- Preload the sounds so the first freeze plays instantly instead of waiting to download.
task.spawn(function()
	local preload = {}
	for _, id in { Config.FreezeSoundId, Config.ThawSoundId, Config.HitSoundId, Config.SwingSoundId,
		Config.ThawSteamSoundId, Config.IceChipSoundId, Config.IceShatterSoundId,
		Config.IceHitCrackSoundId, Config.IceHitCrackleSoundId, Config.IcePickClangSoundId,
		Config.IceBreakGlassSoundId, Config.IceBreakHeavySoundId, Config.IceBreakDebrisSoundId } do
		if id ~= "" then
			local s = Instance.new("Sound")
			s.SoundId = id
			table.insert(preload, s)
		end
	end
	pcall(function() game:GetService("ContentProvider"):PreloadAsync(preload) end)
end)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local localPlayer = Players.LocalPlayer
local FROZEN_TAG = "Frozen"
local START_HEIGHT = 0.2

local shells = {} -- [Model] = Folder

local function emitBurst(root, color)
	local att = Instance.new("Attachment")
	att.Parent = root
	local p = Instance.new("ParticleEmitter")
	p.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	p.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	p.LightEmission = 0.6
	p.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	p.Transparency = NumberSequence.new(0.1, 1)
	p.Lifetime = NumberRange.new(0.4, 0.8)
	p.Speed = NumberRange.new(8, 16)
	p.SpreadAngle = Vector2.new(180, 180)
	p.Drag = 4
	p.Enabled = false
	p.Parent = att
	p:Emit(Config.BurstParticles)
	Debris:AddItem(att, 1.5)
end

--------------------------------------------------------------------------
-- Sound + VFX helpers (all client-side, cleaned up automatically)
--------------------------------------------------------------------------
local fxFolder = Instance.new("Folder")
fxFolder.Name = "FreezeFX"
fxFolder.Parent = workspace

local function playSound(parent, id, volume, speed)
	if not parent or not id or id == "" then return end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.6
	s.PlaybackSpeed = speed or 1
	s.RollOffMaxDistance = 90
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, 4)
end

-- One layer of a bigger sound: optional delay, and an optional cut-off (fades out fast) so a
-- long sample can be used for just its punchy start.
local function soundLayer(parent, id, volume, speed, delay, cutAfter)
	if not parent or not id or id == "" then return end
	local function go()
		if not parent.Parent then return end
		local s = Instance.new("Sound")
		s.SoundId = id
		s.Volume = volume
		s.PlaybackSpeed = speed
		s.RollOffMinDistance = 8
		s.RollOffMaxDistance = 110
		s.Parent = parent
		s:Play()
		if cutAfter then
			task.delay(cutAfter, function()
				if s.Parent then TweenService:Create(s, TweenInfo.new(0.12), { Volume = 0 }):Play() end
			end)
			Debris:AddItem(s, cutAfter + 0.2)
		else
			Debris:AddItem(s, 5)
		end
	end
	if delay and delay > 0 then task.delay(delay, go) else go() end
end

local function fxPart(shape)
	local p = Instance.new("Part")
	p.Shape = shape or Enum.PartType.Block
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

-- White flash where the bat connected.
local function impactFlash(position)
	local ball = fxPart(Enum.PartType.Ball)
	ball.Material = Enum.Material.Neon
	ball.Color = Color3.new(1, 1, 1)
	ball.Size = Vector3.one * 0.6
	ball.Transparency = 0.1
	ball.CFrame = CFrame.new(position)
	ball.Parent = fxFolder
	TweenService:Create(ball, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.one * 3.2, Transparency = 1 }):Play()
	Debris:AddItem(ball, 0.3)
end

-- Frost ring that races out across the floor.
local function shockwave(floorCFrame)
	local ring = fxPart(Enum.PartType.Cylinder)
	ring.Material = Enum.Material.Neon
	ring.Color = Config.IceColor
	ring.Transparency = 0.25
	ring.Size = Vector3.new(0.12, 2, 2)
	ring.CFrame = floorCFrame * CFrame.new(0, 0.08, 0) * CFrame.Angles(0, 0, math.pi / 2) -- lie flat
	ring.Parent = fxFolder
	TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.12, Config.ShockwaveSize, Config.ShockwaveSize), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.5)
end

-- Chunks of ice thrown out from a box (frame/size), arcing up then falling to the floor.
local function shards(frame, size, floorY, count, speed)
	for _ = 1, count do
		local s = fxPart()
		s.Material = Enum.Material.Ice
		s.Color = Config.IceColor:Lerp(Color3.new(1, 1, 1), math.random() * 0.4)
		s.Transparency = 0.2
		local k = 0.25 + math.random() * 0.45
		s.Size = Vector3.new(k, k * (0.6 + math.random() * 0.8), k)
		local startLocal = Vector3.new((math.random() - 0.5) * size.X, (math.random() - 0.3) * size.Y * 0.6, (math.random() - 0.5) * size.Z)
		local start = frame:PointToWorldSpace(startLocal)
		s.CFrame = CFrame.new(start) * CFrame.Angles(math.random() * 6.3, math.random() * 6.3, math.random() * 6.3)
		s.Parent = fxFolder

		local out = Vector3.new(startLocal.X, 0, startLocal.Z)
		out = if out.Magnitude > 0.05 then out.Unit else Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
		out = frame:VectorToWorldSpace(out)
		local dist = (1.5 + math.random() * 2.5) * speed
		local apex = start + out * dist * 0.5 + Vector3.new(0, 0.8 + math.random() * 1.2, 0)
		local landing = start + out * dist
		landing = Vector3.new(landing.X, floorY + s.Size.Y / 2, landing.Z)
		local spin = CFrame.Angles(math.random() * 6.3, math.random() * 6.3, math.random() * 6.3)

		local up = TweenService:Create(s, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = CFrame.new(apex) * spin })
		local down = TweenService:Create(s, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ CFrame = CFrame.new(landing) * spin * spin })
		local fade = TweenService:Create(s, TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.In, 0, false, 0.4),
			{ Transparency = 1, Size = s.Size * 0.5 })
		up.Completed:Once(function() if s.Parent then down:Play() end end)
		up:Play()
		fade:Play()
		Debris:AddItem(s, 0.8)
	end
end

-- Puff of cold mist.
local function mist(root)
	local att = Instance.new("Attachment")
	att.Parent = root
	local p = Instance.new("ParticleEmitter")
	p.Texture = "rbxasset://textures/particles/smoke_main.dds"
	p.Color = ColorSequence.new(Color3.new(1, 1, 1), Config.IceColor)
	p.LightEmission = 0.3
	p.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 4) })
	p.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	p.Lifetime = NumberRange.new(0.7, 1.1)
	p.Speed = NumberRange.new(3, 6)
	p.SpreadAngle = Vector2.new(180, 180)
	p.Drag = 3
	p.Rotation = NumberRange.new(0, 360)
	p.RotSpeed = NumberRange.new(-60, 60)
	p.Enabled = false
	p.Parent = att
	p:Emit(14)
	Debris:AddItem(att, 1.4)
end

-- Symmetrical box around the body (not hats/tools), in the root's frame.
local function measure(model, root)
	local frame = root.CFrame
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = -minV
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part ~= root and part.Transparency < 1 then
			local half = part.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local corner = part.CFrame:PointToWorldSpace(Vector3.new(sx * half.X, sy * half.Y, sz * half.Z))
						local p = frame:PointToObjectSpace(corner)
						minV = minV:Min(p)
						maxV = maxV:Max(p)
					end
				end
			end
		end
	end
	if minV.X == math.huge then
		minV, maxV = Vector3.new(-2, -3, -1), Vector3.new(2, 3, 1)
	end
	local pad = Config.IceShellPadding
	local halfX = math.max(math.abs(minV.X), math.abs(maxV.X)) + Config.IceShellPaddingX -- side-to-side length
	local halfZ = math.max(math.abs(minV.Z), math.abs(maxV.Z)) + pad
	local bottom = minV.Y -- flush with the feet so the cube sits on the floor
	local top = maxV.Y + pad
	return frame, Vector3.new(halfX * 2, top - bottom, halfZ * 2), bottom
end

--------------------------------------------------------------------------
-- Rescue: someone holds E and chips the frozen player out with an ice pick.
-- The rescuer's animation lives in IcePickRescue; every pick hit fires
-- IcePickRescue.Contact and this cracks / chips the ice. The last hit breaks it
-- (the server unfreezes with ThawCause "Rescue" -> shatter() below).
--------------------------------------------------------------------------
local ProximityPromptService = game:GetService("ProximityPromptService")
local IcePickRescue = require(ReplicatedStorage.Shared.IcePickRescue)
local CRACK_COLOR = Color3.fromRGB(236, 248, 255)
local thawing = {} -- [Model] = { ice, shell, baseCFrame, baseSize, cracks = {} }

local function serverNow() return workspace:GetServerTimeNow() end

local function startThawing(model)
	if thawing[model] then return thawing[model] end
	local shell = model:FindFirstChild("IceShell")
	local ice = shell and shell:FindFirstChild("Ice")
	if not ice then return nil end
	local baseCF = ice:GetAttribute("BaseCFrame")
	local baseSize = ice:GetAttribute("BaseSize")
	local t = {
		ice = ice,
		shell = shell,
		baseCFrame = typeof(baseCF) == "CFrame" and baseCF or ice.CFrame,
		baseSize = typeof(baseSize) == "Vector3" and baseSize or ice.Size,
		cracks = {},
	}
	thawing[model] = t
	return t
end

local function stopThawing(model, restoreIce)
	local t = thawing[model]
	if not t then return end
	thawing[model] = nil
	if not restoreIce then return end
	-- let go early: the cracks freeze back over
	for _, c in t.cracks do
		if c.Parent then
			TweenService:Create(c, TweenInfo.new(0.6, Enum.EasingStyle.Sine), { Transparency = 1 }):Play()
			Debris:AddItem(c, 0.65)
		end
	end
	if t.ice.Parent then
		TweenService:Create(t.ice, TweenInfo.new(0.5, Enum.EasingStyle.Sine),
			{ Color = Config.IceColor, Transparency = Config.IceTransparency, CFrame = t.baseCFrame }):Play()
	end
end

-- One crack segment drawn on the ice face (faceCF: origin at the hit, -Z = out of the ice).
local function crackLine(parent, faceCF, from, angle, length, width)
	local p = fxPart()
	p.Name = "Crack"
	p.Material = Enum.Material.SmoothPlastic
	p.Color = CRACK_COLOR
	p.Transparency = 0.05
	p.Size = Vector3.new(width, 0.05, 0.04)
	local base = faceCF * CFrame.new(from.X, from.Y, -0.03) * CFrame.Angles(0, 0, angle)
	p.CFrame = base * CFrame.new(0, 0.025, 0)
	p.Parent = parent
	-- the crack races out from the hit
	TweenService:Create(p, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(width, length, 0.04), CFrame = base * CFrame.new(0, length / 2, 0) }):Play()
	return p, from + Vector2.new(-math.sin(angle), math.cos(angle)) * length
end

-- Little ice chips knocked out of the hit, flying back toward the rescuer.
local function chips(pos, normal, floorY, count)
	for _ = 1, count do
		local s = fxPart()
		s.Material = Enum.Material.Ice
		s.Color = Config.IceColor:Lerp(Color3.new(1, 1, 1), 0.3 + math.random() * 0.5)
		s.Transparency = 0.1
		local k = 0.1 + math.random() * 0.18
		s.Size = Vector3.new(k, k * (0.5 + math.random()), k)
		s.CFrame = CFrame.new(pos) * CFrame.Angles(math.random() * 6.3, math.random() * 6.3, math.random() * 6.3)
		s.Parent = fxFolder
		local side = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 1.6
		local dir = (normal + side).Unit
		local dist = 0.8 + math.random() * 2.2
		local apex = pos + dir * dist * 0.45 + Vector3.new(0, 0.4 + math.random() * 0.9, 0)
		local landing = pos + dir * dist
		landing = Vector3.new(landing.X, floorY + s.Size.Y / 2, landing.Z)
		local spin = CFrame.Angles(math.random() * 6.3, math.random() * 6.3, math.random() * 6.3)
		local fall = math.clamp(0.18 + (apex.Y - landing.Y) * 0.06, 0.2, 0.45)
		local up = TweenService:Create(s, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(apex) * spin })
		local down = TweenService:Create(s, TweenInfo.new(fall, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(landing) * spin * spin })
		up.Completed:Once(function() if s.Parent then down:Play() end end)
		up:Play()
		TweenService:Create(s, TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.In, 0, false, 0.45), { Transparency = 1 }):Play()
		Debris:AddItem(s, 0.8)
	end
end

local function frostPuff(ice, localPos, normal)
	local att = Instance.new("Attachment")
	att.Position = localPos
	att.Parent = ice
	local p = Instance.new("ParticleEmitter")
	p.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	p.Color = ColorSequence.new(Color3.new(1, 1, 1), Config.IceColor)
	p.LightEmission = 0.5
	p.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	p.Transparency = NumberSequence.new(0, 1)
	p.Lifetime = NumberRange.new(0.25, 0.5)
	p.Speed = NumberRange.new(4, 9)
	p.SpreadAngle = Vector2.new(55, 55)
	p.Drag = 5
	p.Acceleration = Vector3.new(0, -12, 0)
	p.EmissionDirection = (normal.X > 0.5 and Enum.NormalId.Right) or (normal.X < -0.5 and Enum.NormalId.Left)
		or (normal.Z > 0.5 and Enum.NormalId.Back) or Enum.NormalId.Front
	p.Enabled = false
	p.Parent = att
	p:Emit(14)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.new(1, 1, 1))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1.4) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(0.4, 0.7)
	smoke.Speed = NumberRange.new(1, 2.5)
	smoke.SpreadAngle = Vector2.new(60, 60)
	smoke.EmissionDirection = p.EmissionDirection
	smoke.Enabled = false
	smoke.Parent = att
	smoke:Emit(4)
	Debris:AddItem(att, 1)
end

IcePickRescue.Contact:Connect(function(rescuer, model, hit, tip)
	if not CollectionService:HasTag(model, FROZEN_TAG) then return end
	local t = startThawing(model)
	if not t or not t.ice.Parent then return end
	local cf, half = t.baseCFrame, t.baseSize / 2
	local lp = cf:PointToObjectSpace(tip)
	-- which face is the rescuer chipping at?
	local rroot = rescuer:FindFirstChild("HumanoidRootPart")
	local rl = rroot and cf:PointToObjectSpace(rroot.Position) or lp
	local normal
	if math.abs(rl.X) / half.X > math.abs(rl.Z) / half.Z then
		normal = Vector3.new(rl.X >= 0 and 1 or -1, 0, 0)
	else
		normal = Vector3.new(0, 0, rl.Z >= 0 and 1 or -1)
	end
	local inset = half - Vector3.new(0.35, 0.35, 0.35)
	local hitL = Vector3.new(math.clamp(lp.X, -inset.X, inset.X), math.clamp(lp.Y, -inset.Y, inset.Y), math.clamp(lp.Z, -inset.Z, inset.Z))
	local mask = Vector3.new(1, 1, 1) - Vector3.new(math.abs(normal.X), 0, math.abs(normal.Z))
	hitL = hitL * mask + normal * half -- snap onto the face
	local hitW = cf:PointToWorldSpace(hitL)
	local nW = cf:VectorToWorldSpace(normal)
	local faceCF = CFrame.lookAt(hitW, hitW + nW)

	-- cracks spread further with every hit
	local n = 2 + hit
	local spin = math.random() * math.pi * 2
	for i = 1, n do
		local ang = spin + (i / n) * math.pi * 2 + (math.random() - 0.5) * 0.8
		local len = 0.25 + math.random() * 0.3 + 0.2 * hit
		local c, endPt = crackLine(t.shell, faceCF, Vector2.zero, ang, len, 0.06)
		table.insert(t.cracks, c)
		if math.random() < 0.65 then
			local c2 = crackLine(t.shell, faceCF, endPt, ang + (math.random() < 0.5 and -1 or 1) * (0.35 + math.random() * 0.5),
				len * (0.35 + math.random() * 0.45), 0.045)
			table.insert(t.cracks, c2)
		end
	end
	-- white bruise where the pick bit in
	local bruise = fxPart(Enum.PartType.Cylinder)
	bruise.Name = "Crack"
	bruise.Material = Enum.Material.SmoothPlastic
	bruise.Color = CRACK_COLOR
	bruise.Transparency = 0.25
	local r = 0.3 + 0.08 * hit
	bruise.Size = Vector3.new(0.04, r, r)
	bruise.CFrame = faceCF * CFrame.new(0, 0, -0.02) * CFrame.Angles(0, math.pi / 2, 0)
	bruise.Parent = t.shell
	table.insert(t.cracks, bruise)

	-- the block clouds up as it weakens, and jolts from the blow
	t.ice.Color = Config.IceColor:Lerp(Color3.new(1, 1, 1), 0.08 * hit)
	t.ice.CFrame = cf * CFrame.new(-normal * 0.07) * CFrame.Angles(math.rad(math.random() - 0.5), 0, math.rad(math.random() - 0.5))
	TweenService:Create(t.ice, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = cf }):Play()

	chips(hitW + nW * 0.1, nW, cf.Position.Y - half.Y, 5 + hit)
	frostPuff(t.ice, cf:ToObjectSpace(CFrame.new(hitW)).Position, normal)
	-- pick hit: crunchy impact with a light crack and a little fracture tail.
	-- Builds a bit with each blow as the block gives way.
	local k = hit / IcePickRescue.MaxHits
	local jitter = (math.random() - 0.5) * 0.08
	soundLayer(t.ice, Config.IceChipSoundId, Config.IceChipVolume * (0.6 + 0.2 * k), 1.18 - 0.06 * k + jitter)
	soundLayer(t.ice, Config.IceHitCrackSoundId, 0.3 + 0.15 * k, 1.45 + jitter, 0, 0.25)
	soundLayer(t.ice, Config.IcePickClangSoundId, 0.12, 1.6 + jitter, 0, 0.15)
	soundLayer(t.ice, Config.IceHitCrackleSoundId, 0.25 + 0.2 * k, 1.15 + jitter, 0.04, 0.3)
end)

local function rescuerCharacter(model)
	local id = model:GetAttribute("ThawBy")
	local p = typeof(id) == "number" and Players:GetPlayerByUserId(id)
	return p and p.Character or nil
end

local function watchThaw(model)
	local current = nil
	local function update()
		if not model:GetAttribute("Frozen") then return end
		local start = model:GetAttribute("ThawStart")
		if typeof(start) == "number" then
			startThawing(model)
			local char = rescuerCharacter(model)
			if char and not IcePickRescue.IsRescuing(char) then
				-- start in sync with when they actually began holding
				IcePickRescue.Start(char, model, os.clock() - math.clamp(serverNow() - start, 0, Config.RescueHoldTime))
			end
			current = char
		else
			local was = current
			current = nil
			-- ThawStart is also cleared right before a successful rescue; wait to see which
			task.delay(0.2, function()
				if model.Parent and CollectionService:HasTag(model, FROZEN_TAG)
					and typeof(model:GetAttribute("ThawStart")) ~= "number" then
					stopThawing(model, true) -- they let go: cracks freeze back over
					if was then IcePickRescue.Stop(was, false) end
					IcePickRescue.StopForModel(model, false)
				end
			end)
		end
	end
	model:GetAttributeChangedSignal("ThawStart"):Connect(update)
	update()
end

-- Your own hold starts the animation instantly (no waiting for the server).
ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
	if prompt.Name ~= "RescuePrompt" then return end
	local model = prompt.Parent and prompt.Parent.Parent
	local char = localPlayer.Character
	if not (model and char and CollectionService:HasTag(model, FROZEN_TAG)) then return end
	local by = model:GetAttribute("ThawBy")
	if typeof(by) == "number" and by ~= localPlayer.UserId then return end -- someone else is on it
	startThawing(model)
	IcePickRescue.Start(char, model, os.clock())
end)
ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt)
	if prompt.Name ~= "RescuePrompt" then return end
	local model = prompt.Parent and prompt.Parent.Parent
	local char = localPlayer.Character
	if not (model and char) then return end
	-- if the hold completed, the server's unfreeze is on its way; only stop if it doesn't come
	task.delay(0.3 + localPlayer:GetNetworkPing() * 2, function()
		if IcePickRescue.GetModel(char) == model and CollectionService:HasTag(model, FROZEN_TAG) then
			IcePickRescue.Stop(char, false)
			if typeof(model:GetAttribute("ThawStart")) ~= "number" then stopThawing(model, true) end
		end
	end)
end)

-- Only show the "Unfreeze" prompt to players who are allowed to use it.
local function canLocalRescue(model)
	local char = localPlayer.Character
	if not char or char == model or char:GetAttribute("Frozen") then return false end
	if Config.TestAnyoneCanRescue then return true end
	local targetPlayer = Players:GetPlayerFromCharacter(model)
	local targetRole = targetPlayer and targetPlayer:GetAttribute("Role") or model:GetAttribute("Role")
	return localPlayer:GetAttribute("Role") == "Runner" and targetRole == "Runner"
end

task.spawn(function()
	while true do
		for _, model in CollectionService:GetTagged(FROZEN_TAG) do
			local root = model:FindFirstChild("HumanoidRootPart")
			local prompt = root and root:FindFirstChild("RescuePrompt")
			if prompt then prompt.Enabled = canLocalRescue(model) end
		end
		task.wait(0.25)
	end
end)

local function buildIce(model, animate)
	if shells[model] then return end
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local frame, fullSize, bottom = measure(model, root)
	local function boxAt(size)
		-- bottom stays planted on the floor whatever the height
		return frame * CFrame.new(0, bottom + size.Y / 2, 0)
	end

	local shell = Instance.new("Folder")
	shell.Name = "IceShell"

	local ice = Instance.new("Part")
	ice.Name = "Ice"
	ice.Material = Enum.Material.Ice
	ice.Color = Config.IceColor
	ice.Anchored = true
	ice.CanCollide = false
	ice.CanQuery = false
	ice.CanTouch = false
	ice.CastShadow = false
	ice.Parent = shell

	local highlight = Instance.new("Highlight")
	highlight.FillColor = Config.IceColor
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = model
	highlight.Parent = shell

	shells[model] = shell
	ice:SetAttribute("BaseSize", fullSize)
	ice:SetAttribute("BaseCFrame", boxAt(fullSize))
	task.defer(watchThaw, model)

	if not animate then -- already frozen when we joined: just show it
		ice.Size = fullSize
		ice.CFrame = boxAt(fullSize)
		ice.Transparency = Config.IceTransparency
		highlight.FillTransparency = Config.HighlightFill
		highlight.OutlineTransparency = 0
		shell.Parent = model
		return
	end

	-- Start already half-formed and visible, so the ice "snaps" on the same frame as the
	-- freeze sound (which peaks ~0.05s in), then shoots up and settles.
	local startSize = Vector3.new(fullSize.X, fullSize.Y * Config.FreezeStartHeight, fullSize.Z)
	ice.Size = startSize
	ice.CFrame = boxAt(startSize)
	ice.Transparency = Config.IceTransparency + 0.2
	highlight.FillTransparency = Config.HighlightFill
	highlight.OutlineTransparency = 0
	shell.Parent = model

	-- Hit + freeze feedback: bonk, crackle, flash, frost ring, ice spray, mist
	playSound(root, Config.HitSoundId, Config.HitVolume, 1.05)
	playSound(root, Config.FreezeSoundId, Config.FreezeVolume, 1)
	impactFlash(root.Position + Vector3.new(0, 0.5, 0))
	shockwave(frame * CFrame.new(0, bottom, 0))
	shards(boxAt(fullSize), fullSize * 0.6, frame.Position.Y + bottom, math.ceil(Config.ShardCount * 0.6), 0.8)
	mist(root)
	emitBurst(root, Config.IceColor)

	-- 1) Rise smoothly a little past full height, slightly slimmer
	local stretchSize = Vector3.new(
		fullSize.X * Config.FreezeSquash,
		fullSize.Y * Config.FreezeStretch,
		fullSize.Z * Config.FreezeSquash
	)
	local rise = TweenService:Create(ice,
		TweenInfo.new(Config.FreezeStretchTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ Size = stretchSize, CFrame = boxAt(stretchSize), Transparency = Config.IceTransparency })
	-- 2) Ease into final size with one soft overshoot
	local settle = TweenService:Create(ice,
		TweenInfo.new(Config.FreezeSettleTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = fullSize, CFrame = boxAt(fullSize) })
	rise.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed and ice.Parent then settle:Play() end
	end)
	rise:Play()

end

-- Rescued: the last pick hit breaks the block apart into chunks that tumble to the floor.
local function shatter(model, shell, ice, root)
	local cf, size = ice.CFrame, ice.Size
	local half = size / 2
	local floorY = cf.Position.Y - half.Y
	ice.Transparency = 1
	for _, c in shell:GetChildren() do
		if c.Name == "Crack" then c:Destroy() end
	end
	local highlight = shell:FindFirstChildOfClass("Highlight")
	if highlight then
		TweenService:Create(highlight, TweenInfo.new(0.15), { FillTransparency = 1, OutlineTransparency = 1 }):Play()
	end
	-- the break: the shatter with a glassy crash on top, then a little rubble
	soundLayer(root, Config.IceShatterSoundId, Config.IceShatterVolume * 0.85, 1)
	soundLayer(root, Config.IceBreakGlassSoundId, 0.45, 1, 0, 1.2)
	soundLayer(root, Config.IceChipSoundId, 0.6, 0.95)
	soundLayer(root, Config.IceBreakDebrisSoundId, 0.3, 1.15, 0.25, 1)

	-- the blow comes from the rescuer's side, so chunks burst mostly away from them
	local rescuer = IcePickRescue.RescuerOf(model)
	local rroot = rescuer and rescuer:FindFirstChild("HumanoidRootPart")
	local push = Vector3.zero
	if rroot then
		local d = (cf.Position - rroot.Position) * Vector3.new(1, 0, 1)
		if d.Magnitude > 0.1 then push = d.Unit * 0.6 end
	end
	for i = 1, 26 do
		local s = fxPart()
		s.Material = Enum.Material.Ice
		s.Color = Config.IceColor:Lerp(Color3.new(1, 1, 1), math.random() * 0.45)
		s.Transparency = Config.IceTransparency * 0.8
		local big = i <= 8
		local k = big and (0.7 + math.random() * 0.5) or (0.25 + math.random() * 0.45)
		s.Size = Vector3.new(k * (0.6 + math.random() * 0.8), k * (0.6 + math.random() * 0.9), k * (0.4 + math.random() * 0.6))
		local startLocal = Vector3.new((math.random() - 0.5) * size.X * 0.9, (math.random() - 0.45) * size.Y * 0.9, (math.random() - 0.5) * size.Z * 0.9)
		local start = cf:PointToWorldSpace(startLocal)
		s.CFrame = CFrame.new(start) * CFrame.Angles(math.random() * 6.3, math.random() * 6.3, math.random() * 6.3)
		s.Parent = fxFolder
		local out = cf:VectorToWorldSpace(startLocal * Vector3.new(1, 0, 1))
		out = (out.Magnitude > 0.05 and out.Unit or Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit) + push
		local dist = (big and 1.2 or 2) + math.random() * (big and 1.5 or 3)
		local apex = start + out * dist * 0.4 + Vector3.new(0, (big and 0.3 or 0.8) + math.random() * 1.2, 0)
		local landing = start + out * dist
		landing = Vector3.new(landing.X, floorY + s.Size.Y * 0.35, landing.Z)
		local spin = CFrame.Angles(math.random() * 6.3, math.random() * 6.3, math.random() * 6.3)
		local fall = math.clamp(0.2 + (apex.Y - landing.Y) * 0.07, 0.25, 0.6)
		local up = TweenService:Create(s, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(apex) * spin })
		local down = TweenService:Create(s, TweenInfo.new(fall, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(landing) * spin * spin })
		up.Completed:Once(function() if s.Parent then down:Play() end end)
		up:Play()
		-- chunks lie on the floor a moment, then melt away
		local linger = 0.16 + fall + 0.5 + math.random() * 0.6
		TweenService:Create(s, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.In, 0, false, linger),
			{ Transparency = 1, Size = s.Size * 0.6 }):Play()
		Debris:AddItem(s, linger + 0.7)
	end
	mist(root)
	emitBurst(root, Color3.new(1, 1, 1))
	shockwave(cf * CFrame.new(0, -half.Y, 0))
	Debris:AddItem(shell, 1.5)
end

local function meltIce(model)
	local shell = shells[model]
	shells[model] = nil
	local rescued = model:GetAttribute("ThawCause") == "Rescue"
	IcePickRescue.StopForModel(model, rescued)
	stopThawing(model, false)
	if not shell or not shell.Parent then return end

	local root = model:FindFirstChild("HumanoidRootPart")
	local ice = shell:FindFirstChild("Ice")
	if rescued and root and ice then
		shatter(model, shell, ice, root)
		return
	end
	local meltTime = 0.7
	if root and ice then
		-- Unthaw: the softened ice melts down into a splash of water and a burst of steam
		playSound(root, Config.ThawSoundId, Config.ThawVolume, 1)
		playSound(root, Config.ThawSteamSoundId, 0.35, 1.1)
		mist(root)
		emitBurst(root, Color3.new(1, 1, 1))
	end

	local info = TweenInfo.new(meltTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, child in shell:GetChildren() do
		if child:IsA("BasePart") then
			local h = 0.1
			local drop = (child.Size.Y - h) / 2
			TweenService:Create(child, info, {
				Transparency = 1,
				Size = Vector3.new(child.Size.X * 1.08, h, child.Size.Z * 1.08), -- spreads as it melts
				CFrame = child.CFrame * CFrame.new(0, -drop, 0),
			}):Play()
		elseif child:IsA("Highlight") then
			TweenService:Create(child, info, { FillTransparency = 1, OutlineTransparency = 1 }):Play()
		end
	end
	Debris:AddItem(shell, 2)
end

CollectionService:GetInstanceAddedSignal(FROZEN_TAG):Connect(function(model)
	buildIce(model, true)
end)
CollectionService:GetInstanceRemovedSignal(FROZEN_TAG):Connect(meltIce)

for _, model in CollectionService:GetTagged(FROZEN_TAG) do
	buildIce(model, false)
end

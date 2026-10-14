-- FreezeService (server-authoritative)
-- Owns: who is frozen, locking their movement, validating bat swings, and rescues.
-- A freeze lasts until a valid teammate holds E on the frozen player (RescuePrompt).
-- While they hold, the model carries ThawBy (UserId) + ThawStart (server time) so every
-- client can draw the ice melting; on success the model gets ProtectedUntil.
-- The ice cube VISUALS are drawn on each client (FreezeEffectsController) so they
-- animate smoothly; the server just tags frozen characters with "Frozen".
-- Works on any character Model with a Humanoid + HumanoidRootPart (players AND NPCs/dummies).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.Shared.FreezeConfig)
local FreezeEvent = ReplicatedStorage.Remotes.FreezeEvent

local TARGET_TAG = "FreezeTarget"
local FROZEN_TAG = "Frozen" -- clients watch this tag to draw the ice cube

local FreezeService = {}

local frozen = {} -- [Model] = state table
local lastTagTime = {} -- [Player] = os.clock()

local frozenChanged = Instance.new("BindableEvent")
-- FreezeService.FrozenChanged:Connect(function(model, isFrozen, byPlayer) end)
FreezeService.FrozenChanged = frozenChanged.Event

--------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------

local function getAlive(model)
	if not model or not model.Parent then return nil end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if hum and root and hum.Health > 0 then
		return hum, root
	end
	return nil
end

-- Role lives on the Player for real players, on the Model for NPCs/dummies.
function FreezeService.GetRole(model)
	local player = Players:GetPlayerFromCharacter(model)
	if player then
		return player:GetAttribute("Role")
	end
	return model:GetAttribute("Role")
end

function FreezeService.IsFrozen(model)
	return frozen[model] ~= nil
end

local function now()
	return workspace:GetServerTimeNow()
end

function FreezeService.IsProtected(model)
	local untilTime = model:GetAttribute("ProtectedUntil")
	return typeof(untilTime) == "number" and untilTime > now()
end

-- Can this player rescue that frozen model?
local function canRescue(player, model)
	if not frozen[model] then return false end
	local char = player.Character
	if not char or char == model or frozen[char] or not getAlive(char) then return false end
	if Config.TestAnyoneCanRescue then return true end
	-- Real rule: Runners rescue Runners (team modes can extend this to "same team").
	return player:GetAttribute("Role") == "Runner" and FreezeService.GetRole(model) == "Runner"
end

local function clearThaw(model)
	model:SetAttribute("ThawBy", nil)
	model:SetAttribute("ThawStart", nil)
end

-- A player who gets frozen can't keep rescuing someone else.
local function cancelRescuesBy(player)
	for model in frozen do
		if model:GetAttribute("ThawBy") == player.UserId then clearThaw(model) end
	end
end

local function createRescuePrompt(model, root, state)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RescuePrompt"
	prompt.ActionText = "Unfreeze"
	prompt.ObjectText = ""
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = Config.RescueHoldTime
	prompt.MaxActivationDistance = Config.RescueRange
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OneGlobally
	prompt.Parent = root

	-- holdStarts[player] = when that player started holding (server time). Kept separately
	-- from the visual ThawBy/ThawStart attributes because Roblox fires HoldEnded a moment
	-- BEFORE Triggered when a hold completes.
	local holdStarts = {}
	state.holdStarts = holdStarts
	table.insert(state.connections, prompt.PromptButtonHoldBegan:Connect(function(player)
		if not canRescue(player, model) then return end
		holdStarts[player] = now()
		if model:GetAttribute("ThawBy") then return end -- someone else is already thawing them
		model:SetAttribute("ThawBy", player.UserId)
		model:SetAttribute("ThawStart", holdStarts[player])
	end))
	table.insert(state.connections, prompt.PromptButtonHoldEnded:Connect(function(player)
		local startedAt = holdStarts[player]
		task.delay(0.2, function()
			-- let a Triggered that follows immediately use the hold first
			if holdStarts[player] == startedAt then holdStarts[player] = nil end
			if frozen[model] and model:GetAttribute("ThawBy") == player.UserId then clearThaw(model) end
		end)
	end))
	table.insert(state.connections, prompt.Triggered:Connect(function(player)
		-- Re-validate everything on the server: who, how close, and that they held long enough
		if not canRescue(player, model) then return end
		local start = holdStarts[player]
		if typeof(start) ~= "number" or now() - start < Config.RescueHoldTime - 0.35 then return end
		local _, myRoot = getAlive(player.Character)
		if not myRoot or (myRoot.Position - root.Position).Magnitude > Config.RescueRange + 2 then return end
		FreezeService.Unfreeze(model, player, "Rescue")
	end))
	state.prompt = prompt
end

local function playSound(parent, id)
	if id == nil or id == "" then return end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.RollOffMaxDistance = 80
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, 4)
end

-- NPCs: the server owns their animations, so pause them here.
-- Players: their client owns animation playback; FrozenPose (LocalScript) pauses those.
local function pauseNpcAnimations(model, hum, state)
	if Players:GetPlayerFromCharacter(model) then return end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then return end
	state.pausedTracks = {}
	for _, track in animator:GetPlayingAnimationTracks() do
		table.insert(state.pausedTracks, { track = track, speed = track.Speed })
		track:AdjustSpeed(0)
	end
	local animate = model:FindFirstChild("Animate")
	if animate and animate:IsA("BaseScript") and animate.Enabled then
		animate.Enabled = false
		state.disabledAnimate = animate
	end
end

local function resumeNpcAnimations(state)
	if state.pausedTracks then
		for _, entry in state.pausedTracks do
			if entry.track.IsPlaying then
				entry.track:AdjustSpeed(entry.speed)
			end
		end
	end
	if state.disabledAnimate and state.disabledAnimate.Parent then
		state.disabledAnimate.Enabled = true
	end
end

--------------------------------------------------------------------------
-- Public: Freeze / Unfreeze
--------------------------------------------------------------------------

function FreezeService.Freeze(model, byPlayer)
	if frozen[model] then return false end -- no duplicate freezes
	local hum, root = getAlive(model)
	if not hum then return false end

	local state = {
		walkSpeed = hum.WalkSpeed,
		jumpPower = hum.JumpPower,
		jumpHeight = hum.JumpHeight,
		autoRotate = hum.AutoRotate,
		wasAnchored = root.Anchored,
		connections = {},
	}
	frozen[model] = state

	-- Lock movement (server side, so exploiters can't just walk away)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	hum.WalkSpeed = 0
	hum.JumpPower = 0
	hum.JumpHeight = 0
	hum.AutoRotate = false
	root.Anchored = true

	pauseNpcAnimations(model, hum, state)

	local frozenPlayer = Players:GetPlayerFromCharacter(model)
	if frozenPlayer then cancelRescuesBy(frozenPlayer) end
	clearThaw(model)
	model:SetAttribute("ThawCause", nil)
	createRescuePrompt(model, root, state)

	model:SetAttribute("Frozen", true)
	CollectionService:AddTag(model, FROZEN_TAG)

	-- Clean up if the character dies or is removed while frozen
	table.insert(state.connections, hum.Died:Connect(function()
		FreezeService.Unfreeze(model)
	end))
	table.insert(state.connections, model.Destroying:Connect(function()
		for _, c in state.connections do c:Disconnect() end
		frozen[model] = nil
	end))

	FreezeEvent:FireAllClients("Frozen", model, byPlayer)
	frozenChanged:Fire(model, true, byPlayer)
	return true
end

function FreezeService.Unfreeze(model, byPlayer, cause)
	local state = frozen[model]
	if not state then return false end
	frozen[model] = nil
	for _, c in state.connections do c:Disconnect() end
	if state.prompt then state.prompt:Destroy() end
	clearThaw(model)
	model:SetAttribute("ThawCause", cause or "Other") -- clients pick the melt effect from this
	if cause == "Rescue" then
		model:SetAttribute("ProtectedUntil", now() + Config.RescueProtection)
	end

	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if hum then
		hum.WalkSpeed = state.walkSpeed
		hum.JumpPower = state.jumpPower
		hum.JumpHeight = state.jumpHeight
		hum.AutoRotate = state.autoRotate
	end
	if root then
		root.Anchored = state.wasAnchored
	end

	resumeNpcAnimations(state)
	model:SetAttribute("Frozen", false)
	CollectionService:RemoveTag(model, FROZEN_TAG)

	FreezeEvent:FireAllClients("Unfrozen", model, byPlayer, cause)
	frozenChanged:Fire(model, false, byPlayer, cause)
	return true
end

--------------------------------------------------------------------------
-- Public: Freezer bat swing (called when a client asks to swing)
-- The client sends NO target; the server picks the best valid one.
--------------------------------------------------------------------------

local function getCandidates()
	local list = {}
	for _, player in Players:GetPlayers() do
		if player.Character then table.insert(list, player.Character) end
	end
	for _, model in CollectionService:GetTagged(TARGET_TAG) do
		if model:IsA("Model") and model:IsDescendantOf(workspace) then
			table.insert(list, model)
		end
	end
	return list
end

local function canSwing(player)
	if player:GetAttribute("Role") ~= "Freezer" then return false, "NotFreezer" end
	local char = player.Character
	if not getAlive(char) then return false, "NotAlive" end
	if frozen[char] then return false, "SelfFrozen" end
	local stanceNow = char:GetAttribute("Stance")
	if stanceNow == "Crawl" or stanceNow == "Slide" then return false, "Busy" end
	local bat = char:FindFirstChild(Config.BatToolName)
	if not (bat and bat:IsA("Tool")) then return false, "NoBatEquipped" end
	return true
end

-- Finds the closest valid Runner in front of the player, with line of sight.
local function findTarget(player)
	local char = player.Character
	local hum, root = getAlive(char)
	if not hum then return nil end

	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = if look.Magnitude > 0 then look.Unit else Vector3.zAxis
	local minDot = math.cos(math.rad(Config.TagConeAngle))

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local best, bestDist = nil, math.huge
	for _, target in getCandidates() do
		if target ~= char and not frozen[target] and not FreezeService.IsProtected(target)
			and FreezeService.GetRole(target) == "Runner" then
			local tHum, tRoot = getAlive(target)
			if tHum then
				local offset = tRoot.Position - root.Position
				local dist = offset.Magnitude
				if dist <= Config.TagRange and dist < bestDist then
					local flat = offset * Vector3.new(1, 0, 1)
					local facing = dist <= Config.TagPointBlank
						or (flat.Magnitude > 0 and flat.Unit:Dot(look) >= minDot)
					if facing then
						-- Line of sight: no tagging through walls
						rayParams.FilterDescendantsInstances = { char, target }
						if not workspace:Raycast(root.Position, offset, rayParams) then
							best, bestDist = target, dist
						end
					end
				end
			end
		end
	end

	return best
end

-- Yields for BatHitDelay so the hit lines up with the bat landing.
function FreezeService.Swing(player)
	local now = os.clock()
	if lastTagTime[player] and now - lastTagTime[player] < Config.TagCooldown then
		return false, "Cooldown"
	end
	local ok, reason = canSwing(player)
	if not ok then return false, reason end
	lastTagTime[player] = now

	-- Everyone else plays the swing animation (the swinger already played it locally)
	for _, other in Players:GetPlayers() do
		if other ~= player then
			FreezeEvent:FireClient(other, "Swing", player.Character)
		end
	end

	task.wait(Config.BatHitDelay)

	-- Re-check: the swinger may have been frozen, died, or unequipped mid-swing
	ok, reason = canSwing(player)
	if not ok then return false, reason end

	local target = findTarget(player)
	if not target then return false, "Miss" end
	if FreezeService.Freeze(target, player) then
		return true, target
	end
	return false, "FreezeFailed"
end

Players.PlayerRemoving:Connect(function(player)
	lastTagTime[player] = nil
end)

return FreezeService

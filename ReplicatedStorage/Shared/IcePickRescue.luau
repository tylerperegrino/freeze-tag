-- IcePickRescue: the rescuer pulls out an ice pick and chips the frozen player out of the ice.
-- Poses + pick were built in Blender (IcePick_R6.blend) on an exact R6 rig, same joint
-- conventions as BatSwing (offsets in each joint's parent-part axes).
-- Runs on every client. The animation is a pure function of time since the hold began, so
-- everyone sees the same strikes at the same moments (contacts at 0.38s, then every 0.5s:
-- 5 hits in the 2.5s hold, the 5th one breaks the ice).
-- FreezeEffectsController listens to IcePickRescue.Contact to crack / chip the ice.
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BatSwing = require(ReplicatedStorage.Shared.BatSwing)
local Config = require(ReplicatedStorage.Shared.FreezeConfig)

local IcePickRescue = {}

local rad = math.rad
local function A(x, y, z) return CFrame.Angles(rad(x), rad(y), rad(z)) end

-- exported from Blender (IcePick_R6.blend). wrist = the pick's rotation in the right hand.
local POSES = {
	-- arm straight up and back, pick cocked behind the head, body leaning back and coiled right,
	-- left arm reaching toward the ice for balance
	windup = { root = A(8.0, -20.0, -0.0), neck = A(-6.0, 20.0, -0.0), rightShoulder = A(77.31, 13.37, 20.39), leftShoulder = A(91.16, -19.7, 17.56), rightHip = A(-18.0, 13.0, -0.0), leftHip = A(4.0, 13.0, -0.0), wrist = A(70.47, -126.89, 39.48) },
	-- chop: body drives forward over the front leg, pick bites into the ice at chest height
	contact = { root = A(-14.0, 12.0, -0.0), neck = A(12.0, -12.0, -0.0), rightShoulder = A(39.47, 35.64, 0.55), leftShoulder = A(39.24, -11.6, 5.06), rightHip = A(-2.0, -8.0, -0.0), leftHip = A(30.0, -8.0, -0.0), wrist = A(-10.16, -135.36, 90.61) },
	-- pry: yank the pick back out of the ice
	pry = { root = A(-6.0, 5.0, -0.0), neck = A(5.0, -5.0, -0.0), rightShoulder = A(37.8, 46.9, -4.6), leftShoulder = A(45.82, -14.4, 3.59), rightHip = A(-8.0, -3.0, -0.0), leftHip = A(20.0, -3.0, -0.0), wrist = A(-7.64, -141.38, 83.33) },
}

-- Ice pick pieces in grip space (+X along the shaft from the hand, +Y = pick side).
local PIECES = {
	{ name = "Grip", shape = "cyl", size = Vector3.new(0.9, 0.26, 0.26), cf = CFrame.new(-0.05, 0, 0), color = Color3.fromRGB(30, 30, 36), material = Enum.Material.Fabric },
	{ name = "Shaft", shape = "cyl", size = Vector3.new(1.0, 0.2, 0.2), cf = CFrame.new(0.85, 0, 0), color = Color3.fromRGB(64, 115, 190), material = Enum.Material.Metal },
	{ name = "Spike", shape = "cyl", size = Vector3.new(0.24, 0.13, 0.13), cf = CFrame.new(-0.6, 0, 0), color = Color3.fromRGB(150, 155, 165), material = Enum.Material.Metal },
	{ name = "Head", shape = "box", size = Vector3.new(0.3, 0.36, 0.16), cf = CFrame.new(1.42, 0, 0), color = Color3.fromRGB(150, 155, 165), material = Enum.Material.Metal },
	{ name = "Pick", shape = "box", size = Vector3.new(0.12, 0.72, 0.07), cf = CFrame.new(1.38, 0.52, 0) * A(0, 0, 12), color = Color3.fromRGB(180, 184, 194), material = Enum.Material.Metal },
	{ name = "Tip", shape = "box", size = Vector3.new(0.1, 0.18, 0.07), cf = CFrame.new(1.25, 0.92, 0) * A(0, 0, 35), color = Color3.fromRGB(215, 220, 228), material = Enum.Material.Metal },
	{ name = "Adze", shape = "box", size = Vector3.new(0.1, 0.3, 0.34), cf = CFrame.new(1.42, -0.3, 0), color = Color3.fromRGB(180, 184, 194), material = Enum.Material.Metal },
}
local PICK_SCALE = 1.3 -- a little bigger than life so it reads from the game camera
local PICK_TIP = Vector3.new(1.2, 1.0, 0) * PICK_SCALE -- the point that bites the ice (grip space)
local C0W = CFrame.new(0, -1, 0, 1, 0, 0, 0, 0, 1, 0, -1, 0) -- same hand grip as a Tool's RightGrip
local GRIP = CFrame.new(0, 0, 0, 0, 1, 0, -1, 0, 0, 0, 0, 1)
local RIGHT_BASE = CFrame.Angles(0, 0, rad(90)) -- right arm base, same as BatSwing's R6 hold

-- Timing (seconds since the hold began)
local DRAW = 0.30 -- pull the pick out and raise it
local TO_CONTACT = 0.08 -- the chop itself (accelerates into the ice)
local TO_PRY = 0.12 -- yank it back out
local TO_WINDUP = 0.30 -- raise for the next chop
local PERIOD = TO_CONTACT + TO_PRY + TO_WINDUP
local BLEND_OUT = 0.35
IcePickRescue.FirstContact = DRAW + TO_CONTACT
IcePickRescue.Period = PERIOD
IcePickRescue.MaxHits = math.floor((Config.RescueHoldTime - IcePickRescue.FirstContact) / PERIOD) + 1
IcePickRescue.StandGap = 3.22 -- rescuer's root to the ice face, so the pick tip bites ~0.1 studs in (measured on the TestDummy)

local contactEvent = Instance.new("BindableEvent")
-- IcePickRescue.Contact:Connect(function(rescuerCharacter, frozenModel, hitIndex, tipWorldPosition) end)
IcePickRescue.Contact = contactEvent.Event

local function ease(a, style, dir)
	return TweenService:GetValue(math.clamp(a, 0, 1), style, dir)
end

local function lerpPose(p1, p2, a)
	local out = {}
	for k, v in p1 do out[k] = v:Lerp(p2[k], a) end
	return out
end

local function poseAt(t)
	if t < DRAW then return POSES.windup end
	local c = (t - DRAW) % PERIOD
	if c < TO_CONTACT then
		return lerpPose(POSES.windup, POSES.contact, ease(c / TO_CONTACT, Enum.EasingStyle.Quad, Enum.EasingDirection.In))
	elseif c < TO_CONTACT + TO_PRY then
		return lerpPose(POSES.contact, POSES.pry, ease((c - TO_CONTACT) / TO_PRY, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
	end
	return lerpPose(POSES.pry, POSES.windup, ease((c - TO_CONTACT - TO_PRY) / TO_WINDUP, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut))
end

local states = {} -- [character] = state

local function buildPick(arm)
	local model = Instance.new("Model")
	model.Name = "IcePick"
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.2, 0.2, 0.2)
	handle.Transparency = 1
	local parts = { handle }
	for _, info in PIECES do
		local p = Instance.new("Part")
		p.Name = info.name
		if info.shape == "cyl" then p.Shape = Enum.PartType.Cylinder end
		p.Size = info.size * PICK_SCALE
		p.Color = info.color
		p.Material = info.material
		p.CFrame = info.cf.Rotation + info.cf.Position * PICK_SCALE
		table.insert(parts, p)
	end
	for _, p in parts do
		p.Anchored = false
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = p ~= handle
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		if p ~= handle then
			local w = Instance.new("Weld")
			w.Part0 = handle
			w.Part1 = p
			w.C0 = p.CFrame
			w.Parent = p
		end
		p.Parent = model
	end
	model.PrimaryPart = handle
	local grip = Instance.new("Weld")
	grip.Name = "PickGrip"
	grip.Part0 = arm
	grip.Part1 = handle
	grip.C0 = C0W * POSES.windup.wrist
	grip.C1 = GRIP
	grip.Parent = handle
	handle.CFrame = arm.CFrame * grip.C0 * GRIP:Inverse()
	return model, handle, grip
end

local function getJoints(character)
	local torso = character:FindFirstChild("Torso")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not (torso and root) then return nil end
	local list = {}
	local function add(key, parent, name)
		local j = parent:FindFirstChild(name)
		if j and j:IsA("Motor6D") then
			local r = j.C0.Rotation
			table.insert(list, { key = key, joint = j, r = r, rInv = r:Inverse(), base = key == "rightShoulder" and RIGHT_BASE or CFrame.identity })
		end
	end
	add("rightShoulder", torso, "Right Shoulder")
	add("leftShoulder", torso, "Left Shoulder")
	add("neck", torso, "Neck")
	add("rightHip", torso, "Right Hip")
	add("leftHip", torso, "Left Hip")
	add("root", root, "RootJoint")
	return list
end

local function setBatHidden(character, hidden)
	local bat = character:FindFirstChild(Config.BatToolName)
	if not bat then return end
	for _, p in bat:GetDescendants() do
		if p:IsA("BasePart") then p.LocalTransparencyModifier = hidden and 1 or 0 end
		if p:IsA("Trail") and hidden then p.Enabled = false end
	end
end

-- Ice block of a frozen model (drawn by FreezeEffectsController).
local function iceBox(model)
	local shell = model:FindFirstChild("IceShell")
	local ice = shell and shell:FindFirstChild("Ice")
	if ice then
		local cf = ice:GetAttribute("BaseCFrame")
		local size = ice:GetAttribute("BaseSize")
		return (typeof(cf) == "CFrame" and cf or ice.CFrame), (typeof(size) == "Vector3" and size or ice.Size)
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	return root and root.CFrame, Vector3.new(5.6, 6.2, 3.4)
end

-- Where the rescuer should stand: square to the nearest face of the ice, StandGap away.
local function standCFrame(model, myRoot)
	local cf, size = iceBox(model)
	if not cf then return nil end
	local half = size / 2
	local lp = cf:PointToObjectSpace(myRoot.Position)
	local pos, normal
	if math.abs(lp.X) / half.X > math.abs(lp.Z) / half.Z then
		local s = lp.X >= 0 and 1 or -1
		pos = Vector3.new(s * (half.X + IcePickRescue.StandGap), 0, math.clamp(lp.Z, -half.Z * 0.4, half.Z * 0.4))
		normal = Vector3.new(s, 0, 0)
	else
		local s = lp.Z >= 0 and 1 or -1
		pos = Vector3.new(math.clamp(lp.X, -half.X * 0.4, half.X * 0.4), 0, s * (half.Z + IcePickRescue.StandGap))
		normal = Vector3.new(0, 0, s)
	end
	local world = cf:PointToWorldSpace(pos)
	world = Vector3.new(world.X, myRoot.Position.Y, world.Z)
	local n = cf:VectorToWorldSpace(normal) * Vector3.new(1, 0, 1)
	return CFrame.lookAt(world, world - n.Unit)
end

local function lockLocal(state)
	local character = state.character
	local hum = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not (hum and root) then return end
	state.saved = { ws = hum.WalkSpeed, jp = hum.JumpPower, jh = hum.JumpHeight, ar = hum.AutoRotate }
	hum.WalkSpeed = 0
	hum.JumpPower = 0
	hum.JumpHeight = 0
	hum.AutoRotate = false
	state.moveFrom = root.CFrame
	state.moveGoal = standCFrame(state.model, root)
end

local function unlockLocal(state)
	local hum = state.character:FindFirstChildOfClass("Humanoid")
	if hum and state.saved then
		hum.WalkSpeed = state.saved.ws
		hum.JumpPower = state.saved.jp
		hum.JumpHeight = state.saved.jh
		hum.AutoRotate = state.saved.ar
	end
	state.saved = nil
end

local function cleanup(state)
	if states[state.character] == state then states[state.character] = nil end
	if state.pick then state.pick:Destroy() end
	unlockLocal(state)
	if state.character.Parent then
		setBatHidden(state.character, false)
		BatSwing.SetSuspended(state.character, false)
	end
end

function IcePickRescue.IsRescuing(character)
	local s = states[character]
	return s ~= nil and not s.stopAt
end

function IcePickRescue.GetModel(character)
	local s = states[character]
	return s and s.model
end

-- startClock: os.clock() at which the hold began (lets late joiners / remote players sync up)
function IcePickRescue.Start(character, model, startClock)
	if not character or not model then return end
	local existing = states[character]
	if existing and existing.model == model and not existing.stopAt then return end
	if existing then cleanup(existing) end
	local arm = character:FindFirstChild("Right Arm")
	local joints = getJoints(character)
	if not (arm and joints) then return end -- R6 only
	local state = {
		character = character,
		model = model,
		start = startClock or os.clock(),
		joints = joints,
		hits = 0,
		isLocal = character == (Players.LocalPlayer and Players.LocalPlayer.Character),
	}
	state.pick, state.handle, state.grip = buildPick(arm)
	state.pick.Parent = character
	BatSwing.SetSuspended(character, true)
	setBatHidden(character, true)
	if state.isLocal then lockLocal(state) end
	states[character] = state
end

-- finished = the ice broke (hold the follow-through a moment); otherwise they let go early.
function IcePickRescue.Stop(character, finished)
	local state = states[character]
	if not state or state.stopAt then return end
	state.stopAt = os.clock()
	state.stopT = state.stopAt - state.start
	state.finished = finished
	unlockLocal(state)
end

function IcePickRescue.StopForModel(model, finished)
	for character, state in states do
		if state.model == model then IcePickRescue.Stop(character, finished) end
	end
end

function IcePickRescue.RescuerOf(model)
	for character, state in states do
		if state.model == model then return character end
	end
	return nil
end

RunService.PreSimulation:Connect(function()
	local now = os.clock()
	for character, state in states do
		if not character.Parent or not state.handle.Parent then
			cleanup(state)
			continue
		end
		local t = now - state.start
		local w
		if state.stopAt then
			local hold = state.finished and 0.12 or 0
			local a = (now - state.stopAt - hold) / BLEND_OUT
			if a >= 1 then
				cleanup(state)
				continue
			end
			w = 1 - ease(a, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			t = state.stopT
			-- pick shrinks away as the arm lowers
			local s = math.clamp(a * 1.6, 0, 1)
			for _, p in state.pick:GetChildren() do
				if p:IsA("BasePart") and p ~= state.handle then p.LocalTransparencyModifier = s end
			end
		else
			w = ease(t / DRAW, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		end
		local pose = poseAt(math.max(t, 0))
		for _, j in state.joints do
			local target = j.rInv * pose[j.key] * j.r * j.base
			j.joint.Transform = if w >= 1 then target else j.joint.Transform:Lerp(target, w)
		end
		state.grip.C0 = C0W * pose.wrist
		-- local player: step into position square to the ice
		if state.isLocal and state.moveGoal and not state.stopAt then
			local root = character:FindFirstChild("HumanoidRootPart")
			if root then
				local a = ease(t / 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				root.CFrame = state.moveFrom:Lerp(state.moveGoal, a)
				root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
				root.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end
end)

-- Contacts fire after the physics step so the pick tip is where it's drawn this frame.
RunService.PostSimulation:Connect(function()
	local now = os.clock()
	for character, state in states do
		if state.stopAt then continue end
		local t = now - state.start
		local due = t >= IcePickRescue.FirstContact and math.floor((t - IcePickRescue.FirstContact) / PERIOD) + 1 or 0
		due = math.min(due, IcePickRescue.MaxHits)
		while state.hits < due do
			state.hits += 1
			local tip = (state.handle.CFrame * CFrame.new(PICK_TIP)).Position
			contactEvent:Fire(character, state.model, state.hits, tip)
		end
	end
end)

return IcePickRescue

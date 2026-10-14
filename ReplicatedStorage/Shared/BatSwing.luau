-- BatSwing: procedural two-handed bat hold + swing (no uploaded animation needed).
-- Every frame, AFTER the Animator has posed the character, we layer extra
-- rotations onto the arm/torso joints' Transform, so this blends on top of
-- walking/running. Works on AnimationConstraint (new) and Motor6D (old) rigs.
--
-- R6 and R15 swings are both TWO-HANDED. Each pose was fitted so the left hand sits
-- on the bat's grip just below the right hand. R15 and R6 have separate pose sets. Both arms tween on the same curves,
-- so the hands move together smoothly with no jitter.
-- Runs on clients only (BatEffectsController calls Equip/Unequip for everyone;
-- the swinger plays Play instantly, others when the server says "Swing").
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.FreezeConfig)

local BatSwing = {}

local rad = math.rad
local function A(x, y, z) return CFrame.Angles(rad(x), rad(y), rad(z)) end

-- Poses are offsets in each joint's PARENT-part axes (+X right, +Y up, +Z back).
-- Shoulders: +X lifts the arm up; +Y turns it to the body's LEFT (right arm inward,
-- left arm outward). Waist/hips/neck: +Y twists LEFT, +X leans back.
local HOLD = {
	rightShoulder = A(-10, 38, 0),
	rightElbow = A(30, 0, 0),
	leftShoulder = A(87, -30, 45),
	leftElbow = A(0, 0, 0),
}

-- R6 rigs have no elbows or separate waist: the torso twist goes through RootJoint
-- ("root", offsets in HumanoidRootPart axes). Fitted separately for R6 proportions.
-- R6 TWO-HANDED POWER SWING, posed in Blender (BatSwing_R6.blend) on an exact R6 + bat rig.
-- Both hands are solved onto the handle every pose (left hand just below the right).
-- raise -> coil (hips & shoulders load up to the right, head stays on target) -> contact
-- (hips fire first, bat comes level through the target at chest height) -> wrap-around
-- follow-through -> recover. Hips counter-twist against the torso so the body uncoils.
local R6_POSES = { -- exported from Blender (BatSwing_R6.blend)
	hold = { root = A(-0.0, 0.0, -0.0), neck = A(-0.0, 0.0, -0.0), rightShoulder = A(-31.67, 62.17, 10.93), leftShoulder = A(49.08, 0.68, 38.37), rightHip = A(-0.0, 0.0, -0.0), leftHip = A(-0.0, 0.0, -0.0), wrist = A(75.85, -70.58, 23.25) },
	raise = { root = A(-0.0, -22.0, -0.0), neck = A(-0.0, 22.0, -0.0), rightShoulder = A(-5.98, 57.48, 1.58), leftShoulder = A(67.46, 2.66, 40.85), rightHip = A(-0.0, 14.3, 6.0), leftHip = A(8.0, 14.3, -4.0), wrist = A(19.21, -77.59, -28.6) },
	coil = { root = A(6.0, -58.0, -6.0), neck = A(-6.0, 58.0, 5.0), rightShoulder = A(20.34, 49.1, -2.99), leftShoulder = A(84.87, 10.64, 48.5), rightHip = A(-4.0, 37.7, 8.0), leftHip = A(22.0, 37.7, -8.0), wrist = A(-35.9, -59.02, -70.35) },
	contact = { root = A(-12.0, 25.0, 5.0), neck = A(10.0, -25.0, -5.0), rightShoulder = A(-18.68, 37.62, 0.16), leftShoulder = A(44.24, 12.61, 67.29), rightHip = A(-14.0, -16.25, 6.0), leftHip = A(24.0, -16.25, -6.0), wrist = A(16.39, 23.01, -71.82) },
	follow = { root = A(-8.0, 75.0, 8.0), neck = A(6.0, -72.0, -6.0), rightShoulder = A(1.57, 62.42, -0.54), leftShoulder = A(43.14, 17.81, 80.12), rightHip = A(-16.0, -48.75, 10.0), leftHip = A(20.0, -48.75, -6.0), wrist = A(-4.72, 80.72, -57.99) },
	recover = { root = A(-3.0, 30.0, 2.0), neck = A(2.0, -30.0, -2.0), rightShoulder = A(-1.63, 64.6, 0.62), leftShoulder = A(55.14, 9.07, 54.14), rightHip = A(-6.0, -19.5, 4.0), leftHip = A(10.0, -19.5, -3.0), wrist = A(-1.73, 175.2, -7.97) },
}
local HOLD_R6 = R6_POSES.hold -- two-handed ready stance
-- [keyframe index] = R6 pose
local R6 = { R6_POSES.raise, R6_POSES.coil, R6_POSES.contact, R6_POSES.follow, R6_POSES.recover }
-- [keyframe index] = { duration, style, direction, smoothing } for R6. Slow load-up, a beat of
-- anticipation at the coil, then the strike ACCELERATES into contact (Quad In) and the
-- follow-through bleeds the speed off (Quad Out) -- that speed contrast is what sells the power.
local E = Enum.EasingStyle
local D = Enum.EasingDirection
local R6_TIMING = {
	{ 0.15, E.Sine, D.Out, 18 },   -- raise
	{ 0.17, E.Quad, D.Out, 18 },   -- coil (eases into the loaded position)
	{ 0.085, E.Quad, D.In, 400 },  -- contact (no smoothing: the bat must pass exactly through the target)
	{ 0.15, E.Quad, D.Out, 400 },  -- follow-through
	{ 0.14, E.Sine, D.InOut, 16 }, -- recover
	{ 0.16, E.Sine, D.Out, 15 },   -- settle into the hold
}
BatSwing.R6ContactTime = R6_TIMING[1][1] + R6_TIMING[2][1] + R6_TIMING[3][1]
local KEYFRAMES = {
	{ -- 1) Big wind-up: body coils hard to the right and leans back, hands drawn back
		--    behind the right shoulder, bat reaching far out behind the character.
		--    Head stays on the target.
		time = "SwingWindupTime", style = Enum.EasingStyle.Sine, dir = Enum.EasingDirection.Out,
		pose = {
			rightShoulder = A(45, 30, -80),
			rightElbow = A(15, 0, 0),
			leftShoulder = A(42, -85, -53),
			leftElbow = A(33, 0, 0),
			waist = A(20, -80, 0),
			hips = A(0, -40, 0),
			neck = A(0, 75, 0),
		},
	},
	{ -- 2) Whip: hips fire, torso snaps through, bat sweeps through LEVEL at chest
		--    height, pointing straight out in front at contact.
		time = "SwingStrikeTime", style = Enum.EasingStyle.Quad, dir = Enum.EasingDirection.In,
		pose = {
			rightShoulder = A(-25, 108, -22),
			rightElbow = A(54, 0, 0),
			leftShoulder = A(14, 28, -60),
			leftElbow = A(140, 0, 0),
			waist = A(-15, 35, 0),
			hips = A(0, 25, 0),
			neck = A(0, -40, 0),
		},
	},
	{ -- 3) Follow-through: the bat keeps travelling FLAT around to the left and
		--    finishes level, extended out to the left side at shoulder height.
		--    (Kept within ~45 degrees of the strike so the bat sweeps around flat
		--    instead of flipping up over the top.)
		time = "SwingFollowTime", style = Enum.EasingStyle.Quad, dir = Enum.EasingDirection.Out,
		pose = {
			rightShoulder = A(-85, 122, 4),
			rightElbow = A(0, 0, 0),
			leftShoulder = A(139, -27, -34),
			leftElbow = A(116, 0, 0),
			waist = A(-10, 45, 0),
			hips = A(0, 28, 0),
			neck = A(0, -45, 0),
		},
	},
	{ -- 4) Recover, halfway: bat comes back up beside the head with both hands on it
		--    (keeps the arms together on the way back to the hold).
		time = "SwingRecoverMidTime", style = Enum.EasingStyle.Sine, dir = Enum.EasingDirection.In,
		pose = {
			rightShoulder = A(-47, 117, 82),
			rightElbow = A(0, 0, 0),
			leftShoulder = A(63, 18, 12),
			leftElbow = A(140, 0, 0),
			waist = A(-5, 22, 0),
			hips = A(0, 14, 0),
			neck = A(0, -22, 0),
		},
	},
	{ -- 5) Settle back into the holding pose
		time = "SwingRecoverTime", style = Enum.EasingStyle.Sine, dir = Enum.EasingDirection.Out,
		pose = HOLD,
	},
}

-- Blend two pose tables (used for in-between poses).
local function blendPose(p1, p2, alpha)
	local out = {}
	for k, v in p1 do out[k] = v:Lerp(p2[k] or CFrame.identity, alpha) end
	for k, v in p2 do if not out[k] then out[k] = CFrame.identity:Lerp(v, alpha) end end
	return out
end

-- The "slot": the whip's first instant, between the wind-up and contact. It makes the
-- bat sweep AROUND on a tilted plane instead of taking the short way over the top.
table.insert(KEYFRAMES, 2, {
	time = "SwingSlotTime", style = Enum.EasingStyle.Quad, dir = Enum.EasingDirection.In,
	pose = blendPose(KEYFRAMES[1].pose, KEYFRAMES[2].pose, 0.5), -- R15: halfway (its path was already flat)
})
KEYFRAMES[3].whip = true -- the cut: whoosh + trail start here
KEYFRAMES[3].style = Enum.EasingStyle.Linear -- contact: keep the bat speed up through the hit
KEYFRAMES[3].dir = Enum.EasingDirection.Out
KEYFRAMES[5].trailOff = true -- recovery starts: trail off

local states = {} -- [Model] = { id, joints = { {key, joint, value: CFrameValue} } }

local function getJoints(character)
	local joints = {}
	local function add(key, part, name)
		local p = character:FindFirstChild(part)
		local j = p and p:FindFirstChild(name)
		if j then joints[key] = j end
	end
	if character:FindFirstChild("UpperTorso") then -- R15
		add("rightShoulder", "RightUpperArm", "RightShoulder")
		add("rightElbow", "RightLowerArm", "RightElbow")
		add("leftShoulder", "LeftUpperArm", "LeftShoulder")
		add("leftElbow", "LeftLowerArm", "LeftElbow")
		add("waist", "UpperTorso", "Waist")
		add("hips", "LowerTorso", "Root")
		add("neck", "Head", "Neck")
	else -- R6
		add("rightShoulder", "Torso", "Right Shoulder")
		add("leftShoulder", "Torso", "Left Shoulder")
		add("neck", "Torso", "Neck")
		add("root", "HumanoidRootPart", "RootJoint")
		add("leftHip", "Torso", "Left Hip")
		add("rightHip", "Torso", "Right Hip")
	end
	return joints
end

-- Rotation of the joint's frame on its parent part (what Transform is relative to).
local function jointBaseRotation(joint)
	if joint:IsA("Motor6D") then
		return joint.C0.Rotation
	elseif joint:IsA("AnimationConstraint") and joint.Attachment0 then
		return joint.Attachment0.CFrame.Rotation
	end
	return nil
end

-- The "wrist": rotates the bat inside the right hand by offsetting the tool's grip weld.
local function applyWrist(character, state, offset)
	local hand = character:FindFirstChild("Right Arm") or character:FindFirstChild("RightHand")
	local weld = hand and hand:FindFirstChild("RightGrip")
	if weld ~= state.wristWeld then
		state.wristWeld = weld
		state.wristBase = weld and weld.C0
	end
	if weld and weld:IsA("Weld") and state.wristBase then
		weld.C0 = state.wristBase * offset
	end
end

-- R6: the idle animation has a "look around" variant that sways the arms. To keep the
-- swing identical every time, these joints use a FIXED base instead of the Animator's
-- pose: the arms always while the bat is held (base = the standard tool-holding pose),
-- the legs only during a swing (so walking/running still animate normally).
local R6_FIXED = {
	rightShoulder = { base = CFrame.Angles(0, 0, math.rad(90)), always = true },
	leftShoulder = { base = CFrame.identity, always = true }, -- two-handed: left hand stays on the bat
	leftHip = { base = CFrame.identity, always = false },
	rightHip = { base = CFrame.identity, always = false },
}

local SMOOTHING = 15 -- higher = follows the keyframes more tightly, lower = softer

local CRAWL_WRIST = CFrame.Angles(math.rad(-72), 0, 0)

-- Characters whose body animation is driven by CharacterAnimator: it writes the base
-- pose first and then calls BatSwing.ApplyLayer itself, so the order is always right.
local external = setmetatable({}, { __mode = "k" })
function BatSwing.SetExternal(character, on)
	external[character] = on or nil
end

-- Suspended: another animation (the ice pick rescue) owns the arms for now.
local suspended = setmetatable({}, { __mode = "k" })
function BatSwing.SetSuspended(character, on)
	suspended[character] = on or nil
end
function BatSwing.IsSuspended(character)
	return suspended[character] == true
end

-- Layer the bat hold / swing onto whatever pose the joints currently have.
function BatSwing.ApplyLayer(character)
	local state = states[character]
	if not state then return end
	if suspended[character] then
		state.lastT = os.clock()
		return
	end
	if not character.Parent then
		states[character] = nil
		return
	end
	if character:GetAttribute("Frozen") then return end -- frozen: hold the pose exactly
	-- Smoothing: every joint follows its target through a quick low-pass filter, so the
	-- swing flows through its keyframes instead of starting/stopping at each one (no jitter).
	local now = os.clock()
	local dt = math.clamp(now - (state.lastT or now), 0, 0.1)
	state.lastT = now
	local alpha = 1 - math.exp(-dt * (state.smoothing or SMOOTHING))
	-- Fade: the left arm / legs blend between Roblox's default animation and the swing pose
	-- (blendW 0 -> 1 -> 0) instead of snapping over in a single frame.
	local w = state.blendW.Value
	for _, entry in state.joints do
		local joint = entry.joint
		local baseRot = joint.Parent and jointBaseRotation(joint)
		if baseRot then
			entry.smooth = (entry.smooth or CFrame.identity):Lerp(entry.value.Value, alpha)
			local conv = baseRot:Inverse() * entry.smooth * baseRot
			local fixed = state.r6 and R6_FIXED[entry.key]
			if fixed and fixed.always then
				joint.Transform = conv * fixed.base
			elseif fixed and w > 0 then
				joint.Transform = conv * fixed.base:Lerp(joint.Transform, 1 - w)
			else
				joint.Transform = conv * joint.Transform
			end
		end
	end
	state.wristSmooth = (state.wristSmooth or CFrame.identity):Lerp(state.wrist.Value, alpha)
	applyWrist(character, state, state.wristSmooth)
end

RunService.PreSimulation:Connect(function()
	for character in states do
		if not external[character] then BatSwing.ApplyLayer(character) end
	end
end)

local function getState(character)
	local state = states[character]
	if state then return state end
	state = { id = 0, joints = {}, r6 = character:FindFirstChild("UpperTorso") == nil }
	state.blendW = Instance.new("NumberValue") -- 0..1: how much the swing owns the left arm / legs
	state.wrist = Instance.new("CFrameValue") -- never parented; just a tween target
	state.wrist.Value = CFrame.identity
	for key, joint in getJoints(character) do
		if jointBaseRotation(joint) then
			local value = Instance.new("CFrameValue") -- never parented; just a tween target
			value.Value = CFrame.identity
			table.insert(state.joints, { key = key, joint = joint, value = value })
		end
	end
	if #state.joints == 0 then return nil end
	states[character] = state
	return state
end

local function playWhoosh(parent)
	if not parent or Config.SwingSoundId == "" then return end
	local s = Instance.new("Sound")
	s.SoundId = Config.SwingSoundId
	s.Volume = Config.SwingVolume
	s.PlaybackSpeed = 1 + (math.random() - 0.5) * 0.1 -- slight variation so repeats don't sound identical
	s.RollOffMaxDistance = 70
	s.Parent = parent
	s:Play()
	game:GetService("Debris"):AddItem(s, 2)
end

local function tweenPose(state, pose, time, style, dir)
	local info = TweenInfo.new(time, style, dir)
	TweenService:Create(state.wrist, info, { Value = pose.wrist or CFrame.identity }):Play()
	for _, entry in state.joints do
		TweenService:Create(entry.value, info, { Value = pose[entry.key] or CFrame.identity }):Play()
	end
end

-- Bat equipped: ease into the two-handed holding pose.
function BatSwing.Equip(character)
	local state = getState(character)
	if not state then return end
	state.id += 1
	state.equipped = true
	tweenPose(state, state.r6 and HOLD_R6 or HOLD, 0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
end

-- Bat put away: ease back to normal and stop layering.
function BatSwing.Unequip(character)
	local state = states[character]
	if not state then return end
	state.id += 1
	state.equipped = false
	state.swinging = false
	local id = state.id
	tweenPose(state, {}, 0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	TweenService:Create(state.blendW, TweenInfo.new(0.2, Enum.EasingStyle.Sine), { Value = 0 }):Play()
	task.delay(0.2, function()
		if states[character] == state and state.id == id then
			states[character] = nil
		end
	end)
end

function BatSwing.Play(character)
	if not character or not character.Parent then return end
	if character:GetAttribute("Frozen") or suspended[character] then return end
	local state = getState(character)
	if not state then return end
	state.id += 1
	local id = state.id
	state.swinging = true
	TweenService:Create(state.blendW, TweenInfo.new(0.08, Enum.EasingStyle.Sine), { Value = 1 }):Play()

	local bat = character:FindFirstChild(Config.BatToolName)
	local handle = bat and bat:FindFirstChild("Handle")
	local trail = handle and handle:FindFirstChild("SwingTrail")

	task.spawn(function()
		local deadline = os.clock() -- keyframes are scheduled on absolute time so frame hitches don't stretch the swing
		for index, kf in KEYFRAMES do
			local duration = Config[kf.time]
			local style, dir = kf.style, kf.dir
			local pose = kf.pose
			state.smoothing = nil
			if state.r6 then
				pose = R6[index] or (index == #KEYFRAMES and HOLD_R6) or kf.pose
				local t = R6_TIMING[index]
				if t then duration, style, dir, state.smoothing = t[1], t[2], t[3], t[4] end
			end
			local lean = Config.SwingBodyLean or 1
			if state.r6 and lean ~= 1 and (pose.root or pose.neck) then
				local scaled = table.clone(pose)
				if pose.root then scaled.root = CFrame.identity:Lerp(pose.root, lean) end
				if pose.neck then scaled.neck = CFrame.identity:Lerp(pose.neck, lean) end
				pose = scaled
			end
			tweenPose(state, pose, duration, style, dir)
			if kf.whip then -- the whip: whoosh + trail on
				playWhoosh(handle or character:FindFirstChild("HumanoidRootPart"))
				if trail then trail.Enabled = true end
			elseif kf.trailOff and trail then -- follow-through done: trail off
				trail.Enabled = false
			end
			deadline += duration
			task.wait(math.max(0, deadline - os.clock() - 1 / 120))
			if state.id ~= id then -- a newer swing / unequip took over
				if trail and state.id ~= id then trail.Enabled = false end
				return
			end
		end
		if trail then trail.Enabled = false end
		if state.id == id then
			state.swinging = false
			state.smoothing = nil
			TweenService:Create(state.blendW, TweenInfo.new(0.25, Enum.EasingStyle.Sine), { Value = 0 }):Play()
		end
	end)
end

return BatSwing

-- RunAnimator: R6 run with bending knees, keyframed in Blender from a classic run-cycle sheet
-- (RunKnees_R6.blend, baked to 48 samples per cycle).
--   * contact: front leg long and almost straight, back heel kicked up behind
--   * down: the stance knee soaks up the landing, body at its lowest
--   * passing: the free foot tucks up under the hips
--   * up: the stance leg drives straight back, the knee punches forward, body at its highest
--   * reach: the free leg opens out forward for the next contact
--   * arms swing opposite the legs; the forward arm crosses in toward the other arm
-- Knees: R6 legs are single blocks, so every R6 character gets client-side two-piece legs
-- (thigh + shin) that replace the visible legs (see BEND LEGS below).
-- The cycle is locked to how far the character actually travels (no foot skating at any speed),
-- and the run fades in/out over Roblox's default animations
-- (idle, jump, fall, and the crouch/crawl/slide stances stay as they are).
-- The bat hold / swing (BatSwing) is layered on top every frame.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BatSwing = require(ReplicatedStorage.Shared.BatSwing)
local Config = require(ReplicatedStorage.Shared.FreezeConfig)

-- TUNING ----------------------------------------------------------------------
local STEP = 3.25 -- studs per step (one cycle = 2 steps); lower = quicker, choppier feet
local MIN_SPEED = 1.5 -- below this the default idle takes over
local FULL_AT = 7 -- speed at which the run is fully blended in
local FADE = 12 -- how quickly the run fades in / out
local BANK = 4 -- lean into turns (degrees per rad/s of turning)
local MAX_BANK = 12
local BEND_LEGS = true -- two-piece legs with knees (set false for plain one-piece R6 legs)
-------------------------------------------------------------------------------

local rad, clamp, floor = math.rad, math.clamp, math.floor
local function A(x, y, z) return CFrame.Angles(rad(x), rad(y), rad(z)) end

-- { rootY (studs), root xyz, neck xyz, rightShoulder xyz, leftShoulder xyz, rightHip xyz, leftHip xyz }
-- Angles in degrees, offsets in each joint's parent-part axes. Exported from Blender.
local SAMPLES = {
	{ -0.111, -11.2, -2.2, 1.7, 12.0, 3.4, -0.8, -40.7, 9.8, 17.3, 30.4, -18.5, 3.5, 43.2, 1.6, 1.0, -6.8, 1.6, -1.0, 8.0, 105.0 },
	{ -0.238, -11.5, -1.1, 1.8, 12.4, 2.6, -0.9, -35.4, 12.2, 17.1, 23.9, -17.6, 0.1, 39.6, 0.8, 1.0, -2.8, 0.8, -1.0, 13.3, 109.6 },
	{ -0.310, -11.8, 0.0, 1.9, 12.7, 1.7, -1.0, -29.0, 15.0, 16.1, 17.4, -16.3, -3.0, 35.2, 0.0, 1.0, 1.8, 0.0, -1.0, 25.0, 114.5 },
	{ -0.308, -11.9, 1.1, 2.0, 12.9, 0.9, -1.0, -21.6, 17.9, 14.4, 10.8, -14.6, -5.8, 30.5, -0.8, 1.0, 6.8, -0.8, -1.0, 36.7, 118.4 },
	{ -0.301, -12.0, 2.2, 2.0, 13.0, 0.0, -1.0, -13.3, 20.7, 11.8, 4.0, -12.8, -8.1, 26.0, -1.6, 1.0, 12.0, -1.6, -1.0, 42.0, 120.0 },
	{ -0.288, -11.9, 3.3, 2.0, 12.9, -0.9, -1.0, -4.2, 23.2, 8.2, -2.9, -10.7, -10.0, 21.9, -2.3, 1.0, 17.4, -2.3, -1.0, 42.0, 119.2 },
	{ -0.277, -11.8, 4.3, 1.9, 12.7, -1.7, -1.0, 5.5, 25.1, 3.7, -10.1, -8.7, -11.5, 18.0, -3.0, 1.0, 23.1, -3.0, -1.0, 41.8, 117.1 },
	{ -0.273, -11.5, 5.3, 1.8, 12.4, -2.6, -0.9, 15.6, 26.1, -1.4, -17.6, -6.7, -12.5, 13.9, -3.7, 1.0, 29.3, -3.7, -1.0, 41.2, 113.9 },
	{ -0.259, -11.2, 6.2, 1.7, 12.0, -3.4, -0.8, 25.7, 26.2, -6.8, -25.0, -4.8, -13.0, 9.2, -4.3, 1.0, 36.2, -4.3, -1.0, 40.0, 110.0 },
	{ -0.197, -10.9, 7.0, 1.6, 11.5, -4.1, -0.8, 35.2, 25.4, -11.9, -32.3, -3.2, -13.1, 3.7, -4.9, 1.0, 43.8, -4.9, -1.0, 34.5, 105.5 },
	{ -0.115, -10.5, 7.7, 1.4, 11.0, -4.8, -0.7, 43.7, 23.9, -16.6, -39.0, -2.0, -13.0, -2.3, -5.4, 1.0, 51.1, -5.4, -1.0, 24.2, 100.1 },
	{ -0.066, -10.1, 8.2, 1.2, 10.5, -5.4, -0.6, 51.0, 21.9, -20.4, -45.0, -1.0, -12.7, -8.4, -5.8, 1.0, 56.8, -5.8, -1.0, 14.4, 93.4 },
	{ -0.031, -9.8, 8.7, 1.0, 10.0, -6.0, -0.5, 56.9, 19.8, -23.2, -50.0, -0.4, -12.4, -14.2, -6.0, 1.0, 59.8, -6.0, -1.0, 10.0, 85.0 },
	{ 0.017, -9.5, 8.9, 0.7, 9.6, -6.4, -0.4, 61.2, 17.9, -25.1, -53.7, -0.1, -12.1, -19.3, -6.2, 1.0, 60.6, -6.2, -1.0, 11.0, 74.6 },
	{ 0.067, -9.2, 9.0, 0.5, 9.3, -6.7, -0.2, 64.0, 16.4, -26.2, -56.2, 0.0, -12.0, -23.4, -6.3, 1.0, 61.0, -6.3, -1.0, 14.2, 63.1 },
	{ 0.101, -9.1, 8.9, 0.2, 9.1, -6.9, -0.1, 65.6, 15.4, -26.4, -57.6, -0.1, -12.1, -26.0, -6.2, 1.0, 61.0, -6.2, -1.0, 20.4, 51.2 },
	{ 0.120, -9.0, 8.7, -0.0, 9.0, -7.0, -0.0, 66.0, 14.9, -26.0, -58.0, -0.3, -12.4, -27.0, -6.0, 1.0, 61.0, -6.0, -1.0, 30.0, 40.0 },
	{ 0.128, -9.1, 8.2, -0.2, 9.1, -6.9, 0.1, 65.1, 15.0, -24.9, -57.7, -0.8, -12.9, -26.2, -5.8, 1.0, 60.0, -5.8, -1.0, 43.2, 30.2 },
	{ 0.129, -9.2, 7.7, -0.5, 9.3, -6.7, 0.2, 62.7, 15.7, -23.1, -56.9, -1.4, -13.5, -24.1, -5.4, 1.0, 57.7, -5.4, -1.0, 58.2, 22.2 },
	{ 0.119, -9.5, 7.0, -0.7, 9.6, -6.4, 0.4, 59.0, 16.7, -20.6, -55.5, -2.2, -14.2, -21.2, -4.9, 1.0, 54.7, -4.9, -1.0, 72.8, 16.1 },
	{ 0.093, -9.8, 6.2, -1.0, 10.0, -6.0, 0.5, 54.3, 17.7, -17.7, -53.6, -3.2, -15.0, -18.2, -4.3, 1.0, 51.8, -4.3, -1.0, 85.0, 12.0 },
	{ 0.055, -10.1, 5.3, -1.2, 10.5, -5.4, 0.6, 48.8, 18.6, -14.3, -51.2, -4.4, -15.8, -15.5, -3.7, 1.0, 49.6, -3.7, -1.0, 93.1, 9.7 },
	{ 0.013, -10.5, 4.3, -1.4, 11.0, -4.8, 0.7, 42.8, 19.0, -10.7, -48.3, -5.9, -16.5, -12.9, -3.0, 1.0, 47.8, -3.0, -1.0, 98.1, 8.5 },
	{ -0.031, -10.9, 3.3, -1.6, 11.5, -4.1, 0.8, 36.7, 19.0, -7.1, -44.9, -7.7, -17.0, -10.1, -2.3, 1.0, 45.8, -2.3, -1.0, 101.5, 8.1 },
	{ -0.111, -11.2, 2.2, -1.7, 12.0, -3.4, 0.8, 30.4, 18.5, -3.5, -40.7, -9.8, -17.3, -6.8, -1.6, 1.0, 43.2, -1.6, -1.0, 105.0, 8.0 },
	{ -0.238, -11.5, 1.1, -1.8, 12.4, -2.6, 0.9, 23.9, 17.6, -0.1, -35.4, -12.2, -17.1, -2.8, -0.8, 1.0, 39.6, -0.8, -1.0, 109.6, 13.3 },
	{ -0.310, -11.8, 0.0, -1.9, 12.7, -1.7, 1.0, 17.4, 16.3, 3.0, -29.0, -15.0, -16.1, 1.8, 0.0, 1.0, 35.2, 0.0, -1.0, 114.5, 25.0 },
	{ -0.308, -11.9, -1.1, -2.0, 12.9, -0.9, 1.0, 10.8, 14.6, 5.8, -21.6, -17.9, -14.4, 6.8, 0.8, 1.0, 30.5, 0.8, -1.0, 118.4, 36.7 },
	{ -0.301, -12.0, -2.2, -2.0, 13.0, 0.0, 1.0, 4.0, 12.8, 8.1, -13.3, -20.7, -11.8, 12.0, 1.6, 1.0, 26.0, 1.6, -1.0, 120.0, 42.0 },
	{ -0.288, -11.9, -3.3, -2.0, 12.9, 0.9, 1.0, -2.9, 10.7, 10.0, -4.2, -23.2, -8.2, 17.4, 2.3, 1.0, 21.9, 2.3, -1.0, 119.2, 42.0 },
	{ -0.277, -11.8, -4.3, -1.9, 12.7, 1.7, 1.0, -10.1, 8.7, 11.5, 5.5, -25.1, -3.7, 23.1, 3.0, 1.0, 18.0, 3.0, -1.0, 117.1, 41.8 },
	{ -0.273, -11.5, -5.3, -1.8, 12.4, 2.6, 0.9, -17.6, 6.7, 12.5, 15.6, -26.1, 1.4, 29.3, 3.7, 1.0, 13.9, 3.7, -1.0, 113.9, 41.2 },
	{ -0.259, -11.2, -6.2, -1.7, 12.0, 3.4, 0.8, -25.0, 4.8, 13.0, 25.7, -26.2, 6.8, 36.2, 4.3, 1.0, 9.2, 4.3, -1.0, 110.0, 40.0 },
	{ -0.197, -10.9, -7.0, -1.6, 11.5, 4.1, 0.8, -32.3, 3.2, 13.1, 35.2, -25.4, 11.9, 43.8, 4.9, 1.0, 3.7, 4.9, -1.0, 105.5, 34.5 },
	{ -0.115, -10.5, -7.7, -1.4, 11.0, 4.8, 0.7, -39.0, 2.0, 13.0, 43.7, -23.9, 16.6, 51.1, 5.4, 1.0, -2.3, 5.4, -1.0, 100.1, 24.2 },
	{ -0.066, -10.1, -8.2, -1.2, 10.5, 5.4, 0.6, -45.0, 1.0, 12.7, 51.0, -21.9, 20.4, 56.8, 5.8, 1.0, -8.4, 5.8, -1.0, 93.4, 14.4 },
	{ -0.031, -9.8, -8.7, -1.0, 10.0, 6.0, 0.5, -50.0, 0.4, 12.4, 56.9, -19.8, 23.2, 59.8, 6.0, 1.0, -14.2, 6.0, -1.0, 85.0, 10.0 },
	{ 0.017, -9.5, -8.9, -0.7, 9.6, 6.4, 0.4, -53.7, 0.1, 12.1, 61.2, -17.9, 25.1, 60.6, 6.2, 1.0, -19.3, 6.2, -1.0, 74.6, 11.0 },
	{ 0.067, -9.2, -9.0, -0.5, 9.3, 6.7, 0.2, -56.2, 0.0, 12.0, 64.0, -16.4, 26.2, 61.0, 6.3, 1.0, -23.4, 6.3, -1.0, 63.1, 14.2 },
	{ 0.101, -9.1, -8.9, -0.2, 9.1, 6.9, 0.1, -57.6, 0.1, 12.1, 65.6, -15.4, 26.4, 61.0, 6.2, 1.0, -26.0, 6.2, -1.0, 51.2, 20.4 },
	{ 0.120, -9.0, -8.7, -0.0, 9.0, 7.0, -0.0, -58.0, 0.3, 12.4, 66.0, -14.9, 26.0, 61.0, 6.0, 1.0, -27.0, 6.0, -1.0, 40.0, 30.0 },
	{ 0.128, -9.1, -8.2, 0.2, 9.1, 6.9, -0.1, -57.7, 0.8, 12.9, 65.1, -15.0, 24.9, 60.0, 5.8, 1.0, -26.2, 5.8, -1.0, 30.2, 43.2 },
	{ 0.129, -9.2, -7.7, 0.5, 9.3, 6.7, -0.2, -56.9, 1.4, 13.5, 62.7, -15.7, 23.1, 57.7, 5.4, 1.0, -24.1, 5.4, -1.0, 22.2, 58.2 },
	{ 0.119, -9.5, -7.0, 0.7, 9.6, 6.4, -0.4, -55.5, 2.2, 14.2, 59.0, -16.7, 20.6, 54.7, 4.9, 1.0, -21.2, 4.9, -1.0, 16.1, 72.8 },
	{ 0.093, -9.8, -6.2, 1.0, 10.0, 6.0, -0.5, -53.6, 3.2, 15.0, 54.3, -17.7, 17.7, 51.8, 4.3, 1.0, -18.2, 4.3, -1.0, 12.0, 85.0 },
	{ 0.055, -10.1, -5.3, 1.2, 10.5, 5.4, -0.6, -51.2, 4.4, 15.8, 48.8, -18.6, 14.3, 49.6, 3.7, 1.0, -15.5, 3.7, -1.0, 9.7, 93.1 },
	{ 0.013, -10.5, -4.3, 1.4, 11.0, 4.8, -0.7, -48.3, 5.9, 16.5, 42.8, -19.0, 10.7, 47.8, 3.0, 1.0, -12.9, 3.0, -1.0, 8.5, 98.1 },
	{ -0.031, -10.9, -3.3, 1.6, 11.5, 4.1, -0.8, -44.9, 7.7, 17.0, 36.7, -19.0, 7.1, 45.8, 2.3, 1.0, -10.1, 2.3, -1.0, 8.1, 101.5 },
}
local N = #SAMPLES

-- Pre-build the pose CFrames for every sample (knees stay as plain angles).
local POSES = table.create(N)
for i, s in SAMPLES do
	POSES[i] = {
		root = CFrame.new(0, s[1], 0) * A(s[2], s[3], s[4]),
		neck = A(s[5], s[6], s[7]),
		rightShoulder = A(s[8], s[9], s[10]),
		leftShoulder = A(s[11], s[12], s[13]),
		rightHip = A(s[14], s[15], s[16]),
		leftHip = A(s[17], s[18], s[19]),
		kneeR = s[20] or 0,
		kneeL = s[21] or 0,
	}
end
local KEYS = { "root", "neck", "rightShoulder", "leftShoulder", "rightHip", "leftHip" }

local RUN_STATES = {
	[Enum.HumanoidStateType.Running] = true,
	[Enum.HumanoidStateType.RunningNoPhysics] = true,
}

local rigs = {} -- [Model] = rig

-- phase 0..1 over one full cycle (two steps), smoothly between the baked samples
local function sampleCycle(phase)
	local x = (phase % 1) * N
	local i0 = floor(x)
	local a = x - i0
	local p0, p1 = POSES[i0 + 1], POSES[(i0 + 1) % N + 1]
	local out = {}
	for _, k in KEYS do out[k] = p0[k]:Lerp(p1[k], a) end
	out.kneeR = p0.kneeR + (p1.kneeR - p0.kneeR) * a
	out.kneeL = p0.kneeL + (p1.kneeL - p0.kneeL) * a
	return out
end

--------------------------------------------------------------------------------
-- BEND LEGS: R6 legs are single blocks, so each client gives every R6 character a
-- two-piece leg (thigh + shin, joined by a knee) that sits exactly where the real leg is.
-- The real legs are hidden locally; the thigh copies the real hip motion every frame
-- (so idle / jump / fall / bat / ice pick poses all still work) and the run adds knee bend.
-- The leg's colour, material and Pants texture are copied onto the new pieces.
--------------------------------------------------------------------------------
local TEMPLATE_W, TEMPLATE_H = 585, 559 -- classic clothing template size
local PX_PER_STUD = 64 -- a leg face is 64 px wide (1 stud) and 128 px tall (2 studs)
local PANTS_FACES = { -- top-left pixel of each face of the leg on the Pants template
	Right = { Front = { 217, 355 }, Back = { 85, 355 }, Left = { 151, 355 }, Right = { 19, 355 } },
	Left = { Front = { 308, 355 }, Back = { 440, 355 }, Left = { 374, 355 }, Right = { 506, 355 } },
}

local function applyPants(part, template, side, half)
	for _, t in part:GetChildren() do
		if t:IsA("Texture") then t:Destroy() end
	end
	if not template or template == "" then return end
	for faceName, xy in PANTS_FACES[side] do
		local tex = Instance.new("Texture")
		tex.Name = "Pants" .. faceName
		tex.Texture = template
		tex.Face = Enum.NormalId[faceName]
		tex.StudsPerTileU = TEMPLATE_W / PX_PER_STUD
		tex.StudsPerTileV = TEMPLATE_H / PX_PER_STUD
		tex.OffsetStudsU = xy[1] / PX_PER_STUD
		tex.OffsetStudsV = (xy[2] + half * PX_PER_STUD) / PX_PER_STUD
		tex.Parent = part
	end
end

local function buildBendLegs(rig)
	local char = rig.char
	local torso = char:FindFirstChild("Torso")
	if not torso then return end
	local model = Instance.new("Model")
	model.Name = "BendLegs"
	local bend = { model = model, sides = {} }
	for _, side in { "Right", "Left" } do
		local leg = char:FindFirstChild(side .. " Leg")
		local hip = rig.joints[side == "Right" and "rightHip" or "leftHip"].joint
		if not leg then model:Destroy() return end
		local function piece(name)
			local p = Instance.new("Part")
			p.Name = name
			p.Size = Vector3.new(1, 1, 1)
			p.Color = leg.Color
			p.Material = leg.Material
			p.TopSurface = Enum.SurfaceType.Smooth
			p.BottomSurface = Enum.SurfaceType.Smooth
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
			p.CFrame = leg.CFrame
			p.Parent = model
			return p
		end
		local thigh, shin = piece(side .. " Thigh"), piece(side .. " Shin")
		local hipMotor = Instance.new("Motor6D")
		hipMotor.Name = side .. " BendHip"
		hipMotor.Part0 = torso
		hipMotor.Part1 = thigh
		hipMotor.C0 = hip.C0
		-- the hip sits 1 stud above the leg's centre, but only 0.5 above the thigh's centre
		hipMotor.C1 = CFrame.new(hip.C1.X, hip.C1.Y - 0.5, hip.C1.Z) * hip.C1.Rotation
		hipMotor.Parent = thigh
		local knee = Instance.new("Motor6D")
		knee.Name = side .. " Knee"
		knee.Part0 = thigh
		knee.Part1 = shin
		-- hinge on the front edge so the kneecap stays closed when the shin swings back
		knee.C0 = CFrame.new(0, -0.5, -0.5)
		knee.C1 = CFrame.new(0, 0.5, -0.5)
		knee.Parent = shin
		bend.sides[side] = { leg = leg, hip = hip, hipMotor = hipMotor, knee = knee, thigh = thigh, shin = shin, bend = 0 }
	end
	rig.bend = bend
	local function refreshClothes()
		if rig.bend ~= bend then return end
		local pants = char:FindFirstChildOfClass("Pants")
		local template = pants and pants.PantsTemplate or nil
		for side, s in bend.sides do
			applyPants(s.thigh, template, side, 0)
			applyPants(s.shin, template, side, 1)
		end
	end
	refreshClothes()
	char.ChildAdded:Connect(function(c) if c:IsA("Pants") then task.defer(refreshClothes) end end)
	char.ChildRemoved:Connect(function(c) if c:IsA("Pants") then task.defer(refreshClothes) end end)
	model.Parent = char
end

local function removeBendLegs(rig)
	if not rig.bend then return end
	for _, s in rig.bend.sides do
		if s.leg.Parent then s.leg.LocalTransparencyModifier = 0 end
	end
	rig.bend.model:Destroy()
	rig.bend = nil
end

-- Called last every frame: copy the real hips onto the thighs, add the knee bend, keep the
-- real legs hidden and the new pieces matching the body (colour, first-person fade).
local function updateBendLegs(rig)
	local b = rig.bend
	if not b then return end
	local torso = rig.char:FindFirstChild("Torso")
	local fade = torso and torso.LocalTransparencyModifier or 0
	local frozen = rig.char:GetAttribute("Frozen")
	for side, s in b.sides do
		if not (s.hip.Parent and s.thigh.Parent) then continue end
		s.hipMotor.Transform = s.hip.Transform
		if not frozen then
			local target = 0
			if rig.pose and rig.weight > 0.001 then
				target = (side == "Right" and rig.pose.kneeR or rig.pose.kneeL) * rig.weight
			end
			s.bend = target
		end
		s.knee.Transform = CFrame.Angles(-rad(s.bend), 0, 0) -- + bend swings the foot back
		s.leg.LocalTransparencyModifier = 1
		s.thigh.LocalTransparencyModifier = fade
		s.shin.LocalTransparencyModifier = fade
		if s.thigh.Color ~= s.leg.Color then
			s.thigh.Color = s.leg.Color
			s.shin.Color = s.leg.Color
		end
	end
end

local function buildRig(char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local torso = char:FindFirstChild("Torso")
	if not (hum and hrp and torso) then return nil end
	local joints = {
		root = hrp:FindFirstChild("RootJoint"),
		neck = torso:FindFirstChild("Neck"),
		rightShoulder = torso:FindFirstChild("Right Shoulder"),
		leftShoulder = torso:FindFirstChild("Left Shoulder"),
		rightHip = torso:FindFirstChild("Right Hip"),
		leftHip = torso:FindFirstChild("Left Hip"),
	}
	local list = {}
	for key, j in joints do
		if not (j and j:IsA("Motor6D")) then return nil end
		local r = j.C0.Rotation
		list[key] = { joint = j, r = r, rInv = r:Inverse() }
	end
	BatSwing.SetExternal(char, true) -- this script calls BatSwing.ApplyLayer after posing
	local rig = { char = char, hum = hum, hrp = hrp, joints = list, phase = 0, weight = 0, speed = 0, bank = 0, pose = nil }
	if BEND_LEGS then
		buildBendLegs(rig)
		hum.Died:Connect(function() removeBendLegs(rig) end)
	end
	return rig
end

RunService.PreSimulation:Connect(function(dt)
	for char, rig in rigs do
		if not char.Parent or not rig.hrp.Parent then
			rigs[char] = nil
			continue
		end
		if not char:GetAttribute("Frozen") then
			local v = rig.hrp.AssemblyLinearVelocity
			local raw = Vector3.new(v.X, 0, v.Z).Magnitude
			rig.speed += (raw - rig.speed) * math.min(1, dt * 10) -- smoothed: no stutter in turns / bumps
			local stance = char:GetAttribute("Stance")
			local running = RUN_STATES[rig.hum:GetState()] and (stance == nil or stance == "Stand") and rig.speed > MIN_SPEED
			local target = running and clamp((rig.speed - MIN_SPEED) / (FULL_AT - MIN_SPEED), 0, 1) or 0
			rig.weight += (target - rig.weight) * (1 - math.exp(-dt * FADE))
			if running then
				rig.phase = (rig.phase + dt * rig.speed / (2 * STEP)) % 1 -- locked to distance travelled
			end
			local turn = clamp(rig.hrp.AssemblyAngularVelocity.Y * BANK, -MAX_BANK, MAX_BANK)
			rig.bank += (turn - rig.bank) * math.min(1, dt * 6)
			if rig.weight > 0.001 then
				local pose = sampleCycle(rig.phase)
				pose.root = pose.root * CFrame.Angles(0, 0, rad(rig.bank)) -- lean into turns
				rig.pose = pose
			end
		end
		-- blend the run over whatever the default Animate produced this frame
		-- (frozen: the default tracks are paused and the last run pose is held)
		if rig.weight > 0.001 and rig.pose then
			for key, j in rig.joints do
				if j.joint.Parent then
					local runT = j.rInv * rig.pose[key] * j.r
					j.joint.Transform = if rig.weight >= 0.999 then runT else j.joint.Transform:Lerp(runT, rig.weight)
				end
			end
		end
		BatSwing.ApplyLayer(char) -- bat hold / swing on top
		-- BatSwing pins the arms to the torso; tilt them back up by the current lean so the bat stays upright.
		if rig.weight > 0.001 and rig.pose and char:FindFirstChild(Config.BatToolName) and not BatSwing.IsSuspended(char) then
			local lean = rig.pose.root:ToEulerAnglesXYZ() -- radians, negative = leaning forward
			local counter = CFrame.Angles(-lean * rig.weight, 0, 0)
			for _, key in { "rightShoulder", "leftShoulder" } do
				local j = rig.joints[key]
				if j.joint.Parent then j.joint.Transform = j.rInv * counter * j.r * j.joint.Transform end
			end
		end
		updateBendLegs(rig)
	end
end)

local function track(char)
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum or hum.RigType ~= Enum.HumanoidRigType.R6 then return end
	char:WaitForChild("HumanoidRootPart", 10)
	local torso = char:WaitForChild("Torso", 10)
	if torso then
		for _, n in { "Neck", "Right Shoulder", "Left Shoulder", "Right Hip", "Left Hip" } do torso:WaitForChild(n, 5) end
	end
	char:WaitForChild("Right Leg", 5)
	char:WaitForChild("Left Leg", 5)
	local rig = buildRig(char)
	if rig then rigs[char] = rig end
end

local function watchPlayer(player)
	player.CharacterAdded:Connect(function(char) task.spawn(track, char) end)
	if player.Character then task.spawn(track, player.Character) end
end
Players.PlayerAdded:Connect(watchPlayer)
for _, p in Players:GetPlayers() do watchPlayer(p) end

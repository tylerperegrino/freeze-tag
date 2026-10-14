-- MovementController: crouch / crawl / slide input. The server decides; this just asks.
--   Crouch: C  (controller B, on-screen button on mobile)  - toggles
--           ...pressed while RUNNING fast = slide instead
--   Crawl:  Z  (controller Y, on-screen button on mobile)  - toggles
--   Jump while crouched or crawling stands you back up.
-- The slide's speed burst is applied here (the player's own client owns their physics):
-- it eases from SlideStartSpeed down to SlideEndSpeed over the slide.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.FreezeConfig)
local MovementRequest = ReplicatedStorage.Remotes.MovementRequest
local player = Players.LocalPlayer

local function currentStance()
	local char = player.Character
	return char and char:GetAttribute("Stance") or "Stand"
end

local function request(stance)
	local char = player.Character
	if not char or char:GetAttribute("Frozen") then return end
	MovementRequest:FireServer(stance)
end

local function horizontalSpeed()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return 0 end
	local v = root.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z).Magnitude
end

local function onCrouch(_, state)
	if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
	local stance = currentStance()
	if stance == "Stand" and horizontalSpeed() >= Config.SlideMinSpeed then
		request("Slide")
	elseif stance ~= "Slide" then
		request(stance == "Crouch" and "Stand" or "Crouch")
	end
	return Enum.ContextActionResult.Sink
end

-- Slide burst: when the server confirms the slide, push the character along the ground.
local RunService = game:GetService("RunService")
local function startSlideBurst(char)
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local v = root.AssemblyLinearVelocity
	local dir = Vector3.new(v.X, 0, v.Z)
	if dir.Magnitude < 1 then dir = root.CFrame.LookVector * Vector3.new(1, 0, 1) end
	dir = dir.Unit
	local att = Instance.new("Attachment")
	att.Name = "SlideAttachment"
	att.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Name = "SlideVelocity"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane -- only along the ground; gravity still works
	lv.PrimaryTangentAxis = Vector3.xAxis
	lv.SecondaryTangentAxis = Vector3.zAxis
	lv.MaxForce = 1e6
	lv.Parent = root
	local t0 = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local a = math.clamp((os.clock() - t0) / Config.SlideDuration, 0, 1)
		local eased = 1 - (1 - a) ^ 2 -- loses speed quickly at first, then glides (friction)
		local speed = Config.SlideStartSpeed + (Config.SlideEndSpeed - Config.SlideStartSpeed) * eased
		lv.PlaneVelocity = Vector2.new(dir.X * speed, dir.Z * speed)
		if a >= 1 or char:GetAttribute("Stance") ~= "Slide" or not lv.Parent then
			conn:Disconnect()
			lv:Destroy()
			att:Destroy()
		end
	end)
end

local function watchSlide(char)
	char:GetAttributeChangedSignal("Stance"):Connect(function()
		if char:GetAttribute("Stance") == "Slide" then startSlideBurst(char) end
	end)
end
player.CharacterAdded:Connect(watchSlide)
if player.Character then watchSlide(player.Character) end

local function onCrawl(_, state)
	if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
	request(currentStance() == "Crawl" and "Stand" or "Crawl")
	return Enum.ContextActionResult.Sink
end

ContextActionService:BindAction("FreezeCrouch", onCrouch, true, Config.CrouchKey, Config.CrouchButton)
ContextActionService:SetTitle("FreezeCrouch", "Crouch")
ContextActionService:SetPosition("FreezeCrouch", UDim2.new(1, -170, 1, -150))
ContextActionService:BindAction("FreezeCrawl", onCrawl, true, Config.CrawlKey, Config.CrawlButton)
ContextActionService:SetTitle("FreezeCrawl", "Crawl")
ContextActionService:SetPosition("FreezeCrawl", UDim2.new(1, -230, 1, -90))

UserInputService.JumpRequest:Connect(function()
	if currentStance() ~= "Stand" then request("Stand") end
end)

-- MovementService (server-authoritative stances)
-- Clients ask for a stance ("Stand" / "Crouch" / "Crawl"); the server validates it,
-- stores it as the character attribute "Stance" (so every client can animate it)
-- and sets WalkSpeed / JumpHeight. Frozen players can't change stance.
-- While prone, the Torso and Head stop colliding with the world so the body lying on
-- the floor doesn't snag or jitter (the HumanoidRootPart still collides as normal).
-- NOTE: the hitbox is still standing-height, so crouch/crawl don't yet fit under low
-- gaps or vents - that's the movement-phase hitbox work.
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.FreezeConfig)
local MovementRequest = ReplicatedStorage.Remotes.MovementRequest

local MovementService = {}

local PRONE_GROUP = "ProneBody"
local VALID = { Stand = true, Crouch = true, Crawl = true, Slide = true }
local SPEED = { Stand = Config.WalkSpeed, Crouch = Config.CrouchSpeed, Crawl = Config.CrawlSpeed, Slide = Config.SlideEndSpeed }
local lastRequest = {} -- [Player] = os.clock()
local lastSlide = {} -- [Player] = os.clock() when their last slide started

pcall(function() PhysicsService:RegisterCollisionGroup(PRONE_GROUP) end)
PhysicsService:CollisionGroupSetCollidable(PRONE_GROUP, "Default", false)

local function setBodyCollision(char, prone)
	for _, name in { "Torso", "Head" } do
		local part = char:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			part.CollisionGroup = prone and PRONE_GROUP or "Default"
		end
	end
end

function MovementService.SetStance(char, stance)
	if not VALID[stance] then return false end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return false end
	if char:GetAttribute("Frozen") or char:GetAttribute("RoundLocked") then return false end
	char:SetAttribute("Stance", stance)
	hum.WalkSpeed = SPEED[stance]
	hum.JumpHeight = stance == "Stand" and 7.2 or 0
	hum.JumpPower = stance == "Stand" and 50 or 0
	setBodyCollision(char, stance == "Crawl" or stance == "Slide")
	return true
end

-- Slide: only from a standing run that's actually fast (server reads the real velocity),
-- not while frozen, and not again until the cooldown is over. Ends itself in a crouch.
local function trySlide(player, char)
	if char:GetAttribute("Stance") ~= "Stand" or char:GetAttribute("Frozen") then return end
	local now = os.clock()
	if lastSlide[player] and now - lastSlide[player] < Config.SlideDuration + Config.SlideCooldown then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local v = root.AssemblyLinearVelocity
	if Vector3.new(v.X, 0, v.Z).Magnitude < Config.SlideMinSpeed - 1 then return end
	if not MovementService.SetStance(char, "Slide") then return end
	lastSlide[player] = now
	task.delay(Config.SlideDuration, function()
		if char.Parent and char:GetAttribute("Stance") == "Slide" then
			MovementService.SetStance(char, "Crouch")
		end
	end)
end

MovementRequest.OnServerEvent:Connect(function(player, stance)
	if typeof(stance) ~= "string" or not VALID[stance] then return end
	local t = os.clock()
	if lastRequest[player] and t - lastRequest[player] < 0.15 then return end -- spam guard
	lastRequest[player] = t
	local char = player.Character
	if not char or char:GetAttribute("Stance") == stance then return end
	if stance == "Slide" then return trySlide(player, char) end
	if char:GetAttribute("Stance") == "Slide" then return end -- a slide always finishes on its own
	MovementService.SetStance(char, stance)
end)

local function onCharacter(char)
	char:SetAttribute("Stance", "Stand")
	local hum = char:WaitForChild("Humanoid", 10)
	if hum then hum.WalkSpeed = Config.WalkSpeed end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(onCharacter)
end)
for _, player in Players:GetPlayers() do
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then task.spawn(onCharacter, player.Character) end
end
Players.PlayerRemoving:Connect(function(player)
	lastRequest[player] = nil
	lastSlide[player] = nil
end)

return MovementService

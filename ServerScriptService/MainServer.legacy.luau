-- MainServer: boots services and wires remotes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local FreezeService = require(ServerScriptService.Services.FreezeService)
local DataManager = require(ServerScriptService.Data.DataManager)
require(ServerScriptService.Services.MovementService) -- crouch / crawl stances
local Config = require(ReplicatedStorage.Shared.FreezeConfig)
local Remotes = ReplicatedStorage.Remotes
local BatTemplate = ServerStorage.Tools:WaitForChild(Config.BatToolName)

-- Client -> Server: "I swung the bat." No arguments are trusted.
Remotes.FreezeRequest.OnServerEvent:Connect(function(player)
	local ok, result = FreezeService.Swing(player)
	if ok then
		DataManager.AwardTag(player)
		print(`[Freeze] {player.Name} bonked {result.Name}`)
	end
end)

-- Freezers get a bat; anyone else loses theirs.
local function findBat(player)
	local char = player.Character
	return (char and char:FindFirstChild(Config.BatToolName))
		or player.Backpack:FindFirstChild(Config.BatToolName)
end

local function refreshBat(player)
	local isFreezer = player:GetAttribute("Role") == "Freezer"
	local bat = findBat(player)
	if isFreezer and not bat and player.Character then
		local newBat = BatTemplate:Clone()
		newBat.Parent = player.Backpack
		local hum = player.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum:EquipTool(newBat) end -- start with it in hand
	elseif not isFreezer and bat then
		bat:Destroy()
	end
end

local function onPlayer(player)
	player:GetAttributeChangedSignal("Role"):Connect(function() refreshBat(player) end)
	player.CharacterAdded:Connect(function(char)
		char:WaitForChild("Humanoid")
		player:WaitForChild("Backpack")
		refreshBat(player)
	end)
	if player.Character then
		task.spawn(refreshBat, player)
	end
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do onPlayer(p) end

print("[MainServer] FreezeService ready")

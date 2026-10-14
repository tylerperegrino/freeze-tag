-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- ProfileStore
local ProfileStore = require(ServerScriptService.Libraries.ProfileStore)

local function GetStoreName()
	return RunService:IsStudio() and "Test" or "Live"
end

local Template = require(ServerScriptService.Data.Template)
local DataManager = require(ServerScriptService.Data.DataManager)
-- Access profile store
local PlayerStore = ProfileStore.New(GetStoreName(),Template)

-- Add leader stats and synchronize player data
local function Initialize(player: Player, profile: typeof(PlayerStore:StartSessionAsync()))

	--Leaderstats
	local leaderstats = Instance.new("Folder", player)
	leaderstats.Name = "leaderstats"
	
	local Level = Instance.new("IntValue", leaderstats)
	Level.Name = "Level"
	Level.Value = profile.Data.Level
	
	local Wins = Instance.new("IntValue", leaderstats)
	Wins.Name = "Wins"
	Wins.Value = profile.Data.Wins
	
	local tags = Instance.new("IntValue", leaderstats)
	tags.Name = "Tags"
	tags.Value = profile.Data.Tags
	
	local Exp = Instance.new("IntValue", player)
	Exp.Name = "Exp"
	Exp.Value = profile.Data.Exp
	
	local currencies = Instance.new("Folder")
	currencies.Name = "Currencies"
	currencies.Parent = player

	local Gems = Instance.new("NumberValue", currencies)
	Gems.Name = "Gems"
	Gems.Value = profile.Data.Gems

	local Coins = Instance.new("NumberValue", currencies)
	Coins.Name = "Coins"
	Coins.Value = profile.Data.Coins
end


-- Creates and store a profile
local function PlayerAdded(player: Player)

	-- Start a new profile session
	local profile = PlayerStore:StartSessionAsync("Player_" .. player.UserId, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	-- Sanity check to ensure profile exists
	if profile ~= nil then

		profile:AddUserId(player.UserId) -- GDPR compliance
		profile:Reconcile() -- Fill in missing data variables from template

		-- Handles session-locking
		profile.OnSessionEnd:Connect(function()
			DataManager.Profiles[player] = nil
			player:Kick("Data error occured. Please rejoin.")
		end)

		if player.Parent == Players then

			DataManager.Profiles[player] = profile	
			Initialize(player, profile)
		else
			-- Player left before the profile session started
			profile:EndSession()
		end


	else
		-- Server shuts down while player is joining
		player:Kick("Data error occured. Please rejoin.")
	end

end

-- Early joiners
for _, player in Players:GetPlayers() do
	task.spawn(PlayerAdded, player)
end

Players.PlayerAdded:Connect(PlayerAdded)

Players.PlayerRemoving:Connect(function(player)
	local profile = DataManager.Profiles[player]
	if not profile then return end
	profile:EndSession()
	DataManager.Profiles[player] = nil
end)
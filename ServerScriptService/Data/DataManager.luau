local DataManager = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LevelConfig = require(ReplicatedStorage.Shared.LevelConfig)

-- Store profiles from playerstore
DataManager.Profiles = {}

function DataManager.AddGems(player: Player, amount: number)
	local profile = DataManager.Profiles[player]
	if not profile then warn("No profile found") return end

	profile.Data.Gems += amount
	player.Currencies.Gems.Value = profile.Data.Gems
end

function DataManager.AddCoins(player: Player, amount: number)
	local profile = DataManager.Profiles[player]
	if not profile then warn("No profile found") return end

	profile.Data.Coins += amount
	player.Currencies.Coins.Value = profile.Data.Coins
end

function DataManager.AwardTag(player : Player)
	local profile = DataManager.Profiles[player]
	if not profile then return end

	profile.Data.Tags += 1
	profile.Data.Exp += 10
	
	local requiredExp = LevelConfig.GetRequiredExp(profile.Data.Level)

	while profile.Data.Exp >= requiredExp do
		profile.Data.Exp -= requiredExp
		profile.Data.Level += 1
		requiredExp = LevelConfig.GetRequiredExp(profile.Data.Level)
	end
	
	player.leaderstats.Level.Value = profile.Data.Level	
	
	player.leaderstats.Tags.Value = profile.Data.Tags
	player.Exp.Value = profile.Data.Exp
end

return DataManager
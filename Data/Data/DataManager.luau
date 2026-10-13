local DataManager = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Store profiles from playerstore
DataManager.Profiles = {}

function DataManager.AddGems(player: Player, amount: number)
	local profile = DataManager.Profiles[player]
	if not profile then warn("No profile found") return end

	profile.Data.Gems += amount
	player.leaderstats.Gems.Value = profile.Data.Gems
end

function DataManager.AddCoins(player: Player, amount: number)
	local profile = DataManager.Profiles[player]
	if not profile then warn("No profile found") return end

	profile.Data.Coins += amount
	player.leaderstats.Coins.Value = profile.Data.Coins
end

return DataManager
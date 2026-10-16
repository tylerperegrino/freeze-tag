local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LevelConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LevelConfig"))
local Player = game.Players.LocalPlayer

local currencies = Player:WaitForChild("Currencies")
local leaderstats = Player:WaitForChild("leaderstats")

local WinsStat = leaderstats:WaitForChild("Wins")
local CoinsLeaderstat = currencies:WaitForChild("Coins")
local GemsLeaderstat = currencies:WaitForChild("Gems")

local Main = script.Parent
local StatsFrame = Main:WaitForChild("Stats")
local Currencies = Main:WaitForChild("Currencies")
local CoinFrame = Currencies:WaitForChild("Coins")
local GemFrame = Currencies:WaitForChild("Gems")
local WinsLabel = StatsFrame:WaitForChild("Wins")

local function updateCurrency(Currency: string, Amount: number)
	if Currency == "Coins" then
		CoinFrame.Amount.Text = Amount
	elseif Currency == "Gems" then
		GemFrame.Amount.Text = Amount
	end
end

CoinsLeaderstat.Changed:Connect(function()
	updateCurrency("Coins", CoinsLeaderstat.Value)
end)

GemsLeaderstat.Changed:Connect(function()
	updateCurrency("Gems", GemsLeaderstat.Value)
end)

updateCurrency("Coins", CoinsLeaderstat.Value)
updateCurrency("Gems", GemsLeaderstat.Value)

local function updateWins()
	WinsLabel.Text = tostring(WinsStat.Value) .. " Wins"
end

WinsStat.Changed:Connect(updateWins)
updateWins()

local TagsStat = leaderstats:WaitForChild("Tags")
local TagsLabel = StatsFrame:WaitForChild("Tags")

local function updateTags()
	TagsLabel.Text = tostring(TagsStat.Value) .. " Tags"
end

TagsStat.Changed:Connect(updateTags)
updateTags()

local LevelStat = leaderstats:WaitForChild("Level")
local Levellabel = Main:WaitForChild("Level")

local function updateLevel()
	Levellabel.Text = "Level " .. tostring(LevelStat.Value)	
end

LevelStat.Changed:Connect(updateLevel)
updateLevel()

local ExpStat = Player:WaitForChild("Exp")
local XPLabel = Main:WaitForChild("XP")
local XPFill = Main:WaitForChild("XPBar"):WaitForChild("Fill")

local function updateXP()
	local XPGoal = LevelConfig.GetRequiredExp(LevelStat.Value)
	XPLabel.Text = tostring(ExpStat.Value) .. "/" .. tostring(XPGoal)
	local progress = math.clamp(ExpStat.Value / XPGoal, 0, 1)
	XPFill.Size = UDim2.fromScale(progress, 1)
end

ExpStat.Changed:Connect(updateXP)
LevelStat.Changed:Connect(updateXP)
updateXP()

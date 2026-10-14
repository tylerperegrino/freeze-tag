-- TEST ONLY — delete or disable once real team assignment (MatchService/TeamService) exists.
-- Makes every player a Freezer. Frozen dummies now stay frozen until someone holds E on them
-- (FreezeConfig.TestAnyoneCanRescue lets you, a Freezer, do that while testing solo).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.FreezeConfig)

local function setup(player)
	player:SetAttribute("Role", "Freezer")
end
Players.PlayerAdded:Connect(setup)
for _, p in Players:GetPlayers() do setup(p) end

print("[TestBootstrap] Players are Freezers; freezes last until rescued (hold E). Anyone can rescue in test:", Config.TestAnyoneCanRescue)

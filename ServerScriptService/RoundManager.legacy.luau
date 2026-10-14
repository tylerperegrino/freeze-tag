local Players = game:GetService("Players") -- gets the service that tracks player
local ReplicatedStorage = game:GetService("ReplicatedStorage") -- gets shared storage

local MIN_PLAYERS = 2 -- minimum players needed to start
local intermission = 10 -- countdown length

local StatusValue = Instance.new("StringValue") -- Creates an object that holds text
StatusValue.Name = "RoundStatus" -- Names it so clients can find it.
StatusValue.Value = "Waiting for players... " .. #Players:GetPlayers() .. "/" .. MIN_PLAYERS -- waiting for players message
StatusValue.Parent = ReplicatedStorage -- Puts it in a place where clients can find it.	

local function updatePlayerCount()
	StatusValue.Value = "Waiting for players... " .. #Players:GetPlayers() .. "/" .. MIN_PLAYERS -- updates the text
end

Players.PlayerAdded:Connect(updatePlayerCount)
updatePlayerCount()
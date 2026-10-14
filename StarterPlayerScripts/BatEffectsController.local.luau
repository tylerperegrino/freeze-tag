-- BatEffectsController:
--  * puts every character holding a bat (you and everyone else) into the two-handed hold pose
--  * plays OTHER players' swings when the server announces them
-- (Your own swing is played instantly by the bat's BatClient script.)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BatSwing = require(ReplicatedStorage.Shared.BatSwing)
local Config = require(ReplicatedStorage.Shared.FreezeConfig)
local FreezeEvent = ReplicatedStorage.Remotes.FreezeEvent

FreezeEvent.OnClientEvent:Connect(function(kind, character)
	if kind == "Swing" and typeof(character) == "Instance" then
		BatSwing.Play(character)
	end
end)

local function isBat(child)
	return child:IsA("Tool") and child.Name == Config.BatToolName
end

local function watchCharacter(character)
	character.ChildAdded:Connect(function(child)
		if isBat(child) then BatSwing.Equip(character) end
	end)
	character.ChildRemoved:Connect(function(child)
		if isBat(child) then BatSwing.Unequip(character) end
	end)
	for _, child in character:GetChildren() do
		if isBat(child) then
			-- wait for the right torso for this rig (R6 has "Torso", R15 has "UpperTorso")
			local hum = character:WaitForChild("Humanoid", 5)
			local torsoName = (hum and hum.RigType == Enum.HumanoidRigType.R6) and "Torso" or "UpperTorso"
			character:WaitForChild(torsoName, 5)
			-- only hold the bat if it's still in hand (it may have been put away meanwhile)
			if child.Parent == character then BatSwing.Equip(character) end
		end
	end
end

local function watchPlayer(player)
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then task.spawn(watchCharacter, player.Character) end
end
Players.PlayerAdded:Connect(watchPlayer)
for _, p in Players:GetPlayers() do watchPlayer(p) end

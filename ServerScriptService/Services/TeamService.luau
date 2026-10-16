-- Owns Roblox teams, gameplay roles, and the Freezer's starting hold.
local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local TeamService = {}
local random = Random.new()
local heldRoots = setmetatable({}, { __mode = "k" })

local function createTeam(name, color)
	local team = Teams:FindFirstChild(name)
	if team then
		assert(team:IsA("Team"), name .. " must be a Team")
	else
		team = Instance.new("Team")
		team.Name = name
	end
	team.TeamColor = BrickColor.new(color)
	team.AutoAssignable = false
	team.Parent = Teams
	return team
end

TeamService.Lobby = createTeam("Lobby", "Medium stone grey")
TeamService.Freezers = createTeam("Freezers", "Bright blue")
TeamService.Runners = createTeam("Runners", "Bright red")

local function setRole(player, role, team)
	player.Team = team
	player.Neutral = false
	player:SetAttribute("Role", role)
end

function TeamService.ApplyHeadStart(player, character)
	if not player:GetAttribute("RoundLocked") or player.Character ~= character then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	character:SetAttribute("RoundLocked", true)
	if heldRoots[root] == nil then heldRoots[root] = root.Anchored end
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.Anchored = true
end

function TeamService.ReleasePlayer(player)
	player:SetAttribute("RoundLocked", false)
	local character = player.Character
	if not character then return end
	character:SetAttribute("RoundLocked", false)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and heldRoots[root] ~= nil then
		if not character:GetAttribute("Frozen") then root.Anchored = heldRoots[root] end
		heldRoots[root] = nil
	end
end

function TeamService.SetLobby(player)
	TeamService.ReleasePlayer(player)
	player:SetAttribute("InTestMap", false)
	player:SetAttribute("TestMapSpawn", nil)
	setRole(player, "Lobby", TeamService.Lobby)
end

function TeamService.AssignRound(participants)
	assert(#participants > 0, "A round needs at least one player")
	local freezer = participants[random:NextInteger(1, #participants)]
	for _, player in participants do
		TeamService.ReleasePlayer(player)
		local isFreezer = player == freezer
		player:SetAttribute("RoundLocked", isFreezer)
		if player.Character then TeamService.ApplyHeadStart(player, player.Character) end
		setRole(player, isFreezer and "Freezer" or "Runner",
			isFreezer and TeamService.Freezers or TeamService.Runners)
	end
	return freezer
end

local function onPlayer(player)
	TeamService.SetLobby(player)
	player.CharacterAdded:Connect(function(character)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if root then TeamService.ApplyHeadStart(player, character) end
	end)
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do onPlayer(player) end
Players.PlayerRemoving:Connect(TeamService.ReleasePlayer)

return TeamService

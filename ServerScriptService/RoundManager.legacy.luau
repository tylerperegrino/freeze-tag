-- The server owns the player requirement, voting deadline, votes, and teleport.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Config = require(ReplicatedStorage.Shared.MapVotingConfig)
local TeamService = require(ServerScriptService.Services.TeamService)

local function getOrCreate(className, name, parent)
	local object = parent:FindFirstChild(name)
	if object then
		assert(object:IsA(className), name .. " has the wrong instance type")
		return object
	end
	object = Instance.new(className)
	object.Name = name
	object.Parent = parent
	return object
end

local status = getOrCreate("StringValue", "RoundStatus", ReplicatedStorage)
local state = getOrCreate("Folder", "MapVotingState", ReplicatedStorage)
local remotes = getOrCreate("Folder", "Remotes", ReplicatedStorage)
local castVote = getOrCreate("RemoteEvent", "CastMapVote", remotes)
local clientReady = getOrCreate("RemoteEvent", "MapVotingReady", remotes)
local voteFinished = getOrCreate("BindableEvent", "MapVoteFinished", ServerStorage)
local connected = {}
local readyPlayers = {}
local votes = {}
local lastRequest = {}
local roundId = 0
local phase = "Waiting"
local random = Random.new()

local function playerCount()
	local count = 0
	for _ in connected do count += 1 end
	return count
end

local function countVotes()
	local counts = table.create(#Config.Maps, 0)
	for player, index in votes do
		if connected[player] then counts[index] += 1 end
	end
	return counts
end

local function publishCounts()
	local counts = countVotes()
	for index, count in counts do
		state:SetAttribute("Votes" .. index, count)
	end
end

local function allPlayersReady()
	for player in connected do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not readyPlayers[player] or not root then return false end
	end
	return true
end

local function waitingMessage()
	local text = "Waiting for players... " .. playerCount() .. "/" .. Config.MinPlayers
	if playerCount() >= Config.MinPlayers and not allPlayersReady() then
		text ..= " - Loading players..."
	end
	status.Value = text
end

local function setPhase(nextPhase, seconds)
	phase = nextPhase
	state:SetAttribute("EndsAt", seconds and (workspace:GetServerTimeNow() + seconds) or 0)
	state:SetAttribute("Phase", nextPhase)
end

local function clearSelections()
	table.clear(votes)
	table.clear(lastRequest)
	for player in connected do player:SetAttribute("MapVoteIndex", 0) end
	state:SetAttribute("WinnerIndex", 0)
	publishCounts()
end

local function waitForPhase(seconds, needsPlayers)
	local deadline = workspace:GetServerTimeNow() + seconds
	repeat
		if needsPlayers and playerCount() < Config.MinPlayers then return false end
		task.wait(0.05)
	until workspace:GetServerTimeNow() >= deadline
	return not needsPlayers or playerCount() >= Config.MinPlayers
end

local function startCountdown()
	local deadline = workspace:GetServerTimeNow() + Config.StartDelaySeconds
	setPhase("Countdown", Config.StartDelaySeconds)
	repeat
		if playerCount() < Config.MinPlayers or not allPlayersReady() then return false end
		local remaining = math.max(0, math.ceil(deadline - workspace:GetServerTimeNow()))
		status.Value = "Players ready! " .. playerCount() .. "/" .. Config.MinPlayers .. " - Map voting in " .. remaining .. "..."
		task.wait(0.05)
	until workspace:GetServerTimeNow() >= deadline
	return playerCount() >= Config.MinPlayers and allPlayersReady()
end

local function resolveDestination(path)
	local object = workspace
	for name in string.gmatch(path, "[^.]+") do
		object = object and object:FindFirstChild(name)
	end
	return object and object:IsA("BasePart") and object or nil
end

local function moveCharacter(player, character)
	local spawnCFrame = player:GetAttribute("TestMapSpawn")
	if typeof(spawnCFrame) ~= "CFrame" then return false end
	local root = character:WaitForChild("HumanoidRootPart", 5)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then return false end
	if not connected[player] or player.Character ~= character then return false end
	character:PivotTo(spawnCFrame)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	TeamService.ApplyHeadStart(player, character)
	return true
end

local function addPlayer(player)
	connected[player] = true
	player:SetAttribute("MapVoteIndex", 0)
	player.CharacterAdded:Connect(function(character)
		if player:GetAttribute("InTestMap") then
			task.spawn(moveCharacter, player, character)
		end
	end)
	if phase == "Waiting" then waitingMessage() end
end

Players.PlayerAdded:Connect(addPlayer)
Players.PlayerRemoving:Connect(function(player)
	connected[player] = nil
	readyPlayers[player] = nil
	votes[player] = nil
	lastRequest[player] = nil
	publishCounts()
	if phase == "Waiting" then waitingMessage() end
end)
for _, player in Players:GetPlayers() do addPlayer(player) end

-- The client announces readiness after its game, UI and artwork finish loading.
clientReady.OnServerEvent:Connect(function(player)
	if connected[player] then readyPlayers[player] = true end
end)

-- One vote per player. Choosing another card replaces their previous choice.
castVote.OnServerEvent:Connect(function(player, requestedRound, index)
	if not connected[player] or phase ~= "MapVoting" then return end
	if workspace:GetServerTimeNow() >= (state:GetAttribute("EndsAt") or 0) then return end
	if typeof(requestedRound) ~= "number" or requestedRound ~= roundId then return end
	if typeof(index) ~= "number" or index % 1 ~= 0 or not Config.Maps[index] then return end
	local now = os.clock()
	if lastRequest[player] and now - lastRequest[player] < 0.08 then return end
	lastRequest[player] = now
	votes[player] = index
	player:SetAttribute("MapVoteIndex", index)
	publishCounts()
end)

state:SetAttribute("RoundId", 0)
clearSelections()
setPhase("Waiting")
waitingMessage()

-- Prototype flow ends on the test map; a round timer/return-to-lobby comes later.
while true do
	while playerCount() < Config.MinPlayers or not allPlayersReady() do
		waitingMessage()
		task.wait(0.1)
	end
	roundId += 1
	state:SetAttribute("RoundId", roundId)
	clearSelections()
	if not startCountdown() then
		setPhase("Waiting")
		waitingMessage()
		continue
	end
	status.Value = "Map voting..."
	setPhase("MapVoteIntro", Config.IntroSeconds)
	local completed = waitForPhase(Config.IntroSeconds, true)
	if completed then
		setPhase("MapVoting", Config.VoteSeconds)
		completed = waitForPhase(Config.VoteSeconds, true)
	end
	if not completed then
		clearSelections()
		setPhase("Waiting")
		waitingMessage()
		continue
	end

	-- Restrict teleporting to players connected when this vote ends.
	local participants = {}
	for player in connected do table.insert(participants, player) end
	table.sort(participants, function(a, b) return a.UserId < b.UserId end)
	local counts = countVotes()
	local highest = math.max(table.unpack(counts))
	local tied = {}
	for index, count in counts do
		if count == highest then table.insert(tied, index) end
	end
	local winner = tied[random:NextInteger(1, #tied)]
	local map = Config.Maps[winner]
	local destination = resolveDestination(map.Destination)
	if not destination then
		warn("[RoundManager] Missing teleport destination: " .. map.Destination)
		clearSelections()
		setPhase("Waiting")
		status.Value = "Test map unavailable"
		task.wait(3)
		continue
	end
	state:SetAttribute("WinnerIndex", winner)
	ReplicatedStorage:SetAttribute("SelectedMap", map.Name)
	status.Value = map.Name .. " selected!"
	setPhase("MapVoteResult", Config.ResultSeconds)
	voteFinished:Fire(map.Name)
	waitForPhase(Config.ResultSeconds, false)
	setPhase("Teleporting", Config.FadeSeconds)
	status.Value = "Loading " .. map.Name .. "..."
	waitForPhase(Config.FadeSeconds, false)

	-- Exclude players who left or lost their character during the result animation.
	local available = {}
	for _, player in participants do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if connected[player] and humanoid and humanoid.Health > 0
			and character:FindFirstChild("HumanoidRootPart") then
			table.insert(available, player)
		end
	end
	participants = available
	if #participants < Config.MinPlayers then
		clearSelections()
		setPhase("Waiting")
		waitingMessage()
		continue
	end
	local freezer = TeamService.AssignRound(participants)
	local columns = math.ceil(math.sqrt(#participants))
	local rows = math.ceil(#participants / columns)
	for slot, player in participants do
		if connected[player] then
			local x = ((slot - 1) % columns - (columns - 1) / 2) * 8
			local z = (math.floor((slot - 1) / columns) - (rows - 1) / 2) * 8
			player:SetAttribute("TestMapSpawn", destination.CFrame * CFrame.new(x, 0, z))
			player:SetAttribute("InTestMap", true)
			if player.Character then moveCharacter(player, player.Character) end
		end
	end
	-- Start the hold after everyone moves, giving Runners a full head start.
	setPhase("HeadStart", Config.FreezerDelaySeconds)
	local releaseAt = workspace:GetServerTimeNow() + Config.FreezerDelaySeconds
	repeat
		local remaining = math.max(0, math.ceil(releaseAt - workspace:GetServerTimeNow()))
		status.Value = "Runners, run! Freezer released in " .. remaining .. "..."
		task.wait(0.05)
	until workspace:GetServerTimeNow() >= releaseAt or not connected[freezer]
	for _, player in participants do TeamService.ReleasePlayer(player) end
	setPhase("Playing")
	status.Value = connected[freezer] and "Freezer released! Run!" or "Freezer left - restart the playtest"
	print("[RoundManager] " .. map.Name .. ": " .. freezer.Name .. " is the Freezer; " .. #participants .. " participants")
	break
end


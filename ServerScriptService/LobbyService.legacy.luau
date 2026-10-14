-- LobbyService: the lobby's prize wheel (free spin with a cooldown, pays coins), the map-voting
-- pads (stand on a pad to vote, countdown, winner) and the shop counter prompt.
-- Map voting result: ReplicatedStorage:GetAttribute("SelectedMap") and ServerStorage.MapVoteFinished:Fire(mapName).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.LobbyConfig)
local DataManager = require(ServerScriptService.Data.DataManager)
local Remotes = ReplicatedStorage.Remotes

local Map = workspace:WaitForChild("Lobby"):WaitForChild("Map")

local function notify(player, text, color)
	Remotes.LobbyNotify:FireClient(player, text, color)
end

--------------------------------------------------------------------------------
-- PRIZE WHEEL
--------------------------------------------------------------------------------
local rotor = Map:WaitForChild("SpinWheel_Rotor")
local pivot = rotor:WaitForChild("WheelPivot")
local BASE = pivot.CFrame -- wheel at rest, slice 1 under the pointer
local SLICE_DEG = 360 / #Config.Wheel.Slices
local spinning = false

rotor:SetAttribute("WheelAngle", 0)

-- write the prize on each slice
for _, d in rotor:GetDescendants() do
	if d.Name == "WheelLabel" and d:IsA("BasePart") then
		local slice = Config.Wheel.Slices[d:GetAttribute("Slice")]
		local label = d:FindFirstChild("Label", true)
		if slice and label then label.Text = tostring(slice.Coins) end
	end
end

local function pickSlice()
	local total = 0
	for _, s in Config.Wheel.Slices do total += s.Weight end
	local r = math.random() * total
	for i, s in Config.Wheel.Slices do
		r -= s.Weight
		if r <= 0 then return i end
	end
	return #Config.Wheel.Slices
end

local function formatTime(sec)
	sec = math.max(0, math.ceil(sec))
	return string.format("%d:%02d", sec // 60, sec % 60)
end

local spinPrompt = Map.SpinWheel:WaitForChild("SpinPromptPart"):WaitForChild("SpinPrompt")
spinPrompt.Triggered:Connect(function(player)
	local profile = DataManager.Profiles[player]
	if not profile then
		notify(player, "Your data is still loading, try again in a moment.")
		return
	end
	if spinning then
		notify(player, "The wheel is already spinning!")
		return
	end
	local now = os.time()
	local waitLeft = (profile.Data.LastFreeSpin or 0) + Config.Wheel.FreeSpinCooldown - now
	if waitLeft > 0 then
		notify(player, "Next free spin in " .. formatTime(waitLeft))
		return
	end
	profile.Data.LastFreeSpin = now
	spinning = true
	spinPrompt.Enabled = false

	local slice = pickSlice()
	local from = rotor:GetAttribute("WheelAngle") or 0
	-- rotating by -(slice-1)*SLICE_DEG brings that slice under the pointer; land somewhere inside it
	local target = -(slice - 1) * SLICE_DEG + (math.random() - 0.5) * SLICE_DEG * 0.7
	local to = from + 360 * Config.Wheel.ExtraTurns + ((target - from) % 360)
	local duration = Config.Wheel.SpinTime
	Remotes.WheelSpin:FireAllClients(from, to, duration, workspace:GetServerTimeNow(), player.UserId)

	task.delay(duration, function()
		pivot.CFrame = BASE * CFrame.Angles(0, 0, math.rad(to % 360))
		rotor:SetAttribute("WheelAngle", to % 360)
		local coins = Config.Wheel.Slices[slice].Coins
		if player.Parent and DataManager.Profiles[player] then
			DataManager.AddCoins(player, coins)
			notify(player, "You won " .. coins .. " coins!", "#ffd23f")
		end
		if coins >= Config.Wheel.AnnounceAtLeast then
			for _, other in Players:GetPlayers() do
				if other ~= player then notify(other, player.DisplayName .. " won " .. coins .. " coins on the wheel!", "#ffd23f") end
			end
		end
		task.wait(0.5)
		spinning = false
		spinPrompt.Enabled = true
	end)
end)

--------------------------------------------------------------------------------
-- MAP VOTING
--------------------------------------------------------------------------------
local voting = Map:WaitForChild("MapVoting")
local pads = {}
for i = 1, 3 do
	local zone = voting:WaitForChild("VoteZone" .. i)
	local glow
	for _, p in voting:GetChildren() do
		if p.Name == "PadGlow" and (p.Position - zone.Position).Magnitude < 3 then glow = p end
	end
	pads[i] = {
		zone = zone,
		radius = zone:GetAttribute("Radius") or 6.9,
		glow = glow,
		title = voting:WaitForChild("MapTitle" .. i):FindFirstChild("Label", true),
		count = voting:WaitForChild("VoteCount" .. i):FindFirstChild("Label", true),
	}
	pads[i].title.Text = Config.Voting.Maps[i] or ("Map " .. i)
end
local timerLabel = voting:WaitForChild("VoteTimer"):FindFirstChild("Label", true)
local headerLabel = voting:WaitForChild("VoteHeader"):FindFirstChild("Label", true)
local GLOW_IDLE = Color3.new(1, 1, 1)
local GLOW_LEAD = Color3.fromRGB(255, 210, 63)

local function countVotes()
	local votes = { 0, 0, 0 }
	for _, plr in Players:GetPlayers() do
		local char = plr.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if root and hum and hum.Health > 0 then
			for i, pad in pads do
				local d = root.Position - pad.zone.Position
				if Vector3.new(d.X, 0, d.Z).Magnitude <= pad.radius and d.Y > -1 and d.Y < 8 then
					votes[i] += 1
					break
				end
			end
		end
	end
	return votes
end

local function showVotes(votes)
	local best = math.max(votes[1], votes[2], votes[3])
	for i, pad in pads do
		pad.count.Text = votes[i] .. (votes[i] == 1 and " VOTE" or " VOTES")
		if pad.glow then pad.glow.Color = (best > 0 and votes[i] == best) and GLOW_LEAD or GLOW_IDLE end
	end
end

task.spawn(function()
	while true do
		headerLabel.Text = "VOTE FOR THE NEXT MAP!"
		local ends = os.clock() + Config.Voting.RoundTime
		local votes = { 0, 0, 0 }
		while os.clock() < ends do
			votes = countVotes()
			showVotes(votes)
			timerLabel.Text = formatTime(ends - os.clock())
			task.wait(0.25)
		end
		-- pick the winner (ties and empty votes are decided at random)
		local best = math.max(votes[1], votes[2], votes[3])
		local tied = {}
		for i = 1, 3 do if votes[i] == best then table.insert(tied, i) end end
		local winner = tied[math.random(#tied)]
		local mapName = Config.Voting.Maps[winner] or ("Map " .. winner)
		ReplicatedStorage:SetAttribute("SelectedMap", mapName)
		ServerStorage.MapVoteFinished:Fire(mapName)
		headerLabel.Text = "NEXT MAP: " .. string.upper(mapName) .. "!"
		timerLabel.Text = ""
		for i, pad in pads do
			if pad.glow then pad.glow.Color = (i == winner) and GLOW_LEAD or GLOW_IDLE end
		end
		task.wait(Config.Voting.ResultTime)
	end
end)

--------------------------------------------------------------------------------
-- SHOP COUNTER
--------------------------------------------------------------------------------
-- The client opens a ScreenGui named "ShopGui" if the game has one, otherwise shows a notice.
local shopPrompt = Map.Shop:WaitForChild("ShopPromptPart"):WaitForChild("ShopPrompt")
shopPrompt.Triggered:Connect(function(player)
	Remotes.OpenShop:FireClient(player)
end)

print("[LobbyService] wheel, map voting and shop ready")

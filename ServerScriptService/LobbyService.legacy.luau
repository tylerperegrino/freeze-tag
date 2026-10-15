-- LobbyService: the prize wheel, shop, and display of the server-controlled map vote.
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
-- The on-screen vote is owned by RoundManager. The old board only displays it.
--------------------------------------------------------------------------------
local voting = Map:FindFirstChild("MapVoting")
local voteState = ReplicatedStorage:WaitForChild("MapVotingState")
local voteConfig = require(ReplicatedStorage.Shared.MapVotingConfig)
local function refreshBoard()
	if not voting then return end
	local header = voting:FindFirstChild("VoteHeader")
	local timer = voting:FindFirstChild("VoteTimer")
	local headerLabel = header and header:FindFirstChild("Label", true)
	local timerLabel = timer and timer:FindFirstChild("Label", true)
	if headerLabel then headerLabel.Text = "MAP VOTING" end
	if timerLabel then
		local current = voteState:GetAttribute("Phase")
		timerLabel.Text = current == "MapVoting" and "CHOOSE ON SCREEN" or ""
	end
	for index, mapInfo in voteConfig.Maps do
		local titlePart = voting:FindFirstChild("MapTitle" .. index)
		local countPart = voting:FindFirstChild("VoteCount" .. index)
		local title = titlePart and titlePart:FindFirstChild("Label", true)
		local count = countPart and countPart:FindFirstChild("Label", true)
		if title then title.Text = mapInfo.Name end
		if count then count.Text = tostring(voteState:GetAttribute("Votes" .. index) or 0) .. " VOTES" end
	end
end
voteState.AttributeChanged:Connect(refreshBoard)
refreshBoard()

--------------------------------------------------------------------------------
-- SHOP COUNTER
--------------------------------------------------------------------------------
-- The client opens a ScreenGui named "ShopGui" if the game has one, otherwise shows a notice.
local shopPrompt = Map.Shop:WaitForChild("ShopPromptPart"):WaitForChild("ShopPrompt")
shopPrompt.Triggered:Connect(function(player)
	Remotes.OpenShop:FireClient(player)
end)

print("[LobbyService] wheel, shop and map vote display ready")

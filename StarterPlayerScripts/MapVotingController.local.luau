-- Client presentation only. The server validates votes and controls the deadline.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")
local StarterGui = game:GetService("StarterGui")
local player = Players.LocalPlayer
local Config = require(ReplicatedStorage.Shared:WaitForChild("MapVotingConfig"))
local state = ReplicatedStorage:WaitForChild("MapVotingState")
local castVote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CastMapVote")
local clientReady = ReplicatedStorage.Remotes:WaitForChild("MapVotingReady")
local gui = player:WaitForChild("PlayerGui"):WaitForChild("VotingUI")
local window = gui:WaitForChild("Window")
local scale = window:WaitForChild("UIScale")
local timer = window:WaitForChild("Timer")
local buttons = {}
local tweenGeneration = 0
local activeTweens = {}
local wasActive = false
local cameraConnection
local hiddenStatus
local previousStatusVisibility
local previousBackpackVisibility
local hovered = {}
local visualTargets = {}
local highlightTweens = {}
local pressTweens = {}
local pressGenerations = {}
local lastClick = 0
local clickSound = Instance.new("Sound")
clickSound.Name = "MapVoteClick"
clickSound.SoundId = Config.ClickSoundId
clickSound.Volume = Config.ClickVolume
clickSound.PlaybackSpeed = Config.ClickPlaybackSpeed
clickSound.Parent = gui

local function targetScale()
	local camera = workspace.CurrentCamera
	local viewport = gui.AbsoluteSize
	if viewport.X < 1 or viewport.Y < 1 then viewport = camera and camera.ViewportSize or Vector2.new(1280, 720) end
	return math.min(viewport.X * Config.PopupWidthFraction / Config.VisibleArtWidth,
		viewport.Y * Config.PopupHeightFraction / Config.VisibleArtHeight)
end

local function resize()
	scale.Scale = targetScale()
	for _, button in buttons do
		button.SelectionStroke.Thickness = math.max(3, 5 / scale.Scale)
	end
end

local function hookCamera()
	if cameraConnection then cameraConnection:Disconnect() end
	local camera = workspace.CurrentCamera
	if camera then cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(resize) end
	resize()
end

local function cancelTweens()
	for _, tween in activeTweens do tween:Cancel() end
	table.clear(activeTweens)
end

local function animate(object, info, properties)
	local tween = TweenService:Create(object, info, properties)
	table.insert(activeTweens, tween)
	tween:Play()
	return tween
end

local function isVisiblePhase(phase)
	return phase == "MapVoting" or phase == "MapVoteResult"
end

-- Cancel an old visual tween before changing its target, so rapid changes stay smooth.
local function updateCardVisual(index, strength)
	if visualTargets[index] == strength then return end
	visualTargets[index] = strength
	local button = buttons[index]
	local stroke = button.SelectionStroke
	for _, tween in highlightTweens[index] or {} do tween:Cancel() end
	stroke.Enabled = true
	local background = strength == 2 and 0.88 or strength == 1 and 0.97 or 1
	local outline = strength == 2 and 0 or strength == 1 and 0.65 or 1
	if not window.Visible then
		button.BackgroundTransparency = background
		stroke.Transparency = outline
		highlightTweens[index] = {}
		return
	end
	local info = TweenInfo.new(Config.HighlightSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fillTween = TweenService:Create(button, info, { BackgroundTransparency = background })
	local strokeTween = TweenService:Create(stroke, info, { Transparency = outline })
	highlightTweens[index] = { fillTween, strokeTween }
	fillTween:Play()
	strokeTween:Play()
end

local function clickPulse(index)
	local stroke = buttons[index].SelectionStroke
	if pressTweens[index] then pressTweens[index]:Cancel() end
	pressGenerations[index] = (pressGenerations[index] or 0) + 1
	local generation = pressGenerations[index]
	local width = math.max(3, 5 / scale.Scale)
	local press = TweenService:Create(stroke, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Thickness = width * 1.3 })
	pressTweens[index] = press
	press:Play()
	press.Completed:Once(function(playbackState)
		if playbackState ~= Enum.PlaybackState.Completed or pressGenerations[index] ~= generation then return end
		local release = TweenService:Create(stroke, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Thickness = math.max(3, 5 / scale.Scale) })
		pressTweens[index] = release
		release:Play()
	end)
end

local function updateSelection()
	local selected = player:GetAttribute("MapVoteIndex") or 0
	local winner = state:GetAttribute("WinnerIndex") or 0
	local phase = state:GetAttribute("Phase")
	for index, button in buttons do
		local highlighted = phase == "MapVoteResult" and winner == index or phase == "MapVoting" and selected == index
		local hover = phase == "MapVoting" and hovered[index]
		updateCardVisual(index, highlighted and 2 or hover and 1 or 0)
		button.Active = phase == "MapVoting"
		button.Selectable = phase == "MapVoting"
		local count = state:GetAttribute("Votes" .. index) or 0
		window["VoteCount" .. index].Text = count .. (count == 1 and " vote" or " votes")
	end
end

local function updatePhase()
	local phase = state:GetAttribute("Phase")
	local active = isVisiblePhase(phase)
	updateSelection()
	if active == wasActive then return end
	wasActive = active
	tweenGeneration += 1
	local generation = tweenGeneration
	cancelTweens()
	if active then
		hiddenStatus = player.PlayerGui:FindFirstChild("RoundStatus", true)
		if hiddenStatus and hiddenStatus:IsA("GuiObject") then
			previousStatusVisibility = hiddenStatus.Visible
			hiddenStatus.Visible = false
		end
		pcall(function()
			previousBackpackVisibility = StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Backpack)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		window.Visible = true
		window.GroupTransparency = 1
		window.Position = UDim2.fromScale(0.5, 0.54)
		scale.Scale = targetScale() * 0.96
		local info = TweenInfo.new(Config.FadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		animate(window, info, { GroupTransparency = 0, Position = UDim2.fromScale(0.5, 0.5) })
		animate(scale, info, { Scale = targetScale() })
	else
		local info = TweenInfo.new(Config.FadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local tween = animate(window, info, { GroupTransparency = 1, Position = UDim2.fromScale(0.5, 0.52) })
		tween.Completed:Once(function(playbackState)
			if playbackState == Enum.PlaybackState.Completed and tweenGeneration == generation then
				window.Visible = false
				if hiddenStatus and hiddenStatus.Parent then hiddenStatus.Visible = previousStatusVisibility end
				if previousBackpackVisibility ~= nil then
					pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, previousBackpackVisibility) end)
				end
			end
		end)
	end
end

for index = 1, #Config.Maps do
	local button = window:WaitForChild("Map" .. index)
	buttons[index] = button
	button.SelectionStroke.Enabled = true
	button.SelectionStroke.Transparency = 1
	button.MouseEnter:Connect(function()
		hovered[index] = true
		updateSelection()
	end)
	button.MouseLeave:Connect(function()
		hovered[index] = false
		updateSelection()
	end)
	button.Activated:Connect(function()
		if state:GetAttribute("Phase") ~= "MapVoting" then return end
		if workspace:GetServerTimeNow() >= (state:GetAttribute("EndsAt") or 0) then return end
		local now = os.clock()
		if now - lastClick < 0.1 then return end
		lastClick = now
		clickSound.TimePosition = 0
		clickSound:Play()
		clickPulse(index)
		castVote:FireServer(state:GetAttribute("RoundId"), index)
	end)
	state:GetAttributeChangedSignal("Votes" .. index):Connect(updateSelection)
end
player:GetAttributeChangedSignal("MapVoteIndex"):Connect(updateSelection)
state:GetAttributeChangedSignal("WinnerIndex"):Connect(updateSelection)
state:GetAttributeChangedSignal("Phase"):Connect(updatePhase)
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hookCamera)
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
hookCamera()
updatePhase()

RunService.RenderStepped:Connect(function()
	if not window.Visible then return end
	local phase = state:GetAttribute("Phase")
	if phase == "MapVoting" then
		local remaining = math.max(0, math.ceil((state:GetAttribute("EndsAt") or 0) - workspace:GetServerTimeNow()))
		timer.Text = "Voting ends in " .. remaining .. "s"
	elseif phase == "MapVoteResult" then
		local winner = state:GetAttribute("WinnerIndex")
		timer.Text = Config.Maps[winner] and (Config.Maps[winner].Name .. " selected!") or "Vote finished"
	else
		timer.Text = "Choose a map"
	end
end)

task.spawn(function()
	if not game:IsLoaded() then game.Loaded:Wait() end
	local ok, err = pcall(function() ContentProvider:PreloadAsync({ window.Artwork, clickSound }) end)
	if not ok then warn("[MapVotingController] Artwork preload: " .. tostring(err)) end
	clientReady:FireServer()
end)

-- LobbyClient: plays the prize-wheel spin (smooth on every client, with ticks as slices pass the
-- pointer), spins the shop's roof coin, and shows lobby notices (wheel wins, cooldowns, shop).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Shared.LobbyConfig)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer

local Map = workspace:WaitForChild("Lobby"):WaitForChild("Map")
local rotor = Map:WaitForChild("SpinWheel_Rotor")
local SLICE_DEG = 360 / #Config.Wheel.Slices
-- the place streams parts in, so positions come from attributes saved in Studio, never from
-- whatever has (or hasn't) streamed in yet

--------------------------------------------------------------------------------
-- notices
--------------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "LobbyNotices"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 20
gui.Parent = player:WaitForChild("PlayerGui")

local holder = Instance.new("Frame")
holder.BackgroundTransparency = 1
holder.AnchorPoint = Vector2.new(0.5, 0)
holder.Position = UDim2.new(0.5, 0, 0, 70)
holder.Size = UDim2.fromOffset(460, 200)
holder.Parent = gui
local list = Instance.new("UIListLayout")
list.HorizontalAlignment = Enum.HorizontalAlignment.Center
list.Padding = UDim.new(0, 6)
list.Parent = holder

local function notice(text, color)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromOffset(440, 44)
	label.BackgroundColor3 = Color3.fromRGB(22, 38, 64)
	label.BackgroundTransparency = 0.15
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color and Color3.fromHex(color) or Color3.new(1, 1, 1)
	label.Text = text
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 10); corner.Parent = label
	local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0, 12); pad.PaddingRight = UDim.new(0, 12)
	pad.PaddingTop = UDim.new(0, 6); pad.PaddingBottom = UDim.new(0, 6); pad.Parent = label
	local stroke = Instance.new("UIStroke"); stroke.Thickness = 2; stroke.Color = Color3.fromRGB(10, 18, 32); stroke.Parent = label
	local scale = Instance.new("UIScale"); scale.Scale = 0.6; scale.Parent = label
	label.Parent = holder
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(3, function()
		local fade = TweenInfo.new(0.4)
		TweenService:Create(label, fade, { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
		TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
		task.wait(0.45)
		label:Destroy()
	end)
end

Remotes:WaitForChild("LobbyNotify").OnClientEvent:Connect(notice)

Remotes:WaitForChild("OpenShop").OnClientEvent:Connect(function()
	local shop = player.PlayerGui:FindFirstChild("ShopGui")
	if shop and shop:IsA("ScreenGui") then
		shop.Enabled = not shop.Enabled
	else
		notice("The shop is opening soon!", "#ffd23f")
	end
end)

--------------------------------------------------------------------------------
-- prize wheel spin
--------------------------------------------------------------------------------
local BASE = rotor:GetAttribute("BasePivot") -- wheel at rest, slice 1 under the pointer
local tick = Instance.new("Sound")
tick.SoundId = "rbxasset://sounds/clickfast.wav"
tick.Volume = 0.6
tick.RollOffMinDistance = 12
tick.RollOffMaxDistance = 90
local tickAnchor = Instance.new("Attachment")
tickAnchor.WorldPosition = BASE.Position
tickAnchor.Parent = workspace.Terrain
tick.Parent = tickAnchor
local spinConn

Remotes:WaitForChild("WheelSpin").OnClientEvent:Connect(function(from, to, duration, startTime)
	if spinConn then spinConn:Disconnect() end
	local lastSlice = math.floor(from / SLICE_DEG)
	spinConn = RunService.RenderStepped:Connect(function()
		local t = math.clamp((workspace:GetServerTimeNow() - startTime) / duration, 0, 1)
		local e = 1 - (1 - t) ^ 4 -- fast start, long slow-down
		local angle = from + (to - from) * e
		local pivot = rotor:FindFirstChild("WheelPivot") -- nil while streamed out
		if pivot then pivot.CFrame = BASE * CFrame.Angles(0, 0, math.rad(angle)) end
		local s = math.floor((angle + SLICE_DEG / 2) / SLICE_DEG)
		if s ~= lastSlice then
			lastSlice = s
			tick.PlaybackSpeed = 0.9 + math.random() * 0.25
			tick:Play()
		end
		if t >= 1 then
			spinConn:Disconnect()
			spinConn = nil
		end
	end)
end)

--------------------------------------------------------------------------------
-- spinning decorations (shop roof coin)
--------------------------------------------------------------------------------
local spinners = {}
local function addSpinner(model)
	local base = model:GetAttribute("BasePivot")
	if model:IsA("Model") and base then
		spinners[model] = { base = base, speed = model:GetAttribute("SpinSpeed") or 40 }
	end
end
for _, m in CollectionService:GetTagged("LobbySpin") do addSpinner(m) end
CollectionService:GetInstanceAddedSignal("LobbySpin"):Connect(addSpinner)
CollectionService:GetInstanceRemovedSignal("LobbySpin"):Connect(function(m) spinners[m] = nil end)

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for model, s in spinners do
		if model.Parent and model:FindFirstChildWhichIsA("BasePart") then
			local pos = s.base.Position
			model:PivotTo(CFrame.new(pos + Vector3.new(0, math.sin(now * 1.6) * 0.35, 0)) * CFrame.Angles(0, math.rad(now * s.speed), 0) * s.base.Rotation)
		end
	end
end)

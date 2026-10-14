local ReplicatedStorage = game:GetService("ReplicatedStorage") -- Gets shared storage
local StatusValue = ReplicatedStorage:WaitForChild("RoundStatus") -- finds servers text value
local StatusLabel = script.Parent -- gets the text label containing script

local function updateStatus() -- display update function
	StatusLabel.Text = StatusValue.Value -- updates the text
end

StatusValue.Changed:Connect(updateStatus)
updateStatus()
-- FrozenPose: when the server marks this character Frozen, hold the exact pose the
-- player was in (mid-run, mid-jump...) by pausing their animations; resume on thaw.
-- Players own their animation playback, so this runs on their own client.
local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local animator = humanoid:WaitForChild("Animator")

local paused = {}
local disabledAnimate = nil

local function freezePose()
	local animate = character:FindFirstChild("Animate")
	if animate and animate:IsA("BaseScript") and animate.Enabled then
		animate.Enabled = false
		disabledAnimate = animate
	end
	for _, track in animator:GetPlayingAnimationTracks() do
		table.insert(paused, { track = track, speed = track.Speed })
		track:AdjustSpeed(0)
	end
end

local function thawPose()
	for _, entry in paused do
		if entry.track.IsPlaying then entry.track:AdjustSpeed(entry.speed) end
	end
	table.clear(paused)
	if disabledAnimate and disabledAnimate.Parent then
		disabledAnimate.Enabled = true
	end
	disabledAnimate = nil
end

character:GetAttributeChangedSignal("Frozen"):Connect(function()
	if character:GetAttribute("Frozen") then freezePose() else thawPose() end
end)

-- Settings shared by RoundManager and MapVotingController.
local destination = "TemporaryTeleportMap.TeleportPoint"

return {
	MinPlayers = 1,
	StartDelaySeconds = 5,
	IntroSeconds = 1.2,
	VoteSeconds = 12,
	ResultSeconds = 1.5,
	FadeSeconds = 0.65,
	HighlightSeconds = 0.18,
	ClickSoundId = "rbxassetid://9112751536",
	ClickVolume = 0.12,
	ClickPlaybackSpeed = 0.95,
	Artwork = "rbxassetid://86968389740019",
	DesignWidth = 1200,
	DesignHeight = 700,
	-- Fit the visible artwork, excluding the transparent margin around it.
	VisibleArtWidth = 915,
	VisibleArtHeight = 610,
	PopupWidthFraction = 0.94,
	PopupHeightFraction = 0.94,
	-- All three choices intentionally share the test platform for now.
	Maps = {
		{ Name = "MAP 1", Destination = destination },
		{ Name = "MAP 2", Destination = destination },
		{ Name = "MAP 3", Destination = destination },
	},
}

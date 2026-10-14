--!strict
-- FreezeConfig: all balance + visual values for freezing / tagging.
-- Shared so the client can read cooldowns for UI; the SERVER enforces them.

local FreezeConfig = {
	-- Tagging (Freezer's basic freeze)
	TagRange = 7, -- studs from Freezer root to target root
	TagConeAngle = 75, -- degrees either side of where the Freezer faces
	TagPointBlank = 3, -- inside this distance, facing direction is ignored
	TagCooldown = 0.9, -- seconds between bat swings (server enforced)

	-- Baseball bat swing (procedural "club" animation, no uploaded asset needed)
	BatToolName = "Bat",
	SwingWindupTime = 0.12, -- raise toward the right shoulder
	SwingSlotTime = 0.14, -- cocked high over the right shoulder
	SwingStrikeTime = 0.1, -- slash (a touch longer so the motion stays smooth at speed)
	SwingFollowTime = 0.13, -- cut carries through, low on the left
	SwingRecoverMidTime = 0.14, -- recovery, first half: bat comes back up
	SwingRecoverTime = 0.18, -- recovery, second half: settle into the hold
	BatHitDelay = 0.38, -- server freeze lands when the R6 bat connects (contact at 0.405s; observers see it right on contact, the swinger ~1 ping later)
	SwingBodyLean = 1, -- how much the body leans/turns into the swing (1 = like the reference, 0 = none)
	SwingSoundId = "rbxassetid://9120972444", -- Wood Whoosh Slicing Air (ProSoundEffects)
	HitSoundId = "rbxassetid://9113502737", -- Body Hits, 2x4 wood (ProSoundEffects)

	-- Freeze animation
	FreezeStartHeight = 0.55, -- ice appears instantly at this fraction of full height (synced with the sound)
	FreezeStretchTime = 0.08, -- ...shoots up past full height in the same beat as the sound...
	FreezeSettleTime = 0.35, -- ...then eases into final size with one soft overshoot
	FreezeStretch = 1.1, -- how much taller than final during the stretch
	FreezeSquash = 0.94, -- how much thinner than final during the stretch
	ThawTweenTime = 0.45, -- ice melts away
	IceColor = Color3.fromRGB(150, 215, 255),
	IceTransparency = 0.35,
	IceShellPadding = 1.2, -- how much bigger than the body the ice cube is (top, front, back)
	IceShellPaddingX = 0.8, -- same, but for the side-to-side length (left/right)
	HighlightFill = 0.65,
	BurstParticles = 30,

	-- Placeholder audio/animation: leave "" until you have your own asset IDs
	-- (e.g. "rbxassetid://123"). Empty = silently skipped.
	FreezeSoundId = "rbxassetid://127777354835900", -- "freeze 1": short snap, peaks at 0.05s, gone by ~0.3s
	-- Other instant options: rbxassetid://137494680585626 (bigger, rings ~1s), rbxassetid://128662938018637 (very short tick)
	ThawSoundId = "rbxassetid://9117947034", -- Puddle splash: ice melts away when rescued (ProSoundEffects)
	ThawSteamSoundId = "rbxassetid://6695868929", -- steam hiss when the ice melts away
	ThawingDripSoundId = "rbxassetid://9126188673", -- looping drips while someone is holding E
	ThawingCrackleSoundId = "rbxassetid://9125611419", -- looping ice crackle while someone is holding E
	SwingVolume = 0.8,
	HitVolume = 0.7,
	FreezeVolume = 0.4,
	ThawVolume = 0.55,

	-- Effects
	BatTrailColor = Color3.fromRGB(200, 235, 255),
	ShardCount = 10, -- ice chunks thrown out on freeze / thaw
	ShockwaveSize = 11, -- frost ring diameter on freeze (studs)
	TagAnimationId = "",

	-- Rescue (hold E on a frozen teammate)
	RescueHoldTime = 2.5, -- seconds of holding E to chip someone out of the ice (the ice pick lands 5 hits in this time)
	IceChipSoundId = "rbxassetid://9118624831", -- pick biting the ice: hard crunchy hit + light debris (ProSoundEffects)
	IceShatterSoundId = "rbxassetid://9114856749", -- ice block shattering when the last hit breaks it (ProSoundEffects)
	IceChipVolume = 1,
	IceShatterVolume = 1,
	-- extra layers so each pick hit and the final break sound violent (all ProSoundEffects)
	IceHitCrackSoundId = "rbxassetid://9114614600", -- glass smash, hammer hit / bullet impact: the sharp crack of each blow
	IceHitCrackleSoundId = "rbxassetid://9114858583", -- large ice block cracking: the fracture spreading after each blow
	IcePickClangSoundId = "rbxassetid://9119072660", -- metal clang: the steel pick biting in
	IceBreakGlassSoundId = "rbxassetid://9114614830", -- big glass crash for the final break
	IceBreakHeavySoundId = "rbxassetid://9114890176", -- heavy glass smash with debris for the final break
	IceBreakDebrisSoundId = "rbxassetid://9118586481", -- rubble settling after the break
	RescueRange = 8, -- studs from the frozen player
	RescueProtection = 2, -- seconds a rescued player can't be re-frozen
	TestAnyoneCanRescue = true, -- TEST ONLY: lets Freezers rescue too (so you can test solo). Set false for real matches.

	-- Stances
	WalkSpeed = 16,
	RunLean = 35, -- degrees the body leans forward at full running speed (the head stays straight up)
	RunBounce = 0.6, -- studs of up-and-down each step (smooth spring)
	RunArmSwing = 95, -- degrees each arm swings forward/back around RunArmForward (exaggerated)
	RunArmForward = 45, -- arms swing around this angle relative to the leaning body
	RunArmFlare = 14, -- degrees the arms swing out from the body
	RunLegSwing = 62, -- degrees each leg swings forward/back (high knees)
	RunTwist = 12, -- degrees the shoulders twist with each arm swing
	CrouchLean = 30, -- degrees the body leans forward while crouched

	-- Slide: press the crouch key (C) while running fast
	SlideMinSpeed = 12, -- must be moving at least this fast to slide (server checked)
	SlideStartSpeed = 32, -- burst speed at the start of the slide
	SlideEndSpeed = 10, -- speed at the end of the slide (it eases down in between)
	SlideDuration = 0.75, -- seconds
	SlideCooldown = 1.2, -- seconds before you can slide again
	SlideSoundId = "rbxassetid://9117933436", -- dirt drag scrape, looped while sliding (ProSoundEffects)
	SlideVolume = 0.45,
	CrouchSpeed = 9,
	CrawlSpeed = 5,
	CrouchKey = Enum.KeyCode.C,
	CrawlKey = Enum.KeyCode.Z,
	CrouchButton = Enum.KeyCode.ButtonB,
	CrawlButton = Enum.KeyCode.ButtonY,

	-- Movement sounds (all client-side; quiet so they don't get tiring)
	FootstepSoundIds = { "rbxassetid://110522236020035", "rbxassetid://135037154891351" }, -- grass footsteps, alternated
	FootstepVolume = 0.55,
	CrouchStepVolume = 0.25,
	CrouchSoundId = "rbxassetid://136224586361044", -- clothing rustle when crouching / standing up
	CrawlDownSoundId = "rbxassetid://9113472966", -- body drop when going prone
	CrawlStrokeSoundId = "rbxassetid://9119197706", -- scrape per crawl stroke
	BreathSoundId = "rbxassetid://9113702967", -- soft exhale with the idle cold-breath puff
	BreathInterval = { 3.5, 5.5 }, -- seconds between idle breaths
}

return table.freeze(FreezeConfig)

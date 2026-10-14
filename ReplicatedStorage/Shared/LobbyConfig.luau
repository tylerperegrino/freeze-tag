-- LobbyConfig: tuning for the lobby's prize wheel and map voting (used by LobbyService + LobbyClient).
return {
	Wheel = {
		FreeSpinCooldown = 600, -- seconds between free spins for each player (saved in their data)
		SpinTime = 5.5, -- seconds the wheel spins before it stops
		ExtraTurns = 5, -- full turns before landing
		AnnounceAtLeast = 250, -- wins this big are announced to the whole server
		-- Slice 1 sits under the pointer when the wheel is at rest; the rest follow clockwise.
		-- Weight = how likely that slice is compared to the others.
		Slices = {
			{ Coins = 25, Weight = 20 },
			{ Coins = 50, Weight = 14 },
			{ Coins = 100, Weight = 8 },
			{ Coins = 25, Weight = 20 },
			{ Coins = 75, Weight = 10 },
			{ Coins = 250, Weight = 3 },
			{ Coins = 25, Weight = 20 },
			{ Coins = 50, Weight = 14 },
			{ Coins = 150, Weight = 5 },
			{ Coins = 35, Weight = 16 },
			{ Coins = 500, Weight = 1 },
			{ Coins = 60, Weight = 12 },
		},
	},
	Voting = {
		RoundTime = 30, -- seconds players have to stand on a pad
		ResultTime = 6, -- seconds the winner is shown before the next vote starts
		-- One map per pad: 1 = blue pad (west, snowy board), 2 = orange (middle, factory board), 3 = purple (east, manor board).
		Maps = { "Snowy Village", "Toy Factory", "Haunted Manor" },
	},
}

local LevelConfig = {}

function LevelConfig.GetRequiredExp(level: number)
	return 100 + (level - 1) * 25
end

return LevelConfig

local DataManager = require(script.Parent:WaitForChild("DataManager"))

for _, player in game:GetService("Players"):GetPlayers() do
	while true do
		task.wait(3)
		
		local currencies = player:FindFirstChild("Currencies")
		if not currencies then continue end
		
		local gems = currencies:FindFirstChild("Gems")
		if not gems then continue end
		
		local coins = currencies:FindFirstChild("Coins")
		if not coins then continue end
		
		DataManager.AddGems(player, 5)
		DataManager.AddCoins(player, 10)
	end
end
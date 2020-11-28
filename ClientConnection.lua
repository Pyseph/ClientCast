return function(ClientCast)
	local StarterPlayer = game:GetService('StarterPlayer')
	local Players = game:GetService('Players')

	local ScriptsHolder = script.Parent
	local ClientHandler = ScriptsHolder.ClientHandler

	local function CloneHandler()
		local Cloned = ClientHandler:Clone()
		ScriptsHolder.Maid:Clone().Parent = Cloned
		ScriptsHolder.Connection:Clone().Parent = Cloned

		return Cloned
	end
	CloneHandler().Parent = StarterPlayer:FindFirstChildOfClass('StarterPlayerScripts')

	for Idx, Player in next, Players:GetPlayers() do
		if Player.Character then
			CloneHandler().Parent = Player:FindFirstChildOfClass('StarterPlayerScripts')
		end
	end
end


return function(ClientCast)
	local StarterPlayer = game:GetService('StarterPlayer')
	local ReplicatedStorage = game:GetService('ReplicatedStorage')
	local Players = game:GetService('Players')
	
	local ReplicationRemote = Instance.new('RemoteEvent')
	ReplicationRemote.Name = 'ClientCast-Replication'
	ReplicationRemote.Parent = ReplicatedStorage
	
	local ClientHandler = script.Parent.ClientHandler
	ClientHandler:Clone().Parent = StarterPlayer:FindFirstChildOfClass('StarterPlayerScripts')
	
	for Idx, Player in next, Players:GetPlayers() do
		if Player.Character then
			ClientHandler:Clone().Parent = Player.Character
		end
	end
	
	local ExpectedKeys = {
		Instance = {'BasePart', 'Terrain'}, 
		Position = 'Vector3', 
		Material = Enum.Material, 
		Normal = 'Vector3'
	}
	
	function Validate(Condition, Message)
		return Condition or error(Message, 3)
	end
	function ValidateResult(Table, Player)
		local BaseErrorMsg = Player.Name .. ' sent invalid raycast result (%s)'
	
		for Key, Data in next, ExpectedKeys do
			local ProvidedData = Table[Key]
			local QuotedKey = '\'' .. Key .. '\''
			Validate(ProvidedData ~= nil, string.format(BaseErrorMsg, 'key ' .. QuotedKey .. ' is undefined'))
	
			local DataType = typeof(Data)
			local ProvidedDataType = typeof(ProvidedData)
			if DataType == 'Enum' then
				Validate(ProvidedDataType == 'EnumItem', string.format(BaseErrorMsg, 'Value ' .. QuotedKey .. ' is not an EnumItem'))
				Validate(Data[ProvidedData.Name])
			elseif DataType == 'table' then
				Validate(ProvidedDataType == 'Instance', string.format(BaseErrorMsg, 'Value ' .. QuotedKey .. ' is not an Instance'))
				local IsValid = false
				
				for Index, Class in next, Data do
					if ProvidedData:IsA(Class) then
						IsValid = true
						break
					end
				end
				
				if not IsValid then
					error('Instance ' .. ProvidedData:GetFullName() .. ' is not a BasePart | Terrain object', 2)
				end
			else
				Validate(ProvidedDataType == Data, string.format(BaseErrorMsg, 'Value ' .. QuotedKey .. ' is not a ' .. Data))
			end
		end
	end
	ReplicationRemote.OnServerEvent:Connect(function(Player, SerializedResult)
		assert(type(SerializedResult) == 'table', Player.Name .. ' sent invalid raycast result (type \'table\' expected, got ' .. typeof(SerializedResult) .. ')')
		ValidateResult(SerializedResult, Player)
	end)
end

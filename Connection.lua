local Maid = require(script.Parent.Maid)

local Connection = {}

local ConnectionBase = {}
local InvokedBase = {}
ConnectionBase.__index = ConnectionBase
InvokedBase.__index = InvokedBase



function ConnectionBase:Invoke(...)
	for _, Data in next, self.Listeners do
		coroutine.wrap(Data.Callback)(...)
	end
	for Index, YieldedThread in next, self.Yielded do
		self.Yielded[Index] = nil
		coroutine.resume(YieldedThread, ...)
	end
end
function ConnectionBase:Destroy()
	self._Maid:Destroy()
end



function InvokedBase:Connect(f)
	local ConnectionReference = self._Reference
	local Timestamp = os.clock()
	local Data = {
		Disconnect = function(self)
			self.Connected = false
			ConnectionReference.Listeners[Timestamp] = nil
		end,
		Callback = f,
		Connected = true
	}
	Data.Destroy = Data.Disconnect
	
	ConnectionReference._Maid['Clean' .. Timestamp .. 'Connection'] = Data
	ConnectionReference.Listeners[Timestamp] = Data
	return Data
end
function InvokedBase:Wait()
	local ConnectionReference = self._Reference
	local Thread = coroutine.running()

	ConnectionReference.Yielded[#ConnectionReference.Yielded + 1] = Thread
	return coroutine.yield()
end



function Connection.new()
	local ConnectionObject = setmetatable({
		Listeners = {},
		Invoked = setmetatable({_Reference = false}, InvokedBase),
		Yielded = {},
		_Maid = Maid.new()
	}, ConnectionBase)
	ConnectionObject.Invoked._Reference = ConnectionObject
	
	return ConnectionObject
end

return Connection

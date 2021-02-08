local Janitor = require(script.Parent.Janitor)

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
	self._Janitor:Destroy()
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

	ConnectionReference._Janitor:Add(Data)
	ConnectionReference.Listeners[Timestamp] = Data
	return Data
end
function InvokedBase:Wait()
	local ConnectionReference = self._Reference
	local Thread = coroutine.running()

	table.insert(ConnectionReference.Yielded, Thread)
	return coroutine.yield()
end



function Connection.new()
	local ConnectionObject = setmetatable({
		Listeners = {},
		Invoked = setmetatable({_Reference = false}, InvokedBase),
		Yielded = {},
		_Janitor = Janitor.new()
	}, ConnectionBase)
	ConnectionObject.Invoked._Reference = ConnectionObject

	return ConnectionObject
end

return Connection
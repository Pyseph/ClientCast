local Connection = {}
local Signal = {}

Connection.__index = Connection
Signal.__index = Signal

function Connection.new(ConnectingSignal)
    return setmetatable({
        Signal = ConnectingSignal,
        Connected = true
    }, Connection)
end

function Connection:Disconnect()
    self.Signal._Connections[self] = nil
    self.Connected = false
end
Connection.Destroy = Connection.Disconnect

function Signal.new()
    local Invoked = {}
    local SignalObj = setmetatable({
        _Connections = {},
        Invoked = Invoked
    }, Signal)

    function Invoked:Wait()
        local CurrentThread, YieldConnection = coroutine.running(), nil
        YieldConnection = SignalObj:Connect(function(...)
            YieldConnection:Disconnect()
            coroutine.resume(CurrentThread, ...)
        end)
        return coroutine.yield()
    end
    function Invoked:Connect(Callback)
        local CreatedConnection = Connection.new(SignalObj)
        SignalObj._Connections[CreatedConnection] = Callback
        return CreatedConnection
    end

    return SignalObj
end

function Signal:Invoke(...)
    for _, Callback in next, self._Connections do
        coroutine.resume(coroutine.create(Callback), ...)
    end
end

local Invoked = {}
Signal.Invoked = Invoked

return Signal
--!strict
-- A small signal. Each handler runs in its own thread, so handlers can yield.

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, Callback: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, Callback: (T...) -> ()) -> Connection,
	Wait: (self: Signal<T...>) -> T...,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
}

local Connection = {}
Connection.__index = Connection

function Connection.Disconnect(self: any)
	if self.Connected then
		self.Connected = false
		local Index = table.find(self._Handlers, self)
		if Index then
			table.remove(self._Handlers, Index)
		end
	end
end

local Signal = {}
Signal.__index = Signal

function Signal.new<T...>(): Signal<T...>
	return setmetatable({ _Handlers = {} }, Signal) :: any
end

function Signal.Connect(self: any, Callback: (...any) -> ())
	local Handler = setmetatable({ Connected = true, _Callback = Callback, _Handlers = self._Handlers }, Connection)
	table.insert(self._Handlers, Handler)
	return Handler
end

function Signal.Once(self: any, Callback: (...any) -> ())
	local Handler
	Handler = self:Connect(function(...)
		Handler:Disconnect()
		Callback(...)
	end)
	return Handler
end

function Signal.Wait(self: any): ...any
	local Thread = coroutine.running()
	self:Once(function(...)
		task.spawn(Thread, ...)
	end)
	return coroutine.yield()
end

function Signal.Fire(self: any, ...: any)
	local Handlers: { any } = table.clone(self._Handlers)
	for _, Handler in Handlers do
		if Handler.Connected then
			task.spawn(Handler._Callback, ...)
		end
	end
end

function Signal.DisconnectAll(self: any)
	for _, Handler in self._Handlers do
		Handler.Connected = false
	end
	table.clear(self._Handlers)
end

return Signal

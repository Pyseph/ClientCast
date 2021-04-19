local o_clock = os.clock
local c_yield = coroutine.yield
local c_running = coroutine.running
local c_resume = coroutine.resume

local Yields = {}
game:GetService('RunService').Stepped:Connect(function()
	local Clock = o_clock()
	for Idx, data in next, Yields do
		local Spent = Clock - data[1]
		if Spent >= data[2] then
			Yields[Idx] = nil
			c_resume(data[3], Spent, Clock)
		end
	end
end)

return function(Time)
	Time = (type(Time) ~= 'number' or Time < 0) and 0 or Time
	Yields[#Yields + 1] = {o_clock(), Time, c_running()}
	return c_yield()
end
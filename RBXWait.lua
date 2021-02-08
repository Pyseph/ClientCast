local heap = {}
local currentSize = 0

function insert(yieldTime, data)
	currentSize += 1
	local start = time()
	heap[currentSize] = {
		pos = start - yieldTime,
		data = data,
		time = start
	}

	-- bubble up
	local pos = currentSize

	local parentIdx = math.floor(pos/2)
	local currentIdx = pos
	while currentIdx > 1 and start-heap[parentIdx].pos < start-heap[currentIdx].pos do
		heap[currentIdx], heap[parentIdx] = heap[parentIdx], heap[currentIdx]
		currentIdx = parentIdx
		parentIdx = math.floor(parentIdx/2)
	end
end
function extractMin()
	if currentSize < 2 then
		heap[1] = nil
		currentSize = 0
		return
	end

	heap[1], heap[currentSize] = heap[currentSize], nil
	-- sink down
	local k = 1
	local start = time()
	while k < currentSize do
		local smallest = k

		local leftChildIdx = 2*k
		local rightChildIdx = 2*k+1

		if leftChildIdx < currentSize and start-heap[smallest].pos < start-heap[leftChildIdx].pos then
			smallest = leftChildIdx
		end
		if rightChildIdx < currentSize and start-heap[smallest].pos < start-heap[rightChildIdx].pos then
			smallest = rightChildIdx
		end

		if smallest == k then
			break
		end

		heap[k], heap[smallest] = heap[smallest], heap[k]
		k = smallest
	end
	currentSize -= 1
end

game:GetService('RunService').Stepped:Connect(function()
	local PrioritizedThread = heap[1]
	if not PrioritizedThread then
		return
	end

	local start = time()
	-- while true do loops could potentially trigger script exhaustion, if you were to have >50k yields for some reason...
	for _ = 1, 10000 do
		local YieldTime = start - PrioritizedThread.time
		if PrioritizedThread.data[2] - YieldTime <= 0 then
			extractMin()
			coroutine.resume(PrioritizedThread.data[1], YieldTime, start)

			PrioritizedThread = heap[1]
			if not PrioritizedThread then 
				break 
			end
		else
			break
		end
	end
end)

return function(Time)
	insert(Time or 0, {coroutine.running(), Time or 0})
	return coroutine.yield()
end
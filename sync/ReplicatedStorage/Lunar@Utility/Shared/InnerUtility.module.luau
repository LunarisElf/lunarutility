local innerUtility = {}

function innerUtility.warn(head: string, msg: string)
	warn(`[LunarUtility] | {head}: {msg}`)
end

function innerUtility.getRangeIndices(array: {number}, target: number)
	local low = 1
	local high = #array

	while low <= high do
		local mid = math.floor((low + high) / 2)
		local val = array[mid]

		if val == target then
			-- Exact match found: return current and next
			return mid, mid + 1
		elseif val < target then
			low = mid + 1
		else
			high = mid - 1
		end
	end

	-- When the loop ends:
	-- 'high' is the index of the value just below the target
	-- 'low' is the index of the value just above the target
	return high, low
end

function innerUtility.LerpNumberSequence(startSeq: NumberSequence, endSeq: NumberSequence, t)
	-- Example Usage:
	-- local startSequence = NumberSequence.new(0) -- Fully opaque
	-- local endSequence = NumberSequence.new(1)   -- Fully transparent
	-- local t = 0.5 -- 50% through the transition
	-- local intermediateSequence = LerpNumberSequence(startSequence, endSequence, t)
	
	local newKeypoints = {}
	-- Assumes startSeq and endSeq have the same number of keypoints
	for i, keypoint in pairs(startSeq.Keypoints) do
		local startVal = keypoint.Value
		local endVal = endSeq.Keypoints[i].Value
		-- Standard lerp formula: a + (b - a) * t
		local lerpedValue = startVal + (endVal - startVal) * t
		table.insert(newKeypoints, NumberSequenceKeypoint.new(keypoint.Time, lerpedValue))
	end
	return NumberSequence.new(newKeypoints)
end

function innerUtility.LerpColorSequence(cs1: ColorSequence, cs2: ColorSequence, alpha: number)
	-- Example Usage:
	-- local color1 = ColorSequence.new(Color3.new(1,0,0)) -- Red
	-- local color2 = ColorSequence.new(Color3.new(0,0,1)) -- Blue
	-- local blended = lerpColorSequence(color1, color2, 0.5) -- Purple
	
	local keys1 = cs1.Keypoints
	local keys2 = cs2.Keypoints
	local newKeys = {}

	-- Assume both sequences have the same number of keypoints for simplicity
	for i = 1, #keys1 do
		local k1 = keys1[i]
		local k2 = keys2[i]

		-- Lerp time and color
		local newTime = k1.Time + (k2.Time - k1.Time) * alpha
		local newColor = k1.Value:Lerp(k2.Value, alpha)

		table.insert(newKeys, ColorSequenceKeypoint.new(newTime, newColor))
	end

	return ColorSequence.new(newKeys)
end

return innerUtility
-- Utility.lua
-- ReplicatedStorage > Shared > Utility
-- General helper functions used by both server and client.

local Utility = {}

-- Returns a random element from a table
function Utility.randomFrom(t: {any}): any
	return t[math.random(1, #t)]
end

-- Clamps a number between min and max
function Utility.clamp(value: number, min: number, max: number): number
	return math.max(min, math.min(max, value))
end

-- Rounds a number to the nearest integer
function Utility.round(n: number): number
	return math.floor(n + 0.5)
end

-- Returns the closest player to a given position (server-side).
-- Optional maxDistance lets callers exclude players far away (e.g. enemies
-- inside an arena shouldn't track players standing in the lobby).
function Utility.getNearestPlayer(position: Vector3, maxDistance: number?)
	local limit = maxDistance or math.huge
	local nearest = nil
	local nearestDist = math.huge
	for _, player in ipairs(game.Players:GetPlayers()) do
		local char = player.Character
		if char and char:FindFirstChild("HumanoidRootPart") then
			local dist = (char.HumanoidRootPart.Position - position).Magnitude
			if dist < nearestDist and dist <= limit then
				nearest = player
				nearestDist = dist
			end
		end
	end
	return nearest, nearestDist
end

-- Deep copy a table
function Utility.deepCopy(t: {any}): {any}
	local copy = {}
	for k, v in pairs(t) do
		copy[k] = type(v) == "table" and Utility.deepCopy(v) or v
	end
	return copy
end

return Utility

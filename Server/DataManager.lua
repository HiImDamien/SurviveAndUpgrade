-- DataManager.lua
-- ServerScriptService > Server > DataManager
-- Wraps DataStoreService with pcall safety. All persistent player data flows through here.

local DataStoreService = game:GetService("DataStoreService")
local DataStore = DataStoreService:GetDataStore("PlayerData_v1")

local DataManager = {}

-- Default data for a brand new player
local function getDefaultData()
	return {
		currency = 0,
		upgrades = {
			speed    = 1.0,   -- multiplier
			strength = 1.0,   -- multiplier
			maxHealth = 100,  -- flat value
		},
		weapons = {
			equipped = "Fists",
			owned = {
				Fists = { level = 1 },
			},
		},
		pets = {
			equipped = nil,
			owned    = {},   -- e.g. { FireFox = { level = 1, essence = 0 } }
		},
		zonesCleared = 0,
	}
end

-- Load a player's data from DataStore (returns default if none found or error)
function DataManager.load(player: Player): {}
	local success, data = pcall(function()
		return DataStore:GetAsync(tostring(player.UserId))
	end)

	if success and data then
		-- Merge in any missing default keys (for returning players missing new fields)
		local defaults = getDefaultData()
		for key, value in pairs(defaults) do
			if data[key] == nil then
				data[key] = value
			end
		end
		return data
	else
		if not success then
			warn("[DataManager] Failed to load data for", player.Name, ":", data)
		end
		return getDefaultData()
	end
end

-- Save a player's data to DataStore.
-- Retries up to 3 times with a short delay so transient network errors
-- (like Studio "NetFail" or queue-full warnings) don't silently lose data.
function DataManager.save(player: Player, data: {})
	local MAX_RETRIES = 3
	local RETRY_DELAY = 2  -- seconds between attempts

	for attempt = 1, MAX_RETRIES do
		local success, err = pcall(function()
			DataStore:SetAsync(tostring(player.UserId), data)
		end)
		if success then return end

		warn(string.format(
			"[DataManager] Save attempt %d/%d failed for %s: %s",
			attempt, MAX_RETRIES, player.Name, tostring(err)
		))
		if attempt < MAX_RETRIES then
			task.wait(RETRY_DELAY)
		end
	end

	warn("[DataManager] All", MAX_RETRIES, "save attempts failed for", player.Name,
		"— data may not have persisted this session")
end

return DataManager

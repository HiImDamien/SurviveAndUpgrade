-- CurrencyManager.lua
-- ServerScriptService > Server > CurrencyManager
-- Tracks in-run currency earned (in memory) and persistent currency (via DataManager).
-- Server is fully authoritative — client never tells server how much currency to give.
--
-- Display rule: the HUD always shows saved + run-earned so the number only ever
-- goes up during a run. The saved balance is captured in startRun() and used as
-- the base for every awardKill() display update.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)
local DataManager = require(script.Parent.DataManager)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CurrencyUpdated = Remotes:WaitForChild("CurrencyUpdated")

local CurrencyManager = {}

-- In-memory run earnings: resets to 0 each run
local runCurrency: { [Player]: number } = {}

-- Saved balance at the moment the player entered the level.
-- Used so awardKill can display saved + earned without touching DataStore mid-run.
local baseBalance: { [Player]: number } = {}

-- ── Lifecycle ────────────────────────────────────────────────────────────────

-- Call on join / lobby reset — just clears the run tally.
function CurrencyManager.initPlayer(player: Player)
	runCurrency[player] = 0
end

-- Call when a player actually enters a level. Records their saved balance so
-- awardKill can show the correct running total during combat.
function CurrencyManager.startRun(player: Player, savedCurrency: number)
	runCurrency[player] = 0
	baseBalance[player] = savedCurrency
end

-- ── Kill reward ───────────────────────────────────────────────────────────────

-- Award currency for a zombie kill (called server-side only).
-- Fires saved + earned so the HUD always shows the player's true total.
function CurrencyManager.awardKill(player: Player, isBoss: boolean)
	if not runCurrency[player] then return end
	local amount = isBoss and Constants.CURRENCY_BOSS_BONUS or Constants.CURRENCY_PER_KILL
	runCurrency[player] = runCurrency[player] + amount
	local display = (baseBalance[player] or 0) + runCurrency[player]
	CurrencyUpdated:FireClient(player, display)
end

-- Get how much currency this player has earned this run
function CurrencyManager.getRunCurrency(player: Player): number
	return runCurrency[player] or 0
end

-- ── Round end ─────────────────────────────────────────────────────────────────

-- Called at round end — adds run earnings to the persistent DataStore balance.
-- Also fires the updated total to the client HUD.
function CurrencyManager.persistRunCurrency(player: Player, playerData: {})
	local earned = runCurrency[player] or 0
	playerData.currency = (playerData.currency or 0) + earned
	DataManager.save(player, playerData)
	runCurrency[player] = 0
	baseBalance[player] = nil
	CurrencyUpdated:FireClient(player, playerData.currency)
	return playerData.currency
end

-- Fire the player's saved (DataStore) balance to their HUD.
-- Call on first join and after resetRun so the lobby always shows the correct total.
function CurrencyManager.refreshClientBalance(player: Player, playerData: {})
	local total = playerData and (playerData.currency or 0) or 0
	CurrencyUpdated:FireClient(player, total)
end

-- ── Shop ──────────────────────────────────────────────────────────────────────

-- Spend persistent currency (for shop purchases).
-- Returns true if successful, false if insufficient funds.
function CurrencyManager.spend(player: Player, playerData: {}, amount: number): boolean
	if playerData.currency < amount then
		return false
	end
	playerData.currency = playerData.currency - amount
	DataManager.save(player, playerData)
	return true
end

-- ── Cleanup ───────────────────────────────────────────────────────────────────

function CurrencyManager.removePlayer(player: Player)
	runCurrency[player] = nil
	baseBalance[player] = nil
end

return CurrencyManager

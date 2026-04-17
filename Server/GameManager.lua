-- GameManager.lua
-- ServerScriptService > Server > GameManager
-- The central state machine for a run. Drives round flow and coordinates all other systems.
--
-- Players start in the lobby. When a player touches a Level pad, TeleportManager
-- calls GameManager.enterLevel(player, levelNumber) — this boots a run at that
-- level's difficulty, teleports the player into the arena, and starts waves.
--
-- ⚠ Phase 1 limitation: run state is still SHARED across all players on the server
-- (one wave counter, one level). A second player touching a level pad while a run
-- is in progress will join that run. True per-player solo instancing comes next.
--
-- States: LOBBY → COUNTDOWN → WAVE_ACTIVE → WAVE_CLEAR → SHOP → GAME_OVER

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local Constants        = require(ReplicatedStorage.Shared.Constants)
local WaveManager      = require(script.Parent.WaveManager)
local CurrencyManager  = require(script.Parent.CurrencyManager)
local DataManager      = require(script.Parent.DataManager)
local CombatManager    = require(script.Parent.CombatManager)
local TeleportManager  = require(script.Parent.TeleportManager)
local WeaponGiver      = require(script.Parent.WeaponGiver)
local ShopManager      = require(script.Parent.ShopManager)

local Remotes          = ReplicatedStorage:WaitForChild("Remotes")
local StateChanged     = Remotes:WaitForChild("StateChanged")

local GameManager = {}

-- State enum
GameManager.State = {
	LOBBY       = "LOBBY",
	COUNTDOWN   = "COUNTDOWN",
	WAVE_ACTIVE = "WAVE_ACTIVE",
	WAVE_CLEAR  = "WAVE_CLEAR",
	SHOP        = "SHOP",
	GAME_OVER   = "GAME_OVER",
}

local currentState = GameManager.State.LOBBY
local currentWave  = 0
local currentLevel = 0     -- 0 = no run active (in lobby)
local runActive    = false -- true while any player is in a level run

-- Per-player data cache (loaded on join, saved on wave end / game over)
local playerData: { [Player]: {} } = {}

-- Players currently participating in the active run
local runParticipants: { [Player]: boolean } = {}

-- ─── Helpers ─────────────────────────────────────────────────────────────────

local function setState(newState: string)
	currentState = newState
	-- Include currentLevel so the client can look up the active level's wave
	-- count from Constants and render the HUD correctly during COUNTDOWN
	-- (before WaveStarted fires).
	StateChanged:FireAllClients(newState, currentWave, currentLevel)
	print("[GameManager] State →", newState)
end

local function getLevelConfig(levelNumber: number)
	return Constants.LEVELS[levelNumber]
end

local function teleportRunToLobby()
	for player in pairs(runParticipants) do
		TeleportManager.teleportToLobby(player)
	end
end

-- ─── Round flow ──────────────────────────────────────────────────────────────

local function startCountdown()
	setState(GameManager.State.COUNTDOWN)
	task.wait(Constants.WAVE_COUNTDOWN)
	GameManager.startNextWave()
end

function GameManager.startNextWave()
	currentWave = currentWave + 1

	local cfg = getLevelConfig(currentLevel)
	local waveCount = cfg and cfg.waves or Constants.WAVES_PER_RUN

	if currentWave > waveCount then
		-- Cleared all waves for this level
		GameManager.onZoneCleared()
		return
	end

	setState(GameManager.State.WAVE_ACTIVE)
	WaveManager.startWave(currentWave, currentLevel)
end

-- Called by WaveManager when all zombies die
function GameManager.onWaveClear()
	setState(GameManager.State.WAVE_CLEAR)

	local cfg = getLevelConfig(currentLevel)
	local waveCount = cfg and cfg.waves or Constants.WAVES_PER_RUN

	if currentWave == waveCount then
		task.wait(2)
		GameManager.onZoneCleared()
	else
		task.wait(3)
		startCountdown()
	end
end

function GameManager.onZoneCleared()
	-- Persist currency and record zone clear for each participant
	for player in pairs(runParticipants) do
		if playerData[player] then
			playerData[player].zonesCleared = (playerData[player].zonesCleared or 0) + 1
			-- Weapon resets to Fists on zone clear; stats/pets persist
			playerData[player].weapons.equipped = "Fists"
			CurrencyManager.persistRunCurrency(player, playerData[player])
		end
	end
	setState(GameManager.State.SHOP)

	-- Return everyone to the lobby — they can buy upgrades and re-enter a level
	task.wait(1.5)
	teleportRunToLobby()
	GameManager.resetRun()
end

function GameManager.onPlayerDied(player: Player)
	if currentState ~= GameManager.State.WAVE_ACTIVE then return end
	if not runParticipants[player] then return end

	-- Persist whatever currency they earned before dying
	if playerData[player] then
		CurrencyManager.persistRunCurrency(player, playerData[player])
	end

	-- Simple rule for now: any death ends the run (works fine for solo).
	-- When multiplayer squads are added, change this to "only end if all dead".
	setState(GameManager.State.GAME_OVER)
	task.wait(3)
	teleportRunToLobby()
	GameManager.resetRun()
end

-- Resets run state and returns the game to LOBBY.
function GameManager.resetRun()
	currentWave = 0
	currentLevel = 0
	runActive = false
	runParticipants = {}
	WaveManager.reset()

	for _, player in ipairs(Players:GetPlayers()) do
		CurrencyManager.initPlayer(player)
	end
	setState(GameManager.State.LOBBY)

	-- After the run ends, refresh every player's currency HUD with their saved
	-- DataStore total so the lobby display always shows real persistent balance.
	for _, player in ipairs(Players:GetPlayers()) do
		if playerData[player] then
			CurrencyManager.refreshClientBalance(player, playerData[player])
		end
	end
end

-- ─── Lobby → Level entry point ───────────────────────────────────────────────

-- Called by TeleportManager when a player touches a Level pad.
function GameManager.enterLevel(player: Player, levelNumber: number)
	local cfg = getLevelConfig(levelNumber)
	if not cfg then
		warn("[GameManager] Unknown level", levelNumber)
		return
	end

	-- If a run is already in progress, just drop this player into it.
	-- (Phase 1 behavior — see the note at the top of this file.)
	if runActive then
		if currentLevel ~= levelNumber then
			-- A different level is being played. Ignore for now — force them
			-- into the active level rather than spinning up a second run.
			warn(string.format(
				"[GameManager] %s tried to enter Level %d but Level %d is active",
				player.Name, levelNumber, currentLevel
			))
		end
		runParticipants[player] = true
		TeleportManager.teleportToArena(player, currentLevel)
		return
	end

	-- Start a fresh run at this level
	runActive = true
	currentLevel = levelNumber
	currentWave = 0
	runParticipants[player] = true

	-- startRun records the saved balance so awardKill can display saved + earned
	CurrencyManager.startRun(player, (playerData[player] and playerData[player].currency) or 0)
	TeleportManager.teleportToArena(player, levelNumber)

	print(string.format("[GameManager] %s started %s", player.Name, cfg.name))
	startCountdown()
end

-- Called by TeleportManager when a player touches a ReturnToLobby pad.
function GameManager.returnToLobby(player: Player)
	-- Always physically teleport them back first
	TeleportManager.teleportToLobby(player)

	if not runParticipants[player] then return end

	-- Save any currency earned during this run before we clear state.
	-- Without this, kill earnings are lost when the player manually exits a level.
	if playerData[player] then
		CurrencyManager.persistRunCurrency(player, playerData[player])
	end

	runParticipants[player] = nil

	-- If they were the last one in the run, end it for the whole server.
	local anyoneLeft = next(runParticipants) ~= nil
	if not anyoneLeft and runActive then
		print("[GameManager] Last participant left — aborting run")
		WaveManager.reset()
		GameManager.resetRun()
	end
end

-- ─── Player lifecycle ────────────────────────────────────────────────────────

function GameManager.onPlayerAdded(player: Player)
	playerData[player] = DataManager.load(player)
	CurrencyManager.initPlayer(player)

	-- Seed the lobby currency HUD with the player's saved DataStore balance.
	-- A short delay lets the client finish initializing its RemoteEvent listeners
	-- before we fire — avoids the event being dropped on first join.
	task.delay(1.5, function()
		if playerData[player] then
			CurrencyManager.refreshClientBalance(player, playerData[player])
		end
	end)

	-- Wire up death detection and weapon re-giving on every spawn.
	-- Roblox clears the Backpack on each respawn, so we must re-clone owned Tools each time.
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid")
		humanoid.Died:Connect(function()
			GameManager.onPlayerDied(player)
		end)

		if playerData[player] then
			WeaponGiver.giveOwnedWeapons(player, playerData[player])
		end
	end)

	-- If the player already has a character when this runs (e.g. Studio play-test),
	-- give weapons immediately rather than waiting for the next CharacterAdded.
	if player.Character and playerData[player] then
		WeaponGiver.giveOwnedWeapons(player, playerData[player])
	end
end

function GameManager.onPlayerRemoving(player: Player)
	if playerData[player] then
		CurrencyManager.persistRunCurrency(player, playerData[player])
	end
	CurrencyManager.removePlayer(player)
	CombatManager.removePlayer(player)
	TeleportManager.removePlayer(player)
	runParticipants[player] = nil
	playerData[player] = nil

	-- If their exit drains the run, clean up.
	if runActive and next(runParticipants) == nil then
		WaveManager.reset()
		GameManager.resetRun()
	end
end

-- ─── Initialise ──────────────────────────────────────────────────────────────

function GameManager.init()
	-- Connect WaveManager callback
	WaveManager.setOnWaveClear(GameManager.onWaveClear)

	-- Init CombatManager with a getter so it can read player data
	CombatManager.init(function(player: Player)
		return playerData[player]
	end)

	-- Init ShopManager with the same getter pattern
	ShopManager.init(function(player: Player)
		return playerData[player]
	end)

	-- Let TeleportManager dispatch level / return-pad events into us
	TeleportManager.init(GameManager)

	-- Connect player events
	Players.PlayerAdded:Connect(GameManager.onPlayerAdded)
	Players.PlayerRemoving:Connect(GameManager.onPlayerRemoving)

	-- Handle players already in game (e.g. during Studio testing)
	for _, player in ipairs(Players:GetPlayers()) do
		GameManager.onPlayerAdded(player)
	end

	-- Weapon switching: client fires this when a Tool is equipped or unequipped.
	-- We update playerData so CombatManager always uses the correct weapon stats.
	local WeaponEquipped = Remotes:WaitForChild("WeaponEquipped")
	WeaponEquipped.OnServerEvent:Connect(function(player: Player, weaponName: string)
		if playerData[player] then
			playerData[player].weapons.equipped = weaponName
			print(string.format("[GameManager] %s equipped %s", player.Name, weaponName))
		end
	end)

	print("[GameManager] Initialized — waiting in LOBBY")
	setState(GameManager.State.LOBBY)
	-- No auto-start: the game begins when a player touches a Level pad.
end

return GameManager

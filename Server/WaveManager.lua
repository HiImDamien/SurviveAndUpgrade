-- WaveManager.lua
-- ServerScriptService > Server > WaveManager
-- Spawns enemies per wave, tracks alive count, fires wave-clear when all die.
-- Now arena-aware: enemies spawn inside the arena for the active level, and
-- difficulty scales from Constants.LEVELS[level].scalar instead of the global
-- wave-number tier.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")
local Constants    = require(ReplicatedStorage.Shared.Constants)
local EnemyAI      = require(script.Parent.EnemyAI)
local ArenaBuilder = require(script.Parent.ArenaBuilder)

-- RemoteEvents
local Remotes           = ReplicatedStorage:WaitForChild("Remotes")
local WaveStarted       = Remotes:WaitForChild("WaveStarted")
local WaveCleared       = Remotes:WaitForChild("WaveCleared")
local EnemyCountUpdated = Remotes:WaitForChild("EnemyCountUpdated")

local WaveManager = {}

local aliveCount  = 0
local currentWave = 0
local currentLevel = 0  -- which Constants.LEVELS[n] is active
local onWaveClearCallback: (() -> ())? = nil

-- Incremented every reset so stale task.delay spawn callbacks can detect
-- they belong to an old run and exit without spawning anything.
local runGeneration = 0

-- Currently-alive enemies we've spawned (used for reset cleanup).
local activeEnemies: { [Model]: boolean } = {}

local function getLevelScalar(): number
	local cfg = Constants.LEVELS[currentLevel]
	return (cfg and cfg.scalar) or Constants.WAVE_SCALAR_EASY
end

local function isBossWave(waveNumber: number, waveCount: number): boolean
	-- Boss waves: last wave of the level, plus thirds along the way.
	return waveNumber == waveCount
		or waveNumber == math.floor(waveCount / 3)
		or waveNumber == math.floor((waveCount * 2) / 3)
end

-- Pick a spawn CFrame inside the current level's arena.
local function getSpawnCFrame(): CFrame
	local cframe = ArenaBuilder.getRandomEnemySpawnCFrame(currentLevel)
	if cframe then return cframe end
	-- Fallback if no arena set up (shouldn't happen post-boot)
	return CFrame.new(0, 5, 0)
end

local function spawnEnemy(waveNumber: number, isBoss: boolean)
	local enemyTemplate = ServerStorage:FindFirstChild("Enemy")
	if not enemyTemplate then
		warn("[WaveManager] No 'Enemy' model found in ServerStorage! Add a rig named 'Enemy'.")
		return
	end

	local enemy = enemyTemplate:Clone()
	enemy.Name = isBoss and "Boss" or "Enemy"
	enemy:SetAttribute("Level", currentLevel)

	enemy:PivotTo(getSpawnCFrame())

	-- Park enemies under workspace.Arenas.Arena_<n> so they stay organised
	local arena = ArenaBuilder.getArena(currentLevel)
	enemy.Parent = arena or workspace

	-- Set health based on level difficulty
	local scalar = getLevelScalar()
	local humanoid: Humanoid = enemy:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.MaxHealth = Constants.ENEMY_BASE_HEALTH * scalar * (isBoss and 10 or 1)
		humanoid.Health    = humanoid.MaxHealth

		activeEnemies[enemy] = true

		humanoid.Died:Connect(function()
			activeEnemies[enemy] = nil
			WaveManager.onEnemyDied()
			EnemyAI.onDied(enemy)
		end)
	end

	-- Start AI movement
	local aiScalar = scalar * (isBoss and 1.5 or 1)
	EnemyAI.startAI(enemy, aiScalar)
end

-- Register a callback for when all enemies in a wave die
function WaveManager.setOnWaveClear(callback: () -> ())
	onWaveClearCallback = callback
end

-- Start a wave. `levelNumber` tells us which arena + difficulty to use.
function WaveManager.startWave(waveNumber: number, levelNumber: number)
	currentWave  = waveNumber
	currentLevel = levelNumber

	local cfg       = Constants.LEVELS[levelNumber]
	local waveCount = (cfg and cfg.waves) or Constants.WAVES_PER_RUN

	local enemyCount: number
	if isBossWave(waveNumber, waveCount) then
		enemyCount = 1  -- single boss
	else
		enemyCount = Constants.BASE_ENEMY_COUNT + (waveNumber * Constants.ENEMIES_PER_WAVE_INCREASE)
	end

	aliveCount = enemyCount

	-- Notify clients (include wave count so UI can show "3 / 20" etc. later)
	WaveStarted:FireAllClients(waveNumber, enemyCount, waveCount)

	local scalar = getLevelScalar()
	local myGeneration = runGeneration  -- capture now; checked inside each delayed spawn
	for i = 1, enemyCount do
		task.delay((i - 1) * 0.5, function()  -- stagger spawns by 0.5s
			-- If the run was reset while we were waiting, don't spawn
			if runGeneration ~= myGeneration then return end
			spawnEnemy(waveNumber, isBossWave(waveNumber, waveCount))
		end)
	end

	print(string.format(
		"[WaveManager] Level %d — Wave %d/%d started (%d enemies, scalar %.2f)",
		levelNumber, waveNumber, waveCount, enemyCount, scalar
	))
end

-- Called whenever any enemy dies
function WaveManager.onEnemyDied()
	aliveCount = math.max(0, aliveCount - 1)
	EnemyCountUpdated:FireAllClients(aliveCount)

	if aliveCount <= 0 then
		WaveCleared:FireAllClients(currentWave)
		if onWaveClearCallback then
			onWaveClearCallback()
		end
	end
end

-- Reset state between runs. Destroys all tracked enemies.
function WaveManager.reset()
	runGeneration += 1  -- invalidates any pending task.delay spawn callbacks
	aliveCount  = 0
	currentWave = 0
	currentLevel = 0

	for enemy in pairs(activeEnemies) do
		if enemy and enemy.Parent then
			enemy:Destroy()
		end
	end
	activeEnemies = {}

	-- Belt-and-suspenders: clean up anything still tagged as enemy in arenas
	local arenas = workspace:FindFirstChild("Arenas")
	if arenas then
		for _, descendant in ipairs(arenas:GetDescendants()) do
			if descendant:IsA("Model") and (descendant.Name == "Enemy" or descendant.Name == "Boss") then
				descendant:Destroy()
			end
		end
	end
end

return WaveManager

-- Constants.lua
-- ReplicatedStorage > Shared > Constants
-- Shared by both server and client. All tunable game values live here.

local Constants = {}

-- Wave Settings
Constants.WAVES_PER_RUN = 30
Constants.BASE_ENEMY_COUNT = 5           -- enemies on wave 1
Constants.ENEMIES_PER_WAVE_INCREASE = 3  -- added each wave

-- Enemy Base Stats
Constants.ENEMY_BASE_HEALTH = 50
Constants.ENEMY_BASE_SPEED  = 8
Constants.ENEMY_BASE_DAMAGE = 8   -- per hit; attack rate is 1 hit per 1.5s = ~5 DPS

-- Wave difficulty scalars (applied per wave group)
Constants.WAVE_SCALAR_EASY   = 1.0   -- waves 1-10
Constants.WAVE_SCALAR_MEDIUM = 1.5   -- waves 11-20
Constants.WAVE_SCALAR_HARD   = 2.25  -- waves 21-30

-- Currency
Constants.CURRENCY_PER_KILL = 1
Constants.CURRENCY_BOSS_BONUS = 50

-- Player Base Stats
Constants.PLAYER_BASE_HEALTH = 150  -- more breathing room in early waves
Constants.PLAYER_BASE_SPEED  = 16
Constants.PLAYER_BASE_DAMAGE = 10

-- Countdown before each wave (seconds)
Constants.WAVE_COUNTDOWN = 3

-- ─── Lobby & Arena Layout ────────────────────────────────────────────────────
-- The lobby sits at the world origin. Each arena is placed far away on the X
-- axis so lobby and arenas never visually or physically overlap. All lobby-
-- and arena-building code references these coordinates; nothing is hardcoded
-- elsewhere.

Constants.LOBBY_ORIGIN = Vector3.new(0, 0, 0)
Constants.LOBBY_SPAWN  = Vector3.new(0, 5, 0)    -- where players spawn / return
Constants.LOBBY_SIZE   = Vector3.new(200, 1, 200)

-- Per-level configuration. Level pads in the lobby read from this table.
-- scalar  = multiplier applied to enemy health/speed/damage (already exists
--           as WAVE_SCALAR_* — levels reuse those)
-- waves   = number of waves in that level's run
-- origin  = world position of this arena's floor center
Constants.LEVELS = {
	[1] = {
		name       = "Level 1 — Easy",
		scalar     = Constants.WAVE_SCALAR_EASY,
		waves      = 10,
		origin     = Vector3.new(500, 0, 0),
		arenaSize  = Vector3.new(150, 1, 150),
		padColor   = Color3.fromRGB(60, 200, 90),
	},
	[2] = {
		name       = "Level 2 — Medium",
		scalar     = Constants.WAVE_SCALAR_MEDIUM,
		waves      = 20,
		origin     = Vector3.new(1000, 0, 0),
		arenaSize  = Vector3.new(180, 1, 180),
		padColor   = Color3.fromRGB(230, 180, 40),
	},
	[3] = {
		name       = "Level 3 — Hard",
		scalar     = Constants.WAVE_SCALAR_HARD,
		waves      = 30,
		origin     = Vector3.new(1500, 0, 0),
		arenaSize  = Vector3.new(220, 1, 220),
		padColor   = Color3.fromRGB(220, 60, 60),
	},
}

return Constants

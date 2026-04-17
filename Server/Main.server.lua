-- Main.server.lua
-- ServerScriptService > Main  (this must be a Script, NOT a ModuleScript)
-- Entry point for all server-side logic. Creates RemoteEvents, builds the
-- lobby + arenas, then boots GameManager.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ─── Create Remotes folder and all RemoteEvents ───────────────────────────────
-- We create them here on the server so they exist before any client tries to find them.

local Remotes = Instance.new("Folder")
Remotes.Name = "Remotes"
Remotes.Parent = ReplicatedStorage

local function makeRemote(name: string)
	local re = Instance.new("RemoteEvent")
	re.Name = name
	re.Parent = Remotes
end

local function makeRemoteFunction(name: string)
	local rf = Instance.new("RemoteFunction")
	rf.Name = name
	rf.Parent = Remotes
end

-- Core gameplay
makeRemote("StateChanged")      -- server → client: game state updates
makeRemote("WaveStarted")       -- server → client: wave number + enemy count + wave total
makeRemote("WaveCleared")       -- server → client: wave number cleared
makeRemote("CurrencyUpdated")   -- server → client: current run currency
makeRemote("PlayerAttack")      -- client → server: player swung their weapon
makeRemote("EnemyCountUpdated") -- server → client: enemies remaining in current wave

-- Lobby interactions (pads)
makeRemote("OpenShop")          -- server → client: open the shop panel
makeRemote("OpenInventory")     -- server → client: open the inventory panel
makeRemote("ShopClosed")        -- client → server: player dismissed the shop UI

-- Weapon system
makeRemote("WeaponEquipped")    -- client → server: player switched to a different Tool
makeRemote("BulletFired")       -- server → client: show bullet trail (origin, endpoint)

-- Shop system
makeRemoteFunction("GetShopData")    -- client → server: fetch owned weapons + currency
makeRemoteFunction("PurchaseWeapon") -- client → server: buy a weapon, returns result

-- ─── Build world ─────────────────────────────────────────────────────────────

local LobbyBuilder = require(script.Parent.Server.LobbyBuilder)
local ArenaBuilder = require(script.Parent.Server.ArenaBuilder)

LobbyBuilder.build()
ArenaBuilder.build()

-- ─── Boot game systems ───────────────────────────────────────────────────────

local GameManager = require(script.Parent.Server.GameManager)
GameManager.init()

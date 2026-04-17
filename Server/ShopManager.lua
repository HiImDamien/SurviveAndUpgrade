-- ShopManager.lua
-- ServerScriptService > Server > ShopManager
-- Handles all shop interactions: fetching player weapon data for the UI,
-- and processing weapon purchase requests with full server-side validation.
-- Currency deduction and DataStore saving happen here — client is never trusted.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponDefinitions = require(ReplicatedStorage.Shared.WeaponDefinitions)
local DataManager       = require(script.Parent.DataManager)
local CurrencyManager   = require(script.Parent.CurrencyManager)
local WeaponGiver       = require(script.Parent.WeaponGiver)

local Remotes         = ReplicatedStorage:WaitForChild("Remotes")
local GetShopData     = Remotes:WaitForChild("GetShopData")
local PurchaseWeapon  = Remotes:WaitForChild("PurchaseWeapon")

local ShopManager = {}

-- getPlayerData: (Player) -> playerData table, injected by GameManager
function ShopManager.init(getPlayerData: (Player) -> {}?)

	-- ── GetShopData ──────────────────────────────────────────────────────────
	-- Client calls this when the shop panel opens to get current owned weapons
	-- and currency so it can render Owned/Buy/CantAfford states correctly.
	GetShopData.OnServerInvoke = function(player: Player)
		local data = getPlayerData(player)
		if not data then
			return { owned = {}, currency = 0 }
		end
		return {
			owned    = (data.weapons and data.weapons.owned) or {},
			currency = data.currency or 0,
		}
	end

	-- ── PurchaseWeapon ───────────────────────────────────────────────────────
	-- Client calls this when the player clicks "BUY" on a weapon card.
	-- Returns a result table so the client can update the UI without re-fetching.
	PurchaseWeapon.OnServerInvoke = function(player: Player, weaponName: string)
		local data = getPlayerData(player)
		if not data then
			return { success = false, message = "Data not ready" }
		end

		-- Validate weapon exists
		local weaponDef = WeaponDefinitions[weaponName]
		if not weaponDef then
			return { success = false, message = "Unknown weapon" }
		end

		-- Can't buy Fists — always free and always owned
		if weaponName == "Fists" then
			return { success = false, message = "Already owned" }
		end

		-- Already purchased?
		if data.weapons and data.weapons.owned and data.weapons.owned[weaponName] then
			return { success = false, message = "Already owned" }
		end

		-- Enough currency?
		local cost = weaponDef.unlockCost
		if (data.currency or 0) < cost then
			return { success = false, message = "Not enough $" }
		end

		-- Deduct currency and save
		local ok = CurrencyManager.spend(player, data, cost)
		if not ok then
			return { success = false, message = "Purchase failed" }
		end

		-- Add weapon to owned set
		if not data.weapons then data.weapons = {} end
		if not data.weapons.owned then data.weapons.owned = {} end
		data.weapons.owned[weaponName] = { level = 1 }

		-- Persist to DataStore
		DataManager.save(player, data)

		-- Put the new weapon in their backpack immediately (if they have one)
		WeaponGiver.giveOwnedWeapons(player, data)

		-- Push new currency balance to client HUD
		CurrencyManager.refreshClientBalance(player, data)

		print(string.format("[ShopManager] %s purchased %s for $%d (balance: $%d)",
			player.Name, weaponName, cost, data.currency))

		return {
			success  = true,
			message  = "Purchased!",
			owned    = data.weapons.owned,
			currency = data.currency,
		}
	end

	print("[ShopManager] Initialized")
end

return ShopManager

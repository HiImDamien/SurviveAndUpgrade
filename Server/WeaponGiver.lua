-- WeaponGiver.lua
-- ServerScriptService > Server > WeaponGiver
-- Clones owned weapon Tools from ServerStorage/WeaponModels into a player's Backpack.
-- Called on join, on every respawn (Roblox clears Backpack on respawn), and after purchase.
-- Fists are always skipped — bare hands are the default, no Tool model needed.

local ServerStorage = game:GetService("ServerStorage")

local WeaponGiver = {}

local WeaponModels = ServerStorage:WaitForChild("WeaponModels")

-- Clone all owned weapons into the player's Backpack.
-- Safe to call multiple times — skips anything already in the backpack or equipped.
function WeaponGiver.giveOwnedWeapons(player: Player, playerData: {})
	local ownedWeapons = (playerData.weapons and playerData.weapons.owned) or {}
	print(string.format("[WeaponGiver] giveOwnedWeapons called for %s — owned: %s",
		player.Name, table.concat((function()
			local names = {}
			for k in pairs(ownedWeapons) do table.insert(names, k) end
			return names
		end)(), ", ")))

	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		warn(string.format("[WeaponGiver] No Backpack found for %s — skipping", player.Name))
		return
	end

	for weaponName in pairs(ownedWeapons) do
		if weaponName == "Fists" then continue end  -- no Tool for bare hands

		-- Don't duplicate if already in backpack or currently held (in character)
		if backpack:FindFirstChild(weaponName) then continue end
		local char = player.Character
		if char and char:FindFirstChild(weaponName) then continue end

		local model = WeaponModels:FindFirstChild(weaponName)
		if model then
			model:Clone().Parent = backpack
			print(string.format("[WeaponGiver] Gave %s to %s", weaponName, player.Name))
		else
			warn(string.format("[WeaponGiver] No model found in WeaponModels for: %s", weaponName))
		end
	end
end

return WeaponGiver

-- WeaponDefinitions.lua
-- ReplicatedStorage > Shared > WeaponDefinitions
-- Defines all weapons, their base stats, upgrade levels, and costs.
-- Weapons are permanent unlocks; each has 10 upgrade levels.

local WeaponDefinitions = {}

-- Unlock path (player can buy in any order based on price):
-- Fists (free) → Knife → Bat → Sword → Pistol → Shotgun → (more TBD)

WeaponDefinitions.Fists = {
	unlockCost = 0,        -- free default weapon
	baseStats  = { damage = 5, speed = 1.0, range = 4 },
	upgradeLevels = {
		[2]  = { damage = 7 },
		[5]  = { damage = 10, speed = 1.1 },
		[10] = { damage = 15, speed = 1.2 },
	},
	upgradeCosts = { 25, 40, 60, 80, 100, 130, 160, 200, 250 }, -- levels 2-10
}

WeaponDefinitions.Knife = {
	unlockCost = 100,
	baseStats  = { damage = 15, speed = 1.5, range = 3 },
	upgradeLevels = {
		[2]  = { damage = 20 },
		[5]  = { damage = 30, speed = 1.8 },
		[10] = { damage = 50, speed = 2.0, bleed = true },
	},
	upgradeCosts = { 50, 75, 100, 150, 200, 250, 300, 400, 500 },
}

WeaponDefinitions.Bat = {
	unlockCost = 250,
	baseStats  = { damage = 25, speed = 0.9, range = 5 },
	upgradeLevels = {
		[2]  = { damage = 32 },
		[5]  = { damage = 45, knockback = true },
		[10] = { damage = 70, speed = 1.1, knockback = true },
	},
	upgradeCosts = { 75, 110, 150, 200, 260, 320, 400, 500, 650 },
}

WeaponDefinitions.Sword = {
	unlockCost = 500,
	baseStats  = { damage = 40, speed = 1.0, range = 6 },
	upgradeLevels = {
		[2]  = { damage = 50 },
		[5]  = { damage = 70, range = 7 },
		[10] = { damage = 110, range = 8, bleed = true },
	},
	upgradeCosts = { 100, 150, 200, 275, 350, 450, 575, 725, 900 },
}

-- Ranged weapons (TBD — stats placeholders)
WeaponDefinitions.Pistol = {
	unlockCost = 800,
	baseStats  = { damage = 30, speed = 1.2, range = 20, ranged = true },
	upgradeLevels = {
		[2]  = { damage = 38 },
		[5]  = { damage = 55, speed = 1.4 },
		[10] = { damage = 80, speed = 1.6, pierce = true },
	},
	upgradeCosts = { 150, 220, 300, 400, 520, 650, 800, 1000, 1300 },
}

WeaponDefinitions.Shotgun = {
	unlockCost = 1200,
	baseStats  = { damage = 20, speed = 0.6, range = 10, ranged = true, pellets = 5 },
	upgradeLevels = {
		[2]  = { damage = 26 },
		[5]  = { pellets = 7, damage = 30 },
		[10] = { pellets = 9, damage = 40, speed = 0.8 },
	},
	upgradeCosts = { 200, 300, 420, 560, 720, 900, 1100, 1400, 1800 },
}

return WeaponDefinitions

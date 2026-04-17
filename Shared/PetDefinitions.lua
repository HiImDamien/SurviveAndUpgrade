-- PetDefinitions.lua
-- ReplicatedStorage > Shared > PetDefinitions
-- Defines all pets, rarities, bonus types, and per-level bonuses.
-- Pets obtained via loot boxes (weighted by rarity) or milestone rewards.

local PetDefinitions = {}

-- Rarity tiers (used for loot box weighting — weights TBD)
PetDefinitions.Rarities = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }

-- ─── Stat Boost Pets ─────────────────────────────────────────────────────────

PetDefinitions.FireFox = {
	displayName  = "Fire Fox",
	rarity       = "Rare",
	bonusType    = "damage",                     -- flat damage added to attacks
	bonusPerLevel = { 5, 10, 16, 23, 32 },       -- levels 1-5
}

PetDefinitions.StoneTurtle = {
	displayName  = "Stone Turtle",
	rarity       = "Common",
	bonusType    = "health",                     -- added to max health
	bonusPerLevel = { 25, 45, 70, 100, 140 },
}

PetDefinitions.WindFerret = {
	displayName  = "Wind Ferret",
	rarity       = "Uncommon",
	bonusType    = "speed",                      -- added to walk speed
	bonusPerLevel = { 2, 4, 6, 9, 13 },
}

-- ─── Active Attacker Pets ─────────────────────────────────────────────────────

PetDefinitions.GuardDog = {
	displayName  = "Guard Dog",
	rarity       = "Uncommon",
	bonusType    = "attacker",
	bonusPerLevel = {
		{ damage = 5,  cooldown = 3.0, range = 15 },
		{ damage = 12, cooldown = 2.5, range = 15 },
		{ damage = 22, cooldown = 2.0, range = 18 },
		{ damage = 35, cooldown = 1.5, range = 18 },
		{ damage = 52, cooldown = 1.0, range = 20 },
	},
}

PetDefinitions.PhoenixHawk = {
	displayName  = "Phoenix Hawk",
	rarity       = "Epic",
	bonusType    = "attacker",
	bonusPerLevel = {
		{ damage = 15, cooldown = 2.5, range = 20 },
		{ damage = 28, cooldown = 2.0, range = 22 },
		{ damage = 44, cooldown = 1.8, range = 24 },
		{ damage = 65, cooldown = 1.5, range = 26 },
		{ damage = 90, cooldown = 1.2, range = 28 },
	},
}

-- ─── Utility Pets ─────────────────────────────────────────────────────────────

PetDefinitions.ShadowCat = {
	displayName  = "Shadow Cat",
	rarity       = "Rare",
	bonusType    = "wallhack",   -- highlights enemies through walls (client-side)
	bonusPerLevel = { true, true, true, true, true },  -- toggle, level just increases range TBD
}

-- ─── Legendary ────────────────────────────────────────────────────────────────

PetDefinitions.CosmicDragon = {
	displayName  = "Cosmic Dragon",
	rarity       = "Legendary",
	bonusType    = "attacker",
	bonusPerLevel = {
		{ damage = 40, cooldown = 2.0, range = 30 },
		{ damage = 70, cooldown = 1.8, range = 32 },
		{ damage = 110, cooldown = 1.5, range = 34 },
		{ damage = 160, cooldown = 1.2, range = 36 },
		{ damage = 220, cooldown = 1.0, range = 40 },
	},
}

return PetDefinitions

-- CombatManager.lua
-- ServerScriptService > Server > CombatManager
-- Handles player attack requests from the client.
-- Validates range, applies damage, awards currency on kill.
-- Server is fully authoritative — client only sends attack intent.
--
-- Ranged weapons: client sends mouse.Hit.Position as an aim target.
-- The server casts a ray from the player's position toward that point
-- and deals damage only if an actual enemy is hit within weapon range.
-- A BulletFired event is sent to all clients for the visual trail.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants         = require(ReplicatedStorage.Shared.Constants)
local WeaponDefinitions = require(ReplicatedStorage.Shared.WeaponDefinitions)
local CurrencyManager   = require(script.Parent.CurrencyManager)

local Remotes       = ReplicatedStorage:WaitForChild("Remotes")
local PlayerAttack  = Remotes:WaitForChild("PlayerAttack")
local BulletFired   = Remotes:WaitForChild("BulletFired")

local CombatManager = {}

-- Track last attack time per player for cooldown enforcement
local lastAttackTime: { [Player]: number } = {}

-- ─── Helpers ─────────────────────────────────────────────────────────────────

-- Builds the effective weapon stats for a player based on their equipped weapon,
-- upgrade level, and strength multiplier from their upgrade tree.
-- All baseStats fields are forwarded so ranged/pellets flags come through too.
local function getWeaponStats(playerData: {}): {}
	local weaponName = playerData.weapons and playerData.weapons.equipped or "Fists"
	local weaponDef  = WeaponDefinitions[weaponName] or WeaponDefinitions.Fists
	if not weaponDef then weaponName = "Fists"; weaponDef = WeaponDefinitions.Fists end

	local ownedWeapons = playerData.weapons and playerData.weapons.owned or {}
	local level = (ownedWeapons[weaponName] and ownedWeapons[weaponName].level) or 1

	-- Start with ALL base stats (preserves ranged, pellets, etc.)
	local stats = {}
	for k, v in pairs(weaponDef.baseStats) do
		stats[k] = v
	end

	-- Apply upgrade level overrides (higher levels layer on top)
	for upgradeLevel, overrides in pairs(weaponDef.upgradeLevels) do
		if level >= upgradeLevel then
			for stat, value in pairs(overrides) do
				if type(value) == "number" then
					stats[stat] = value
				elseif type(value) == "boolean" then
					stats[stat] = value
				end
			end
		end
	end

	-- Apply strength multiplier from upgrade tree
	local strengthMult = (playerData.upgrades and playerData.upgrades.strength) or 1.0
	stats.damage = stats.damage * strengthMult

	return stats
end

-- Returns enemies within melee range of an origin point, sorted closest-first.
-- Enemies live under workspace.Arenas.Arena_<n>.
local function getEnemiesInRange(origin: Vector3, range: number): { Model }
	local found = {}
	local arenas = workspace:FindFirstChild("Arenas")
	if not arenas then return found end

	for _, obj in ipairs(arenas:GetDescendants()) do
		if (obj.Name == "Enemy" or obj.Name == "Boss") and obj:IsA("Model") then
			local root     = obj:FindFirstChild("HumanoidRootPart")
			local humanoid = obj:FindFirstChildOfClass("Humanoid")
			if root and humanoid and humanoid.Health > 0 then
				local dist = ((root :: BasePart).Position - origin).Magnitude
				if dist <= range then
					table.insert(found, { model = obj, dist = dist })
				end
			end
		end
	end
	table.sort(found, function(a, b) return a.dist < b.dist end)

	local models = {}
	for _, entry in ipairs(found) do
		table.insert(models, entry.model)
	end
	return models
end

-- Casts a single ray from `origin` toward `targetPos`, returns the hit enemy
-- model and the exact world hit position (for the bullet trail endpoint).
-- Returns nil, nil if nothing was hit within `maxRange`.
local function raycastForEnemy(origin: Vector3, targetPos: Vector3, maxRange: number, ignoreModel: Model)
	local direction = (targetPos - origin)
	local dist      = direction.Magnitude

	-- Normalise and clamp to weapon range
	local unitDir = direction.Unit
	local castDist = math.min(dist, maxRange)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ignoreModel }

	local result = workspace:Raycast(origin, unitDir * castDist, params)
	if not result then
		-- Nothing hit — return the max-range endpoint for the trail
		return nil, origin + unitDir * castDist
	end

	local hit    = result.Instance
	local endPos = result.Position

	-- Walk the full ancestor chain — FindFirstAncestorOfClass only returns the
	-- first Model going up, which could be an accessory or sub-model inside the
	-- enemy rig. We keep walking until we find one named "Enemy" or "Boss".
	local current = hit.Parent
	while current and current ~= workspace do
		if current:IsA("Model") and (current.Name == "Enemy" or current.Name == "Boss") then
			local humanoid = current:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				return current :: Model, endPos
			end
			break  -- found the right model but it's already dead — stop searching
		end
		current = current.Parent
	end

	-- Hit something (wall, floor) but not an enemy
	return nil, endPos
end

-- ─── Attack handler ───────────────────────────────────────────────────────────

-- targetPos: Vector3 sent by the client (mouse.Hit.Position). May be nil for
-- melee weapons or old clients — falls back gracefully.
local function handleAttack(player: Player, playerData: {}, targetPos: Vector3?)
	local char = player.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart
	if not root then return end

	local stats    = getWeaponStats(playerData)
	local cooldown = 1 / stats.speed  -- speed = attacks per second

	-- Server-side cooldown enforcement
	local now = tick()
	if lastAttackTime[player] and (now - lastAttackTime[player]) < (cooldown * 0.8) then
		return
	end
	lastAttackTime[player] = now

	-- ── Ranged path ──────────────────────────────────────────────────────────
	if stats.ranged then
		-- Need a target direction — if client didn't send one, shoot straight ahead
		local aimPos = targetPos or (root.Position + root.CFrame.LookVector * stats.range)

		if stats.pellets and stats.pellets > 1 then
			-- Shotgun: fire N pellets in a spread cone
			local pelletDamage = stats.damage / stats.pellets  -- damage split across pellets
			local spreadAngle  = 10  -- degrees half-angle

			for _ = 1, stats.pellets do
				-- Randomise direction within a cone
				local angle   = math.rad(spreadAngle)
				local randVec = Vector3.new(
					math.random() * 2 - 1,
					math.random() * 2 - 1,
					math.random() * 2 - 1
				).Unit * math.tan(angle)
				local baseDir  = (aimPos - root.Position).Unit
				local spreadDir = (baseDir + randVec).Unit
				local pelletTarget = root.Position + spreadDir * stats.range

				local hitModel, endPos = raycastForEnemy(root.Position, pelletTarget, stats.range, char)
				BulletFired:FireAllClients(root.Position, endPos)

				if hitModel then
					local humanoid = hitModel:FindFirstChildOfClass("Humanoid")
					if humanoid and humanoid.Health > 0 then
						humanoid:TakeDamage(pelletDamage)
						if humanoid.Health <= 0 then
							CurrencyManager.awardKill(player, hitModel.Name == "Boss")
						end
					end
				end
			end

			print(string.format("[CombatManager] %s fired Shotgun (%d pellets)", player.Name, stats.pellets))

		else
			-- Single-shot ranged (Pistol)
			local hitModel, endPos = raycastForEnemy(root.Position, aimPos, stats.range, char)
			BulletFired:FireAllClients(root.Position, endPos)

			if hitModel then
				local humanoid = hitModel:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then
					humanoid:TakeDamage(stats.damage)
					print(string.format("[CombatManager] %s shot %s for %.1f dmg (%.1f HP left)",
						player.Name, hitModel.Name, stats.damage, humanoid.Health))
					if humanoid.Health <= 0 then
						CurrencyManager.awardKill(player, hitModel.Name == "Boss")
					end
				end
			else
				print(string.format("[CombatManager] %s fired Pistol — missed", player.Name))
			end
		end

		return
	end

	-- ── Melee path ───────────────────────────────────────────────────────────
	local enemies = getEnemiesInRange(root.Position, stats.range)
	if #enemies == 0 then return end

	local target   = enemies[1]
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	humanoid:TakeDamage(stats.damage)
	print(string.format("[CombatManager] %s hit %s for %.1f dmg (%.1f HP left)",
		player.Name, target.Name, stats.damage, humanoid.Health))

	if humanoid.Health <= 0 then
		CurrencyManager.awardKill(player, target.Name == "Boss")
	end
end

-- ─── Public API ───────────────────────────────────────────────────────────────

-- getPlayerData: function(player) -> playerData table (provided by GameManager)
function CombatManager.init(getPlayerData: (Player) -> {}?)
	-- Client now fires PlayerAttack with an optional Vector3 aim position
	PlayerAttack.OnServerEvent:Connect(function(player: Player, targetPos: Vector3?)
		local data = getPlayerData(player)
		if data then
			handleAttack(player, data, targetPos)
		end
	end)
	print("[CombatManager] Initialized")
end

function CombatManager.removePlayer(player: Player)
	lastAttackTime[player] = nil
end

return CombatManager

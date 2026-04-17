-- EnemyAI.lua
-- ServerScriptService > Server > EnemyAI
-- Handles enemy movement (direct tracking for now) and attacks.
-- Pathfinding can be upgraded to PathfindingService later without changing the interface.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Utility   = require(ReplicatedStorage.Shared.Utility)
local Constants = require(ReplicatedStorage.Shared.Constants)

local EnemyAI = {}

local ATTACK_RANGE    = 5    -- studs — how close enemy must be to swing
local ATTACK_COOLDOWN = 1.5  -- seconds between attacks (prevents machine-gun hits)
local MOVE_INTERVAL   = 0.25 -- seconds between movement updates
local MAX_TARGET_DIST = 250  -- studs — ignore players farther than this (keeps
                             -- enemies from chasing lobby players through walls)

-- Moves an enemy toward the nearest player and attacks when in range.
-- Each enemy gets its own loop via task.spawn.
function EnemyAI.startAI(enemyModel: Model, waveScalar: number)
	local humanoid: Humanoid = enemyModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	humanoid.WalkSpeed = Constants.ENEMY_BASE_SPEED * waveScalar

	local lastAttack = 0  -- timestamp of last attack (per-enemy)

	task.spawn(function()
		while enemyModel.Parent and humanoid.Health > 0 do
			if not enemyModel.PrimaryPart then break end

			local nearestPlayer, dist = Utility.getNearestPlayer(enemyModel.PrimaryPart.Position, MAX_TARGET_DIST)

			if nearestPlayer then
				local char = nearestPlayer.Character
				if char and char:FindFirstChild("HumanoidRootPart") then
					humanoid:MoveTo(char.HumanoidRootPart.Position)

					-- Attack only if in range AND cooldown has passed
					local now = tick()
					if dist <= ATTACK_RANGE and (now - lastAttack) >= ATTACK_COOLDOWN then
						lastAttack = now
						EnemyAI.attack(enemyModel, nearestPlayer, waveScalar)
					end
				end
			end

			task.wait(MOVE_INTERVAL)
		end
	end)
end

-- Deals damage to the target player (server-side only)
function EnemyAI.attack(enemyModel: Model, player: Player, waveScalar: number)
	local char = player.Character
	if not char then return end
	local humanoid: Humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local damage = Constants.ENEMY_BASE_DAMAGE * waveScalar
	humanoid:TakeDamage(damage)
	print(string.format("[EnemyAI] %s hit %s for %.1f damage", enemyModel.Name, player.Name, damage))
end

-- Called when an enemy dies — cleans up the model after a short delay
function EnemyAI.onDied(enemyModel: Model)
	task.delay(1, function()
		if enemyModel and enemyModel.Parent then
			enemyModel:Destroy()
		end
	end)
end

return EnemyAI

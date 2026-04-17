-- InputHandler.lua
-- StarterPlayer > StarterPlayerScripts > Client > InputHandler
-- Handles all player input: attacking, interacting with shop, etc.
-- Supports mouse/keyboard AND controller. Mobile not yet implemented.
-- Input is detected client-side; damage is always processed server-side.

local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local Remotes         = ReplicatedStorage:WaitForChild("Remotes")
local PlayerAttack    = Remotes:WaitForChild("PlayerAttack")
local WeaponEquipped  = Remotes:WaitForChild("WeaponEquipped")

local UIManager = require(script.Parent.UIManager)

local player = Players.LocalPlayer
local mouse  = player:GetMouse()

local InputHandler = {}

local attackCooldown = false

-- ─── Attack ───────────────────────────────────────────────────────────────────

-- Fires the server with attack intent + aim position.
-- mouse.Hit.Position gives the 3D world point the cursor is over, which the
-- server uses as the ray direction for ranged weapons. Melee weapons ignore it.
function InputHandler.onAttack()
	if attackCooldown then return end
	if UIManager.isMenuOpen() then return end  -- block attacks while any menu is open
	attackCooldown = true

	local aimPos = mouse.Hit.Position
	PlayerAttack:FireServer(aimPos)
	-- TODO: Play local swing animation here

	task.delay(0.4, function()  -- client-side visual cooldown (server enforces real one)
		attackCooldown = false
	end)
end

-- ─── Weapon equip detection ───────────────────────────────────────────────────
-- When the player switches Tools (presses 1/2/3 or clicks the hotbar), Roblox
-- moves the Tool between Backpack and Character. We detect that and tell the
-- server which weapon is now active so CombatManager uses the right stats.

local function onCharacterAdded(character: Model)
	-- When switching weapons Roblox always removes the old tool first, then
	-- adds the new one. Without a debounce we'd fire "Fists" on every switch.
	-- Solution: delay the Fists event by one frame — if a new tool equips
	-- in that window, cancel the Fists fire and send the real weapon name instead.
	local pendingFists: thread? = nil

	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			-- Cancel the pending "Fists" revert — a real weapon just equipped
			if pendingFists then
				task.cancel(pendingFists)
				pendingFists = nil
			end
			WeaponEquipped:FireServer(child.Name)
		end
	end)

	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			-- Schedule Fists; a new weapon may arrive within the next frame
			pendingFists = task.delay(0.05, function()
				pendingFists = nil
				WeaponEquipped:FireServer("Fists")
			end)
		end
	end)
end

-- Hook into current character (Studio play-test) and all future respawns
if player.Character then onCharacterAdded(player.Character) end
player.CharacterAdded:Connect(onCharacterAdded)

-- ─── Input binding ────────────────────────────────────────────────────────────

function InputHandler.init()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end  -- ignore if UI is focused / chat is open

		-- Mouse (PC) or Controller (R2 / R1)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.KeyCode == Enum.KeyCode.ButtonR2
			or input.KeyCode == Enum.KeyCode.ButtonR1
		then
			InputHandler.onAttack()
		end
	end)

	print("[InputHandler] Initialized — mouse and controller supported")
end

return InputHandler

-- BulletEffect.lua
-- StarterPlayer > StarterPlayerScripts > Client > BulletEffect
-- Listens for BulletFired events from the server and draws a brief visual trail.
-- Purely cosmetic — no gameplay logic here.
-- Works for any ranged weapon (Pistol single-shot, Shotgun pellets, etc.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local Remotes     = ReplicatedStorage:WaitForChild("Remotes")
local BulletFired = Remotes:WaitForChild("BulletFired")

-- ─── Trail drawing ────────────────────────────────────────────────────────────

-- Creates a thin rectangular Part spanning from `startPos` to `endPos`,
-- then tweens its transparency from 0 → 1 and destroys it.
local function drawBulletTrail(startPos: Vector3, endPos: Vector3)
	local length    = (endPos - startPos).Magnitude
	if length < 0.1 then return end  -- degenerate ray, skip

	local midPoint  = (startPos + endPos) / 2
	local direction = (endPos - startPos).Unit

	local trail = Instance.new("Part")
	trail.Name        = "BulletTrail"
	trail.Anchored    = true
	trail.CanCollide  = false
	trail.CanQuery    = false
	trail.CastShadow  = false
	trail.Size        = Vector3.new(0.05, 0.05, length)
	trail.CFrame      = CFrame.lookAt(midPoint, endPos)
	trail.Material    = Enum.Material.Neon
	trail.Color       = Color3.fromRGB(255, 220, 100)  -- warm muzzle-flash yellow
	trail.Transparency = 0
	trail.Parent      = workspace

	-- Tween transparency 0 → 1 over 0.12 seconds, then destroy
	local tween = TweenService:Create(
		trail,
		TweenInfo.new(0.12, Enum.EasingStyle.Linear),
		{ Transparency = 1 }
	)
	tween:Play()
	tween.Completed:Connect(function()
		trail:Destroy()
	end)
end

-- ─── Optional: play the pistol's FireSound locally ───────────────────────────
-- The Pistol Handle contains a FireSound. We look for it in the player's
-- equipped Tool so the sound plays from their character position.
local Players = game:GetService("Players")
local player  = Players.LocalPlayer

local function playFireSound()
	local char = player.Character
	if not char then return end

	-- The equipped Tool is a child of the Character
	for _, child in ipairs(char:GetChildren()) do
		if child:IsA("Tool") then
			local handle    = child:FindFirstChild("Handle")
			local fireSound = handle and handle:FindFirstChild("FireSound")
			if fireSound and fireSound:IsA("Sound") then
				fireSound:Play()
				return
			end
		end
	end
end

-- ─── Event listener ───────────────────────────────────────────────────────────

BulletFired.OnClientEvent:Connect(function(startPos: Vector3, endPos: Vector3)
	drawBulletTrail(startPos, endPos)
	playFireSound()
end)

print("[BulletEffect] Initialized — listening for bullet trails")

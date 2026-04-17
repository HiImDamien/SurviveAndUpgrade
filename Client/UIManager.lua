-- UIManager.lua
-- StarterPlayer > StarterPlayerScripts > Client > UIManager
-- Builds and manages the in-game HUD:
--   • Wave counter, enemy count, currency display, health bar
--   • Weapon Shop panel — mouse/keyboard + full gamepad navigation
--   • Inventory panel (placeholder)
--
-- Gamepad shop flow:
--   Open shop pad → shop opens, first card auto-selected
--   Left stick / D-pad → navigate between weapon cards
--   A (Cross) → click selected button (Buy / Close)
--   B (Circle) → close shop from anywhere in the panel

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService        = game:GetService("GuiService")
local UserInputService  = game:GetService("UserInputService")

local Remotes           = ReplicatedStorage:WaitForChild("Remotes")
local StateChanged      = Remotes:WaitForChild("StateChanged")
local WaveStarted       = Remotes:WaitForChild("WaveStarted")
local WaveCleared       = Remotes:WaitForChild("WaveCleared")
local CurrencyUpdated   = Remotes:WaitForChild("CurrencyUpdated")
local EnemyCountUpdated = Remotes:WaitForChild("EnemyCountUpdated")
local OpenShop          = Remotes:WaitForChild("OpenShop")
local OpenInventory     = Remotes:WaitForChild("OpenInventory")
local ShopClosed        = Remotes:WaitForChild("ShopClosed")
local GetShopData       = Remotes:WaitForChild("GetShopData")
local PurchaseWeapon    = Remotes:WaitForChild("PurchaseWeapon")

local Constants         = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))
local WeaponDefinitions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeaponDefinitions"))

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local UIManager = {}

-- ─── HUD references ───────────────────────────────────────────────────────────
local waveFrame:     Frame
local waveLabel:     TextLabel
local enemyFrame:    Frame
local enemyLabel:    TextLabel
local currencyLabel: TextLabel
local healthFill:    Frame
local healthLabel:   TextLabel

local WAVE_HUD_STATES: { [string]: boolean } = {
	COUNTDOWN   = true,
	WAVE_ACTIVE = true,
	WAVE_CLEAR  = true,
}

-- ─── Shop state ───────────────────────────────────────────────────────────────
local shopOverlay:       ScreenGui
local shopCurrencyLabel: TextLabel
local inventoryPanel:    Frame

local WEAPON_ORDER = { "Knife", "Bat", "Sword", "Pistol", "Shotgun" }

local shopCardButtons: { [string]: TextButton } = {}
local shopAllSelectables: { TextButton } = {}  -- ordered list for gamepad focus restore
local menuOpen = false  -- exposed via UIManager.isMenuOpen()

-- ─── Public: lets InputHandler block attacks while the shop is up ─────────────
function UIManager.isMenuOpen(): boolean
	return menuOpen
end

-- ─── Helpers ─────────────────────────────────────────────────────────────────

local function makeCorner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function makePadding(parent: Instance, px: number)
	local p = Instance.new("UIPadding")
	p.PaddingLeft  = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.Parent = parent
end

-- ─── Shop close — shared by close button, B button, and scrim click ──────────
local function hideShop()
	if shopOverlay then shopOverlay.Enabled = false end
	menuOpen = false
	GuiService.SelectedObject = nil  -- release gamepad focus
	-- Tell the server the shop was dismissed so it can apply a re-open cooldown.
	-- This prevents the shop from immediately popping back up while the player
	-- is still standing on the pad or just stepping off it.
	ShopClosed:FireServer()
end

-- ─── Shop refresh ─────────────────────────────────────────────────────────────

local function refreshShop(owned: { [string]: any }, currency: number)
	if shopCurrencyLabel then
		shopCurrencyLabel.Text = string.format("$ %d", currency)
	end

	for _, weaponName in ipairs(WEAPON_ORDER) do
		local btn = shopCardButtons[weaponName]
		local def = WeaponDefinitions[weaponName]
		if not btn or not def then continue end

		if owned[weaponName] then
			btn:SetAttribute("owned", true)
			btn.BackgroundColor3 = Color3.fromRGB(35, 110, 55)
			btn.Text             = "✓  OWNED"
			btn.TextColor3       = Color3.fromRGB(130, 240, 160)
		else
			btn:SetAttribute("owned", false)
			local canAfford = currency >= def.unlockCost
			if canAfford then
				btn.BackgroundColor3 = Color3.fromRGB(50, 165, 90)
				btn.Text             = string.format("BUY  $%d", def.unlockCost)
				btn.TextColor3       = Color3.fromRGB(255, 255, 255)
			else
				btn.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
				btn.Text             = string.format("$%d", def.unlockCost)
				btn.TextColor3       = Color3.fromRGB(120, 120, 140)
			end
		end
	end
end

-- ─── Build HUD ────────────────────────────────────────────────────────────────

local function buildHUD()
	local hud = Instance.new("ScreenGui")
	hud.Name            = "HUD"
	hud.ResetOnSpawn    = false
	hud.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
	hud.Parent          = playerGui

	waveFrame = Instance.new("Frame")
	waveFrame.Name                   = "WaveFrame"
	waveFrame.Size                   = UDim2.new(0, 220, 0, 40)
	waveFrame.Position               = UDim2.new(0.5, -110, 0, 16)
	waveFrame.BackgroundColor3       = Color3.fromRGB(20, 20, 20)
	waveFrame.BackgroundTransparency = 0.35
	waveFrame.BorderSizePixel        = 0
	waveFrame.Visible                = false
	waveFrame.Parent                 = hud
	makeCorner(waveFrame, 8)

	waveLabel = Instance.new("TextLabel")
	waveLabel.Name                   = "WaveLabel"
	waveLabel.Size                   = UDim2.new(1, 0, 1, 0)
	waveLabel.BackgroundTransparency = 1
	waveLabel.Text                   = "WAVE — / 30"
	waveLabel.Font                   = Enum.Font.GothamBold
	waveLabel.TextColor3             = Color3.fromRGB(255, 255, 255)
	waveLabel.TextSize               = 18
	waveLabel.Parent                 = waveFrame

	enemyFrame = Instance.new("Frame")
	enemyFrame.Name                   = "EnemyFrame"
	enemyFrame.Size                   = UDim2.new(0, 180, 0, 28)
	enemyFrame.Position               = UDim2.new(0.5, -90, 0, 64)
	enemyFrame.BackgroundColor3       = Color3.fromRGB(160, 40, 40)
	enemyFrame.BackgroundTransparency = 0.4
	enemyFrame.BorderSizePixel        = 0
	enemyFrame.Visible                = false
	enemyFrame.Parent                 = hud
	makeCorner(enemyFrame, 6)

	enemyLabel = Instance.new("TextLabel")
	enemyLabel.Name                   = "EnemyLabel"
	enemyLabel.Size                   = UDim2.new(1, 0, 1, 0)
	enemyLabel.BackgroundTransparency = 1
	enemyLabel.Text                   = "☠  0 REMAINING"
	enemyLabel.Font                   = Enum.Font.GothamBold
	enemyLabel.TextColor3             = Color3.fromRGB(255, 190, 190)
	enemyLabel.TextSize               = 13
	enemyLabel.Parent                 = enemyFrame

	local currencyFrame = Instance.new("Frame")
	currencyFrame.Name                   = "CurrencyFrame"
	currencyFrame.Size                   = UDim2.new(0, 150, 0, 40)
	currencyFrame.Position               = UDim2.new(1, -166, 0, 16)
	currencyFrame.BackgroundColor3       = Color3.fromRGB(20, 20, 20)
	currencyFrame.BackgroundTransparency = 0.35
	currencyFrame.BorderSizePixel        = 0
	currencyFrame.Parent                 = hud
	makeCorner(currencyFrame, 8)
	makePadding(currencyFrame, 8)

	currencyLabel = Instance.new("TextLabel")
	currencyLabel.Name                   = "CurrencyLabel"
	currencyLabel.Size                   = UDim2.new(1, 0, 1, 0)
	currencyLabel.BackgroundTransparency = 1
	currencyLabel.Text                   = "$ 0"
	currencyLabel.Font                   = Enum.Font.GothamBold
	currencyLabel.TextColor3             = Color3.fromRGB(255, 215, 0)
	currencyLabel.TextSize               = 18
	currencyLabel.TextXAlignment         = Enum.TextXAlignment.Right
	currencyLabel.Parent                 = currencyFrame

	local healthContainer = Instance.new("Frame")
	healthContainer.Name                   = "HealthContainer"
	healthContainer.Size                   = UDim2.new(0, 240, 0, 50)
	healthContainer.Position               = UDim2.new(0, 16, 1, -66)
	healthContainer.BackgroundTransparency = 1
	healthContainer.Parent                 = hud

	healthLabel = Instance.new("TextLabel")
	healthLabel.Name                   = "HealthLabel"
	healthLabel.Size                   = UDim2.new(1, 0, 0, 20)
	healthLabel.Position               = UDim2.new(0, 0, 0, 0)
	healthLabel.BackgroundTransparency = 1
	healthLabel.Text                   = "HP  100 / 100"
	healthLabel.Font                   = Enum.Font.GothamBold
	healthLabel.TextColor3             = Color3.fromRGB(220, 220, 220)
	healthLabel.TextSize               = 13
	healthLabel.TextXAlignment         = Enum.TextXAlignment.Left
	healthLabel.Parent                 = healthContainer

	local healthBg = Instance.new("Frame")
	healthBg.Name                   = "HealthBg"
	healthBg.Size                   = UDim2.new(1, 0, 0, 22)
	healthBg.Position               = UDim2.new(0, 0, 0, 24)
	healthBg.BackgroundColor3       = Color3.fromRGB(40, 40, 40)
	healthBg.BackgroundTransparency = 0.3
	healthBg.BorderSizePixel        = 0
	healthBg.Parent                 = healthContainer
	makeCorner(healthBg, 6)

	healthFill = Instance.new("Frame")
	healthFill.Name             = "HealthFill"
	healthFill.Size             = UDim2.new(1, 0, 1, 0)
	healthFill.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
	healthFill.BorderSizePixel  = 0
	healthFill.Parent           = healthBg
	makeCorner(healthFill, 6)
end

-- ─── Build Weapon Shop panel ──────────────────────────────────────────────────

local function buildShopPanel()
	local overlay = Instance.new("ScreenGui")
	overlay.Name           = "ShopOverlay"
	overlay.ResetOnSpawn   = false
	overlay.IgnoreGuiInset = true
	overlay.DisplayOrder   = 10
	overlay.Enabled        = false
	overlay.Parent         = playerGui

	local scrim = Instance.new("TextButton")
	scrim.Name                   = "Scrim"
	scrim.Size                   = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
	scrim.BackgroundTransparency = 0.45
	scrim.AutoButtonColor        = false
	scrim.Text                   = ""
	scrim.Parent                 = overlay

	local panel = Instance.new("Frame")
	panel.Name             = "Panel"
	panel.AnchorPoint      = Vector2.new(0.5, 0.5)
	panel.Size             = UDim2.new(0, 660, 0, 510)
	panel.Position         = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
	panel.BorderSizePixel  = 0
	panel.Parent           = scrim
	makeCorner(panel, 12)

	-- Title bar
	local titleBar = Instance.new("Frame")
	titleBar.Name             = "TitleBar"
	titleBar.Size             = UDim2.new(1, 0, 0, 52)
	titleBar.BackgroundColor3 = Color3.fromRGB(45, 115, 210)
	titleBar.BorderSizePixel  = 0
	titleBar.Parent           = panel
	makeCorner(titleBar, 12)

	local titleFix = Instance.new("Frame")
	titleFix.Size             = UDim2.new(1, 0, 0, 12)
	titleFix.Position         = UDim2.new(0, 0, 1, -12)
	titleFix.BackgroundColor3 = Color3.fromRGB(45, 115, 210)
	titleFix.BorderSizePixel  = 0
	titleFix.Parent           = titleBar

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size                   = UDim2.new(0, 300, 1, 0)
	titleLabel.Position               = UDim2.new(0, 18, 0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text                   = "WEAPON SHOP"
	titleLabel.Font                   = Enum.Font.GothamBold
	titleLabel.TextColor3             = Color3.fromRGB(255, 255, 255)
	titleLabel.TextSize               = 21
	titleLabel.TextXAlignment         = Enum.TextXAlignment.Left
	titleLabel.Parent                 = titleBar

	shopCurrencyLabel = Instance.new("TextLabel")
	shopCurrencyLabel.Size                   = UDim2.new(0, 200, 1, 0)
	shopCurrencyLabel.Position               = UDim2.new(1, -218, 0, 0)
	shopCurrencyLabel.BackgroundTransparency = 1
	shopCurrencyLabel.Text                   = "$ 0"
	shopCurrencyLabel.Font                   = Enum.Font.GothamBold
	shopCurrencyLabel.TextColor3             = Color3.fromRGB(255, 215, 0)
	shopCurrencyLabel.TextSize               = 18
	shopCurrencyLabel.TextXAlignment         = Enum.TextXAlignment.Right
	shopCurrencyLabel.Parent                 = titleBar

	-- Scrollable card area
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name                   = "CardScroll"
	scrollFrame.Size                   = UDim2.new(1, -24, 1, -118)
	scrollFrame.Position               = UDim2.new(0, 12, 0, 60)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel        = 0
	scrollFrame.ScrollBarThickness     = 5
	scrollFrame.ScrollBarImageColor3   = Color3.fromRGB(80, 90, 120)
	scrollFrame.AutomaticCanvasSize    = Enum.AutomaticSize.Y
	scrollFrame.CanvasSize             = UDim2.new(0, 0, 0, 0)
	scrollFrame.Parent                 = panel

	local grid = Instance.new("UIGridLayout")
	grid.CellSize            = UDim2.new(0, 300, 0, 158)
	grid.CellPadding         = UDim2.new(0, 12, 0, 10)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.SortOrder           = Enum.SortOrder.LayoutOrder
	grid.Parent              = scrollFrame

	local scrollPad = Instance.new("UIPadding")
	scrollPad.PaddingTop    = UDim.new(0, 6)
	scrollPad.PaddingBottom = UDim.new(0, 6)
	scrollPad.Parent        = scrollFrame

	-- Weapon cards
	for order, weaponName in ipairs(WEAPON_ORDER) do
		local def = WeaponDefinitions[weaponName]
		if not def then continue end

		local card = Instance.new("Frame")
		card.Name             = weaponName .. "Card"
		card.LayoutOrder      = order
		card.BackgroundColor3 = Color3.fromRGB(26, 28, 38)
		card.BorderSizePixel  = 0
		card.Parent           = scrollFrame
		makeCorner(card, 10)

		local stroke = Instance.new("UIStroke")
		stroke.Color     = Color3.fromRGB(55, 58, 80)
		stroke.Thickness = 1
		stroke.Parent    = card

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size                   = UDim2.new(1, -90, 0, 30)
		nameLabel.Position               = UDim2.new(0, 14, 0, 12)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text                   = weaponName:upper()
		nameLabel.Font                   = Enum.Font.GothamBold
		nameLabel.TextColor3             = Color3.fromRGB(240, 240, 255)
		nameLabel.TextSize               = 20
		nameLabel.TextXAlignment         = Enum.TextXAlignment.Left
		nameLabel.Parent                 = card

		local isRanged = def.baseStats.ranged == true
		local badge = Instance.new("Frame")
		badge.Size             = UDim2.new(0, 68, 0, 20)
		badge.Position         = UDim2.new(1, -82, 0, 16)
		badge.BackgroundColor3 = isRanged
			and Color3.fromRGB(45, 140, 210)
			or  Color3.fromRGB(190, 70, 70)
		badge.BorderSizePixel  = 0
		badge.Parent           = card
		makeCorner(badge, 4)

		local badgeLabel = Instance.new("TextLabel")
		badgeLabel.Size                   = UDim2.fromScale(1, 1)
		badgeLabel.BackgroundTransparency = 1
		badgeLabel.Text                   = isRanged and "RANGED" or "MELEE"
		badgeLabel.Font                   = Enum.Font.GothamBold
		badgeLabel.TextColor3             = Color3.fromRGB(255, 255, 255)
		badgeLabel.TextSize               = 11
		badgeLabel.Parent                 = badge

		local statsLabel = Instance.new("TextLabel")
		statsLabel.Size                   = UDim2.new(1, -28, 0, 20)
		statsLabel.Position               = UDim2.new(0, 14, 0, 52)
		statsLabel.BackgroundTransparency = 1
		statsLabel.Text                   = string.format(
			"DMG  %d    ·    SPD  %.1f    ·    RNG  %d",
			def.baseStats.damage, def.baseStats.speed, def.baseStats.range
		)
		statsLabel.Font           = Enum.Font.Gotham
		statsLabel.TextColor3     = Color3.fromRGB(165, 170, 195)
		statsLabel.TextSize       = 12
		statsLabel.TextXAlignment = Enum.TextXAlignment.Left
		statsLabel.Parent         = card

		local costHint = Instance.new("TextLabel")
		costHint.Size                   = UDim2.new(1, -28, 0, 18)
		costHint.Position               = UDim2.new(0, 14, 0, 76)
		costHint.BackgroundTransparency = 1
		costHint.Text                   = string.format("Unlock cost: $%d", def.unlockCost)
		costHint.Font                   = Enum.Font.Gotham
		costHint.TextColor3             = Color3.fromRGB(120, 125, 155)
		costHint.TextSize               = 11
		costHint.TextXAlignment         = Enum.TextXAlignment.Left
		costHint.Parent                 = card

		local divider = Instance.new("Frame")
		divider.Size             = UDim2.new(1, -28, 0, 1)
		divider.Position         = UDim2.new(0, 14, 0, 103)
		divider.BackgroundColor3 = Color3.fromRGB(45, 48, 65)
		divider.BorderSizePixel  = 0
		divider.Parent           = card

		local buyBtn = Instance.new("TextButton")
		buyBtn.Name             = "BuyButton"
		buyBtn.Size             = UDim2.new(1, -28, 0, 38)
		buyBtn.Position         = UDim2.new(0, 14, 0, 110)
		buyBtn.BackgroundColor3 = Color3.fromRGB(50, 165, 90)
		buyBtn.Text             = string.format("BUY  $%d", def.unlockCost)
		buyBtn.Font             = Enum.Font.GothamBold
		buyBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
		buyBtn.TextSize         = 14
		buyBtn.BorderSizePixel  = 0
		buyBtn.AutoButtonColor  = false
		-- Gamepad: mark as selectable so D-pad / left-stick can reach it
		buyBtn.Selectable       = true
		buyBtn.Parent           = card
		makeCorner(buyBtn, 8)

		-- Soft blue outline when this button has gamepad focus.
		-- Deliberately NOT pure white — a bright white stroke bleeds into the
		-- white button text and makes it hard to read.
		local selectionHighlight = Instance.new("UIStroke")
		selectionHighlight.Color     = Color3.fromRGB(100, 160, 255)  -- soft blue, not blinding
		selectionHighlight.Thickness = 2
		selectionHighlight.Enabled   = false
		selectionHighlight.Parent    = buyBtn

		buyBtn.SelectionGained:Connect(function()
			selectionHighlight.Enabled = true
		end)
		buyBtn.SelectionLost:Connect(function()
			selectionHighlight.Enabled = false
		end)

		-- Mouse hover: darken the button slightly so white text keeps contrast
		-- even if Roblox applies any ambient highlight on top.
		local BUY_COLOR_NORMAL = Color3.fromRGB(50, 165, 90)
		local BUY_COLOR_HOVER  = Color3.fromRGB(38, 130, 70)
		buyBtn.MouseEnter:Connect(function()
			if not buyBtn:GetAttribute("owned") and not buyBtn:GetAttribute("purchasing") then
				buyBtn.BackgroundColor3 = BUY_COLOR_HOVER
			end
		end)
		buyBtn.MouseLeave:Connect(function()
			if not buyBtn:GetAttribute("owned") and not buyBtn:GetAttribute("purchasing") then
				buyBtn.BackgroundColor3 = BUY_COLOR_NORMAL
			end
		end)

		shopCardButtons[weaponName] = buyBtn
		table.insert(shopAllSelectables, buyBtn)

		buyBtn.MouseButton1Click:Connect(function()
			if buyBtn:GetAttribute("owned")      then return end
			if buyBtn:GetAttribute("purchasing") then return end

			buyBtn:SetAttribute("purchasing", true)
			local prevText  = buyBtn.Text
			local prevColor = buyBtn.BackgroundColor3
			buyBtn.Text             = "..."
			buyBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)

			local result = PurchaseWeapon:InvokeServer(weaponName)
			buyBtn:SetAttribute("purchasing", false)

			if result and result.success then
				refreshShop(result.owned, result.currency)
			else
				buyBtn.Text             = (result and result.message) or "Error"
				buyBtn.BackgroundColor3 = Color3.fromRGB(160, 50, 50)
				task.delay(1.5, function()
					buyBtn.Text             = prevText
					buyBtn.BackgroundColor3 = prevColor
				end)
			end
		end)
	end

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name             = "CloseButton"
	closeBtn.AnchorPoint      = Vector2.new(0.5, 1)
	closeBtn.Position         = UDim2.new(0.5, 0, 1, -12)
	closeBtn.Size             = UDim2.new(0, 140, 0, 38)
	closeBtn.BackgroundColor3 = Color3.fromRGB(50, 52, 70)
	closeBtn.Text             = "CLOSE  [B]"   -- hint visible on-screen
	closeBtn.Font             = Enum.Font.GothamBold
	closeBtn.TextColor3       = Color3.fromRGB(210, 210, 225)
	closeBtn.TextSize         = 14
	closeBtn.BorderSizePixel  = 0
	closeBtn.AutoButtonColor  = false
	closeBtn.Selectable       = true  -- gamepad-navigable
	closeBtn.Parent           = panel
	makeCorner(closeBtn, 8)

	local closeBtnStroke = Instance.new("UIStroke")
	closeBtnStroke.Color     = Color3.fromRGB(100, 160, 255)  -- matches buy-button focus style
	closeBtnStroke.Thickness = 2
	closeBtnStroke.Enabled   = false
	closeBtnStroke.Parent    = closeBtn

	closeBtn.SelectionGained:Connect(function() closeBtnStroke.Enabled = true  end)
	closeBtn.SelectionLost:Connect(function()  closeBtnStroke.Enabled = false end)

	closeBtn.MouseButton1Click:Connect(hideShop)
	scrim.MouseButton1Click:Connect(hideShop)
	table.insert(shopAllSelectables, closeBtn)

	-- Absorb clicks on the panel body so they don't propagate to the scrim
	local swallow = Instance.new("TextButton")
	swallow.Size                   = UDim2.fromScale(1, 1)
	swallow.BackgroundTransparency = 1
	swallow.Text                   = ""
	swallow.AutoButtonColor        = false
	swallow.ZIndex                 = 0
	swallow.Parent                 = panel

	return overlay
end

-- ─── Inventory placeholder ────────────────────────────────────────────────────

local function buildPlaceholderPanel(title: string, accentColor: Color3): Frame
	local overlay = Instance.new("ScreenGui")
	overlay.Name           = title .. "Overlay"
	overlay.ResetOnSpawn   = false
	overlay.IgnoreGuiInset = true
	overlay.DisplayOrder   = 10
	overlay.Enabled        = false
	overlay.Parent         = playerGui

	local scrim = Instance.new("TextButton")
	scrim.Name                   = "Scrim"
	scrim.Size                   = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
	scrim.BackgroundTransparency = 0.4
	scrim.AutoButtonColor        = false
	scrim.Text                   = ""
	scrim.Parent                 = overlay

	local panel = Instance.new("Frame")
	panel.Name             = "Panel"
	panel.AnchorPoint      = Vector2.new(0.5, 0.5)
	panel.Size             = UDim2.new(0, 480, 0, 320)
	panel.Position         = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(24, 26, 32)
	panel.BorderSizePixel  = 0
	panel.Parent           = scrim
	makeCorner(panel, 10)

	local titleBar = Instance.new("Frame")
	titleBar.Name             = "TitleBar"
	titleBar.Size             = UDim2.new(1, 0, 0, 44)
	titleBar.BackgroundColor3 = accentColor
	titleBar.BorderSizePixel  = 0
	titleBar.Parent           = panel
	makeCorner(titleBar, 10)

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size                   = UDim2.fromScale(1, 1)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text                   = title
	titleLabel.Font                   = Enum.Font.GothamBold
	titleLabel.TextColor3             = Color3.fromRGB(255, 255, 255)
	titleLabel.TextSize               = 20
	titleLabel.Parent                 = titleBar

	local body = Instance.new("TextLabel")
	body.Size                   = UDim2.new(1, -40, 1, -120)
	body.Position               = UDim2.new(0, 20, 0, 60)
	body.BackgroundTransparency = 1
	body.Text                   = title .. " coming soon."
	body.Font                   = Enum.Font.Gotham
	body.TextColor3             = Color3.fromRGB(210, 210, 215)
	body.TextSize               = 15
	body.TextWrapped            = true
	body.TextYAlignment         = Enum.TextYAlignment.Top
	body.Parent                 = panel

	local close = Instance.new("TextButton")
	close.Name             = "Close"
	close.AnchorPoint      = Vector2.new(0.5, 1)
	close.Position         = UDim2.new(0.5, 0, 1, -16)
	close.Size             = UDim2.new(0, 120, 0, 36)
	close.BackgroundColor3 = Color3.fromRGB(60, 60, 68)
	close.Text             = "Close"
	close.Font             = Enum.Font.GothamBold
	close.TextColor3       = Color3.fromRGB(255, 255, 255)
	close.TextSize         = 16
	close.BorderSizePixel  = 0
	close.Parent           = panel
	makeCorner(close, 8)

	local function hide()
		overlay.Enabled = false
		menuOpen = false
		GuiService.SelectedObject = nil
	end
	close.MouseButton1Click:Connect(hide)
	scrim.MouseButton1Click:Connect(hide)

	local swallow = Instance.new("TextButton")
	swallow.Size                   = UDim2.fromScale(1, 1)
	swallow.BackgroundTransparency = 1
	swallow.Text                   = ""
	swallow.AutoButtonColor        = false
	swallow.ZIndex                 = 0
	swallow.Parent                 = panel

	return panel
end

local function buildOverlayPanels()
	shopOverlay    = buildShopPanel()
	inventoryPanel = buildPlaceholderPanel("Inventory", Color3.fromRGB(160, 90, 220))
end

-- ─── Event handlers ───────────────────────────────────────────────────────────

function UIManager.onStateChanged(state: string, waveNumber: number, levelNumber: number?)
	local shouldShow = WAVE_HUD_STATES[state] == true
	if waveFrame  then waveFrame.Visible  = shouldShow end
	if enemyFrame then enemyFrame.Visible = shouldShow end

	if state == "LOBBY" or state == "GAME_OVER" or state == "SHOP" then
		if waveLabel  then waveLabel.Text  = "WAVE — / —" end
		if enemyLabel then enemyLabel.Text = "☠  0 REMAINING" end
		return
	end

	if state == "COUNTDOWN" then
		local cfg      = levelNumber and Constants.LEVELS[levelNumber] or nil
		local total    = (cfg and cfg.waves) or 30
		local nextWave = (waveNumber or 0) + 1
		if waveLabel  then waveLabel.Text  = string.format("WAVE %d / %d", nextWave, total) end
		if enemyLabel then enemyLabel.Text = "☠  0 REMAINING" end
	end

	print("[UIManager] State:", state, "| Wave:", waveNumber, "| Level:", levelNumber)
end

function UIManager.onWaveStarted(waveNumber: number, zombieCount: number, waveTotal: number?)
	local total = waveTotal or 30
	waveLabel.Text  = string.format("WAVE %d / %d", waveNumber, total)
	enemyLabel.Text = string.format("☠  %d REMAINING", zombieCount)
end

function UIManager.onWaveCleared(waveNumber: number)
	waveLabel.Text  = string.format("WAVE %d CLEAR!", waveNumber)
	enemyLabel.Text = "☠  0 REMAINING"
end

function UIManager.onCurrencyUpdated(amount: number)
	currencyLabel.Text = string.format("$ %d", amount)
	if shopCurrencyLabel then
		shopCurrencyLabel.Text = string.format("$ %d", amount)
	end
end

function UIManager.onEnemyCountUpdated(count: number)
	enemyLabel.Text = string.format("☠  %d REMAINING", count)
end

-- ─── Health bar ───────────────────────────────────────────────────────────────

local function updateHealthBar()
	local char = player.Character
	if not char then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local pct = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
	healthFill.Size = UDim2.new(pct, 0, 1, 0)

	if pct > 0.5 then
		healthFill.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
	elseif pct > 0.25 then
		healthFill.BackgroundColor3 = Color3.fromRGB(220, 180, 40)
	else
		healthFill.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
	end

	healthLabel.Text = string.format(
		"HP  %d / %d",
		math.floor(humanoid.Health),
		math.floor(humanoid.MaxHealth)
	)
end

-- ─── Init ─────────────────────────────────────────────────────────────────────

function UIManager.init()
	buildHUD()
	buildOverlayPanels()

	StateChanged.OnClientEvent:Connect(UIManager.onStateChanged)
	WaveStarted.OnClientEvent:Connect(UIManager.onWaveStarted)
	WaveCleared.OnClientEvent:Connect(UIManager.onWaveCleared)
	CurrencyUpdated.OnClientEvent:Connect(UIManager.onCurrencyUpdated)
	EnemyCountUpdated.OnClientEvent:Connect(UIManager.onEnemyCountUpdated)

	-- Shop open: fetch data, refresh cards, show panel, set gamepad focus
	OpenShop.OnClientEvent:Connect(function()
		task.spawn(function()
			local shopData = GetShopData:InvokeServer()
			if shopData then
				refreshShop(shopData.owned or {}, shopData.currency or 0)
			end
			if shopOverlay then
				shopOverlay.Enabled = true
				menuOpen = true

				-- Gamepad: auto-select the first weapon card's buy button
				if UserInputService.GamepadEnabled and shopAllSelectables[1] then
					GuiService.SelectedObject = shopAllSelectables[1]
				end
			end
		end)
	end)

	OpenInventory.OnClientEvent:Connect(function()
		local gui = inventoryPanel and inventoryPanel:FindFirstAncestorOfClass("ScreenGui")
		if gui then
			gui.Enabled = true
			menuOpen = true
		end
	end)

	-- B button (Circle on PlayStation) closes the shop from anywhere in the panel
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.ButtonB and menuOpen then
			hideShop()
		end
	end)

	task.spawn(function()
		while true do
			updateHealthBar()
			task.wait(0.1)
		end
	end)

	print("[UIManager] HUD initialized")
end

return UIManager

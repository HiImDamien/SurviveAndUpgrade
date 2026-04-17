-- LobbyBuilder.lua
-- ServerScriptService > Server > LobbyBuilder
-- Builds the player lobby programmatically on server boot.
-- Produces: floor + walls + SpawnLocation + 5 interaction pads (Shop, Inventory,
-- Level 1, Level 2, Level 3). Pads are tagged with attributes so TeleportManager
-- can pick them up generically — no hardcoded names.
--
-- The lobby is a purely "functional" placeholder. Replace parts with proper
-- building models later without changing this file's interface.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)

local LobbyBuilder = {}

-- ─── Part helpers ────────────────────────────────────────────────────────────

local function makePart(props: {[string]: any}): Part
	local p = Instance.new("Part")
	p.Anchored       = true
	p.CanCollide     = true
	p.TopSurface     = Enum.SurfaceType.Smooth
	p.BottomSurface  = Enum.SurfaceType.Smooth
	p.Material       = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	return p
end

-- Adds a SurfaceGui label on top of a pad so the player can see what it is.
-- White text + solid black stroke keeps it readable against any neon-pad colour.
local function addPadLabel(pad: Part, text: string, _textColor: Color3)
	local sg = Instance.new("SurfaceGui")
	sg.Face              = Enum.NormalId.Top
	sg.LightInfluence    = 0
	sg.AlwaysOnTop       = true
	sg.PixelsPerStud     = 50
	sg.Parent            = pad

	local label = Instance.new("TextLabel")
	label.Size                   = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font                   = Enum.Font.GothamBlack
	label.Text                   = text
	label.TextColor3             = Color3.fromRGB(255, 255, 255)   -- bright white
	label.TextScaled             = true
	-- Solid black outline so the text pops cleanly over the neon glow
	label.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 0
	label.Parent                 = sg
end

-- Creates a flat pad with a label and attributes for TeleportManager to key off.
-- attributes example: { PadType = "Level", Level = 2 }
local function buildPad(
	parent: Instance,
	name: string,
	position: Vector3,
	color: Color3,
	labelText: string,
	attributes: {[string]: any}
): Part
	local pad = makePart({
		Name            = name,
		Size            = Vector3.new(14, 1, 14),
		Position        = position,
		Color           = color,
		Material        = Enum.Material.Neon,
		Parent          = parent,
	})
	addPadLabel(pad, labelText, Color3.fromRGB(20, 20, 20))
	for attr, value in pairs(attributes) do
		pad:SetAttribute(attr, value)
	end
	return pad
end

-- ─── Lobby geometry ──────────────────────────────────────────────────────────

local function buildFloor(parent: Instance)
	local origin = Constants.LOBBY_ORIGIN
	local size   = Constants.LOBBY_SIZE

	makePart({
		Name     = "Floor",
		Size     = size,
		Position = origin,
		Color    = Color3.fromRGB(70, 75, 85),
		Material = Enum.Material.Slate,
		Parent   = parent,
	})
end

-- Thin walls so players can't wander off the edge into the void
local function buildWalls(parent: Instance)
	local origin  = Constants.LOBBY_ORIGIN
	local size    = Constants.LOBBY_SIZE
	local height  = 20
	local thick   = 2
	local color   = Color3.fromRGB(55, 60, 70)

	-- North / South walls (along X axis)
	for _, zOffset in ipairs({ size.Z / 2, -size.Z / 2 }) do
		makePart({
			Name     = "Wall",
			Size     = Vector3.new(size.X, height, thick),
			Position = origin + Vector3.new(0, height / 2, zOffset),
			Color    = color,
			Parent   = parent,
		})
	end
	-- East / West walls (along Z axis)
	for _, xOffset in ipairs({ size.X / 2, -size.X / 2 }) do
		makePart({
			Name     = "Wall",
			Size     = Vector3.new(thick, height, size.Z),
			Position = origin + Vector3.new(xOffset, height / 2, 0),
			Color    = color,
			Parent   = parent,
		})
	end
end

local function buildSpawn(parent: Instance): SpawnLocation
	local spawn = Instance.new("SpawnLocation")
	spawn.Name             = "LobbySpawn"
	spawn.Size             = Vector3.new(8, 1, 8)
	spawn.Position         = Constants.LOBBY_SPAWN
	spawn.Anchored         = true
	spawn.CanCollide       = true
	spawn.TopSurface       = Enum.SurfaceType.Smooth
	spawn.Material         = Enum.Material.Neon
	spawn.Color            = Color3.fromRGB(200, 230, 255)
	spawn.Neutral          = true
	spawn.AllowTeamChangeOnTouch = false
	spawn.Parent           = parent
	return spawn
end

-- ─── Pads ────────────────────────────────────────────────────────────────────

local function buildInteractionPads(parent: Instance)
	local origin = Constants.LOBBY_ORIGIN

	-- Utility pads on the south side of the lobby (behind spawn)
	buildPad(parent, "ShopPad",
		origin + Vector3.new(-30, 1.5, -30),
		Color3.fromRGB(70, 140, 230),
		"SHOP",
		{ PadType = "Shop" }
	)

	buildPad(parent, "InventoryPad",
		origin + Vector3.new(30, 1.5, -30),
		Color3.fromRGB(160, 90, 220),
		"INVENTORY",
		{ PadType = "Inventory" }
	)

	-- Level pads lined up on the north side of the lobby
	for levelNumber = 1, 3 do
		local cfg = Constants.LEVELS[levelNumber]
		if cfg then
			local xOffset = (levelNumber - 2) * 24  -- -24, 0, +24
			buildPad(parent, "Level" .. levelNumber .. "Pad",
				origin + Vector3.new(xOffset, 1.5, 40),
				cfg.padColor,
				"LEVEL " .. levelNumber,
				{ PadType = "Level", Level = levelNumber }
			)
		end
	end
end

-- ─── Public API ──────────────────────────────────────────────────────────────

-- Builds the lobby and parents everything under workspace.Lobby.
-- Safe to call multiple times — it destroys the previous lobby first.
function LobbyBuilder.build(): Folder
	local existing = workspace:FindFirstChild("Lobby")
	if existing then existing:Destroy() end

	local folder = Instance.new("Folder")
	folder.Name   = "Lobby"
	folder.Parent = workspace

	buildFloor(folder)
	buildWalls(folder)
	buildSpawn(folder)
	buildInteractionPads(folder)

	print("[LobbyBuilder] Lobby built at", Constants.LOBBY_ORIGIN)
	return folder
end

return LobbyBuilder

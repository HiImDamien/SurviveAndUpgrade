-- ArenaBuilder.lua
-- ServerScriptService > Server > ArenaBuilder
-- Builds 3 physical level arenas far from the lobby, one per Constants.LEVELS entry.
-- Each arena has:
--   • a floor sized per Constants.LEVELS[n].arenaSize
--   • walls
--   • a player spawn point (tagged ArenaSpawn = true, Level = n)
--   • 4 enemy spawn points at the corners (tagged EnemySpawn = true, Level = n)
--   • a "Return to Lobby" pad (PadType = "ReturnToLobby")
--
-- WaveManager uses this file's tags to find where to spawn enemies for a given
-- level. TeleportManager uses them to teleport players in / out.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)

local ArenaBuilder = {}

-- ─── Part helpers ────────────────────────────────────────────────────────────

local function makePart(props: {[string]: any}): Part
	local p = Instance.new("Part")
	p.Anchored      = true
	p.CanCollide    = true
	p.TopSurface    = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material      = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	return p
end

local function addLabel(part: Part, text: string, color: Color3)
	local sg = Instance.new("SurfaceGui")
	sg.Face           = Enum.NormalId.Top
	sg.LightInfluence = 0
	sg.AlwaysOnTop    = true
	sg.PixelsPerStud  = 50
	sg.Parent         = part

	local label = Instance.new("TextLabel")
	label.Size                    = UDim2.fromScale(1, 1)
	label.BackgroundTransparency  = 1
	label.Font                    = Enum.Font.GothamBlack
	label.Text                    = text
	label.TextColor3              = color
	label.TextScaled              = true
	label.TextStrokeTransparency  = 0.4
	label.Parent                  = sg
end

-- ─── Per-level builder ───────────────────────────────────────────────────────

local function buildArena(parent: Instance, levelNumber: number)
	local cfg = Constants.LEVELS[levelNumber]
	if not cfg then return end

	local folder = Instance.new("Folder")
	folder.Name   = "Arena_" .. levelNumber
	folder.Parent = parent
	folder:SetAttribute("Level", levelNumber)

	local origin = cfg.origin
	local size   = cfg.arenaSize

	-- Floor
	makePart({
		Name     = "Floor",
		Size     = size,
		Position = origin,
		Color    = Color3.fromRGB(50, 55, 65),
		Material = Enum.Material.Slate,
		Parent   = folder,
	})

	-- Walls (same pattern as lobby)
	local wallHeight = 30
	local wallThick  = 2
	local wallColor  = Color3.fromRGB(40, 45, 55)

	for _, zOffset in ipairs({ size.Z / 2, -size.Z / 2 }) do
		makePart({
			Name     = "Wall",
			Size     = Vector3.new(size.X, wallHeight, wallThick),
			Position = origin + Vector3.new(0, wallHeight / 2, zOffset),
			Color    = wallColor,
			Parent   = folder,
		})
	end
	for _, xOffset in ipairs({ size.X / 2, -size.X / 2 }) do
		makePart({
			Name     = "Wall",
			Size     = Vector3.new(wallThick, wallHeight, size.Z),
			Position = origin + Vector3.new(xOffset, wallHeight / 2, 0),
			Color    = wallColor,
			Parent   = folder,
		})
	end

	-- Player spawn point (non-collidable marker — teleport target)
	local spawn = makePart({
		Name        = "PlayerSpawn",
		Size        = Vector3.new(6, 1, 6),
		Position    = origin + Vector3.new(0, 1.5, 0),
		Color       = Color3.fromRGB(200, 230, 255),
		Material    = Enum.Material.Neon,
		CanCollide  = false,
		Parent      = folder,
	})
	spawn:SetAttribute("ArenaSpawn", true)
	spawn:SetAttribute("Level", levelNumber)

	-- Enemy spawn markers (4 corners, inset)
	local inset = 20
	local corners = {
		Vector3.new( size.X / 2 - inset, 1.5,  size.Z / 2 - inset),
		Vector3.new(-size.X / 2 + inset, 1.5,  size.Z / 2 - inset),
		Vector3.new( size.X / 2 - inset, 1.5, -size.Z / 2 + inset),
		Vector3.new(-size.X / 2 + inset, 1.5, -size.Z / 2 + inset),
	}
	for i, offset in ipairs(corners) do
		local marker = makePart({
			Name        = "EnemySpawn" .. i,
			Size        = Vector3.new(4, 1, 4),
			Position    = origin + offset,
			Color       = Color3.fromRGB(180, 40, 40),
			Material    = Enum.Material.Neon,
			Transparency = 0.7,
			CanCollide  = false,
			Parent      = folder,
		})
		marker:SetAttribute("EnemySpawn", true)
		marker:SetAttribute("Level", levelNumber)
	end

	-- Return-to-lobby pad (near the player spawn so they can see it)
	local returnPad = makePart({
		Name        = "ReturnPad",
		Size        = Vector3.new(10, 1, 10),
		Position    = origin + Vector3.new(0, 1.5, -size.Z / 2 + 8),
		Color       = Color3.fromRGB(230, 230, 230),
		Material    = Enum.Material.Neon,
		Parent      = folder,
	})
	returnPad:SetAttribute("PadType", "ReturnToLobby")
	addLabel(returnPad, "← LOBBY", Color3.fromRGB(20, 20, 20))

	print(string.format("[ArenaBuilder] Built Arena_%d at %s (%s)", levelNumber, tostring(origin), cfg.name))
end

-- ─── Public API ──────────────────────────────────────────────────────────────

-- Builds all 3 arenas under workspace.Arenas. Idempotent — destroys previous first.
function ArenaBuilder.build(): Folder
	local existing = workspace:FindFirstChild("Arenas")
	if existing then existing:Destroy() end

	local folder = Instance.new("Folder")
	folder.Name   = "Arenas"
	folder.Parent = workspace

	for levelNumber in pairs(Constants.LEVELS) do
		buildArena(folder, levelNumber)
	end

	return folder
end

-- Returns the Arena_<n> folder for a given level, or nil if not built.
function ArenaBuilder.getArena(levelNumber: number): Folder?
	local arenas = workspace:FindFirstChild("Arenas")
	if not arenas then return nil end
	return arenas:FindFirstChild("Arena_" .. levelNumber) :: Folder?
end

-- Returns the CFrame the player should teleport to when entering this level.
function ArenaBuilder.getPlayerSpawnCFrame(levelNumber: number): CFrame?
	local arena = ArenaBuilder.getArena(levelNumber)
	if not arena then return nil end
	local spawn = arena:FindFirstChild("PlayerSpawn")
	if not spawn then return nil end
	return (spawn :: Part).CFrame + Vector3.new(0, 3, 0)
end

-- Returns a random enemy spawn CFrame for the given level.
function ArenaBuilder.getRandomEnemySpawnCFrame(levelNumber: number): CFrame?
	local arena = ArenaBuilder.getArena(levelNumber)
	if not arena then return nil end

	local markers = {}
	for _, child in ipairs(arena:GetChildren()) do
		if child:GetAttribute("EnemySpawn") then
			table.insert(markers, child)
		end
	end
	if #markers == 0 then return nil end

	local chosen = markers[math.random(1, #markers)] :: Part
	-- Add a little randomness inside the marker so multiple enemies don't stack
	local jitter = Vector3.new(
		math.random(-3, 3),
		0,
		math.random(-3, 3)
	)
	return (chosen.CFrame + jitter) + Vector3.new(0, 3, 0)
end

return ArenaBuilder

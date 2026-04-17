-- TeleportManager.lua
-- ServerScriptService > Server > TeleportManager
-- Finds every interaction pad tagged by LobbyBuilder / ArenaBuilder, hooks up
-- Touched events, and dispatches to GameManager (level entry) or remote fires
-- (shop / inventory / lobby return).
--
-- Pads are identified purely by the `PadType` attribute — no hardcoded names.
-- Add a new pad type by giving a part that attribute, then handling it here.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TeleportManager = {}

-- Will be set via init() to avoid a circular require with GameManager.
local gameManagerRef: any = nil

-- Per-player pad cooldown. Prevents re-firing while standing on the pad.
local PAD_COOLDOWN = 1.5  -- seconds
local lastTouch: { [Player]: number } = {}

-- Per-player post-close cooldown for the shop pad.
-- After the player dismisses the shop, this blocks the pad from immediately
-- re-opening while they're still standing on it or just stepping off.
local SHOP_CLOSE_COOLDOWN = 3  -- seconds
local shopClosedAt: { [Player]: number } = {}

-- ─── Helpers ─────────────────────────────────────────────────────────────────

-- Returns the Player whose character owns the given part, or nil.
local function playerFromTouchedPart(part: BasePart): Player?
	local char = part:FindFirstAncestorOfClass("Model")
	if not char then return nil end
	return Players:GetPlayerFromCharacter(char)
end

local function onCooldown(player: Player): boolean
	local last = lastTouch[player]
	if last and (tick() - last) < PAD_COOLDOWN then return true end
	lastTouch[player] = tick()
	return false
end

-- Move a player's character to a CFrame. Safe on dead/missing characters.
local function moveCharacterTo(player: Player, destination: CFrame)
	local char = player.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	char:PivotTo(destination)
end

-- ─── Pad handlers ────────────────────────────────────────────────────────────

local function handleLevelPad(player: Player, levelNumber: number)
	if gameManagerRef and gameManagerRef.enterLevel then
		gameManagerRef.enterLevel(player, levelNumber)
	else
		warn("[TeleportManager] No GameManager.enterLevel wired up")
	end
end

local function handleShopPad(player: Player)
	-- Block re-open for SHOP_CLOSE_COOLDOWN seconds after the player dismissed the shop
	local closedAt = shopClosedAt[player]
	if closedAt and (tick() - closedAt) < SHOP_CLOSE_COOLDOWN then return end

	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local openShop = remotes and remotes:FindFirstChild("OpenShop")
	if openShop then
		(openShop :: RemoteEvent):FireClient(player)
	end
end

local function handleInventoryPad(player: Player)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local openInv = remotes and remotes:FindFirstChild("OpenInventory")
	if openInv then
		(openInv :: RemoteEvent):FireClient(player)
	end
end

local function handleReturnPad(player: Player)
	if gameManagerRef and gameManagerRef.returnToLobby then
		gameManagerRef.returnToLobby(player)
	else
		-- Fallback: just teleport even if GameManager doesn't know
		TeleportManager.teleportToLobby(player)
	end
end

local function onPadTouched(pad: BasePart, touchingPart: BasePart)
	local player = playerFromTouchedPart(touchingPart)
	if not player then return end
	if onCooldown(player) then return end

	local padType = pad:GetAttribute("PadType")
	if padType == "Level" then
		local levelNumber = pad:GetAttribute("Level")
		if typeof(levelNumber) == "number" then
			handleLevelPad(player, levelNumber)
		end
	elseif padType == "Shop" then
		handleShopPad(player)
	elseif padType == "Inventory" then
		handleInventoryPad(player)
	elseif padType == "ReturnToLobby" then
		handleReturnPad(player)
	end
end

-- Walks the given subtree and wires Touched on anything with a PadType attribute.
local function wirePadsIn(root: Instance)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant:GetAttribute("PadType") then
			descendant.Touched:Connect(function(other)
				onPadTouched(descendant, other)
			end)
		end
	end
	-- Also wire anything added later (e.g. if builders rerun)
	root.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") and descendant:GetAttribute("PadType") then
			descendant.Touched:Connect(function(other)
				onPadTouched(descendant, other)
			end)
		end
	end)
end

-- ─── Public API ──────────────────────────────────────────────────────────────

function TeleportManager.teleportToLobby(player: Player)
	local ReplicatedStorageConst = require(ReplicatedStorage.Shared.Constants)
	local target = CFrame.new(ReplicatedStorageConst.LOBBY_SPAWN + Vector3.new(0, 3, 0))
	moveCharacterTo(player, target)
end

function TeleportManager.teleportToArena(player: Player, levelNumber: number)
	local ArenaBuilder = require(script.Parent.ArenaBuilder)
	local cframe = ArenaBuilder.getPlayerSpawnCFrame(levelNumber)
	if cframe then
		moveCharacterTo(player, cframe)
	else
		warn("[TeleportManager] No arena spawn for level", levelNumber)
	end
end

function TeleportManager.removePlayer(player: Player)
	lastTouch[player]    = nil
	shopClosedAt[player] = nil
end

-- Call once after the lobby + arenas are built.
-- `gameManager` is passed in to avoid a circular require.
function TeleportManager.init(gameManager: any)
	gameManagerRef = gameManager

	local lobby  = workspace:FindFirstChild("Lobby")
	local arenas = workspace:FindFirstChild("Arenas")
	if lobby  then wirePadsIn(lobby)  end
	if arenas then wirePadsIn(arenas) end

	Players.PlayerRemoving:Connect(TeleportManager.removePlayer)

	-- When the client dismisses the shop, stamp the close time so the pad
	-- won't reopen for SHOP_CLOSE_COOLDOWN seconds while they walk away.
	local remotes   = ReplicatedStorage:WaitForChild("Remotes")
	local shopClosed = remotes:WaitForChild("ShopClosed") :: RemoteEvent
	shopClosed.OnServerEvent:Connect(function(player: Player)
		shopClosedAt[player] = tick()
	end)

	print("[TeleportManager] Initialized — pads wired")
end

return TeleportManager

-- ClientMain.client.lua
-- StarterPlayer > StarterPlayerScripts > ClientMain  (this must be a LocalScript)
-- Entry point for all client-side logic. Boots UIManager and InputHandler.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for remotes to exist (server creates them on startup)
ReplicatedStorage:WaitForChild("Remotes")

local UIManager    = require(script.Parent.Client.UIManager)
local InputHandler = require(script.Parent.Client.InputHandler)

UIManager.init()
InputHandler.init()

print("[ClientMain] Client systems online")

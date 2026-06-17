---@diagnostic disable: undefined-global

local function addPath(pattern)
    if not string.find(package.path, pattern, 1, true) then
        package.path = package.path .. ";" .. pattern
    end
end

local function bootstrapModulePaths()
    addPath("?.lua")
    addPath("?/init.lua")

    if not shell or not fs then return end

    local running = shell.getRunningProgram and shell.getRunningProgram() or nil
    if not running or running == "" then return end

    local rootDir = fs.getDir(running)
    if rootDir and rootDir ~= "" then
        addPath(fs.combine(rootDir, "?.lua"))
        addPath(fs.combine(rootDir, "?/init.lua"))
    end
end

bootstrapModulePaths()

local Blackjack = require("games.blackjack")

Blackjack.run({
    baseBet = 5,
    currencyItem = "minecraft:iron_ingot",
    monitorScale = 0.5,
    layout = {
        -- Standard casino machine format:
        -- 2x3 Monitor
        -- Advanced Computer | Hopper
        -- House Chest | Player Chest
        monitor = "right",
        hopper = "left",
        houseChest = "back",
        playerChest = "bottom",
        requireHopper = true
    }
})

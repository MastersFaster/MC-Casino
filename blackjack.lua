---@diagnostic disable: undefined-global

local function loadLocalModule(moduleName)
    local ok, moduleOrErr = pcall(require, moduleName)
    if ok then return moduleOrErr end

    if not shell or not fs then
        error(moduleOrErr)
    end

    local running = shell.getRunningProgram and shell.getRunningProgram() or ""
    local resolved = shell.resolve and shell.resolve(running) or running
    local scriptDir = fs.getDir(resolved)
    local modulePath = string.gsub(moduleName, "%%.", "/") .. ".lua"
    local candidate = fs.combine(scriptDir, modulePath)

    if fs.exists(candidate) then
        return dofile(candidate)
    end

    error(moduleOrErr)
end

local Blackjack = loadLocalModule("games.blackjack")

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

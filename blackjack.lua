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
    local projectDir = fs.getDir(scriptDir)
    local modulePath = string.gsub(moduleName, "%%.", "/") .. ".lua"
    local candidates = {
        fs.combine("/MC-Casino", modulePath),
        fs.combine("MC-Casino", modulePath),
        fs.combine("/rootfs", modulePath),
        fs.combine("rootfs", modulePath),
        fs.combine("/", modulePath),
        fs.combine(projectDir, modulePath),
        fs.combine(scriptDir, modulePath)
    }

    for _, candidate in ipairs(candidates) do
        if fs.exists(candidate) then
            return dofile(candidate)
        end
    end

    error(moduleOrErr .. "\nTried paths: " .. table.concat(candidates, ", "))
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

---@diagnostic disable: undefined-global

local Layout = {}
local LOCAL_SIDES = {"left", "right", "top", "bottom", "front", "back"}

local function dedupeNames(names)
    local out = {}
    local seen = {}

    for _, name in ipairs(names) do
        if name and name ~= "" and not seen[name] then
            seen[name] = true
            table.insert(out, name)
        end
    end

    return out
end

local function allPeripheralNames()
    local names = {}

    for _, side in ipairs(LOCAL_SIDES) do
        if peripheral.isPresent(side) then
            table.insert(names, side)
        end
    end

    for _, name in ipairs(peripheral.getNames()) do
        table.insert(names, name)
    end

    return dedupeNames(names)
end

local function hasType(name, match)
    local lowerMatch = string.lower(match)

    local pType = peripheral.getType(name)
    if pType and string.find(string.lower(pType), lowerMatch, 1, true) then
        return true
    end

    if peripheral.getTypes then
        local ok, types = pcall(peripheral.getTypes, name)
        if ok and types then
            for _, t in ipairs(types) do
                if t and string.find(string.lower(t), lowerMatch, 1, true) then
                    return true
                end
            end
        end
    end

    return false
end

local function isInventory(name)
    if not name then return false end
    local ok = pcall(function() peripheral.call(name, "list") end)
    return ok
end

local function inventorySize(name)
    local ok, size = pcall(function() return peripheral.call(name, "size") end)
    if ok then return size end
    return nil
end

local function looksLikeHopper(name)
    if hasType(name, "hopper") then
        return true
    end

    if string.find(string.lower(name), "hopper", 1, true) then
        return true
    end

    local size = inventorySize(name)
    if size == 5 then
        return true
    end

    return false
end

local function resolveName(ref)
    if not ref then return nil end

    if peripheral.isPresent(ref) then
        return ref
    end

    for _, name in ipairs(allPeripheralNames()) do
        if name == ref then
            return name
        end
    end

    -- Allow placeholder refs like "sophisticatedstorage:chest_x" where x is numeric.
    if type(ref) == "string" and string.find(ref, "_x", 1, true) then
        local escaped = string.gsub(ref, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
        local pattern = "^" .. string.gsub(escaped, "_x", "_%%d+") .. "$"

        local matches = {}
        for _, name in ipairs(allPeripheralNames()) do
            if string.match(name, pattern) then
                table.insert(matches, name)
            end
        end

        if #matches > 0 then
            table.sort(matches)
            return matches[1]
        end
    end

    return nil
end

local function findByType(typeName)
    for _, name in ipairs(allPeripheralNames()) do
        if hasType(name, typeName) then
            return name
        end
    end
    return nil
end

local function findHopperName(exclude)
    for _, name in ipairs(allPeripheralNames()) do
        if not exclude[name] and looksLikeHopper(name) then
            return name
        end
    end

    return nil
end

local function collectChestCandidates(exclude)
    local result = {}

    for _, name in ipairs(allPeripheralNames()) do
        if not exclude[name] and isInventory(name) and not looksLikeHopper(name) then
            table.insert(result, name)
        end
    end

    table.sort(result)
    return result
end

local function peripheralSummary()
    local out = {}

    for _, name in ipairs(allPeripheralNames()) do
        local pType = peripheral.getType(name) or "unknown"
        table.insert(out, name .. "(" .. pType .. ")")
    end

    table.sort(out)
    return table.concat(out, ", ")
end

function Layout.resolve(config)
    config = config or {}

    local used = {}

    local monitorName = resolveName(config.monitor)
    if monitorName and not hasType(monitorName, "monitor") then
        monitorName = nil
    end
    monitorName = monitorName or findByType("monitor")
    if not monitorName then
        error("No monitor found. Peripherals seen: " .. peripheralSummary())
    end
    used[monitorName] = true

    local hopperName = resolveName(config.hopper)
    if hopperName and not looksLikeHopper(hopperName) then
        hopperName = nil
    end

    if not hopperName then
        hopperName = findHopperName(used)
    end

    if config.requireHopper ~= false and not hopperName then
        error("No hopper found. Peripherals seen: " .. peripheralSummary())
    end

    if hopperName then
        used[hopperName] = true
    end

    local houseName = resolveName(config.houseChest)
    if houseName and not isInventory(houseName) then
        houseName = nil
    end

    local playerName = resolveName(config.playerChest)
    if playerName and not isInventory(playerName) then
        playerName = nil
    end

    if houseName then used[houseName] = true end
    if playerName then used[playerName] = true end

    if not houseName or not playerName then
        local candidates = collectChestCandidates(used)

        if not houseName then
            houseName = candidates[1]
            if houseName then used[houseName] = true end
        end

        if not playerName then
            if candidates[1] == houseName then
                playerName = candidates[2]
            else
                playerName = candidates[1]
            end
        end
    end

    if not houseName or not playerName then
        error("Two chests are required: house chest and player chest. Only adjacent or modem-network peripherals are visible to ComputerCraft. If your second chest is next to the first chest (not next to the computer), attach a wired modem to that chest and to the computer, or move the second chest to an adjacent computer side. Peripherals seen: " .. peripheralSummary())
    end

    return {
        monitorName = monitorName,
        hopperName = hopperName,
        houseChestName = houseName,
        playerChestName = playerName,
        monitor = peripheral.wrap(monitorName),
        hopper = hopperName and peripheral.wrap(hopperName) or nil,
        houseChest = peripheral.wrap(houseName),
        playerChest = peripheral.wrap(playerName)
    }
end

function Layout.prepareMonitor(mon, options)
    options = options or {}
    options.scale = 0.5

    mon.setBackgroundColor(options.background or colors.green)
    mon.setTextColor(options.text or colors.white)
    if mon.setTextScale and options.scale then
        mon.setTextScale(options.scale)
    end
    mon.clear()
end

return Layout

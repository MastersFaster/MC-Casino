---@diagnostic disable: undefined-global

local Layout = {}

local function resolveName(ref)
    if not ref then return nil end
    if peripheral.isPresent(ref) then return ref end

    for _, name in ipairs(peripheral.getNames()) do
        if name == ref then return name end
    end

    return nil
end

local function findByType(typeName)
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == typeName then
            return name
        end
    end
    return nil
end

local function isInventory(name)
    if not name then return false end
    local ok = pcall(function() peripheral.call(name, "list") end)
    return ok
end

local function findHopperName(exclude)
    for _, name in ipairs(peripheral.getNames()) do
        if not exclude[name] then
            local pType = peripheral.getType(name)
            if pType and string.find(string.lower(pType), "hopper", 1, true) then
                return name
            end

            if isInventory(name) then
                local ok, size = pcall(function() return peripheral.call(name, "size") end)
                if ok and size == 5 then
                    return name
                end
            end
        end
    end

    return nil
end

local function collectChestCandidates(exclude)
    local result = {}

    for _, name in ipairs(peripheral.getNames()) do
        if not exclude[name] and isInventory(name) then
            table.insert(result, name)
        end
    end

    table.sort(result)
    return result
end

function Layout.resolve(config)
    config = config or {}

    local used = {}

    local monitorName = resolveName(config.monitor) or findByType("monitor")
    if not monitorName then
        error("No monitor found. Connect a 2x3 monitor to this computer or modem network.")
    end
    used[monitorName] = true

    local hopperName = resolveName(config.hopper) or findHopperName(used)
    if config.requireHopper ~= false and not hopperName then
        error("No hopper found. Expected hopper in the casino layout (Computer | Hopper).")
    end
    if hopperName then
        used[hopperName] = true
    end

    local houseName = resolveName(config.houseChest)
    local playerName = resolveName(config.playerChest)

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
        error("Two chests are required: house chest and player chest.")
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

    mon.setBackgroundColor(options.background or colors.green)
    mon.setTextColor(options.text or colors.white)
    if mon.setTextScale and options.scale then
        mon.setTextScale(options.scale)
    end
    mon.clear()
end

return Layout

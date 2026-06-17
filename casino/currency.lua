---@diagnostic disable: undefined-global

local Currency = {}
Currency.__index = Currency

function Currency.new(config)
    local self = setmetatable({}, Currency)
    self.itemName = config.itemName
    self.playerInventory = config.playerInventory
    self.houseInventory = config.houseInventory
    self.playerInventoryName = config.playerInventoryName
    self.houseInventoryName = config.houseInventoryName
    return self
end

function Currency:count(inv)
    local total = 0
    local items = inv.list()

    for _, item in pairs(items) do
        if item.name == self.itemName then
            total = total + item.count
        end
    end

    return total
end

local function safePeripheralName(inv, fallbackName)
    if fallbackName and fallbackName ~= "" then
        return fallbackName
    end

    if inv then
        local ok, name = pcall(peripheral.getName, inv)
        if ok and name and name ~= "" then
            return name
        end
    end

    return nil
end

local function joinErrors(errors)
    if #errors == 0 then return "unknown transfer failure" end
    return table.concat(errors, " | ")
end

local function appendError(errors, label, err)
    table.insert(errors, label .. ": " .. tostring(err))
end

local function isSideName(name)
    return name == "left" or name == "right" or name == "top" or name == "bottom" or name == "front" or name == "back"
end

local function tryTransfer(fromInv, toInv, fromName, toName, slot, amount)
    local errors = {}

    local okWrapper, movedWrapper = pcall(function()
        return fromInv.pushItems(toName, slot, amount)
    end)
    if okWrapper then
        return movedWrapper or 0
    end
    appendError(errors, "wrapper pushItems", movedWrapper)

    local okPush, movedPush = pcall(function()
        return peripheral.call(fromName, "pushItems", toName, slot, amount)
    end)
    if okPush then
        return movedPush or 0
    end
    appendError(errors, "named pushItems", movedPush)

    local okPull, movedPull = pcall(function()
        return peripheral.call(toName, "pullItems", fromName, slot, amount)
    end)
    if okPull then
        return movedPull or 0
    end
    appendError(errors, "named pullItems", movedPull)

    return nil, joinErrors(errors)
end

function Currency:validateTransferRoutes()
    local fromName = safePeripheralName(self.playerInventory, self.playerInventoryName)
    local toName = safePeripheralName(self.houseInventory, self.houseInventoryName)

    if not fromName or not toName then
        error("Currency validation failed: unable to resolve player/house inventory names")
    end

    -- Mixed naming domains (local side + modem remote name) often fail push/pull routing.
    local fromIsSide = isSideName(fromName)
    local toIsSide = isSideName(toName)
    if fromIsSide ~= toIsSide then
        error(
            "Currency transfer domain mismatch: player inventory is '" .. fromName ..
            "' and house inventory is '" .. toName .. "'. " ..
            "Use both chests in the same domain: either both directly adjacent side names or both modem remote names. " ..
            "Recommended fix: put wired modems on BOTH chests and configure playerChest/houseChest to their modem names."
        )
    end

    local _, forwardErr = tryTransfer(self.playerInventory, self.houseInventory, fromName, toName, 1, 0)
    local _, reverseErr = tryTransfer(self.houseInventory, self.playerInventory, toName, fromName, 1, 0)

    if forwardErr and reverseErr then
        error(
            "Currency transfer route validation failed between " .. fromName .. " and " .. toName ..
            ". Ensure both inventories are visible on the same computer/modem network. " ..
            "Forward errors: " .. forwardErr .. " || Reverse errors: " .. reverseErr
        )
    end
end

function Currency:move(fromInv, toInv, amount, fromNameHint, toNameHint)
    if amount <= 0 then return true end

    local remaining = amount
    local fromName = safePeripheralName(fromInv, fromNameHint)
    local toName = safePeripheralName(toInv, toNameHint)

    if not fromName or not toName then
        error("Unable to resolve inventory peripheral names for transfer")
    end

    for slot, item in pairs(fromInv.list()) do
        if item.name == self.itemName then
            local toMove = math.min(item.count, remaining)

            local moved, err = tryTransfer(fromInv, toInv, fromName, toName, slot, toMove)
            if moved == nil then
                error("Transfer failed from " .. fromName .. " to " .. toName .. ": " .. err)
            end

            remaining = remaining - moved
            if remaining <= 0 then
                return true
            end
        end
    end

    return false
end

function Currency:getPlayerMoney()
    return self:count(self.playerInventory)
end

function Currency:getHouseMoney()
    return self:count(self.houseInventory)
end

function Currency:playerCanCover(amount)
    return self:getPlayerMoney() >= amount
end

function Currency:houseCanCover(amount)
    return self:getHouseMoney() >= amount
end

function Currency:settleLoss(amount)
    return self:move(
        self.playerInventory,
        self.houseInventory,
        amount,
        self.playerInventoryName,
        self.houseInventoryName
    )
end

function Currency:settleWin(amount)
    return self:move(
        self.houseInventory,
        self.playerInventory,
        amount,
        self.houseInventoryName,
        self.playerInventoryName
    )
end

-- Backwards-compatible aliases.
function Currency:takeBet(amount)
    return self:settleLoss(amount)
end

function Currency:payOut(amount)
    return self:settleWin(amount)
end

return Currency

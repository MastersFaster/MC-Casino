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

            local moved = 0

            local okPush, movedOrErr = pcall(function()
                return peripheral.call(fromName, "pushItems", toName, slot, toMove)
            end)

            if okPush then
                moved = movedOrErr or 0
            else
                -- Some local+modem combos reject push by name; pull from destination is a safe fallback.
                local okPull, pulledOrErr = pcall(function()
                    return peripheral.call(toName, "pullItems", fromName, slot, toMove)
                end)

                if okPull then
                    moved = pulledOrErr or 0
                else
                    error("Transfer failed from " .. fromName .. " to " .. toName .. ": " .. tostring(movedOrErr) .. " | " .. tostring(pulledOrErr))
                end
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

function Currency:takeBet(amount)
    return self:move(
        self.playerInventory,
        self.houseInventory,
        amount,
        self.playerInventoryName,
        self.houseInventoryName
    )
end

function Currency:payOut(amount)
    return self:move(
        self.houseInventory,
        self.playerInventory,
        amount,
        self.houseInventoryName,
        self.playerInventoryName
    )
end

return Currency

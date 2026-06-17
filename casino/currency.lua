---@diagnostic disable: undefined-global

local Currency = {}
Currency.__index = Currency

function Currency.new(config)
    local self = setmetatable({}, Currency)
    self.itemName = config.itemName
    self.playerInventory = config.playerInventory
    self.houseInventory = config.houseInventory
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

function Currency:move(fromInv, toInv, amount)
    if amount <= 0 then return true end

    local remaining = amount
    local toName = peripheral.getName(toInv)

    for slot, item in pairs(fromInv.list()) do
        if item.name == self.itemName then
            local toMove = math.min(item.count, remaining)
            local moved = fromInv.pushItems(toName, slot, toMove)
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
    return self:move(self.playerInventory, self.houseInventory, amount)
end

function Currency:payOut(amount)
    return self:move(self.houseInventory, self.playerInventory, amount)
end

return Currency

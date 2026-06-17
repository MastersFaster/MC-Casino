---@diagnostic disable: undefined-global, undefined-field

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
    local candidates = {
        fs.combine("/MC-Casino", modulePath),
        fs.combine("MC-Casino", modulePath),
        fs.combine(scriptDir, modulePath),
        fs.combine("/", modulePath)
    }

    for _, candidate in ipairs(candidates) do
        if fs.exists(candidate) then
            return dofile(candidate)
        end
    end

    error(moduleOrErr .. "\nTried paths: " .. table.concat(candidates, ", "))
end

local Layout = loadLocalModule("casino.layout")
local Currency = loadLocalModule("casino.currency")
local pullEvent = os.pullEvent

local function printPeripheralBootInfo()
    if not peripheral then return end

    print("[MC-Casino] Peripheral scan on boot")

    local names = peripheral.getNames()
    table.sort(names)

    if #names == 0 then
        print("  none")
        return
    end

    for _, name in ipairs(names) do
        local pType = peripheral.getType(name) or "unknown"
        print("  - " .. name .. " (" .. pType .. ")")
    end
end

local function getScriptDir()
    if not shell or not fs then
        return "."
    end

    local running = shell.getRunningProgram and shell.getRunningProgram() or ""
    local resolved = shell.resolve and shell.resolve(running) or running
    return fs.getDir(resolved)
end

local function resolveCardsDir()
    if not fs then return nil end

    local scriptDir = getScriptDir()
    local candidates = {
        fs.combine("/MC-Casino", "cards"),
        fs.combine("MC-Casino", "cards"),
        fs.combine(scriptDir, "cards"),
        "/cards"
    }

    for _, path in ipairs(candidates) do
        if fs.exists(path) and fs.isDir(path) then
            return path
        end
    end

    return nil
end

local suits = {"S", "H", "C", "D"}
local ranks = {"A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"}

local CARD_W = 9
local DEALER_Y = 6
local PLAYER_Y = 16
local BUTTON_Y1 = 28
local BUTTON_Y2 = 33

local HIT_BOX = {x = 3, y = BUTTON_Y1, w = 12, h = 3}
local STAND_BOX = {x = 21, y = BUTTON_Y1, w = 12, h = 3}
local DOUBLE_BOX = {x = 3, y = BUTTON_Y2, w = 12, h = 3}
local QUIT_BOX = {x = 21, y = BUTTON_Y2, w = 12, h = 3}
local CASH_BOX = {x = 12, y = 38, w = 12, h = 3}

local function inBox(x, y, bx, by, bw, bh)
    return x >= bx and x <= bx + bw - 1 and y >= by and y <= by + bh - 1
end

local function cardValue(card)
    if card.rank == "A" then return 11 end
    if card.rank == "K" or card.rank == "Q" or card.rank == "J" then return 10 end
    return tonumber(card.rank)
end

local function handValue(hand)
    local total, aces = 0, 0

    for _, card in ipairs(hand) do
        total = total + cardValue(card)
        if card.rank == "A" then aces = aces + 1 end
    end

    while total > 21 and aces > 0 do
        total = total - 10
        aces = aces - 1
    end

    return total
end

local function newDeck()
    local deck = {}

    for _, suit in ipairs(suits) do
        for _, rank in ipairs(ranks) do
            table.insert(deck, {rank = rank, suit = suit})
        end
    end

    for i = #deck, 2, -1 do
        local j = math.random(i)
        deck[i], deck[j] = deck[j], deck[i]
    end

    return deck
end

local Game = {}
Game.__index = Game

function Game.new(config)
    config = config or {}

    local self = setmetatable({}, Game)
    self.baseBet = config.baseBet or 5

    self.layout = Layout.resolve(config.layout)
    self.monitor = self.layout.monitor
    self.monitorName = self.layout.monitorName
    self.monitorScale = config.monitorScale or 0.5

    Layout.prepareMonitor(self.monitor, {
        scale = self.monitorScale,
        background = colors.green,
        text = colors.white
    })

    self.monitorWidth, self.monitorHeight = self.monitor.getSize()

    self.currency = Currency.new({
        itemName = config.currencyItem or "minecraft:iron_ingot",
        playerInventory = self.layout.playerChest,
        houseInventory = self.layout.houseChest,
        playerInventoryName = self.layout.playerChestName,
        houseInventoryName = self.layout.houseChestName
    })
    self.currency:validateTransferRoutes()

    self.cardsDir = resolveCardsDir()
    self.cardImageCache = {}
    self.imageSupportChecked = false
    self.canDrawImages = false

    return self
end

function Game:ensureImageSupport()
    if self.imageSupportChecked then
        return self.canDrawImages
    end

    self.imageSupportChecked = true
    self.canDrawImages = paintutils and paintutils.loadImage and paintutils.drawImage and self.cardsDir ~= nil
    return self.canDrawImages
end

function Game:cardAssetName(card)
    local suitMap = {
        S = "spades",
        H = "hearts",
        C = "clubs",
        D = "diamonds"
    }

    local rankMap = {
        A = 1,
        J = 11,
        Q = 12,
        K = 13
    }

    local suit = suitMap[card.suit]
    local rank = rankMap[card.rank] or tonumber(card.rank)

    if not suit or not rank then
        return nil
    end

    return string.format("%s_%d.png", suit, rank)
end

function Game:drawCardImage(x, y, filename)
    if not self:ensureImageSupport() then
        return false
    end

    local path = fs.combine(self.cardsDir, filename)
    if not fs.exists(path) then
        return false
    end

    local image = self.cardImageCache[path]
    if image == false then
        return false
    end

    if not image then
        local ok, loaded = pcall(paintutils.loadImage, path)
        if not ok or not loaded then
            self.cardImageCache[path] = false
            return false
        end
        image = loaded
        self.cardImageCache[path] = image
    end

    local previous = term.current()
    term.redirect(self.monitor)
    local ok = pcall(paintutils.drawImage, image, x, y)
    term.redirect(previous)
    return ok
end

function Game:centerText(y, text)
    local x = math.floor((self.monitorWidth - #text) / 2) + 1
    self.monitor.setCursorPos(x, y)
    self.monitor.write(text)
end

function Game:cardX(index)
    return 3 + (index - 1) * (CARD_W + 2)
end

function Game:drawCard(x, y, card)
    local cardAsset = self:cardAssetName(card)
    if cardAsset and self:drawCardImage(x, y, cardAsset) then
        return
    end

    self.monitor.setBackgroundColor(colors.white)
    self.monitor.setTextColor(colors.black)

    self.monitor.setCursorPos(x, y)
    self.monitor.write("+-------+")
    self.monitor.setCursorPos(x, y + 1)
    self.monitor.write("|       |")

    local label = card.rank .. card.suit
    local pad = 7 - #label
    local left = math.floor(pad / 2)
    local right = pad - left

    self.monitor.setCursorPos(x, y + 2)
    self.monitor.write("|" .. string.rep(" ", left) .. label .. string.rep(" ", right) .. "|")
    self.monitor.setCursorPos(x, y + 3)
    self.monitor.write("|       |")
    self.monitor.setCursorPos(x, y + 4)
    self.monitor.write("+-------+")

    self.monitor.setBackgroundColor(colors.green)
    self.monitor.setTextColor(colors.white)
end

function Game:drawHiddenCard(x, y)
    if self:drawCardImage(x, y, "spades_0.png") then
        return
    end

    self.monitor.setBackgroundColor(colors.white)
    self.monitor.setTextColor(colors.black)

    self.monitor.setCursorPos(x, y)
    self.monitor.write("+-------+")
    self.monitor.setCursorPos(x, y + 1)
    self.monitor.write("|#######|")
    self.monitor.setCursorPos(x, y + 2)
    self.monitor.write("|#  ?  #|")
    self.monitor.setCursorPos(x, y + 3)
    self.monitor.write("|#######|")
    self.monitor.setCursorPos(x, y + 4)
    self.monitor.write("+-------+")

    self.monitor.setBackgroundColor(colors.green)
    self.monitor.setTextColor(colors.white)
end

function Game:drawButton(x, y, w, label)
    self.monitor.setBackgroundColor(colors.gray)
    self.monitor.setTextColor(colors.white)

    self.monitor.setCursorPos(x, y)
    self.monitor.write("+" .. string.rep("-", w - 2) .. "+")

    local pad = (w - 2) - #label
    local left = math.floor(pad / 2)
    local right = pad - left

    self.monitor.setCursorPos(x, y + 1)
    self.monitor.write("|" .. string.rep(" ", left) .. label .. string.rep(" ", right) .. "|")
    self.monitor.setCursorPos(x, y + 2)
    self.monitor.write("+" .. string.rep("-", w - 2) .. "+")

    self.monitor.setBackgroundColor(colors.green)
    self.monitor.setTextColor(colors.white)
end

function Game:drawTable(playerHand, dealerHand, revealDealer, playerTotal, money, bet, houseMoney)
    self.monitor.clear()

    self:centerText(2, "BLACKJACK CASINO")

    self.monitor.setCursorPos(3, 4)
    self.monitor.write("Dealer:")
    for i, card in ipairs(dealerHand) do
        if i > 3 then break end
        local cx = self:cardX(i)
        if i == 2 and not revealDealer then
            self:drawHiddenCard(cx, DEALER_Y)
        else
            self:drawCard(cx, DEALER_Y, card)
        end
    end

    self.monitor.setCursorPos(3, 13)
    self.monitor.write("Player:")
    for i, card in ipairs(playerHand) do
        if i > 3 then break end
        self:drawCard(self:cardX(i), PLAYER_Y, card)
    end

    self.monitor.setCursorPos(3, 22)
    self.monitor.write("Total: " .. playerTotal)

    self.monitor.setCursorPos(3, 23)
    self.monitor.write("Iron: " .. money .. "  Bet: " .. bet)

    self.monitor.setCursorPos(3, 24)
    self.monitor.write("House: " .. houseMoney)

    self:drawButton(CASH_BOX.x, CASH_BOX.y, CASH_BOX.w, "Cashout")
    self:drawButton(HIT_BOX.x, HIT_BOX.y, HIT_BOX.w, "Hit")
    self:drawButton(STAND_BOX.x, STAND_BOX.y, STAND_BOX.w, "Stand")
    self:drawButton(DOUBLE_BOX.x, DOUBLE_BOX.y, DOUBLE_BOX.w, "Double")
    self:drawButton(QUIT_BOX.x, QUIT_BOX.y, QUIT_BOX.w, "Quit")
end

function Game:getRoundBet(money, houseMoney)
    local bet = self.baseBet
    if bet > money then bet = money end
    if bet > houseMoney then bet = houseMoney end
    if bet < 1 then bet = 1 end
    return bet
end

function Game:showOutOfService(message)
    self.monitor.setBackgroundColor(colors.red)
    self.monitor.setTextColor(colors.white)
    self.monitor.clear()
    self:centerText(math.floor(self.monitorHeight / 2) - 1, "OUT OF SERVICE")
    self:centerText(math.floor(self.monitorHeight / 2) + 1, message or "House chest is empty.")
    sleep(4)
    Layout.prepareMonitor(self.monitor, {
        scale = self.monitorScale,
        background = colors.green,
        text = colors.white
    })
end

function Game:showMessage(text, seconds)
    self.monitor.clear()
    self:centerText(math.floor(self.monitorHeight / 2), text)
    sleep(seconds or 2)
end

function Game:waitTouch()
    while true do
        local _, side, x, y = pullEvent("monitor_touch")
        if side == self.monitorName then
            return x, y
        end
    end
end

function Game:syncHopperDeposits()
    local hopper = self.layout.hopper
    local hopperName = self.layout.hopperName
    local playerChestName = self.layout.playerChestName

    if not hopper or not hopperName or not playerChestName then
        return 0
    end

    local movedTotal = 0
    local itemName = self.currency.itemName

    for slot, item in pairs(hopper.list()) do
        if item.name == itemName then
            local requested = item.count
            local moved = 0

            local okPush, movedPush = pcall(function()
                return hopper.pushItems(playerChestName, slot, requested)
            end)
            if okPush and movedPush then
                moved = movedPush
            else
                local okPull, movedPull = pcall(function()
                    return peripheral.call(playerChestName, "pullItems", hopperName, slot, requested)
                end)
                if okPull and movedPull then
                    moved = movedPull
                end
            end

            movedTotal = movedTotal + moved
        end
    end

    return movedTotal
end

function Game:playRound()
    self:syncHopperDeposits()

    local money = self.currency:getPlayerMoney()
    local houseMoney = self.currency:getHouseMoney()

    if money <= 0 then
        self:showMessage("Insert iron into hopper to play.", 3)
        return true
    end

    if houseMoney <= 0 then
        self:showOutOfService("House chest empty. Cashing out.")
        self:showMessage("Cashout: take iron from player chest.", 3)
        return false
    end

    local bet = self:getRoundBet(money, houseMoney)
    if bet > houseMoney then
        self:showOutOfService("House cannot cover bets.")
        self:showMessage("Cashout: take iron from player chest.", 3)
        return false
    end

    local deck = newDeck()
    local player, dealer = {}, {}

    table.insert(player, table.remove(deck))
    table.insert(player, table.remove(deck))
    table.insert(dealer, table.remove(deck))
    table.insert(dealer, table.remove(deck))

    local revealDealer = false
    local canDouble = true

    while true do
        self:syncHopperDeposits()

        local playerTotal = handValue(player)
        money = self.currency:getPlayerMoney()
        houseMoney = self.currency:getHouseMoney()
        self:drawTable(player, dealer, revealDealer, playerTotal, money, bet, houseMoney)

        if playerTotal > 21 then
            if not self.currency:settleLoss(bet) then
                self:showMessage("Loss transfer failed.", 3)
                return false
            end
            self.monitor.setCursorPos(3, 27)
            self.monitor.write("Bust! You lose.")
            sleep(2)
            return true
        end

        local x, y = self:waitTouch()

        if inBox(x, y, CASH_BOX.x, CASH_BOX.y, CASH_BOX.w, CASH_BOX.h) then
            self:showMessage("Cashout: take iron from player chest.", 3)
            return false
        end

        if inBox(x, y, HIT_BOX.x, HIT_BOX.y, HIT_BOX.w, HIT_BOX.h) then
            table.insert(player, table.remove(deck))
            canDouble = false
        elseif inBox(x, y, STAND_BOX.x, STAND_BOX.y, STAND_BOX.w, STAND_BOX.h) then
            revealDealer = true
            while handValue(dealer) < 17 do
                table.insert(dealer, table.remove(deck))
                self:drawTable(player, dealer, true, playerTotal, money, bet, houseMoney)
                sleep(0.3)
            end

            local dealerTotal = handValue(dealer)
            local result = "Push."

            if dealerTotal > 21 or playerTotal > dealerTotal then
                result = "You win!"
                if not self.currency:houseCanCover(bet) then
                    self:showOutOfService("House cannot pay winnings.")
                    self:showMessage("Cashout: take iron from player chest.", 3)
                    return false
                end
                if not self.currency:settleWin(bet) then
                    self:showOutOfService("Payout transfer failed.")
                    self:showMessage("Cashout: take iron from player chest.", 3)
                    return false
                end
            elseif playerTotal < dealerTotal then
                result = "You lose."
                if not self.currency:settleLoss(bet) then
                    self:showMessage("Loss transfer failed.", 3)
                    return false
                end
            end

            money = self.currency:getPlayerMoney()
            houseMoney = self.currency:getHouseMoney()
            self:drawTable(player, dealer, true, playerTotal, money, bet, houseMoney)
            self.monitor.setCursorPos(3, 27)
            self.monitor.write(result)
            sleep(2)
            return true
        elseif inBox(x, y, DOUBLE_BOX.x, DOUBLE_BOX.y, DOUBLE_BOX.w, DOUBLE_BOX.h) then
            local proposedBet = bet * 2
            if canDouble and self.currency:playerCanCover(proposedBet) and self.currency:houseCanCover(proposedBet) then
                bet = proposedBet
                table.insert(player, table.remove(deck))
                canDouble = false
            else
                self.monitor.setCursorPos(3, 27)
                self.monitor.write("Cannot double (funds/house limit).")
                sleep(1)
            end
        elseif inBox(x, y, QUIT_BOX.x, QUIT_BOX.y, QUIT_BOX.w, QUIT_BOX.h) then
            self:showMessage("Thanks for playing!", 2)
            return false
        end
    end
end

function Game:run()
    while true do
        local shouldContinue = self:playRound()
        if not shouldContinue then
            break
        end
    end
end

printPeripheralBootInfo()

local game = Game.new({
    baseBet = 5,
    currencyItem = "minecraft:iron_ingot",
    monitorScale = 0.5,
    layout = {
        -- Standard casino machine format:
        -- 2x3 Monitor
        -- Advanced Computer | Hopper
        -- House Chest | Player Chest
        monitor = "top",
        hopper = "right",
        houseChest = "sophisticatedstorage:chest_1",
        playerChest = "sophisticatedstorage:chest_0",
        requireHopper = true
    }
})

game:run()

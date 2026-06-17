---@diagnostic disable: undefined-global, undefined-field

local Layout = require("casino.layout")
local Currency = require("casino.currency")
local pullEvent = os.pullEvent

local BlackjackGame = {}
BlackjackGame.__index = BlackjackGame

local suits = {"S", "H", "C", "D"}
local ranks = {"A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"}

local CARD_W, CARD_H = 9, 5
local DEALER_Y = 6
local PLAYER_Y = 16
local BUTTON_Y1 = 28
local BUTTON_Y2 = 33

local HIT_BOX = {x = 3, y = BUTTON_Y1, w = 12, h = 3}
local STAND_BOX = {x = 21, y = BUTTON_Y1, w = 12, h = 3}
local DOUBLE_BOX = {x = 3, y = BUTTON_Y2, w = 12, h = 3}
local QUIT_BOX = {x = 21, y = BUTTON_Y2, w = 12, h = 3}
local CASH_BOX = {x = 12, y = 24, w = 12, h = 3}

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

function BlackjackGame.new(config)
    config = config or {}

    local self = setmetatable({}, BlackjackGame)
    self.baseBet = config.baseBet or 5

    self.layout = Layout.resolve(config.layout)
    self.monitor = self.layout.monitor
    self.monitorName = self.layout.monitorName

    Layout.prepareMonitor(self.monitor, {
        scale = config.monitorScale or 0.5,
        background = colors.green,
        text = colors.white
    })

    self.monitorWidth, self.monitorHeight = self.monitor.getSize()

    self.currency = Currency.new({
        itemName = config.currencyItem or "minecraft:iron_ingot",
        playerInventory = self.layout.playerChest,
        houseInventory = self.layout.houseChest
    })

    return self
end

function BlackjackGame:centerText(y, text)
    local x = math.floor((self.monitorWidth - #text) / 2) + 1
    self.monitor.setCursorPos(x, y)
    self.monitor.write(text)
end

function BlackjackGame:cardX(index)
    return 3 + (index - 1) * (CARD_W + 2)
end

function BlackjackGame:drawCard(x, y, card)
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

function BlackjackGame:drawHiddenCard(x, y)
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

function BlackjackGame:drawButton(x, y, w, label)
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

function BlackjackGame:drawTable(playerHand, dealerHand, revealDealer, playerTotal, money, bet)
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

    self.monitor.setCursorPos(3, 23)
    self.monitor.write("Total: " .. playerTotal)

    self.monitor.setCursorPos(3, 25)
    self.monitor.write("Iron: " .. money .. "  Bet: " .. bet)

    self:drawButton(CASH_BOX.x, CASH_BOX.y, CASH_BOX.w, "Cashout")
    self:drawButton(HIT_BOX.x, HIT_BOX.y, HIT_BOX.w, "Hit")
    self:drawButton(STAND_BOX.x, STAND_BOX.y, STAND_BOX.w, "Stand")
    self:drawButton(DOUBLE_BOX.x, DOUBLE_BOX.y, DOUBLE_BOX.w, "Double")
    self:drawButton(QUIT_BOX.x, QUIT_BOX.y, QUIT_BOX.w, "Quit")
end

function BlackjackGame:getRoundBet(money)
    local bet = self.baseBet
    if bet > money then bet = money end
    if bet < 1 then bet = 1 end
    return bet
end

function BlackjackGame:showMessage(text, seconds)
    self.monitor.clear()
    self:centerText(math.floor(self.monitorHeight / 2), text)
    sleep(seconds or 2)
end

function BlackjackGame:waitTouch()
    while true do
        local _, side, x, y = pullEvent("monitor_touch")
        if side == self.monitorName then
            return x, y
        end
    end
end

function BlackjackGame:playRound()
    local money = self.currency:getPlayerMoney()
    if money <= 0 then
        self:showMessage("Insert iron into hopper to play.", 3)
        return true
    end

    local bet = self:getRoundBet(money)
    if not self.currency:takeBet(bet) then
        self:showMessage("Not enough iron for bet.", 2)
        return true
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
        local playerTotal = handValue(player)
        money = self.currency:getPlayerMoney()
        self:drawTable(player, dealer, revealDealer, playerTotal, money, bet)

        if playerTotal > 21 then
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
                self:drawTable(player, dealer, true, playerTotal, money, bet)
                sleep(0.3)
            end

            local dealerTotal = handValue(dealer)
            local result = "Push."

            if dealerTotal > 21 or playerTotal > dealerTotal then
                result = "You win!"
                self.currency:payOut(bet * 2)
            elseif playerTotal < dealerTotal then
                result = "You lose."
            else
                self.currency:payOut(bet)
            end

            money = self.currency:getPlayerMoney()
            self:drawTable(player, dealer, true, playerTotal, money, bet)
            self.monitor.setCursorPos(3, 27)
            self.monitor.write(result)
            sleep(2)
            return true
        elseif inBox(x, y, DOUBLE_BOX.x, DOUBLE_BOX.y, DOUBLE_BOX.w, DOUBLE_BOX.h) then
            if canDouble and self.currency:getPlayerMoney() >= bet and self.currency:takeBet(bet) then
                bet = bet * 2
                table.insert(player, table.remove(deck))
                canDouble = false
            else
                self.monitor.setCursorPos(3, 27)
                self.monitor.write("Cannot double right now.")
                sleep(1)
            end
        elseif inBox(x, y, QUIT_BOX.x, QUIT_BOX.y, QUIT_BOX.w, QUIT_BOX.h) then
            self:showMessage("Thanks for playing!", 2)
            return false
        end
    end
end

function BlackjackGame:run()
    while true do
        local shouldContinue = self:playRound()
        if not shouldContinue then
            break
        end
    end
end

local M = {}

function M.run(config)
    local game = BlackjackGame.new(config)
    game:run()
end

return M

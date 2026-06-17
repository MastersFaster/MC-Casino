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

local function readAllText(path)
    if not fs or not fs.exists(path) then
        return nil
    end

    local handle = fs.open(path, "r")
    if not handle then
        return nil
    end

    local content = handle.readAll()
    handle.close()
    return content
end

local suits = {"S", "H", "C", "D"}
local ranks = {"A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"}

local MIN_CARD_W = 9
local MAX_CARD_W = 18
local MIN_CARD_H = 5

local function imageSize(image)
    local h = #image
    local w = 0

    if h > 0 and type(image[1]) == "table" then
        w = #image[1]
    end

    return w, h
end

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function normalizeImageSize(image, targetW, targetH)
    local srcW, srcH = imageSize(image)
    if srcW <= 0 or srcH <= 0 then
        return nil
    end

    if srcW == targetW and srcH == targetH then
        return image
    end

    local out = {}

    for y = 1, targetH do
        out[y] = {}
        local sourceY = clamp(math.floor(((y - 0.5) * srcH / targetH) + 0.5), 1, srcH)
        local sourceRow = image[sourceY]

        for x = 1, targetW do
            local sourceX = clamp(math.floor(((x - 0.5) * srcW / targetW) + 0.5), 1, srcW)
            out[y][x] = sourceRow[sourceX]
        end
    end

    return out
end

local function blitImageSize(image)
    local h = #image
    if h == 0 then
        return 0, 0
    end

    local firstRow = image[1]
    if type(firstRow) ~= "table" or type(firstRow[1]) ~= "string" then
        return 0, 0
    end

    return #firstRow[1], h
end

local function normalizeBlitImageSize(image, targetW, targetH)
    local srcW, srcH = blitImageSize(image)
    if srcW <= 0 or srcH <= 0 then
        return nil
    end

    if srcW == targetW and srcH == targetH then
        return image
    end

    local out = {}

    for y = 1, targetH do
        local sourceY = clamp(math.floor(((y - 0.5) * srcH / targetH) + 0.5), 1, srcH)
        local srcRow = image[sourceY]
        local text, fg, bg = srcRow[1], srcRow[2], srcRow[3]

        local textOut, fgOut, bgOut = {}, {}, {}
        for x = 1, targetW do
            local sourceX = clamp(math.floor(((x - 0.5) * srcW / targetW) + 0.5), 1, srcW)
            textOut[x] = text:sub(sourceX, sourceX)
            fgOut[x] = fg:sub(sourceX, sourceX)
            bgOut[x] = bg:sub(sourceX, sourceX)
        end

        out[y] = {table.concat(textOut), table.concat(fgOut), table.concat(bgOut)}
    end

    return out
end

local function fitImagePreserveAspect(image, targetW, targetH, fillColor)
    local srcW, srcH = imageSize(image)
    if srcW <= 0 or srcH <= 0 then
        return nil
    end

    local scaleX = targetW / srcW
    local scaleY = targetH / srcH
    local scale = math.min(scaleX, scaleY)
    if scale <= 0 then
        return nil
    end

    local fitW = math.max(1, math.floor(srcW * scale + 0.5))
    local fitH = math.max(1, math.floor(srcH * scale + 0.5))
    local resized = normalizeImageSize(image, fitW, fitH)
    if not resized then
        return nil
    end

    local out = {}
    local offsetX = math.floor((targetW - fitW) / 2)
    local offsetY = math.floor((targetH - fitH) / 2)

    for y = 1, targetH do
        out[y] = {}
        for x = 1, targetW do
            out[y][x] = fillColor
        end
    end

    for y = 1, fitH do
        for x = 1, fitW do
            out[y + offsetY][x + offsetX] = resized[y][x]
        end
    end

    return out
end

local function blitImageSize(image)
    local h = #image
    local w = 0

    if h > 0 and type(image[1]) == "table" and type(image[1][1]) == "string" then
        w = #image[1][1]
    end

    return w, h
end

local function normalizeBlitImageSize(image, targetW, targetH)
    local srcW, srcH = blitImageSize(image)
    if srcW <= 0 or srcH <= 0 then
        return nil
    end

    if srcW == targetW and srcH == targetH then
        return image
    end

    local out = {}

    for y = 1, targetH do
        local sourceY = clamp(math.floor(((y - 0.5) * srcH / targetH) + 0.5), 1, srcH)
        local srcRow = image[sourceY]
        local srcText, srcFg, srcBg = srcRow[1], srcRow[2], srcRow[3]

        local textChars = {}
        local fgChars = {}
        local bgChars = {}

        for x = 1, targetW do
            local sourceX = clamp(math.floor(((x - 0.5) * srcW / targetW) + 0.5), 1, srcW)
            textChars[x] = string.sub(srcText, sourceX, sourceX)
            fgChars[x] = string.sub(srcFg, sourceX, sourceX)
            bgChars[x] = string.sub(srcBg, sourceX, sourceX)
        end

        out[y] = {table.concat(textChars), table.concat(fgChars), table.concat(bgChars)}
    end

    return out
end

local function fitBlitImagePreserveAspect(image, targetW, targetH, fillFg, fillBg)
    local srcW, srcH = blitImageSize(image)
    if srcW <= 0 or srcH <= 0 then
        return nil
    end

    local scaleX = targetW / srcW
    local scaleY = targetH / srcH
    local scale = math.min(scaleX, scaleY)
    if scale <= 0 then
        return nil
    end

    local fitW = math.max(1, math.floor(srcW * scale + 0.5))
    local fitH = math.max(1, math.floor(srcH * scale + 0.5))
    local resized = normalizeBlitImageSize(image, fitW, fitH)
    if not resized then
        return nil
    end

    local out = {}
    local offsetX = math.floor((targetW - fitW) / 2)
    local offsetY = math.floor((targetH - fitH) / 2)

    local blankText = string.rep(" ", targetW)
    local blankFg = string.rep(fillFg, targetW)
    local blankBg = string.rep(fillBg, targetW)

    for y = 1, targetH do
        out[y] = {blankText, blankFg, blankBg}
    end

    for y = 1, fitH do
        local row = resized[y]
        local text = row[1]
        local fg = row[2]
        local bg = row[3]

        local leftText = string.rep(" ", offsetX)
        local rightText = string.rep(" ", targetW - fitW - offsetX)

        local leftFg = string.rep(fillFg, offsetX)
        local rightFg = string.rep(fillFg, targetW - fitW - offsetX)

        local leftBg = string.rep(fillBg, offsetX)
        local rightBg = string.rep(fillBg, targetW - fitW - offsetX)

        out[y + offsetY] = {
            leftText .. text .. rightText,
            leftFg .. fg .. rightFg,
            leftBg .. bg .. rightBg
        }
    end

    return out
end

local function extractLuaCardTables(fileText)
    local chunk = string.match(fileText, "local%s+image%s*,%s*palette%s*=%s*(.-)%s*term%.clear%s*%(")
    if not chunk then
        return nil, nil
    end

    local loader, err = load("return " .. chunk, "card_asset", "t", {})
    if not loader then
        return nil, err
    end

    local ok, image, palette = pcall(loader)
    if not ok or type(image) ~= "table" or type(palette) ~= "table" then
        return nil, "invalid card asset lua data"
    end

    return image, palette
end

local function fitBlitPreserveAspect(image, targetW, targetH, fillFg, fillBg)
    local srcW, srcH = blitImageSize(image)
    if srcW <= 0 or srcH <= 0 then
        return nil
    end

    local scaleX = targetW / srcW
    local scaleY = targetH / srcH
    local scale = math.min(scaleX, scaleY)
    if scale <= 0 then
        return nil
    end

    local fitW = math.max(1, math.floor(srcW * scale + 0.5))
    local fitH = math.max(1, math.floor(srcH * scale + 0.5))
    local resized = normalizeBlitImageSize(image, fitW, fitH)
    if not resized then
        return nil
    end

    local out = {}
    local offsetX = math.floor((targetW - fitW) / 2)
    local offsetY = math.floor((targetH - fitH) / 2)

    for y = 1, targetH do
        out[y] = {string.rep(" ", targetW), string.rep(fillFg, targetW), string.rep(fillBg, targetW)}
    end

    for y = 1, fitH do
        local targetY = y + offsetY
        local srcRow = resized[y]
        local text, fg, bg = out[targetY][1], out[targetY][2], out[targetY][3]
        local insertPos = offsetX + 1
        out[targetY][1] = text:sub(1, insertPos - 1) .. srcRow[1] .. text:sub(insertPos + fitW)
        out[targetY][2] = fg:sub(1, insertPos - 1) .. srcRow[2] .. fg:sub(insertPos + fitW)
        out[targetY][3] = bg:sub(1, insertPos - 1) .. srcRow[3] .. bg:sub(insertPos + fitW)
    end

    return out
end

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
    self.cardScale = tonumber(config.cardScale) or 1
    if self.cardScale < 0.5 then self.cardScale = 0.5 end
    if self.cardScale > 2.0 then self.cardScale = 2.0 end

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
    self:computeLayout()

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
    self.luaCardCache = {}
    self.imageSupportChecked = false
    self.canDrawImages = false

    return self
end

function Game:refreshMonitorGeometry()
    local width, height = self.monitor.getSize()
    if width == self.monitorWidth and height == self.monitorHeight then
        return
    end

    self.monitorWidth = width
    self.monitorHeight = height
    self:computeLayout()

    -- Rebuild normalized images using the new card dimensions.
    self.cardImageCache = {}
    self.luaCardCache = {}
end

function Game:computeLayout()
    local buttonY1 = self.monitorHeight - 11
    local buttonY2 = buttonY1 + 5

    self.cardGap = 2
    -- Size cards for the common 2-card blackjack state; when a 3rd card appears
    -- we dynamically tighten spacing instead of shrinking the art itself.
    local maxCardWByWidth = math.floor((self.monitorWidth - 6) / 2)
    local scaledCardW = math.floor(maxCardWByWidth * self.cardScale + 0.5)
    self.cardW = clamp(scaledCardW, MIN_CARD_W, math.min(MAX_CARD_W, maxCardWByWidth))

    local maxCardHByHeight = math.floor((buttonY1 - 24) / 2)
    if maxCardHByHeight < MIN_CARD_H then
        maxCardHByHeight = MIN_CARD_H
    end

    -- Card art is portrait-oriented, so keep cards taller than they are wide.
    local desiredCardH = math.floor(self.cardW * 1.4)
    self.cardH = clamp(desiredCardH, MIN_CARD_H, maxCardHByHeight)

    self.dealerLabelY = 4
    self.dealerY = self.dealerLabelY + 2
    self.playerY = self.dealerY + self.cardH + 6
    self.playerLabelY = self.playerY - 3

    local cashY = buttonY1 - 4

    while true do
        local infoTotalY = self.playerY + self.cardH + 1
        local infoHouseY = infoTotalY + 2
        if infoHouseY < cashY - 1 or self.cardH <= MIN_CARD_H then
            break
        end
        self.cardH = self.cardH - 1
        self.playerY = self.dealerY + self.cardH + 6
        self.playerLabelY = self.playerY - 3
    end

    self.hitBox = {x = 3, y = buttonY1, w = 12, h = 3}
    self.standBox = {x = 21, y = buttonY1, w = 12, h = 3}
    self.doubleBox = {x = 3, y = buttonY2, w = 12, h = 3}
    self.quitBox = {x = 21, y = buttonY2, w = 12, h = 3}
    self.cashBox = {x = 12, y = cashY, w = 12, h = 3}

    self.infoTotalY = self.playerY + self.cardH + 1
    self.infoMoneyY = self.infoTotalY + 1
    self.infoHouseY = self.infoTotalY + 2
end

function Game:getCardRowLayout(cardCount)
    local shown = math.max(1, math.min(cardCount, 3))
    local spacing = self.cardW + self.cardGap

    if shown > 1 then
        local maxSpacing = math.floor((self.monitorWidth - 4 - self.cardW) / (shown - 1))
        if maxSpacing < 1 then maxSpacing = 1 end
        spacing = math.min(spacing, maxSpacing)
    end

    local totalWidth = self.cardW + (shown - 1) * spacing
    local startX = math.floor((self.monitorWidth - totalWidth) / 2) + 1
    if startX < 2 then startX = 2 end

    return startX, spacing, shown
end

function Game:ensureImageSupport()
    if self.imageSupportChecked then
        return self.canDrawImages
    end

    self.imageSupportChecked = true
    self.canDrawImages = self.cardsDir ~= nil
    return self.canDrawImages
end

function Game:loadLuaCardAsset(path)
    local content = readAllText(path)
    if not content then
        return nil
    end

    local imageSrc, paletteSrc = content:match("local%s+image%s*,%s*palette%s*=%s*(%b{})%s*,%s*(%b{})")
    if not imageSrc or not paletteSrc then
        return nil
    end

    local chunk, err = load("return " .. imageSrc .. "," .. paletteSrc, "@" .. path, "t", {})
    if not chunk then
        return nil, err
    end

    local ok, image, palette = pcall(chunk)
    if not ok or type(image) ~= "table" then
        return nil
    end

    return image, palette
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

    return string.format("%s_%d", suit, rank)
end

function Game:drawCardImage(x, y, basename)
    local luaPath = fs.combine(self.cardsDir or "", basename .. ".lua")
    if self.cardsDir and fs.exists(luaPath) then
        local cached = self.luaCardCache[luaPath]
        if cached ~= false then
            if not cached then
                local okRead, fileText = pcall(function()
                    return fs.open(luaPath, "r")
                end)

                if not okRead or not fileText then
                    self.luaCardCache[luaPath] = false
                else
                    local content = fileText.readAll()
                    fileText.close()

                    local image, palette = extractLuaCardTables(content)
                    if not image or not palette then
                        self.luaCardCache[luaPath] = false
                    else
                        local fitted = fitBlitImagePreserveAspect(image, self.cardW, self.cardH, "0", "0")
                        if not fitted then
                            self.luaCardCache[luaPath] = false
                        else
                            self.luaCardCache[luaPath] = {
                                image = fitted,
                                palette = palette
                            }
                        end
                    end
                end

                cached = self.luaCardCache[luaPath]
            end

            if cached and cached.image and cached.palette then
                local previous = term.current()
                term.redirect(self.monitor)

                for i = 0, 15 do
                    local pal = cached.palette[i]
                    if pal and term.setPaletteColor then
                        term.setPaletteColor(2 ^ i, table.unpack(pal))
                    end
                end

                for rowIndex, row in ipairs(cached.image) do
                    term.setCursorPos(x, y + rowIndex - 1)
                    term.blit(row[1], row[2], row[3])
                end

                if term.setPaletteColor and term.nativePaletteColor then
                    for i = 0, 15 do
                        term.setPaletteColor(2 ^ i, term.nativePaletteColor(2 ^ i))
                    end
                end

                term.redirect(previous)
                return true
            end
        end
    end

    if not self:ensureImageSupport() then
        return false
    end

    local nfpPath = fs.combine(self.cardsDir, basename .. ".nfp")
    if not fs.exists(nfpPath) then return false end

    local image = self.cardImageCache[nfpPath]
    if image == false then
        return false
    end

    if not image then
        local ok, loaded = pcall(paintutils.loadImage, nfpPath)
        if not ok or not loaded then
            self.cardImageCache[nfpPath] = false
            return false
        end

        local normalized = fitImagePreserveAspect(loaded, self.cardW, self.cardH, colors.white)
        if not normalized then
            self.cardImageCache[nfpPath] = false
            return false
        end

        image = {kind = "paint", rows = normalized}
        self.cardImageCache[nfpPath] = image
    end

    local previous = term.current()
    term.redirect(self.monitor)

    local ok = true
    if image.kind == "blit" then
        if type(image.palette) == "table" then
            for i = 0, 15 do
                local entry = image.palette[i]
                if entry then
                    self.monitor.setPaletteColor(2 ^ i, entry[1], entry[2], entry[3])
                end
            end
        end

        for rowIndex, row in ipairs(image.rows) do
            self.monitor.setCursorPos(x, y + rowIndex - 1)
            self.monitor.blit(row[1], row[2], row[3])
        end
    else
        ok = pcall(paintutils.drawImage, image.rows, x, y)
    end

    term.redirect(previous)
    return ok
end

function Game:centerText(y, text)
    local x = math.floor((self.monitorWidth - #text) / 2) + 1
    self.monitor.setCursorPos(x, y)
    self.monitor.write(text)
end

function Game:cardX(index, startX, spacing)
    return startX + (index - 1) * spacing
end

function Game:drawCardLabelOverlay(x, y, card)
    -- Intentionally left empty: preserving original art without overlay text.
end

function Game:drawCard(x, y, card)
    local cardAsset = self:cardAssetName(card)
    if cardAsset and self:drawCardImage(x, y, cardAsset) then
        self:drawCardLabelOverlay(x, y, card)
        return
    end

    local innerW = self.cardW - 2
    local innerH = self.cardH - 2

    self.monitor.setBackgroundColor(colors.white)
    self.monitor.setTextColor(colors.black)

    self.monitor.setCursorPos(x, y)
    self.monitor.write("+" .. string.rep("-", innerW) .. "+")

    for row = 1, innerH do
        self.monitor.setCursorPos(x, y + row)
        self.monitor.write("|" .. string.rep(" ", innerW) .. "|")
    end

    local label = card.rank .. card.suit
    local pad = innerW - #label
    if pad < 0 then pad = 0 end
    local left = math.floor(pad / 2)
    local right = pad - left

    local labelY = y + math.floor(self.cardH / 2)
    self.monitor.setCursorPos(x, labelY)
    self.monitor.write("|" .. string.rep(" ", left) .. label .. string.rep(" ", right) .. "|")

    self.monitor.setCursorPos(x, y + self.cardH - 1)
    self.monitor.write("+" .. string.rep("-", innerW) .. "+")

    self.monitor.setBackgroundColor(colors.green)
    self.monitor.setTextColor(colors.white)
end

function Game:drawHiddenCard(x, y)
    if self:drawCardImage(x, y, "spades_0") then
        return
    end

    local innerW = self.cardW - 2
    local innerH = self.cardH - 2

    self.monitor.setBackgroundColor(colors.white)
    self.monitor.setTextColor(colors.black)

    self.monitor.setCursorPos(x, y)
    self.monitor.write("+" .. string.rep("-", innerW) .. "+")

    for row = 1, innerH do
        self.monitor.setCursorPos(x, y + row)
        if row == math.floor((innerH + 1) / 2) then
            local leftHashes = math.floor((innerW - 1) / 2)
            local rightHashes = innerW - leftHashes - 1
            self.monitor.write("|" .. string.rep("#", leftHashes) .. "?" .. string.rep("#", rightHashes) .. "|")
        else
            self.monitor.write("|" .. string.rep("#", innerW) .. "|")
        end
    end

    self.monitor.setCursorPos(x, y + self.cardH - 1)
    self.monitor.write("+" .. string.rep("-", innerW) .. "+")

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
    self:refreshMonitorGeometry()

    self.monitor.clear()

    self:centerText(2, "BLACKJACK CASINO")

    self.monitor.setCursorPos(3, self.dealerLabelY)
    local dealerCodes = {}
    for i, card in ipairs(dealerHand) do
        if i > 3 then break end
        if i == 2 and not revealDealer then
            table.insert(dealerCodes, "??")
        else
            table.insert(dealerCodes, card.rank .. card.suit)
        end
    end
    self.monitor.write("Dealer: " .. table.concat(dealerCodes, " "))

    local dealerStartX, dealerSpacing, dealerShown = self:getCardRowLayout(#dealerHand)
    for i, card in ipairs(dealerHand) do
        if i > dealerShown then break end
        local cx = self:cardX(i, dealerStartX, dealerSpacing)
        if i == 2 and not revealDealer then
            self:drawHiddenCard(cx, self.dealerY)
        else
            self:drawCard(cx, self.dealerY, card)
        end
    end

    self.monitor.setCursorPos(3, self.playerLabelY)
    local playerCodes = {}
    for i, card in ipairs(playerHand) do
        if i > 3 then break end
        table.insert(playerCodes, card.rank .. card.suit)
    end
    self.monitor.write("Player: " .. table.concat(playerCodes, " "))

    local playerStartX, playerSpacing, playerShown = self:getCardRowLayout(#playerHand)
    for i, card in ipairs(playerHand) do
        if i > playerShown then break end
        self:drawCard(self:cardX(i, playerStartX, playerSpacing), self.playerY, card)
    end

    self.monitor.setCursorPos(3, self.infoTotalY)
    self.monitor.write("Total: " .. playerTotal)

    self.monitor.setCursorPos(3, self.infoMoneyY)
    self.monitor.write("Iron: " .. money .. "  Bet: " .. bet)

    self.monitor.setCursorPos(3, self.infoHouseY)
    self.monitor.write("House: " .. houseMoney)

    self:drawButton(self.cashBox.x, self.cashBox.y, self.cashBox.w, "Cashout")
    self:drawButton(self.hitBox.x, self.hitBox.y, self.hitBox.w, "Hit")
    self:drawButton(self.standBox.x, self.standBox.y, self.standBox.w, "Stand")
    self:drawButton(self.doubleBox.x, self.doubleBox.y, self.doubleBox.w, "Double")
    self:drawButton(self.quitBox.x, self.quitBox.y, self.quitBox.w, "Quit")
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

        if inBox(x, y, self.cashBox.x, self.cashBox.y, self.cashBox.w, self.cashBox.h) then
            self:showMessage("Cashout: take iron from player chest.", 3)
            return false
        end

        if inBox(x, y, self.hitBox.x, self.hitBox.y, self.hitBox.w, self.hitBox.h) then
            table.insert(player, table.remove(deck))
            canDouble = false
        elseif inBox(x, y, self.standBox.x, self.standBox.y, self.standBox.w, self.standBox.h) then
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
        elseif inBox(x, y, self.doubleBox.x, self.doubleBox.y, self.doubleBox.w, self.doubleBox.h) then
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
        elseif inBox(x, y, self.quitBox.x, self.quitBox.y, self.quitBox.w, self.quitBox.h) then
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
    cardScale = 0.5,
    layout = {
        -- Standard casino machine format:
        -- 2x3 Monitor
        -- Advanced Computer | Hopper
        -- House Chest | Player Chest
        monitor = "top",
        hopper = "right",
        houseChest = "sophisticatedstorage:limited_barrel_x",
        playerChest = "sophisticatedstorage:chest_x",
        requireHopper = true
    }
})

game:run()

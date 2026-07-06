local card_vis = require("src.rndr.card_vis")
local action_deck_logic = require("src.sys.action_deck_logic")
local burn_palette = require("data.burn_palette")

local action_deck_viewer = {}

local BACKDROP_COLOR = { 0, 0, 0, 0.82 }
local PANEL_COLOR = { 0, 0, 0, 0.94 }
local PANEL_BORDER_COLOR = { 1, 1, 1, 1 }
local THUMB_BACKING_COLOR = { 0.035, 0.032, 0.028, 1 }
local BURN_TEXT_COLOR = { 0, 0, 0, 1 }
local TEXT_COLOR = { 1, 1, 1, 1 }
local PANEL_MARGIN_X = 32
local PANEL_MARGIN_Y = 62
local PANEL_W = 560
local PANEL_PAD = 18
local PANEL_TITLE_H = 30
local THUMB_W = 76
local THUMB_H = 102
local THUMB_GAP = 12
local BURN_LABEL_SIZE = 24
local SCROLL_STEP = 96
local DRAWN_CARD_DIM_ALPHA = 0.34
local FATIGUE_BADGE_SIZE = 34

local open_agent = nil
local deck_scroll = 0
local discard_scroll = 0

local function pointInRect(x, y, rect)
    return x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

local function hexToColor(hex, alpha)
    if type(hex) ~= "string" or #hex < 6 then
        return { 1, 1, 1, alpha or 1 }
    end

    return {
        tonumber(hex:sub(1, 2), 16) / 255,
        tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255,
        alpha or 1,
    }
end

local function getBurnColor(burn_rating)
    return hexToColor(burn_palette["burn" .. tostring(burn_rating)], 1)
end

local function getLayout()
    local screen_w = love.graphics.getWidth()
    local screen_h = love.graphics.getHeight()
    local panel_h = screen_h - PANEL_MARGIN_Y * 2

    return {
        deck = {
            x = PANEL_MARGIN_X,
            y = PANEL_MARGIN_Y,
            w = PANEL_W,
            h = panel_h,
        },
        discard = {
            x = screen_w - PANEL_MARGIN_X - PANEL_W,
            y = PANEL_MARGIN_Y,
            w = PANEL_W,
            h = panel_h,
        },
        preview = {
            x = PANEL_MARGIN_X + PANEL_W,
            y = PANEL_MARGIN_Y,
            w = screen_w - (PANEL_MARGIN_X + PANEL_W) * 2,
            h = panel_h,
        },
    }
end

local function getGrid(panel, cards)
    local content_x = panel.x + PANEL_PAD
    local content_y = panel.y + PANEL_PAD + PANEL_TITLE_H
    local content_w = panel.w - PANEL_PAD * 2
    local content_h = panel.h - PANEL_PAD * 2 - PANEL_TITLE_H
    local cols = math.max(1, math.floor((content_w + THUMB_GAP) / (THUMB_W + THUMB_GAP)))
    local rows = math.ceil(#cards / cols)
    local total_h = rows * THUMB_H + math.max(0, rows - 1) * THUMB_GAP

    return {
        x = content_x,
        y = content_y,
        w = content_w,
        h = content_h,
        cols = cols,
        total_h = total_h,
        max_scroll = math.max(0, total_h - content_h),
    }
end

local function clampScroll(scroll, grid)
    return math.max(0, math.min(scroll, grid.max_scroll))
end

local function getDeckCards(agent)
    local cards = {}

    for _, card in ipairs(agent and agent.action_draw_pile or {}) do
        cards[#cards + 1] = {
            card = card,
            dimmed = false,
            fatigued = action_deck_logic.isCardFatigued(agent, card),
        }
    end

    for _, card in ipairs(agent and agent.action_hand or {}) do
        cards[#cards + 1] = {
            card = card,
            dimmed = true,
            fatigued = action_deck_logic.isCardFatigued(agent, card),
        }
    end

    for _, card in ipairs(agent and agent.action_discard_pile or {}) do
        cards[#cards + 1] = {
            card = card,
            dimmed = true,
            fatigued = action_deck_logic.isCardFatigued(agent, card),
        }
    end

    table.sort(cards, function(a, b)
        return (a.card.action_slot or 0) < (b.card.action_slot or 0)
    end)

    return cards
end

local function getItemCard(item)
    return item and (item.card or item) or nil
end

local function isItemDimmed(item)
    return item and item.dimmed or false
end

local function isItemFatigued(item)
    return item and item.fatigued or false
end

local function getCardAt(cards, grid, scroll, mouse_x, mouse_y)
    if mouse_x < grid.x or mouse_x > grid.x + grid.w or mouse_y < grid.y or mouse_y > grid.y + grid.h then
        return nil
    end

    for index, card in ipairs(cards) do
        local col = (index - 1) % grid.cols
        local row = math.floor((index - 1) / grid.cols)
        local x = grid.x + col * (THUMB_W + THUMB_GAP)
        local y = grid.y + row * (THUMB_H + THUMB_GAP) - scroll

        if mouse_x >= x and mouse_x <= x + THUMB_W and mouse_y >= y and mouse_y <= y + THUMB_H then
            return getItemCard(card)
        end
    end

    return nil
end

local function drawThumb(item, x, y, show_burn)
    local card = getItemCard(item)

    love.graphics.setColor(THUMB_BACKING_COLOR)
    love.graphics.rectangle("fill", x, y, THUMB_W, THUMB_H)
    card_vis.drawCardPortrait(card, x, y, THUMB_W, THUMB_H)

    if isItemDimmed(item) or isItemFatigued(item) then
        love.graphics.setColor(0, 0, 0, 1 - DRAWN_CARD_DIM_ALPHA)
        love.graphics.rectangle("fill", x, y, THUMB_W, THUMB_H)
    end

    if isItemFatigued(item) then
        local badge_x = x + (THUMB_W - FATIGUE_BADGE_SIZE) / 2
        local badge_y = y + (THUMB_H - FATIGUE_BADGE_SIZE) / 2

        love.graphics.setColor(getBurnColor(card.burn_rating))
        love.graphics.rectangle("fill", badge_x, badge_y, FATIGUE_BADGE_SIZE, FATIGUE_BADGE_SIZE)
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", badge_x, badge_y, FATIGUE_BADGE_SIZE, FATIGUE_BADGE_SIZE)
        love.graphics.line(
            badge_x + 8,
            badge_y + 8,
            badge_x + FATIGUE_BADGE_SIZE - 8,
            badge_y + FATIGUE_BADGE_SIZE - 8
        )
        love.graphics.line(
            badge_x + FATIGUE_BADGE_SIZE - 8,
            badge_y + 8,
            badge_x + 8,
            badge_y + FATIGUE_BADGE_SIZE - 8
        )
        love.graphics.setLineWidth(1)
    end

    love.graphics.setColor(PANEL_BORDER_COLOR)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, THUMB_W, THUMB_H)
    love.graphics.setLineWidth(1)

    if show_burn and card.burn_rating then
        local font = love.graphics.getFont()
        local text_y = y + (BURN_LABEL_SIZE - font:getHeight()) / 2 - 1

        love.graphics.setColor(getBurnColor(card.burn_rating))
        love.graphics.rectangle("fill", x, y, BURN_LABEL_SIZE, BURN_LABEL_SIZE)
        love.graphics.setColor(BURN_TEXT_COLOR)
        love.graphics.printf(tostring(card.burn_rating), x, text_y, BURN_LABEL_SIZE, "center")
    end
end

local function drawPanel(panel, title, cards, scroll, show_burn)
    local grid = getGrid(panel, cards)
    scroll = clampScroll(scroll, grid)

    love.graphics.setColor(PANEL_COLOR)
    love.graphics.rectangle("fill", panel.x, panel.y, panel.w, panel.h)
    love.graphics.setColor(PANEL_BORDER_COLOR)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", panel.x, panel.y, panel.w, panel.h)
    love.graphics.setLineWidth(1)

    love.graphics.setColor(TEXT_COLOR)
    love.graphics.printf(title, panel.x + PANEL_PAD, panel.y + PANEL_PAD, panel.w - PANEL_PAD * 2, "center")

    love.graphics.setScissor(grid.x, grid.y, grid.w, grid.h)

    for index, card in ipairs(cards) do
        local col = (index - 1) % grid.cols
        local row = math.floor((index - 1) / grid.cols)
        local x = grid.x + col * (THUMB_W + THUMB_GAP)
        local y = grid.y + row * (THUMB_H + THUMB_GAP) - scroll

        if y + THUMB_H >= grid.y and y <= grid.y + grid.h then
            drawThumb(card, x, y, show_burn)
        end
    end

    love.graphics.setScissor()

    return scroll, grid
end

local function drawPreview(card, preview)
    if not card then
        return
    end

    local card_w = card_vis.getCardWidth()
    local card_h = card_vis.getCardHeight(card)
    local scale = math.min(1.25, preview.w / card_w, preview.h / card_h)
    local x = preview.x + (preview.w - card_w * scale) / 2
    local y = preview.y + (preview.h - card_h * scale) / 2

    card_vis.drawScaledCard(card, x, y, scale)
end

function action_deck_viewer.open(agent)
    open_agent = agent
    deck_scroll = 0
    discard_scroll = 0
end

function action_deck_viewer.close()
    if not open_agent then
        return false
    end

    open_agent = nil
    deck_scroll = 0
    discard_scroll = 0

    return true
end

function action_deck_viewer.isOpen()
    return open_agent ~= nil
end

function action_deck_viewer.draw()
    if not open_agent then
        return
    end

    local layout = getLayout()
    local deck_cards = getDeckCards(open_agent)
    local discard_cards = open_agent.action_discard_pile or {}
    local mouse_x, mouse_y = love.mouse.getPosition()

    love.graphics.setColor(BACKDROP_COLOR)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())

    deck_scroll = drawPanel(layout.deck, "DECK", deck_cards, deck_scroll, true)
    discard_scroll = drawPanel(layout.discard, "DISCARD", discard_cards, discard_scroll, false)

    local deck_grid = getGrid(layout.deck, deck_cards)
    local discard_grid = getGrid(layout.discard, discard_cards)
    local hovered_card = getCardAt(deck_cards, deck_grid, deck_scroll, mouse_x, mouse_y)
        or getCardAt(discard_cards, discard_grid, discard_scroll, mouse_x, mouse_y)

    drawPreview(hovered_card, layout.preview)
    love.graphics.setColor(1, 1, 1, 1)
end

function action_deck_viewer.mousepressed(x, y, button)
    if not open_agent then
        return false
    end

    if button == 2 then
        action_deck_viewer.close()
        return true
    end

    if button ~= 1 then
        return true
    end

    local layout = getLayout()

    if not pointInRect(x, y, layout.deck) and not pointInRect(x, y, layout.discard) then
        action_deck_viewer.close()
    end

    return true
end

function action_deck_viewer.wheelmoved(_, y)
    if not open_agent then
        return false
    end

    local layout = getLayout()
    local mouse_x, mouse_y = love.mouse.getPosition()

    if pointInRect(mouse_x, mouse_y, layout.deck) then
        local grid = getGrid(layout.deck, getDeckCards(open_agent))
        deck_scroll = clampScroll(deck_scroll - y * SCROLL_STEP, grid)
    elseif pointInRect(mouse_x, mouse_y, layout.discard) then
        local grid = getGrid(layout.discard, open_agent.action_discard_pile or {})
        discard_scroll = clampScroll(discard_scroll - y * SCROLL_STEP, grid)
    end

    return true
end

return action_deck_viewer

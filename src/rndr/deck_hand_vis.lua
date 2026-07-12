local card_vis = require("src.rndr.card_vis")
local agent_logic = require("src.sys.agent_logic")
local card_play = require("src.sys.card_play")
local action_vis = require("src.rndr.action_vis")
local sfx_logic = require("src.sys.sfx_logic")
local equip_logic = require("src.sys.equip_logic")

local deck_hand_vis = {}

local HAND_CARD_SPACING = 180
local HAND_EDGE_MARGIN = 48
local CARD_BACKING_PADDING = 8
local HOVER_PREVIEW_HAND_GAP = 18
local HOVER_PREVIEW_TOP_MARGIN = 18
local DRAG_IMAGE_W = 60
local DRAG_OUTLINE_W = 2
local LEX_PANEL_X = 32
local LEX_PANEL_GAP_FROM_HAND = 18
local LEX_PANEL_W = 390
local LEX_PANEL_PAD = 12
local LEX_PANEL_HEADER_H = 24
local LEX_PANEL_ROW_GAP = 10
local LEX_PANEL_THUMB_W = 57
local LEX_PANEL_THUMB_H = 77
local LEX_PANEL_THUMB_GAP = 8
local LEX_PANEL_COLOR = { 0, 0, 0, 0.94 }
local LEX_PANEL_BORDER_COLOR = { 1, 1, 1, 1 }
local LEX_HEADER_COLOR = { 0.1373, 0.7922, 0.9686, 1 }

local player_hand_scroll = 0
local hovered_card_key
local dragging_hand_index = nil
local lex_panel_index = 1

local function getSelectedHand()
    local agent = agent_logic.getSelectedAgent()

    return agent and agent.action_hand or nil
end

local function getPlayerHandLayout()
    local player_hand = getSelectedHand()
    local card_count = player_hand and #player_hand or 0

    if card_count == 0 then
        return nil
    end

    local screen_width = love.graphics.getWidth()
    local screen_height = love.graphics.getHeight()
    local available_width = screen_width - HAND_EDGE_MARGIN * 2
    local card_width = card_vis.getCardWidth()
    local hand_face_width = card_width + HAND_CARD_SPACING * (card_count - 1)
    local hand_outer_width = hand_face_width + CARD_BACKING_PADDING * 2
    local max_scroll = math.max(0, hand_outer_width - available_width)
    local scroll = math.max(0, math.min(player_hand_scroll, max_scroll))
    local start_x = (screen_width - hand_outer_width) / 2 + CARD_BACKING_PADDING

    if max_scroll > 0 then
        player_hand_scroll = scroll
        start_x = HAND_EDGE_MARGIN + CARD_BACKING_PADDING - scroll
    elseif player_hand_scroll ~= 0 then
        player_hand_scroll = 0
    end

    return {
        cards = player_hand,
        count = card_count,
        start_x = start_x,
        spacing = HAND_CARD_SPACING,
        y = screen_height - card_vis.getVisibleHandCardHeight(),
    }
end

local function getLexurgyPanelItem()
    local agent = agent_logic.getSelectedAgent()
    local items = equip_logic.getEquippedLexurgyItems(agent)

    if #items == 0 then
        lex_panel_index = 1
        return nil, items
    end

    lex_panel_index = math.max(1, math.min(lex_panel_index, #items))

    return items[lex_panel_index], items
end

local function getLexurgyPanelLayout()
    local hand_layout = getPlayerHandLayout()
    local hand_y = hand_layout and hand_layout.y or (love.graphics.getHeight() - card_vis.getVisibleHandCardHeight())
    local row_h = LEX_PANEL_THUMB_H
    local panel_h = LEX_PANEL_PAD * 2 + LEX_PANEL_HEADER_H + row_h * 2 + LEX_PANEL_ROW_GAP

    return {
        x = LEX_PANEL_X,
        y = hand_y - LEX_PANEL_GAP_FROM_HAND - panel_h,
        w = LEX_PANEL_W,
        h = panel_h,
        deck_row_y = hand_y - LEX_PANEL_GAP_FROM_HAND - panel_h + LEX_PANEL_PAD + LEX_PANEL_HEADER_H,
        discard_row_y = hand_y - LEX_PANEL_GAP_FROM_HAND - panel_h + LEX_PANEL_PAD + LEX_PANEL_HEADER_H + row_h + LEX_PANEL_ROW_GAP,
    }
end

local function pointInRect(x, y, rect)
    return rect and x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

local function getLexurgyRowMetrics(cards, layout)
    local content_x = layout.x + LEX_PANEL_PAD
    local content_w = layout.w - LEX_PANEL_PAD * 2
    local max_cols = math.max(1, math.floor((content_w + LEX_PANEL_THUMB_GAP) / (LEX_PANEL_THUMB_W + LEX_PANEL_THUMB_GAP)))
    local visible_count = math.min(#cards, max_cols)
    local row_w = visible_count > 0
        and visible_count * LEX_PANEL_THUMB_W + (visible_count - 1) * LEX_PANEL_THUMB_GAP
        or 0

    return {
        content_x = content_x,
        content_w = content_w,
        max_cols = max_cols,
        visible_count = visible_count,
        start_x = content_x + (content_w - row_w) / 2,
    }
end

local function getLexurgyCardAt(cards, layout, row_y, mouse_x, mouse_y)
    local metrics = getLexurgyRowMetrics(cards, layout)
    local x = metrics.content_x
    local y = row_y

    if mouse_x < x or mouse_x > x + metrics.content_w or mouse_y < y or mouse_y > y + LEX_PANEL_THUMB_H then
        return nil
    end

    for index = 1, metrics.visible_count do
        local thumb_x = metrics.start_x + (index - 1) * (LEX_PANEL_THUMB_W + LEX_PANEL_THUMB_GAP)

        if mouse_x >= thumb_x and mouse_x <= thumb_x + LEX_PANEL_THUMB_W then
            return cards[index]
        end
    end

    return nil
end

local function getHoveredLexurgyCard()
    local item = getLexurgyPanelItem()

    if not item then
        return nil
    end

    local layout = getLexurgyPanelLayout()
    local mouse_x, mouse_y = love.mouse.getPosition()
    local deck_cards = equip_logic.getLexDrawCards(item)
    local discard_cards = equip_logic.getLexDiscardCards(item)

    return getLexurgyCardAt(deck_cards, layout, layout.deck_row_y, mouse_x, mouse_y)
        or getLexurgyCardAt(discard_cards, layout, layout.discard_row_y, mouse_x, mouse_y)
end

local function getHoveredHandCard(layout)
    if not layout then
        return nil
    end

    local mouse_x, mouse_y = love.mouse.getPosition()
    local card_width = card_vis.getCardWidth()

    for index = layout.count, 1, -1 do
        local card = layout.cards[index]
        local x = layout.start_x + (index - 1) * layout.spacing
        local card_height = card_vis.getCardHeight(card)

        if mouse_x >= x and mouse_x <= x + card_width and mouse_y >= layout.y and mouse_y <= layout.y + card_height then
            return card, index
        end
    end

    return nil
end

function deck_hand_vis.load()
    player_hand_scroll = 0
    hovered_card_key = nil
    dragging_hand_index = nil
    lex_panel_index = 1
end

function deck_hand_vis.reload()
    deck_hand_vis.load()
end

function deck_hand_vis.getPlayerHand()
    return getSelectedHand() or {}
end

function deck_hand_vis.drawPlayerHand()
    local layout = getPlayerHandLayout()
    local agent = agent_logic.getSelectedAgent()

    if not layout then
        return
    end

    for index, card in ipairs(layout.cards) do
        card_vis.loadCardAssets(card)

        if not card_play.isDragging() or index ~= dragging_hand_index then
            card_vis.drawCard(card, layout.start_x + (index - 1) * layout.spacing, layout.y, { unit = agent })
        end
    end
end

local function drawLexurgyCardRow(cards, layout, row_y, dimmed)
    local metrics = getLexurgyRowMetrics(cards, layout)

    love.graphics.setScissor(metrics.content_x, row_y, metrics.content_w, LEX_PANEL_THUMB_H)

    for index = 1, metrics.visible_count do
        local thumb_x = metrics.start_x + (index - 1) * (LEX_PANEL_THUMB_W + LEX_PANEL_THUMB_GAP)

        love.graphics.setColor(0.035, 0.032, 0.028, 1)
        love.graphics.rectangle("fill", thumb_x, row_y, LEX_PANEL_THUMB_W, LEX_PANEL_THUMB_H)
        card_vis.drawCardPortrait(cards[index], thumb_x, row_y, LEX_PANEL_THUMB_W, LEX_PANEL_THUMB_H)
        if dimmed then
            love.graphics.setColor(0, 0, 0, 0.42)
            love.graphics.rectangle("fill", thumb_x, row_y, LEX_PANEL_THUMB_W, LEX_PANEL_THUMB_H)
        end
        love.graphics.setColor(LEX_PANEL_BORDER_COLOR)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", thumb_x, row_y, LEX_PANEL_THUMB_W, LEX_PANEL_THUMB_H)
        love.graphics.setLineWidth(1)
    end

    love.graphics.setScissor()
end

function deck_hand_vis.drawLexurgyPanel()
    local item = getLexurgyPanelItem()

    if not item then
        return
    end

    local layout = getLexurgyPanelLayout()

    love.graphics.setColor(LEX_PANEL_COLOR)
    love.graphics.rectangle("fill", layout.x, layout.y, layout.w, layout.h)
    love.graphics.setColor(LEX_PANEL_BORDER_COLOR)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", layout.x, layout.y, layout.w, layout.h)
    love.graphics.setLineWidth(1)

    love.graphics.setColor(LEX_HEADER_COLOR)
    love.graphics.printf(item.name or item.id or "Lexurgy", layout.x + LEX_PANEL_PAD, layout.y + LEX_PANEL_PAD - 7, layout.w - LEX_PANEL_PAD * 2, "center")

    drawLexurgyCardRow(equip_logic.getLexDrawCards(item), layout, layout.deck_row_y, false)
    drawLexurgyCardRow(equip_logic.getLexDiscardCards(item), layout, layout.discard_row_y, true)

    love.graphics.setColor(1, 1, 1, 1)
end

function deck_hand_vis.drawFocusedCard()
    if card_play.isDragging() then
        return
    end

    local layout = getPlayerHandLayout()
    local hovered_card = getHoveredLexurgyCard() or getHoveredHandCard(layout)
    local hovered_key = hovered_card and (hovered_card.id or hovered_card.name) or nil

    if hovered_key ~= hovered_card_key then
        hovered_card_key = hovered_key

        if hovered_key then
            sfx_logic.playNamed("cardhover")
        end
    end

    if not hovered_card then
        return
    end

    local screen_width = love.graphics.getWidth()
    local card_width = card_vis.getCardWidth()
    local card_height = card_vis.getCardHeight(hovered_card)
    local preview_outer_height = card_height + CARD_BACKING_PADDING * 2
    local hand_y = layout and layout.y or (love.graphics.getHeight() - card_vis.getVisibleHandCardHeight())
    local available_height = hand_y - HOVER_PREVIEW_HAND_GAP - HOVER_PREVIEW_TOP_MARGIN
    local scale = 1

    if available_height > 0 then
        scale = math.min(1, available_height / preview_outer_height)
    end

    local preview_outer_top = hand_y - HOVER_PREVIEW_HAND_GAP - preview_outer_height * scale
    preview_outer_top = math.max(HOVER_PREVIEW_TOP_MARGIN, preview_outer_top)

    card_vis.drawScaledCard(
        hovered_card,
        (screen_width - card_width * scale) / 2,
        preview_outer_top + CARD_BACKING_PADDING * scale,
        scale,
        { unit = agent_logic.getSelectedAgent() }
    )
end

function deck_hand_vis.draw()
    if not agent_logic.getSelectedAgent() then
        hovered_card_key = nil
        return
    end

    deck_hand_vis.drawLexurgyPanel()
    deck_hand_vis.drawPlayerHand()
    deck_hand_vis.drawFocusedCard()
    deck_hand_vis.drawDraggedCard()
end

function deck_hand_vis.wheelmoved(_, y)
    local item, items = getLexurgyPanelItem()

    if item then
        local mouse_x, mouse_y = love.mouse.getPosition()

        if pointInRect(mouse_x, mouse_y, getLexurgyPanelLayout()) then
            if #items > 1 then
                if y > 0 then
                    lex_panel_index = lex_panel_index - 1
                elseif y < 0 then
                    lex_panel_index = lex_panel_index + 1
                end

                if lex_panel_index < 1 then
                    lex_panel_index = #items
                elseif lex_panel_index > #items then
                    lex_panel_index = 1
                end
            end

            return
        end
    end

    player_hand_scroll = player_hand_scroll - y * 140
end

function deck_hand_vis.mousepressed(room, button)
    if button ~= 1 or card_play.isDragging() then
        return false
    end

    local layout = getPlayerHandLayout()
    local card, index = getHoveredHandCard(layout)
    local agent = agent_logic.getSelectedAgent()
    local selected_tile = agent_logic.getSelectedTile()

    if not card or not agent or not selected_tile then
        return false
    end

    if card_play.startDrag(agent, selected_tile, card, index) then
        dragging_hand_index = index
        return true
    end

    return false
end

function deck_hand_vis.mousereleased(room, x, y, button, camera_x, camera_y)
    if button ~= 1 or not card_play.isDragging() then
        return false
    end

    local played, event = card_play.release(room, x, y, camera_x, camera_y)

    dragging_hand_index = nil

    if played and event then
        action_vis.start(event)
    end

    return played
end

function deck_hand_vis.drawDraggedCard()
    local card = card_play.getDraggedCard()

    if not card then
        return
    end

    local mouse_x, mouse_y = love.mouse.getPosition()
    local image_x = mouse_x - DRAG_IMAGE_W / 2
    local image_y = mouse_y - DRAG_IMAGE_W / 2

    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.setLineWidth(DRAG_OUTLINE_W)
    love.graphics.rectangle("line", image_x, image_y, DRAG_IMAGE_W, DRAG_IMAGE_W)
    love.graphics.setLineWidth(1)
    card_vis.drawCardImageOnly(card, mouse_x, mouse_y, DRAG_IMAGE_W)
end

return deck_hand_vis

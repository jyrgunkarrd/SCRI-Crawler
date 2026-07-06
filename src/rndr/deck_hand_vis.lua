local card_vis = require("src.rndr.card_vis")
local agent_logic = require("src.sys.agent_logic")
local card_play = require("src.sys.card_play")
local action_vis = require("src.rndr.action_vis")
local sfx_logic = require("src.sys.sfx_logic")

local deck_hand_vis = {}

local HAND_CARD_SPACING = 180
local HAND_EDGE_MARGIN = 48
local CARD_BACKING_PADDING = 8
local HOVER_PREVIEW_HAND_GAP = 18
local HOVER_PREVIEW_TOP_MARGIN = 18
local DRAG_IMAGE_W = 60
local DRAG_OUTLINE_W = 2

local player_hand_scroll = 0
local hovered_card_key
local dragging_hand_index = nil

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
end

function deck_hand_vis.reload()
    deck_hand_vis.load()
end

function deck_hand_vis.getPlayerHand()
    return getSelectedHand() or {}
end

function deck_hand_vis.drawPlayerHand()
    local layout = getPlayerHandLayout()

    if not layout then
        return
    end

    for index, card in ipairs(layout.cards) do
        card_vis.loadCardAssets(card)

        if not card_play.isDragging() or index ~= dragging_hand_index then
            card_vis.drawCard(card, layout.start_x + (index - 1) * layout.spacing, layout.y)
        end
    end
end

function deck_hand_vis.drawFocusedCard()
    if card_play.isDragging() then
        return
    end

    local layout = getPlayerHandLayout()
    local hovered_card = getHoveredHandCard(layout)
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
    local available_height = layout.y - HOVER_PREVIEW_HAND_GAP - HOVER_PREVIEW_TOP_MARGIN
    local scale = 1

    if available_height > 0 then
        scale = math.min(1, available_height / preview_outer_height)
    end

    local preview_outer_top = layout.y - HOVER_PREVIEW_HAND_GAP - preview_outer_height * scale
    preview_outer_top = math.max(HOVER_PREVIEW_TOP_MARGIN, preview_outer_top)

    card_vis.drawScaledCard(
        hovered_card,
        (screen_width - card_width * scale) / 2,
        preview_outer_top + CARD_BACKING_PADDING * scale,
        scale
    )
end

function deck_hand_vis.draw()
    if not agent_logic.getSelectedAgent() then
        hovered_card_key = nil
        return
    end

    deck_hand_vis.drawPlayerHand()
    deck_hand_vis.drawFocusedCard()
    deck_hand_vis.drawDraggedCard()
end

function deck_hand_vis.wheelmoved(_, y)
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

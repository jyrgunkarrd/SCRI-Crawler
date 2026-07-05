local card_vis = require("src.rndr.card_vis")
local sfx_logic = require("src.sys.sfx_logic")

local deck_hand_vis = {}

local DEV_HAND_PATH = "data.dev_hand"
local CARD_INDEX_PATH = "data.cards.index"
local HAND_CARD_SPACING = 180
local HAND_EDGE_MARGIN = 48
local CARD_BACKING_PADDING = 8
local HOVER_PREVIEW_HAND_GAP = 18
local HOVER_PREVIEW_TOP_MARGIN = 18

local card_index
local player_hand = {}
local player_hand_scroll = 0
local hovered_card_key

local function addCardById(card_id, quantity)
    local card = card_index and card_index.byId[card_id] or nil

    if not card then
        print("Unknown card id in dev hand: " .. tostring(card_id))
        return
    end

    for _ = 1, math.max(0, math.floor(quantity or 0)) do
        player_hand[#player_hand + 1] = card
        card_vis.loadCardAssets(card)
    end
end

local function buildDevHand()
    player_hand = {}
    player_hand_scroll = 0
    package.loaded[DEV_HAND_PATH] = nil

    local ok, dev_hand = pcall(require, DEV_HAND_PATH)

    if not ok then
        print("Unable to load dev hand: " .. tostring(dev_hand))
        return
    end

    for _, entry in ipairs(dev_hand.hand or {}) do
        for card_id, quantity in pairs(entry) do
            addCardById(card_id, quantity)
        end
    end
end

local function getPlayerHandLayout()
    local card_count = #player_hand

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
    package.loaded[CARD_INDEX_PATH] = nil
    card_index = require(CARD_INDEX_PATH)
    buildDevHand()
end

function deck_hand_vis.reload()
    deck_hand_vis.load()
end

function deck_hand_vis.getPlayerHand()
    return player_hand
end

function deck_hand_vis.drawPlayerHand()
    local layout = getPlayerHandLayout()

    if not layout then
        return
    end

    for index, card in ipairs(layout.cards) do
        card_vis.drawCard(card, layout.start_x + (index - 1) * layout.spacing, layout.y)
    end
end

function deck_hand_vis.drawFocusedCard()
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
    deck_hand_vis.drawPlayerHand()
    deck_hand_vis.drawFocusedCard()
end

function deck_hand_vis.wheelmoved(_, y)
    player_hand_scroll = player_hand_scroll - y * 140
end

return deck_hand_vis

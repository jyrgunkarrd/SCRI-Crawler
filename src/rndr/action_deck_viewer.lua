local card_vis = require("src.rndr.card_vis")
local action_deck_logic = require("src.sys.action_deck_logic")
local XP_levels = require("src.sys.XP_levels")
local sfx_logic = require("src.sys.sfx_logic")
local burn_palette = require("data.burn_palette")
local card_index = require("data.cards.index")
local skill_tree_defs = require("data.skill_trees")

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
local HAND_BADGE_SIZE = 28
local HAND_BADGE_FONT_SIZE = 18
local HAND_BADGE_GLYPH = "\226\156\139"
local TREE_TAB_H = 32
local TREE_TAB_GAP = 6
local TREE_CONTENT_TOP_PAD = 26
local TREE_CONTENT_BOTTOM_PAD = 34
local TREE_NODE_LABEL_H = 22
local TREE_NODE_GAP_Y = 42
local TREE_BRIDGE_GAP_Y = 56
local TREE_CAPSTONE_GAP_Y = 62
local TREE_LINE_COLOR = { 1, 1, 1, 0.72 }
local TREE_LOCKED_COLOR = { 0.45, 0.45, 0.45, 1 }
local TREE_LOCKED_DIM_COLOR = { 0, 0, 0, 0.58 }
local TREE_POINT_COLOR = { 1, 0.8275, 0.349, 1 }
local TREE_POINT_TEXT_COLOR = { 0, 0, 0, 1 }
local TREE_POINT_BOX_SIZE = 32
local TREE_POINT_BOX_GAP = 4
local TREE_PLUS_SIZE = 26
local TREE_PLUS_GAP = 6
local SELECTED_CARD_COLOR = { 1, 0.8275, 0.349, 1 }

local open_agent = nil
local open_mode = "deck"
local active_tree_tab = 1
local deck_scroll = 0
local discard_scroll = 0
local tree_scroll = 0
local pool_scroll = 0
local selected_swap = nil
local hand_badge_font = nil

local skill_tree_lookup = {}

for _, tree in ipairs(skill_tree_defs or {}) do
    skill_tree_lookup[tree.id] = tree
end

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

local function getTreePanels(layout)
    local gap = PANEL_PAD
    local panel_h = (layout.discard.h - gap) / 2

    return {
        {
            x = layout.discard.x,
            y = layout.discard.y,
            w = layout.discard.w,
            h = panel_h,
        },
        {
            x = layout.discard.x,
            y = layout.discard.y + panel_h + gap,
            w = layout.discard.w,
            h = panel_h,
        },
    }
end

local function getTreeTabs(agent)
    local assigned = agent and agent.skill_trees
    local ids = assigned and { assigned.tab1ID, assigned.tab2ID, assigned.tab3ID } or {}
    local tabs = {}

    for index, id in ipairs(ids) do
        local tree = skill_tree_lookup[id]

        if tree then
            tabs[#tabs + 1] = {
                index = index,
                id = id,
                name = tree.name or id,
                tree = tree,
            }
        end
    end

    return tabs
end

local function getActiveTree(agent)
    local tabs = getTreeTabs(agent)

    if #tabs == 0 then
        return nil, tabs
    end

    active_tree_tab = math.max(1, math.min(active_tree_tab, #tabs))

    return tabs[active_tree_tab].tree, tabs
end

local function getTreeTabRects(panel, tabs)
    local rects = {}

    if #tabs == 0 then
        return rects
    end

    local total_gap = TREE_TAB_GAP * (#tabs - 1)
    local tab_w = (panel.w - PANEL_PAD * 2 - total_gap) / #tabs
    local tab_y = panel.y + PANEL_PAD

    for index, tab in ipairs(tabs) do
        rects[#rects + 1] = {
            x = panel.x + PANEL_PAD + (index - 1) * (tab_w + TREE_TAB_GAP),
            y = tab_y,
            w = tab_w,
            h = TREE_TAB_H,
            index = index,
            tab = tab,
        }
    end

    return rects
end

local function cloneNodeCard(node)
    local card = card_index.byId[node and node.cardID]

    if not card then
        return nil
    end

    local clone = {}

    for key, value in pairs(card) do
        clone[key] = value
    end

    return clone
end

local function cloneBaseCard(card)
    local source = card_index.byId[card and (card.base_id or card.id)] or card

    if not source then
        return nil
    end

    local clone = {}

    for key, value in pairs(source) do
        clone[key] = value
    end

    clone.base_id = source.id

    if card then
        if card.art_id ~= nil then
            clone.art_id = card.art_id
        end

        if card.art ~= nil then
            clone.art = card.art
        end

        if card.image_dir ~= nil then
            clone.image_dir = card.image_dir
        end
    end

    return clone
end

local function cloneCardForDeckSlot(card, slot_card)
    local clone = cloneBaseCard(card)

    if not clone or not slot_card then
        return nil
    end

    clone.base_id = clone.id
    clone.action_deck_id = slot_card.action_deck_id
    clone.action_slot = slot_card.action_slot
    clone.burn_rating = slot_card.burn_rating

    return clone
end

local function getSkillCardPool(agent)
    if not agent then
        return {}
    end

    agent.skill_card_pool = agent.skill_card_pool or {}

    return agent.skill_card_pool
end

local function addSkillCardToPool(agent, card)
    local clone = cloneBaseCard(card)

    if clone then
        local pool = getSkillCardPool(agent)
        pool[#pool + 1] = clone
    end
end

local function getNodeValue(agent, node_key)
    agent.skill_node_values = agent.skill_node_values or {}

    return math.max(0, math.floor(tonumber(agent.skill_node_values[node_key]) or 0))
end

local function setNodeValue(agent, node_key, value)
    agent.skill_node_values = agent.skill_node_values or {}
    agent.skill_node_values[node_key] = math.max(0, math.floor(tonumber(value) or 0))
end

local function getNodeMaxValue(entry)
    return math.max(0, math.floor(tonumber(entry and entry.node and entry.node.maxvalue) or 0))
end

local function isNodeMaxed(agent, entry)
    return getNodeValue(agent, entry and entry.key) >= getNodeMaxValue(entry)
end

local function getPointBoxRect(panel)
    return {
        x = panel.x - TREE_POINT_BOX_GAP - TREE_POINT_BOX_SIZE,
        y = panel.y,
        w = TREE_POINT_BOX_SIZE,
        h = TREE_POINT_BOX_SIZE,
    }
end

local function sortColumnNodes(nodes)
    local sorted = {}

    for _, node in ipairs(nodes or {}) do
        sorted[#sorted + 1] = node
    end

    table.sort(sorted, function(a, b)
        return (tonumber(a.pos) or 0) > (tonumber(b.pos) or 0)
    end)

    return sorted
end

local function firstNode(nodes)
    return nodes and nodes[1] or nil
end

local function buildSkillTreeNodeLayout(tree, panel)
    local nodes = tree and tree.nodes or {}
    local tab_area_h = TREE_TAB_H + TREE_CONTENT_TOP_PAD
    local content_x = panel.x + PANEL_PAD
    local content_y = panel.y + PANEL_PAD + tab_area_h
    local content_w = panel.w - PANEL_PAD * 2
    local col_gap = (content_w - THUMB_W * 3) / 2
    local step_y = THUMB_H + TREE_NODE_LABEL_H + TREE_NODE_GAP_Y
    local columns = {
        sortColumnNodes(nodes.col1),
        sortColumnNodes(nodes.col2),
        sortColumnNodes(nodes.col3),
    }
    local layout_nodes = {}
    local column_entries = { {}, {}, {} }
    local column_bottoms = {}
    local capstone_entries = {}
    local bridge_entry = nil
    local method_entry = nil
    local max_count = 0

    for _, column in ipairs(columns) do
        max_count = math.max(max_count, #column)
    end

    for col_index, column in ipairs(columns) do
        local x = content_x + (col_index - 1) * (THUMB_W + col_gap)
        local section_key = "col" .. tostring(col_index)

        for row_index, node in ipairs(column) do
            local y = content_y + (row_index - 1) * step_y - tree_scroll
            local entry = {
                node = node,
                card = cloneNodeCard(node),
                key = ("%s:%s:%d"):format(tree.id or "tree", section_key, row_index),
                x = x,
                y = y,
                w = THUMB_W,
                h = THUMB_H,
                label_y = y + THUMB_H,
                column = col_index,
                row = row_index,
            }

            layout_nodes[#layout_nodes + 1] = entry
            column_entries[col_index][row_index] = entry
            column_bottoms[col_index] = entry
        end
    end

    local bridge_node = firstNode(nodes.bridge)
    local bridge_x = content_x + (content_w - THUMB_W) / 2
    local bridge_y = content_y + max_count * step_y + TREE_BRIDGE_GAP_Y - tree_scroll
    bridge_entry = bridge_node and {
        node = bridge_node,
        card = cloneNodeCard(bridge_node),
        key = ("%s:bridge:1"):format(tree.id or "tree"),
        x = bridge_x,
        y = bridge_y,
        w = THUMB_W,
        h = THUMB_H,
        label_y = bridge_y + THUMB_H,
        bridge = true,
    } or nil

    if bridge_entry then
        layout_nodes[#layout_nodes + 1] = bridge_entry
    end

    local cap_y = bridge_y + THUMB_H + TREE_NODE_LABEL_H + TREE_CAPSTONE_GAP_Y
    local cap_nodes = { firstNode(nodes.cap1), firstNode(nodes.cap2), firstNode(nodes.cap3) }

    for index, node in ipairs(cap_nodes) do
        if node then
            local x = content_x + (index - 1) * (THUMB_W + col_gap)

            layout_nodes[#layout_nodes + 1] = {
                node = node,
                card = cloneNodeCard(node),
                key = ("%s:cap%d:1"):format(tree.id or "tree", index),
                x = x,
                y = cap_y,
                w = THUMB_W,
                h = THUMB_H,
                label_y = cap_y + THUMB_H,
                capstone = true,
                column = index,
            }
            capstone_entries[index] = layout_nodes[#layout_nodes]
        end
    end

    local method_node = firstNode(nodes.methodcap)
    local method_y = cap_y + THUMB_H + TREE_NODE_LABEL_H + TREE_CAPSTONE_GAP_Y

    method_entry = method_node and {
        node = method_node,
        card = cloneNodeCard(method_node),
        key = ("%s:methodcap:1"):format(tree.id or "tree"),
        x = bridge_x,
        y = method_y,
        w = THUMB_W,
        h = THUMB_H,
        label_y = method_y + THUMB_H,
        methodcap = true,
    } or nil

    if method_entry then
        layout_nodes[#layout_nodes + 1] = method_entry
    end

    local content_h = max_count * step_y
        + TREE_BRIDGE_GAP_Y
        + THUMB_H
        + TREE_NODE_LABEL_H
        + TREE_CAPSTONE_GAP_Y
        + THUMB_H
        + TREE_NODE_LABEL_H
        + TREE_CAPSTONE_GAP_Y
        + THUMB_H
        + TREE_NODE_LABEL_H
        + TREE_CONTENT_BOTTOM_PAD

    return {
        nodes = layout_nodes,
        columns = columns,
        column_entries = column_entries,
        column_bottoms = column_bottoms,
        capstones = capstone_entries,
        bridge = bridge_entry,
        methodcap = method_entry,
        content_h = content_h,
        content_x = content_x,
        content_y = content_y,
        content_w = content_w,
        viewport_y = content_y,
        viewport_h = panel.y + panel.h - PANEL_PAD - content_y,
    }
end

local function getTreeMaxScroll(tree, panel)
    if not tree then
        return 0
    end

    local tree_layout = buildSkillTreeNodeLayout(tree, panel)
    return math.max(0, tree_layout.content_h - tree_layout.viewport_h)
end

local function hasPoint(agent, entry)
    return entry and getNodeValue(agent, entry.key) > 0
end

local function allColumnNodesHavePoint(agent, tree_layout, column_index)
    for _, entry in ipairs(tree_layout.column_entries[column_index] or {}) do
        if not hasPoint(agent, entry) then
            return false
        end
    end

    return true
end

local function allOtherTreeNodesMaxed(agent, tree_layout, method_entry)
    for _, entry in ipairs(tree_layout.nodes) do
        if entry ~= method_entry and not isNodeMaxed(agent, entry) then
            return false
        end
    end

    return true
end

local function isNodePrerequisiteMet(agent, entry, tree_layout)
    if not entry or not entry.key then
        return false
    end

    if entry.methodcap then
        return allOtherTreeNodesMaxed(agent, tree_layout, entry)
    end

    if entry.capstone then
        return allColumnNodesHavePoint(agent, tree_layout, entry.column)
    end

    if entry.bridge then
        for _, bottom in ipairs(tree_layout.column_bottoms) do
            if hasPoint(agent, bottom) then
                return true
            end
        end

        return false
    end

    if entry.column and entry.row then
        if entry.row == 1 then
            return true
        end

        local column = tree_layout.column_entries[entry.column] or {}
        local above = column[entry.row - 1]
        local below = column[entry.row + 1]
        local bridge = entry == tree_layout.column_bottoms[entry.column] and tree_layout.bridge or nil

        return hasPoint(agent, above) or hasPoint(agent, below) or hasPoint(agent, bridge)
    end

    return false
end

local function canSpendOnNode(agent, entry, tree_layout)
    return XP_levels.getSkillPoints(agent) > 0
        and isNodePrerequisiteMet(agent, entry, tree_layout)
        and not isNodeMaxed(agent, entry)
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

    for index, card in ipairs(agent and agent.action_draw_pile or {}) do
        cards[#cards + 1] = {
            card = card,
            dimmed = false,
            fatigued = action_deck_logic.isCardFatigued(agent, card),
            pile = "action_draw_pile",
            index = index,
            in_hand = false,
        }
    end

    for index, card in ipairs(agent and agent.action_hand or {}) do
        cards[#cards + 1] = {
            card = card,
            dimmed = true,
            fatigued = action_deck_logic.isCardFatigued(agent, card),
            pile = "action_hand",
            index = index,
            in_hand = true,
        }
    end

    for index, card in ipairs(agent and agent.action_discard_pile or {}) do
        cards[#cards + 1] = {
            card = card,
            dimmed = true,
            fatigued = action_deck_logic.isCardFatigued(agent, card),
            pile = "action_discard_pile",
            index = index,
            in_hand = false,
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

local function isItemInHand(item)
    return item and item.in_hand or false
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

local function getItemAt(cards, grid, scroll, mouse_x, mouse_y)
    if mouse_x < grid.x or mouse_x > grid.x + grid.w or mouse_y < grid.y or mouse_y > grid.y + grid.h then
        return nil
    end

    for index, item in ipairs(cards) do
        local col = (index - 1) % grid.cols
        local row = math.floor((index - 1) / grid.cols)
        local x = grid.x + col * (THUMB_W + THUMB_GAP)
        local y = grid.y + row * (THUMB_H + THUMB_GAP) - scroll

        if mouse_x >= x and mouse_x <= x + THUMB_W and mouse_y >= y and mouse_y <= y + THUMB_H then
            return item, index
        end
    end

    return nil
end

local function isSelectedSwapItem(kind, item, index)
    if not selected_swap or selected_swap.kind ~= kind then
        return false
    end

    if kind == "deck" then
        return item and selected_swap.pile == item.pile and selected_swap.index == item.index
    end

    return selected_swap.index == index
end

local function drawHandBadge(x, y)
    if not hand_badge_font then
        hand_badge_font = love.graphics.newFont("assets/fonts/icons.otf", HAND_BADGE_FONT_SIZE)
    end

    local previous_font = love.graphics.getFont()
    local badge_x = x + THUMB_W - HAND_BADGE_SIZE - 5
    local badge_y = y + THUMB_H - HAND_BADGE_SIZE - 5

    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.circle("fill", badge_x + HAND_BADGE_SIZE / 2, badge_y + HAND_BADGE_SIZE / 2, HAND_BADGE_SIZE / 2)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(hand_badge_font)
    love.graphics.printf(
        HAND_BADGE_GLYPH,
        badge_x,
        badge_y + (HAND_BADGE_SIZE - hand_badge_font:getHeight()) / 2,
        HAND_BADGE_SIZE,
        "center"
    )
    love.graphics.setFont(previous_font)
end

local function drawThumb(item, x, y, show_burn, selected)
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

    love.graphics.setColor(selected and SELECTED_CARD_COLOR or PANEL_BORDER_COLOR)
    love.graphics.setLineWidth(selected and 4 or 2)
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

    if isItemInHand(item) then
        drawHandBadge(x, y)
    end
end

local function drawPanel(panel, title, cards, scroll, show_burn, selection_kind)
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
            drawThumb(card, x, y, show_burn, isSelectedSwapItem(selection_kind, card, index))
        end
    end

    love.graphics.setScissor()

    return scroll, grid
end

local function drawSkillCardPool(panel, agent)
    local pool = getSkillCardPool(agent)

    pool_scroll = drawPanel(panel, "CARDS", pool, pool_scroll, false, "pool")
end

local function drawEmptyPanel(panel)
    love.graphics.setColor(PANEL_COLOR)
    love.graphics.rectangle("fill", panel.x, panel.y, panel.w, panel.h)
    love.graphics.setColor(PANEL_BORDER_COLOR)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", panel.x, panel.y, panel.w, panel.h)
    love.graphics.setLineWidth(1)
end

local function drawFittedSingleLineText(text, x, y, w, h)
    local font = love.graphics.getFont()
    local text_w = math.max(1, font:getWidth(text))
    local text_h = math.max(1, font:getHeight())
    local scale = math.min(1, w / text_w, h / text_h)
    local draw_x = x + (w - text_w * scale) / 2
    local draw_y = y + (h - text_h * scale) / 2

    love.graphics.print(text, draw_x, draw_y, 0, scale, scale)
end

local function drawTreeTabs(panel, tabs)
    for _, rect in ipairs(getTreeTabRects(panel, tabs)) do
        local selected = rect.index == active_tree_tab

        love.graphics.setColor(selected and PANEL_BORDER_COLOR or THUMB_BACKING_COLOR)
        love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
        love.graphics.setColor(PANEL_BORDER_COLOR)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(selected and BURN_TEXT_COLOR or TEXT_COLOR)
        drawFittedSingleLineText(rect.tab.name, rect.x + 4, rect.y + 2, rect.w - 8, rect.h - 4)
    end
end

local function getNodePlusRect(entry, panel)
    local right_x = entry.x + entry.w + TREE_PLUS_GAP
    local left_x = entry.x - TREE_PLUS_GAP - TREE_PLUS_SIZE
    local x = right_x + TREE_PLUS_SIZE <= panel.x + panel.w - PANEL_PAD and right_x or left_x

    return {
        x = x,
        y = entry.y + (entry.h - TREE_PLUS_SIZE) / 2,
        w = TREE_PLUS_SIZE,
        h = TREE_PLUS_SIZE,
    }
end

local function drawPointBox(panel, agent)
    local points = XP_levels.getSkillPoints(agent)

    if points <= 0 then
        return
    end

    local rect = getPointBoxRect(panel)
    local font = love.graphics.getFont()

    love.graphics.setColor(TREE_POINT_COLOR)
    love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
    love.graphics.setColor(TREE_POINT_TEXT_COLOR)
    love.graphics.printf(tostring(points), rect.x, rect.y + (rect.h - font:getHeight()) / 2, rect.w, "center")
end

local function drawPlusButton(rect)
    local font = love.graphics.getFont()

    love.graphics.setColor(TREE_POINT_COLOR)
    love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
    love.graphics.setColor(TREE_POINT_TEXT_COLOR)
    love.graphics.printf("+", rect.x, rect.y + (rect.h - font:getHeight()) / 2, rect.w, "center")
end

local function drawTreeNode(entry, panel, agent, tree_layout)
    local prerequisite_met = isNodePrerequisiteMet(agent, entry, tree_layout)
    local outline_color = prerequisite_met and PANEL_BORDER_COLOR or TREE_LOCKED_COLOR
    local label_text_color = prerequisite_met and TEXT_COLOR or TREE_LOCKED_COLOR

    love.graphics.setColor(THUMB_BACKING_COLOR)
    love.graphics.rectangle("fill", entry.x, entry.y, entry.w, entry.h)

    if entry.card then
        card_vis.drawCardPortrait(entry.card, entry.x, entry.y, entry.w, entry.h)
    end

    if not prerequisite_met then
        love.graphics.setColor(TREE_LOCKED_DIM_COLOR)
        love.graphics.rectangle("fill", entry.x, entry.y, entry.w, entry.h)
    end

    love.graphics.setColor(outline_color)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", entry.x, entry.y, entry.w, entry.h)
    love.graphics.setLineWidth(1)

    love.graphics.setColor(THUMB_BACKING_COLOR)
    love.graphics.rectangle("fill", entry.x, entry.label_y, entry.w, TREE_NODE_LABEL_H)
    love.graphics.setColor(outline_color)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", entry.x, entry.label_y, entry.w, TREE_NODE_LABEL_H)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(label_text_color)
    love.graphics.printf(
        tostring(getNodeValue(agent, entry.key)) .. "/" .. tostring(entry.node and entry.node.maxvalue or 0),
        entry.x,
        entry.label_y -2,
        entry.w,
        "center"
    )

    if canSpendOnNode(agent, entry, tree_layout) then
        drawPlusButton(getNodePlusRect(entry, panel))
    end
end

local function drawTreeConnection(from_entry, to_entry)
    if not from_entry or not to_entry then
        return
    end

    local from_x = from_entry.x + from_entry.w / 2
    local from_y = from_entry.label_y + TREE_NODE_LABEL_H
    local to_x = to_entry.x + to_entry.w / 2
    local to_y = to_entry.y

    love.graphics.setColor(TREE_LINE_COLOR)
    love.graphics.setLineWidth(3)
    love.graphics.line(from_x, from_y, to_x, to_y)
    love.graphics.setLineWidth(1)
end

local function drawSkillTree(panel, agent)
    local tree, tabs = getActiveTree(agent)

    drawEmptyPanel(panel)

    if #tabs == 0 or not tree then
        return nil
    end

    tree_scroll = math.min(tree_scroll, getTreeMaxScroll(tree, panel))
    drawTreeTabs(panel, tabs)

    local tree_layout = buildSkillTreeNodeLayout(tree, panel)
    local mouse_x, mouse_y = love.mouse.getPosition()
    local hovered_card = nil

    love.graphics.setScissor(panel.x + 3, tree_layout.viewport_y, panel.w - 6, tree_layout.viewport_h)

    for _, column in ipairs(tree_layout.columns) do
        local previous_entry = nil

        for _, entry in ipairs(tree_layout.nodes) do
            if entry.column and not entry.capstone and entry.node and column[entry.row] == entry.node then
                if previous_entry then
                    drawTreeConnection(previous_entry, entry)
                end

                previous_entry = entry
            end
        end
    end

    if tree_layout.bridge then
        for _, bottom in ipairs(tree_layout.column_bottoms) do
            drawTreeConnection(bottom, tree_layout.bridge)
        end
    end

    for _, entry in ipairs(tree_layout.nodes) do
        if entry.y + entry.h + TREE_NODE_LABEL_H >= tree_layout.viewport_y
            and entry.y <= tree_layout.viewport_y + tree_layout.viewport_h
        then
            drawTreeNode(entry, panel, agent, tree_layout)

            if pointInRect(mouse_x, mouse_y, {
                x = entry.x,
                y = entry.y,
                w = entry.w,
                h = entry.h + TREE_NODE_LABEL_H,
            }) then
                hovered_card = entry.card
            end
        end
    end

    love.graphics.setScissor()
    drawPointBox(panel, agent)

    return hovered_card
end

local function spendOnTreeNodeAt(panel, agent, x, y)
    local tree = getActiveTree(agent)

    if not tree or XP_levels.getSkillPoints(agent) <= 0 then
        return false
    end

    local tree_layout = buildSkillTreeNodeLayout(tree, panel)

    if y < tree_layout.viewport_y or y > tree_layout.viewport_y + tree_layout.viewport_h then
        return false
    end

    for _, entry in ipairs(tree_layout.nodes) do
        if canSpendOnNode(agent, entry, tree_layout) and pointInRect(x, y, getNodePlusRect(entry, panel)) then
            if XP_levels.spendSkillPoint(agent) then
                setNodeValue(agent, entry.key, getNodeValue(agent, entry.key) + 1)
                addSkillCardToPool(agent, entry.card)
                sfx_logic.playNamed("token_select")
                return true
            end

            return false
        end
    end

    return false
end

local function swapDeckCardWithPoolCard(agent, deck_entry, pool_index)
    local pool = getSkillCardPool(agent)
    local pool_card = pool[pool_index]
    local pile = agent and deck_entry and agent[deck_entry.pile] or nil
    local deck_card = pile and pile[deck_entry.index] or nil

    if not pool_card or not deck_card then
        return false
    end

    local replacement = cloneCardForDeckSlot(pool_card, deck_card)
    local swapped_out = cloneBaseCard(deck_card)

    if not replacement or not swapped_out then
        return false
    end

    pile[deck_entry.index] = replacement
    pool[pool_index] = swapped_out
    selected_swap = nil
    sfx_logic.playNamed("token_select")

    return true
end

local function selectOrSwapDeckCard(agent, deck_entry)
    if not deck_entry then
        return false
    end

    if selected_swap and selected_swap.kind == "pool" then
        return swapDeckCardWithPoolCard(agent, deck_entry, selected_swap.index)
    end

    selected_swap = {
        kind = "deck",
        pile = deck_entry.pile,
        index = deck_entry.index,
    }

    return true
end

local function selectOrSwapPoolCard(agent, pool_index)
    if not pool_index or not getSkillCardPool(agent)[pool_index] then
        return false
    end

    if selected_swap and selected_swap.kind == "deck" then
        return swapDeckCardWithPoolCard(agent, selected_swap, pool_index)
    end

    selected_swap = {
        kind = "pool",
        index = pool_index,
    }

    return true
end

local function drawPreview(card, preview, unit)
    if not card then
        return
    end

    local card_w = card_vis.getCardWidth()
    local card_h = card_vis.getCardHeight(card)
    local scale = math.min(1.25, preview.w / card_w, preview.h / card_h)
    local x = preview.x + (preview.w - card_w * scale) / 2
    local y = preview.y + (preview.h - card_h * scale) / 2

    card_vis.drawScaledCard(card, x, y, scale, { unit = unit })
end

function action_deck_viewer.open(agent, mode)
    open_agent = agent
    open_mode = mode or "deck"
    active_tree_tab = 1
    deck_scroll = 0
    discard_scroll = 0
    tree_scroll = 0
    pool_scroll = 0
    selected_swap = nil
end

function action_deck_viewer.close()
    if not open_agent then
        return false
    end

    open_agent = nil
    open_mode = "deck"
    active_tree_tab = 1
    deck_scroll = 0
    discard_scroll = 0
    tree_scroll = 0
    pool_scroll = 0
    selected_swap = nil

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
    local hovered_card

    love.graphics.setColor(BACKDROP_COLOR)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())

    deck_scroll = drawPanel(layout.deck, "DECK", deck_cards, deck_scroll, true, open_mode == "tree" and "deck" or nil)

    local deck_grid = getGrid(layout.deck, deck_cards)
    hovered_card = getCardAt(deck_cards, deck_grid, deck_scroll, mouse_x, mouse_y)

    if open_mode == "tree" then
        local tree_panels = getTreePanels(layout)
        local tree_hover = drawSkillTree(tree_panels[1], open_agent)

        drawSkillCardPool(tree_panels[2], open_agent)

        local pool_cards = getSkillCardPool(open_agent)
        local pool_grid = getGrid(tree_panels[2], pool_cards)
        local pool_hover = getCardAt(pool_cards, pool_grid, pool_scroll, mouse_x, mouse_y)

        hovered_card = tree_hover or pool_hover or hovered_card
    else
        discard_scroll = drawPanel(layout.discard, "DISCARD", discard_cards, discard_scroll, false)

        local discard_grid = getGrid(layout.discard, discard_cards)
        hovered_card = hovered_card or getCardAt(discard_cards, discard_grid, discard_scroll, mouse_x, mouse_y)
    end

    drawPreview(hovered_card, layout.preview, open_agent)
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
    local in_right_panel = pointInRect(x, y, layout.discard)

    if open_mode == "tree" then
        in_right_panel = false

        local tree_panels = getTreePanels(layout)

        for _, panel in ipairs(tree_panels) do
            if pointInRect(x, y, panel) then
                in_right_panel = true
                break
            end
        end

        if pointInRect(x, y, layout.deck) then
            local deck_cards = getDeckCards(open_agent)
            local deck_grid = getGrid(layout.deck, deck_cards)
            local deck_entry = getItemAt(deck_cards, deck_grid, deck_scroll, x, y)

            if selectOrSwapDeckCard(open_agent, deck_entry) then
                return true
            end
        end

        local tree_panel = tree_panels[1]
        local pool_panel = tree_panels[2]

        if pointInRect(x, y, tree_panel) then
            if spendOnTreeNodeAt(tree_panel, open_agent, x, y) then
                return true
            end

            local _, tabs = getActiveTree(open_agent)

            for _, rect in ipairs(getTreeTabRects(tree_panel, tabs)) do
                if pointInRect(x, y, rect) then
                    sfx_logic.playNamed("token_select")
                    active_tree_tab = rect.index
                    tree_scroll = 0
                    return true
                end
            end
        end

        if pointInRect(x, y, pool_panel) then
            local pool = getSkillCardPool(open_agent)
            local pool_grid = getGrid(pool_panel, pool)
            local _, pool_index = getItemAt(pool, pool_grid, pool_scroll, x, y)

            if selectOrSwapPoolCard(open_agent, pool_index) then
                return true
            end
        end
    end

    if not pointInRect(x, y, layout.deck) and not in_right_panel then
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
    elseif open_mode == "tree" and pointInRect(mouse_x, mouse_y, getTreePanels(layout)[1]) then
        local tree = getActiveTree(open_agent)
        tree_scroll = math.max(0, math.min(tree_scroll - y * SCROLL_STEP, getTreeMaxScroll(tree, getTreePanels(layout)[1])))
    elseif open_mode == "tree" and pointInRect(mouse_x, mouse_y, getTreePanels(layout)[2]) then
        local grid = getGrid(getTreePanels(layout)[2], getSkillCardPool(open_agent))
        pool_scroll = clampScroll(pool_scroll - y * SCROLL_STEP, grid)
    elseif open_mode ~= "tree" and pointInRect(mouse_x, mouse_y, layout.discard) then
        local grid = getGrid(layout.discard, open_agent.action_discard_pile or {})
        discard_scroll = clampScroll(discard_scroll - y * SCROLL_STEP, grid)
    end

    return true
end

return action_deck_viewer

local agent_logic = require("src.sys.agent_logic")
local fate_logic = require("src.sys.fate_logic")
local image_loader = require("src.assets.image_loader")
local map_tiles = require("src.rndr.map_tiles")

local agent_uix = {}

local PANEL_X = 24
local PANEL_Y = 24
local PANEL_W = 460
local PANEL_H = 190
local PANEL_PAD = 18
local PORTRAIT_BOX_SIZE = PANEL_H - PANEL_PAD * 2
local PORTRAIT_BOX_X = PANEL_X + PANEL_PAD
local PORTRAIT_BOX_Y = PANEL_Y + PANEL_PAD
local PORTRAIT_PAD = 10
local PORTRAIT_RADIUS = (PORTRAIT_BOX_SIZE - PORTRAIT_PAD * 2) / 2
local CONTENT_X = PORTRAIT_BOX_X + PORTRAIT_BOX_SIZE + PANEL_PAD
local CONTENT_Y = PANEL_Y + PANEL_PAD
local CONTENT_W = PANEL_X + PANEL_W - PANEL_PAD - CONTENT_X
local STAT_X = CONTENT_X
local STAT_Y = CONTENT_Y + 52
local STAT_ROW_H = 32
local PANEL_COLOR = { 0, 0, 0, 0.86 }
local TEXT_COLOR = { 1, 1, 1, 1 }
local OUTLINE_COLOR = { 0.02, 0.018, 0.015, 1 }
local MODAL_BACKDROP_COLOR = { 0, 0, 0, 0.80 }
local MODAL_FILL_COLOR = { 0, 0, 0, 0.94 }
local MODAL_BORDER_COLOR = { 1, 1, 1, 1 }
local FATE_ROW_COLOR = { 0.075, 0.07, 0.062, 1 }
local FATE_ROW_BORDER_COLOR = { 0.22, 0.2, 0.17, 1 }
local FATE_POS_COLOR = { 0.9765, 0.6314, 0, 1 }
local FATE_BAD_COLOR = { 1, 0.2784, 0.2706, 1 }
local FATE_CRIT_COLOR = { 1, 0.1686, 0.9922, 1 }
local AGENT_IMAGE_DIR = "assets/images/agents"
local ENEMY_IMAGE_DIR = "assets/images/enemy"
local ENEMY_OUTLINE_COLOR = { 0.6118, 0, 0.0431, 1 }
local MODAL_GAP = 18
local MODAL_H = 560
local MODAL_IMAGE_W = MODAL_H
local MODAL_SLOT_W = 640
local MODAL_DECK_W = 220
local MODAL_PAD = 18
local MODAL_TITLE_H = 30
local MODAL_TITLE_GAP = 8
local SLOT_COLS = 5
local SLOT_ROWS = 2
local SLOT_BOX_W = 97
local SLOT_BOX_H = 74
local SLOT_LABEL_H = 30
local SLOT_GAP_X = 12
local SLOT_GAP_Y = 14
local INVENTORY_COLS = 10
local INVENTORY_ROWS = 4
local INVENTORY_PAD = 12
local INVENTORY_GAP = 4
local FATE_SECTION_GAP = 14
local FATE_ROW_H = 28
local FATE_ROW_GAP = 6
local FATE_FONT_SIZE = 16
local full_images = {}
local missing_full_images = {}
local fate_font
local modal_unit = nil
local modal_kind = nil
local STAT_COLORS = {
    ap = { 1, 1, 1, 1 },
    hp = { 1, 0.2902, 0.4941, 1 },
    lp = { 0.1412, 0.8157, 1, 1 },
    atk = { 0.9961, 0.3373, 0.1765, 1 },
}
local AGENT_STAT_ORDER = {
    { id = "ap", label = "AP" },
    { id = "hp", label = "HP" },
    { id = "lp", label = "LP" },
}
local ENEMY_STAT_ORDER = {
    { id = "hp", label = "HP" },
    { id = "atk", label = "ATK" },
}

local function pointInRect(x, y, rect_x, rect_y, rect_w, rect_h)
    return x >= rect_x and x <= rect_x + rect_w and y >= rect_y and y <= rect_y + rect_h
end

local function getModalLayout()
    local total_w = MODAL_IMAGE_W + MODAL_GAP + MODAL_SLOT_W + MODAL_GAP + MODAL_DECK_W
    local x = (love.graphics.getWidth() - total_w) / 2
    local y = (love.graphics.getHeight() - MODAL_H) / 2 + (MODAL_TITLE_H + MODAL_TITLE_GAP) / 2
    local slot_x = x + MODAL_IMAGE_W + MODAL_GAP

    return {
        image_x = x,
        image_y = y,
        image_w = MODAL_IMAGE_W,
        image_h = MODAL_H,
        slot_x = slot_x,
        slot_y = y,
        slot_w = MODAL_SLOT_W,
        slot_h = MODAL_H,
        deck_x = slot_x + MODAL_SLOT_W + MODAL_GAP,
        deck_y = y,
        deck_w = MODAL_DECK_W,
        deck_h = MODAL_H,
    }
end

local function getEnemyModalLayout()
    local total_w = MODAL_IMAGE_W + MODAL_GAP + MODAL_DECK_W
    local x = (love.graphics.getWidth() - total_w) / 2
    local y = (love.graphics.getHeight() - MODAL_H) / 2 + (MODAL_TITLE_H + MODAL_TITLE_GAP) / 2

    return {
        image_x = x,
        image_y = y,
        image_w = MODAL_IMAGE_W,
        image_h = MODAL_H,
        deck_x = x + MODAL_IMAGE_W + MODAL_GAP,
        deck_y = y,
        deck_w = MODAL_DECK_W,
        deck_h = MODAL_H,
    }
end

local function getImageDir(kind)
    return kind == "enemy" and ENEMY_IMAGE_DIR or AGENT_IMAGE_DIR
end

local function getFullImage(unit, kind)
    if not unit or not unit.id then
        return nil
    end

    local cache_key = (kind or "agent") .. ":" .. unit.id

    if full_images[cache_key] then
        return full_images[cache_key]
    end

    if missing_full_images[cache_key] then
        return nil
    end

    local image_dir = getImageDir(kind)
    local paths = {
        ("%s/%s-full.webp"):format(image_dir, unit.id),
        ("%s/%sfull.webp"):format(image_dir, unit.id),
    }

    for _, path in ipairs(paths) do
        if love.filesystem.getInfo(path, "file") then
            local ok, image = pcall(image_loader.newImage, path)

            if ok then
                full_images[cache_key] = image
                return image
            end

            print("Unable to load full " .. tostring(kind or "agent") .. " image '" .. path .. "': " .. tostring(image))
        end
    end

    missing_full_images[cache_key] = true

    return nil
end

local function buildHexPoints(center_x, center_y, radius)
    local points = {}

    for index = 0, 5 do
        local angle = math.rad(-90 + index * 60)
        points[#points + 1] = center_x + radius * math.cos(angle)
        points[#points + 1] = center_y + radius * math.sin(angle)
    end

    return points
end

local function drawPortrait(unit, kind)
    local image = kind == "enemy" and map_tiles.getEnemyPortrait(unit) or map_tiles.getAgentPortrait(unit)
    local center_x = PORTRAIT_BOX_X + PORTRAIT_BOX_SIZE / 2
    local center_y = PORTRAIT_BOX_Y + PORTRAIT_BOX_SIZE / 2
    local points = buildHexPoints(center_x, center_y, PORTRAIT_RADIUS)
    local outline_color = kind == "enemy" and ENEMY_OUTLINE_COLOR or OUTLINE_COLOR

    love.graphics.setColor(0.035, 0.032, 0.028, 1)
    love.graphics.rectangle("fill", PORTRAIT_BOX_X, PORTRAIT_BOX_Y, PORTRAIT_BOX_SIZE, PORTRAIT_BOX_SIZE)

    if image then
        local scale = (PORTRAIT_RADIUS * 2) / math.min(image:getWidth(), image:getHeight())

        love.graphics.stencil(function()
            love.graphics.polygon("fill", points)
        end, "replace", 1)

        love.graphics.setStencilTest("equal", 1)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(
            image,
            center_x,
            center_y,
            0,
            scale,
            scale,
            image:getWidth() / 2,
            image:getHeight() / 2
        )
        love.graphics.setStencilTest()
    end

    love.graphics.setColor(outline_color)
    love.graphics.setLineWidth(3)
    love.graphics.polygon("line", points)
    love.graphics.setLineWidth(1)
end

local function drawStatValue(label, stat, color, index, pending_cost)
    local current = math.floor(tonumber(stat and stat.current) or 0)
    local maximum = math.floor(tonumber(stat and stat.maximum) or 0)

    local y = STAT_Y + (index - 1) * STAT_ROW_H
    local value_text = label == "ATK" and tostring(current) or ("%d / %d"):format(current, maximum)
    local font = love.graphics.getFont()
    local value_w = font:getWidth(value_text)
    local value_x = STAT_X + CONTENT_W - value_w

    love.graphics.setColor(TEXT_COLOR)
    love.graphics.print(label, STAT_X, y)

    if pending_cost and pending_cost > 0 then
        local cost_text = "-" .. tostring(pending_cost)
        local cost_w = font:getWidth(cost_text)

        love.graphics.setColor(color)
        love.graphics.print(cost_text, value_x - cost_w - 14, y)
    end

    love.graphics.setColor(color)
    love.graphics.print(value_text, value_x, y)
end

local function getFateValueColor(entry)
    if entry.fail or entry.neg then
        return FATE_BAD_COLOR
    end

    if entry.crit then
        return FATE_CRIT_COLOR
    end

    return FATE_POS_COLOR
end

local function drawFullImageWindow(unit, kind, layout)
    local image = getFullImage(unit, kind)
    local fallback_label = kind == "enemy" and "Enemy" or "Agent"
    local title_w = math.min(layout.image_w, math.max(180, love.graphics.getFont():getWidth(unit.name or unit.id or fallback_label) + 28))
    local title_x = layout.image_x + (layout.image_w - title_w) / 2
    local title_y = layout.image_y - MODAL_TITLE_H - MODAL_TITLE_GAP

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(unit.name or unit.id or fallback_label, title_x + 6, title_y + 5, title_w - 12, "center")

    love.graphics.setColor(MODAL_FILL_COLOR)
    love.graphics.rectangle("fill", layout.image_x, layout.image_y, layout.image_w, layout.image_h)

    if not image then
        return
    end

    local scale = math.min(layout.image_w / image:getWidth(), layout.image_h / image:getHeight())

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setScissor(layout.image_x, layout.image_y, layout.image_w, layout.image_h)
    love.graphics.draw(
        image,
        layout.image_x + layout.image_w / 2,
        layout.image_y + layout.image_h / 2,
        0,
        scale,
        scale,
        image:getWidth() / 2,
        image:getHeight() / 2
    )
    love.graphics.setScissor()
end

local function drawSlotWindow(agent, layout)
    local section_h = (layout.slot_h - FATE_SECTION_GAP) / 2
    local slot_section_x = layout.slot_x
    local slot_section_y = layout.slot_y
    local lower_section_x = layout.slot_x
    local lower_section_y = layout.slot_y + section_h + FATE_SECTION_GAP
    local grid_w = SLOT_COLS * SLOT_BOX_W + (SLOT_COLS - 1) * SLOT_GAP_X
    local grid_h = SLOT_ROWS * (SLOT_LABEL_H + SLOT_BOX_H) + (SLOT_ROWS - 1) * SLOT_GAP_Y
    local start_x = slot_section_x + (layout.slot_w - grid_w) / 2
    local start_y = slot_section_y + (section_h - grid_h) / 2
    local previous_font = love.graphics.getFont()

    if not fate_font then
        fate_font = love.graphics.newFont("assets/fonts/Furore.otf", FATE_FONT_SIZE)
    end

    love.graphics.setColor(MODAL_FILL_COLOR)
    love.graphics.rectangle("fill", layout.slot_x, layout.slot_y, layout.slot_w, layout.slot_h)
    love.graphics.setColor(MODAL_BORDER_COLOR)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", slot_section_x, slot_section_y, layout.slot_w, section_h)
    love.graphics.rectangle("line", lower_section_x, lower_section_y, layout.slot_w, section_h)
    love.graphics.setLineWidth(1)
    love.graphics.setFont(fate_font)

    for index = 1, SLOT_COLS * SLOT_ROWS do
        local slot_name = (agent.slots and agent.slots[index]) or ""
        local col = (index - 1) % SLOT_COLS
        local row = math.floor((index - 1) / SLOT_COLS)
        local x = start_x + col * (SLOT_BOX_W + SLOT_GAP_X)
        local y = start_y + row * (SLOT_LABEL_H + SLOT_BOX_H + SLOT_GAP_Y)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("fill", x, y, SLOT_BOX_W, SLOT_LABEL_H)
        love.graphics.rectangle("line", x, y, SLOT_BOX_W, SLOT_LABEL_H)
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.printf(slot_name, x + 2, y + 6, SLOT_BOX_W - 4, "center")

        love.graphics.setColor(0.04, 0.038, 0.034, 1)
        love.graphics.rectangle("fill", x, y + SLOT_LABEL_H, SLOT_BOX_W, SLOT_BOX_H)
        love.graphics.setColor(MODAL_BORDER_COLOR)
        love.graphics.rectangle("line", x, y + SLOT_LABEL_H, SLOT_BOX_W, SLOT_BOX_H)
    end

    love.graphics.setFont(previous_font)

    local available_w = layout.slot_w - INVENTORY_PAD * 2
    local available_h = section_h - INVENTORY_PAD * 2
    local cell_size = math.floor(math.min(
        (available_w - (INVENTORY_COLS - 1) * INVENTORY_GAP) / INVENTORY_COLS,
        (available_h - (INVENTORY_ROWS - 1) * INVENTORY_GAP) / INVENTORY_ROWS
    ))
    local grid_w = INVENTORY_COLS * cell_size + (INVENTORY_COLS - 1) * INVENTORY_GAP
    local grid_h = INVENTORY_ROWS * cell_size + (INVENTORY_ROWS - 1) * INVENTORY_GAP
    local inventory_x = lower_section_x + (layout.slot_w - grid_w) / 2
    local inventory_y = lower_section_y + (section_h - grid_h) / 2

    for row = 0, INVENTORY_ROWS - 1 do
        for col = 0, INVENTORY_COLS - 1 do
            local x = inventory_x + col * (cell_size + INVENTORY_GAP)
            local y = inventory_y + row * (cell_size + INVENTORY_GAP)

            love.graphics.setColor(0.04, 0.038, 0.034, 1)
            love.graphics.rectangle("fill", x, y, cell_size, cell_size)
            love.graphics.setColor(MODAL_BORDER_COLOR)
            love.graphics.rectangle("line", x, y, cell_size, cell_size)
        end
    end
end

local function drawFateRows(entries, section_x, section_y, section_w, section_h)
    local row_x = section_x + MODAL_PAD
    local row_y = section_y + MODAL_PAD
    local row_w = section_w - MODAL_PAD * 2

    for index, entry in ipairs(entries) do
        local y = row_y + (index - 1) * (FATE_ROW_H + FATE_ROW_GAP)

        if y + FATE_ROW_H <= section_y + section_h - MODAL_PAD then
            love.graphics.setColor(FATE_ROW_COLOR)
            love.graphics.rectangle("fill", row_x, y, row_w, FATE_ROW_H)
            love.graphics.setColor(FATE_ROW_BORDER_COLOR)
            love.graphics.rectangle("line", row_x, y, row_w, FATE_ROW_H)

            love.graphics.setColor(getFateValueColor(entry))
            love.graphics.print(entry.value_text, row_x + 14, y + 5)

            love.graphics.setColor(TEXT_COLOR)
            love.graphics.printf("x" .. tostring(entry.quantity), row_x + row_w - 58, y + 5, 44, "right")
        end
    end
end

local function drawFateDeckWindow(unit, layout)
    local deck = fate_logic.getAgentDeck(unit)
    local discard = fate_logic.getAgentDiscard(unit)
    local section_h = (layout.deck_h - FATE_SECTION_GAP) / 2
    local deck_section_x = layout.deck_x
    local deck_section_y = layout.deck_y
    local discard_section_x = layout.deck_x
    local discard_section_y = layout.deck_y + section_h + FATE_SECTION_GAP
    local previous_font = love.graphics.getFont()

    if not fate_font then
        fate_font = love.graphics.newFont("assets/fonts/Furore.otf", FATE_FONT_SIZE)
    end

    love.graphics.setColor(MODAL_FILL_COLOR)
    love.graphics.rectangle("fill", layout.deck_x, layout.deck_y, layout.deck_w, layout.deck_h)

    love.graphics.setColor(MODAL_BORDER_COLOR)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", deck_section_x, deck_section_y, layout.deck_w, section_h)
    love.graphics.rectangle("line", discard_section_x, discard_section_y, layout.deck_w, section_h)
    love.graphics.setLineWidth(1)
    love.graphics.setFont(fate_font)

    drawFateRows(deck, deck_section_x, deck_section_y, layout.deck_w, section_h)
    drawFateRows(discard, discard_section_x, discard_section_y, layout.deck_w, section_h)

    love.graphics.setFont(previous_font)
end

local function drawFateModal()
    if not modal_unit then
        return
    end

    local layout = modal_kind == "enemy" and getEnemyModalLayout() or getModalLayout()

    love.graphics.setColor(MODAL_BACKDROP_COLOR)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())

    drawFullImageWindow(modal_unit, modal_kind, layout)

    if modal_kind ~= "enemy" then
        drawSlotWindow(modal_unit, layout)
    end

    drawFateDeckWindow(modal_unit, layout)

    love.graphics.setColor(1, 1, 1, 1)
end

function agent_uix.draw()
    local unit, kind = agent_logic.getSelectedUnit()

    if not unit then
        return
    end

    local stats = agent_logic.getSelectedStats()
    local preview = agent_logic.getMovementPreview()
    local pending_ap_cost = kind == "agent" and preview and preview.cost or nil
    local stat_order = kind == "enemy" and ENEMY_STAT_ORDER or AGENT_STAT_ORDER
    local fallback_label = kind == "enemy" and "Enemy" or "Agent"

    love.graphics.setColor(PANEL_COLOR)
    love.graphics.rectangle("fill", PANEL_X, PANEL_Y, PANEL_W, PANEL_H)

    drawPortrait(unit, kind)

    love.graphics.setColor(TEXT_COLOR)
    love.graphics.print(unit.name or unit.id or fallback_label, CONTENT_X, CONTENT_Y)

    for index, stat in ipairs(stat_order) do
        drawStatValue(stat.label, stats[stat.id], STAT_COLORS[stat.id], index, stat.id == "ap" and pending_ap_cost or nil)
    end

    love.graphics.setColor(1, 1, 1, 1)

    drawFateModal()
end

function agent_uix.mousepressed(x, y, button)
    if button ~= 1 then
        return false
    end

    if modal_unit then
        local layout = modal_kind == "enemy" and getEnemyModalLayout() or getModalLayout()
        local in_image = pointInRect(x, y, layout.image_x, layout.image_y, layout.image_w, layout.image_h)
        local in_slot = layout.slot_x and pointInRect(x, y, layout.slot_x, layout.slot_y, layout.slot_w, layout.slot_h)
        local in_deck = pointInRect(x, y, layout.deck_x, layout.deck_y, layout.deck_w, layout.deck_h)

        if not in_image and not in_slot and not in_deck then
            modal_unit = nil
            modal_kind = nil
        end

        return true
    end

    local unit, kind = agent_logic.getSelectedUnit()

    if unit and pointInRect(x, y, PORTRAIT_BOX_X, PORTRAIT_BOX_Y, PORTRAIT_BOX_SIZE, PORTRAIT_BOX_SIZE) then
        modal_unit = unit
        modal_kind = kind
        return true
    end

    return false
end

function agent_uix.closeModal()
    if not modal_unit then
        return false
    end

    modal_unit = nil
    modal_kind = nil

    return true
end

function agent_uix.isModalOpen()
    return modal_unit ~= nil
end

return agent_uix

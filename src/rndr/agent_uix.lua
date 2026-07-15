local agent_logic = require("src.sys.agent_logic")
local fate_logic = require("src.sys.fate_logic")
local image_loader = require("src.assets.image_loader")
local map_tiles = require("src.rndr.map_tiles")
local action_deck_viewer = require("src.rndr.action_deck_viewer")
local burn_palette = require("data.burn_palette")
local block_logic = require("src.sys.block_logic")
local XP_levels = require("src.sys.XP_levels")
local luggage = require("src.sys.luggage")
local sfx_logic = require("src.sys.sfx_logic")
local equip_logic = require("src.sys.equip_logic")
local card_play = require("src.sys.card_play")
local card_vis = require("src.rndr.card_vis")

local agent_uix = {}

local PANEL_X = 24
local PANEL_Y = 24
local PANEL_W = 460
local PANEL_H = 190
local PANEL_PAD = 18
local BURN_CLOCK_GAP = 12
local BURN_CLOCK_SIZE = 135
local BURN_CLOCK_X = PANEL_X + PANEL_W + BURN_CLOCK_GAP
local BURN_CLOCK_Y = PANEL_Y + (PANEL_H - BURN_CLOCK_SIZE) / 2
local BURN_CLOCK_SEGMENTS = 4
local BURN_CLOCK_CIRCLE_SEGMENTS = 128
local BURN_CLOCK_OUTER_RADIUS = 58
local BURN_CLOCK_CENTER_RADIUS = 39
local BURN_CLOCK_FONT_SIZE = 15
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
local ENEMY_STAT_Y = STAT_Y - 12
local STAT_ROW_H = 32
local PANEL_COLOR = { 0, 0, 0, 0.86 }
local TEXT_COLOR = { 1, 1, 1, 1 }
local OUTLINE_COLOR = { 0.02, 0.018, 0.015, 1 }
local MODAL_BACKDROP_COLOR = { 0, 0, 0, 0.80 }
local MODAL_FILL_COLOR = { 0, 0, 0, 0.94 }
local MODAL_BORDER_COLOR = { 1, 1, 1, 1 }
local EQUIP_VALID_COLOR = { 1, 0.8275, 0.3529, 1 }
local EQUIP_GHOST_VALID_COLOR = { 0.4078, 0.6824, 0.5804, 1 }
local EQUIP_GHOST_INVALID_COLOR = { 1, 0, 0.2863, 1 }
local FATE_ROW_COLOR = { 0.075, 0.07, 0.062, 1 }
local FATE_ROW_BORDER_COLOR = { 0.22, 0.2, 0.17, 1 }
local FATE_POS_COLOR = { 0.9765, 0.6314, 0, 1 }
local FATE_BAD_COLOR = { 1, 0.2784, 0.2706, 1 }
local FATE_CRIT_COLOR = { 1, 0.1686, 0.9922, 1 }
local AGENT_IMAGE_DIR = "assets/images/agents"
local ENEMY_IMAGE_DIR = "assets/images/enemy"
local HAZARD_IMAGE_DIR = "assets/images/hazard"
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
local MODAL_STAT_LABEL_W = 150
local MODAL_STAT_LABEL_H = 28
local MODAL_STAT_LABEL_GAP = 18
local MODAL_STAT_LABEL_Y_GAP = 8
local MODAL_STAT_LABEL_OUTLINE_W = 3
local MODAL_STAT_BUTTON_SIZE = 26
local MODAL_STAT_BUTTON_Y_GAP = 5
local MODAL_STAT_POINTS_W = 210
local MODAL_STAT_POINTS_H = 24
local MODAL_STAT_POINTS_Y_GAP = 5
local BLOCK_ICON_FONT_SIZE = 22
local XP_COLOR = { 1, 0.8275, 0.3529, 1 }
local XP_GAUGE_X = PANEL_X
local XP_GAUGE_Y = PANEL_Y + PANEL_H + 8
local XP_GAUGE_W = PANEL_W
local XP_GAUGE_H = 28
local XP_GAUGE_OUTLINE_W = 3
local LEVEL_BADGE_SIZE = 38
local LEVEL_BADGE_OUTLINE_W = 3
local LEVEL_BADGE_PULSE_SPEED = 3.4
local LEVEL_BADGE_PULSE_SCALE = 0.08
local DECK_BUTTON_SIZE = 74
local DECK_BUTTON_GAP = 16
local DECK_BUTTON_ICON_PAD = 14
local TREE_BUTTON_BRACKET_PAD = 6
local TREE_BUTTON_BRACKET_LEN = 18
local TREE_BUTTON_BRACKET_PULSE_SPEED = 3.4
local TREE_BUTTON_BRACKET_PULSE_SCALE = 0.08
local DECK_ICON_PATH = "assets/images/icons/deck.webp"
local TREE_ICON_PATH = "assets/images/icons/tree.webp"
local EQUIP_PREVIEW_PAD = 18
local EQUIP_PREVIEW_IMAGE_SIZE = 150
local EQUIP_PREVIEW_THUMB_W = 45
local EQUIP_PREVIEW_THUMB_H = 61
local EQUIP_PREVIEW_THUMB_GAP = 6
local EQUIP_PREVIEW_ROW_GAP = 10
local EQUIP_PREVIEW_HEADER_H = 30
local EQUIP_PREVIEW_CLICK_DRAG_THRESHOLD = 6
local full_images = {}
local missing_full_images = {}
local equip_images = {}
local missing_equip_images = {}
local deck_icon = nil
local missing_deck_icon = false
local tree_icon = nil
local missing_tree_icon = false
local fate_font
local burn_clock_font
local block_icon_font
local modal_unit = nil
local modal_kind = nil
local modal_offset_y = 0
agent_uix.equipment_card_draw_enabled = true
local equip_drag = nil
local pinned_equipment = nil
local hovered_preview_card_key = nil
local BLOCK_GLYPH = "\239\143\173"
local BLOCK_COLOR = { 0.7412, 0.6824, 0.7176, 1 }
local STAT_COLORS = {
    ap = { 1, 1, 1, 1 },
    hp = { 1, 0.2902, 0.4941, 1 },
    lp = { 0.1412, 0.8157, 1, 1 },
    atk = { 0.9961, 0.3373, 0.1765, 1 },
    spd = { 1, 1, 1, 1 },
    rng = { 1, 0.8706, 0.3137, 1 },
    bp = { 0.7255, 0.8, 0.6667, 1 },
}
local AGENT_STAT_ORDER = {
    { id = "ap", label = "AP" },
    { id = "hp", label = "HP" },
    { id = "lp", label = "LP" },
}
local ENEMY_STAT_ORDER = {
    { id = "hp", label = "HP" },
    { id = "atk", label = "ATK" },
    { id = "spd", label = "SPD" },
    { id = "rng", label = "RNG" },
}
local DOOR_STAT_ORDER = {
    { id = "hp", label = "HP" },
    { id = "bp", label = "BP" },
}
local HAZARD_STAT_ORDER = {
    { id = "hp", label = "HP" },
    { id = "bp", label = "BP" },
    { id = "atk", label = "ATK" },
    { id = "rng", label = "RNG" },
}

local function pointInRect(x, y, rect_x, rect_y, rect_w, rect_h)
    return x >= rect_x and x <= rect_x + rect_w and y >= rect_y and y <= rect_y + rect_h
end

local function pointInAnyRect(x, y, rects)
    for _, rect in ipairs(rects or {}) do
        if pointInRect(x, y, rect.x, rect.y, rect.w, rect.h) then
            return rect
        end
    end

    return nil
end

local function getModalLayout()
    local total_w = MODAL_IMAGE_W + MODAL_GAP + MODAL_SLOT_W + MODAL_GAP + MODAL_DECK_W
    local x = (love.graphics.getWidth() - total_w) / 2
    local y = (love.graphics.getHeight() - MODAL_H) / 2 + (MODAL_TITLE_H + MODAL_TITLE_GAP) / 2 + modal_offset_y
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
    local y = (love.graphics.getHeight() - MODAL_H) / 2 + (MODAL_TITLE_H + MODAL_TITLE_GAP) / 2 + modal_offset_y

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
    if kind == "hazard" then
        return HAZARD_IMAGE_DIR
    end

    return kind == "enemy" and ENEMY_IMAGE_DIR or AGENT_IMAGE_DIR
end

local function getDeckIcon()
    if deck_icon then
        return deck_icon
    end

    if missing_deck_icon then
        return nil
    end

    if not love.filesystem.getInfo(DECK_ICON_PATH, "file") then
        missing_deck_icon = true
        return nil
    end

    local ok, image = pcall(image_loader.newImage, DECK_ICON_PATH)

    if not ok then
        print("Unable to load deck icon '" .. DECK_ICON_PATH .. "': " .. tostring(image))
        missing_deck_icon = true
        return nil
    end

    deck_icon = image

    return deck_icon
end

local function getTreeIcon()
    if tree_icon then
        return tree_icon
    end

    if missing_tree_icon then
        return nil
    end

    if not love.filesystem.getInfo(TREE_ICON_PATH, "file") then
        missing_tree_icon = true
        return nil
    end

    local ok, image = pcall(image_loader.newImage, TREE_ICON_PATH)

    if not ok then
        print("Unable to load tree icon '" .. TREE_ICON_PATH .. "': " .. tostring(image))
        missing_tree_icon = true
        return nil
    end

    tree_icon = image

    return tree_icon
end

local function getEquipImage(item)
    if not item or not item.image_path then
        return nil
    end

    if equip_images[item.image_path] then
        return equip_images[item.image_path]
    end

    if missing_equip_images[item.image_path] then
        return nil
    end

    if not love.filesystem.getInfo(item.image_path, "file") then
        missing_equip_images[item.image_path] = true
        return nil
    end

    local ok, image = pcall(image_loader.newImage, item.image_path)

    if not ok then
        print("Unable to load equipment image '" .. item.image_path .. "': " .. tostring(image))
        missing_equip_images[item.image_path] = true
        return nil
    end

    equip_images[item.image_path] = image

    return image
end

local function getBaseStat(unit, stat_id)
    for _, stat in ipairs(unit and unit.stats or {}) do
        if stat[stat_id] ~= nil then
            return math.floor(fate_logic.getScaledStatValue(unit, stat_id, stat[stat_id]))
        end
    end

    return 0
end

local function getModalStatLabelRects(layout)
    local stat_ids = { "strength", "agility", "lex" }
    local total_w = #stat_ids * MODAL_STAT_LABEL_W + (#stat_ids - 1) * MODAL_STAT_LABEL_GAP
    local start_x = layout.slot_x + (layout.slot_w - total_w) / 2
    local y = layout.slot_y - MODAL_STAT_LABEL_H - MODAL_STAT_LABEL_Y_GAP
    local rects = {}

    for index, stat_id in ipairs(stat_ids) do
        local x = start_x + (index - 1) * (MODAL_STAT_LABEL_W + MODAL_STAT_LABEL_GAP)

        rects[#rects + 1] = {
            stat_id = stat_id,
            x = x,
            y = y,
            w = MODAL_STAT_LABEL_W,
            h = MODAL_STAT_LABEL_H,
        }
    end

    return rects
end

local function getModalStatButtonRects(layout)
    local label_rects = getModalStatLabelRects(layout)
    local button_y = label_rects[1].y - MODAL_STAT_BUTTON_SIZE - MODAL_STAT_BUTTON_Y_GAP
    local rects = {}

    for _, label_rect in ipairs(label_rects) do
        rects[#rects + 1] = {
            stat_id = label_rect.stat_id,
            x = label_rect.x + (label_rect.w - MODAL_STAT_BUTTON_SIZE) / 2,
            y = button_y,
            w = MODAL_STAT_BUTTON_SIZE,
            h = MODAL_STAT_BUTTON_SIZE,
        }
    end

    return rects
end

local function getModalStatPointsRect(layout)
    local button_rects = getModalStatButtonRects(layout)
    local y = button_rects[1].y - MODAL_STAT_POINTS_H - MODAL_STAT_POINTS_Y_GAP

    return {
        x = layout.slot_x + (layout.slot_w - MODAL_STAT_POINTS_W) / 2,
        y = y,
        w = MODAL_STAT_POINTS_W,
        h = MODAL_STAT_POINTS_H,
    }
end

local function getSlotSectionLayout(layout)
    local section_h = (layout.slot_h - FATE_SECTION_GAP) / 2
    local grid_w = SLOT_COLS * SLOT_BOX_W + (SLOT_COLS - 1) * SLOT_GAP_X
    local grid_h = SLOT_ROWS * (SLOT_LABEL_H + SLOT_BOX_H) + (SLOT_ROWS - 1) * SLOT_GAP_Y

    return {
        section_h = section_h,
        x = layout.slot_x,
        y = layout.slot_y,
        w = layout.slot_w,
        h = section_h,
        grid_x = layout.slot_x + (layout.slot_w - grid_w) / 2,
        grid_y = layout.slot_y + (section_h - grid_h) / 2,
    }
end

local function getEquipSlotRects(layout)
    local section = getSlotSectionLayout(layout)
    local rects = {}

    for index = 1, SLOT_COLS * SLOT_ROWS do
        local col = (index - 1) % SLOT_COLS
        local row = math.floor((index - 1) / SLOT_COLS)
        local x = section.grid_x + col * (SLOT_BOX_W + SLOT_GAP_X)
        local y = section.grid_y + row * (SLOT_LABEL_H + SLOT_BOX_H + SLOT_GAP_Y)

        rects[#rects + 1] = {
            index = index,
            label_x = x,
            label_y = y,
            x = x,
            y = y + SLOT_LABEL_H,
            w = SLOT_BOX_W,
            h = SLOT_BOX_H,
        }
    end

    return rects
end

local function getInventoryLayout(layout)
    local section_h = (layout.slot_h - FATE_SECTION_GAP) / 2
    local lower_section_x = layout.slot_x
    local lower_section_y = layout.slot_y + section_h + FATE_SECTION_GAP
    local available_w = layout.slot_w - INVENTORY_PAD * 2
    local available_h = section_h - INVENTORY_PAD * 2
    local cell_size = math.floor(math.min(
        (available_w - (INVENTORY_COLS - 1) * INVENTORY_GAP) / INVENTORY_COLS,
        (available_h - (INVENTORY_ROWS - 1) * INVENTORY_GAP) / INVENTORY_ROWS
    ))
    local grid_w = INVENTORY_COLS * cell_size + (INVENTORY_COLS - 1) * INVENTORY_GAP
    local grid_h = INVENTORY_ROWS * cell_size + (INVENTORY_ROWS - 1) * INVENTORY_GAP

    return {
        section_x = lower_section_x,
        section_y = lower_section_y,
        section_w = layout.slot_w,
        section_h = section_h,
        cell_size = cell_size,
        x = lower_section_x + (layout.slot_w - grid_w) / 2,
        y = lower_section_y + (section_h - grid_h) / 2,
        w = grid_w,
        h = grid_h,
    }
end

local function getInventoryCellAtPoint(layout, x, y)
    local inventory = getInventoryLayout(layout)

    for row = 1, INVENTORY_ROWS do
        for col = 1, INVENTORY_COLS do
            local cell_x = inventory.x + (col - 1) * (inventory.cell_size + INVENTORY_GAP)
            local cell_y = inventory.y + (row - 1) * (inventory.cell_size + INVENTORY_GAP)

            if pointInRect(x, y, cell_x, cell_y, inventory.cell_size, inventory.cell_size) then
                return col, row
            end
        end
    end

    return nil, nil
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

local function hexToColor(hex, alpha)
    if type(hex) ~= "string" or #hex < 6 then
        return 1, 1, 1, alpha or 1
    end

    return tonumber(hex:sub(1, 2), 16) / 255,
        tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255,
        alpha or 1
end

local function buildCircleSegmentPoints(center_x, center_y, radius, start_angle, end_angle)
    local points = { center_x, center_y }
    local steps = math.max(4, math.ceil(BURN_CLOCK_CIRCLE_SEGMENTS / BURN_CLOCK_SEGMENTS))

    for index = 0, steps do
        local angle = start_angle + (end_angle - start_angle) * index / steps

        points[#points + 1] = center_x + math.cos(angle) * radius
        points[#points + 1] = center_y + math.sin(angle) * radius
    end

    return points
end

local function drawPortrait(unit, kind)
    local image = kind == "hazard" and map_tiles.getHazardPortrait(unit)
        or kind == "enemy" and map_tiles.getEnemyPortrait(unit)
        or map_tiles.getAgentPortrait(unit)
    local center_x = PORTRAIT_BOX_X + PORTRAIT_BOX_SIZE / 2
    local center_y = PORTRAIT_BOX_Y + PORTRAIT_BOX_SIZE / 2
    local points = buildHexPoints(center_x, center_y, PORTRAIT_RADIUS)
    local outline_color = kind == "enemy" and ENEMY_OUTLINE_COLOR
        or kind == "hazard" and { 0.9765, 0.6314, 0, 1 }
        or OUTLINE_COLOR

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

local function drawAgentLevelBadge(agent)
    local level_text = tostring(XP_levels.getLevel(agent))
    local font = love.graphics.getFont()
    local x = PORTRAIT_BOX_X
    local y = PORTRAIT_BOX_Y
    local has_unspent_points = XP_levels.getStatPoints(agent) > 0 or XP_levels.getSkillPoints(agent) > 0
    local scale = 1

    if has_unspent_points then
        scale = 1 + math.sin(love.timer.getTime() * LEVEL_BADGE_PULSE_SPEED) * LEVEL_BADGE_PULSE_SCALE
    end

    local size = LEVEL_BADGE_SIZE * scale
    local draw_x = x + (LEVEL_BADGE_SIZE - size) / 2
    local draw_y = y + (LEVEL_BADGE_SIZE - size) / 2

    if has_unspent_points then
        love.graphics.setColor(XP_COLOR)
        love.graphics.rectangle("fill", draw_x, draw_y, size, size)
        love.graphics.setColor(0, 0, 0, 1)
    else
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.rectangle("fill", draw_x, draw_y, size, size)
        love.graphics.setColor(XP_COLOR)
        love.graphics.setLineWidth(LEVEL_BADGE_OUTLINE_W)
        love.graphics.rectangle("line", draw_x, draw_y, size, size)
        love.graphics.setLineWidth(1)
    end

    love.graphics.print(
        level_text,
        draw_x + (size - font:getWidth(level_text)) / 2,
        draw_y + (size - font:getHeight()) / 2
    )
end

local function drawAgentXpGauge(agent)
    if XP_levels.isMaxLevel(agent) then
        return
    end

    local xp = XP_levels.getXp(agent)
    local needed = math.max(1, XP_levels.getXpToNext(agent))
    local fill_w = math.min(XP_GAUGE_W, XP_GAUGE_W * xp / needed)
    local text = tostring(xp)
    local font = love.graphics.getFont()
    local text_x = XP_GAUGE_X + (XP_GAUGE_W - font:getWidth(text)) / 2
    local text_y = XP_GAUGE_Y + (XP_GAUGE_H - font:getHeight()) / 2
    local text_color = text_x <= XP_GAUGE_X + fill_w and { 0, 0, 0, 1 } or XP_COLOR

    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", XP_GAUGE_X, XP_GAUGE_Y, XP_GAUGE_W, XP_GAUGE_H)

    if fill_w > 0 then
        love.graphics.setColor(XP_COLOR)
        love.graphics.rectangle("fill", XP_GAUGE_X, XP_GAUGE_Y, fill_w, XP_GAUGE_H)
    end

    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.setLineWidth(XP_GAUGE_OUTLINE_W)
    love.graphics.rectangle("line", XP_GAUGE_X, XP_GAUGE_Y, XP_GAUGE_W, XP_GAUGE_H)
    love.graphics.setLineWidth(1)

    love.graphics.setColor(text_color)
    love.graphics.print(text, text_x, text_y)
end

local function drawBurnClock(agent)
    local center_x = BURN_CLOCK_X + BURN_CLOCK_SIZE / 2
    local center_y = BURN_CLOCK_Y + BURN_CLOCK_SIZE / 2
    local previous_line_width = love.graphics.getLineWidth()
    local previous_font = love.graphics.getFont()
    local burn_level = math.max(0, math.floor(tonumber(agent and agent.burn_level) or 0))
    local filled_segments = math.max(0, math.min(BURN_CLOCK_SEGMENTS, burn_level))

    if not burn_clock_font then
        burn_clock_font = love.graphics.newFont("assets/fonts/Furore.otf", BURN_CLOCK_FONT_SIZE)
    end

    love.graphics.setColor(PANEL_COLOR)
    love.graphics.rectangle("fill", BURN_CLOCK_X, BURN_CLOCK_Y, BURN_CLOCK_SIZE, BURN_CLOCK_SIZE)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.circle("fill", center_x, center_y, BURN_CLOCK_OUTER_RADIUS, BURN_CLOCK_CIRCLE_SEGMENTS)

    for index = 1, filled_segments do
        local start_angle = math.rad(-90 + (index - 1) * 360 / BURN_CLOCK_SEGMENTS)
        local end_angle = math.rad(-90 + index * 360 / BURN_CLOCK_SEGMENTS)
        local palette_index = index + 1

        love.graphics.setColor(hexToColor(burn_palette["burn" .. tostring(palette_index)], 1))
        love.graphics.polygon("fill", buildCircleSegmentPoints(center_x, center_y, BURN_CLOCK_OUTER_RADIUS, start_angle, end_angle))
    end

    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.setLineWidth(4)

    for index = 0, BURN_CLOCK_SEGMENTS - 1 do
        local angle = math.rad(-90 + index * 360 / BURN_CLOCK_SEGMENTS)
        love.graphics.line(
            center_x,
            center_y,
            center_x + math.cos(angle) * BURN_CLOCK_OUTER_RADIUS,
            center_y + math.sin(angle) * BURN_CLOCK_OUTER_RADIUS
        )
    end

    love.graphics.circle("fill", center_x, center_y, BURN_CLOCK_CENTER_RADIUS, BURN_CLOCK_CIRCLE_SEGMENTS)

    love.graphics.setColor(TEXT_COLOR)
    love.graphics.setFont(burn_clock_font)
    local font = burn_clock_font
    local text = "Burn"
    love.graphics.print(
        text,
        center_x - font:getWidth(text) / 2,
        center_y - font:getHeight() / 2
    )

    love.graphics.setFont(previous_font)
    love.graphics.setLineWidth(previous_line_width)
end

local function drawBlockInline(block_value, value_x, y)
    local previous_font = love.graphics.getFont()
    local number_text = tostring(math.max(0, math.floor(tonumber(block_value) or 0)))
    local number_w = previous_font:getWidth(number_text)

    if not block_icon_font then
        block_icon_font = love.graphics.newFont("assets/fonts/icons.otf", BLOCK_ICON_FONT_SIZE)
    end

    local icon_w = block_icon_font:getWidth(BLOCK_GLYPH)
    local block_w = icon_w + 5 + number_w
    local block_x = value_x - block_w - 18

    love.graphics.setColor(BLOCK_COLOR)
    love.graphics.setFont(block_icon_font)
    love.graphics.print(BLOCK_GLYPH, block_x, y - 1)
    love.graphics.setFont(previous_font)
    love.graphics.print(number_text, block_x + icon_w + 5, y)
end

local function drawStatValue(label, stat, color, index, pending_cost, stat_y, block_value, stat_x, stat_w)
    local current = math.floor(tonumber(stat and stat.current) or 0)
    local maximum = math.floor(tonumber(stat and stat.maximum) or 0)
    stat_x = stat_x or STAT_X
    stat_w = stat_w or CONTENT_W

    local y = (stat_y or STAT_Y) + (index - 1) * STAT_ROW_H
    local value_text = (label == "ATK" or label == "SPD" or label == "RNG")
        and tostring(current)
        or ("%d / %d"):format(current, maximum)
    local font = love.graphics.getFont()
    local value_w = font:getWidth(value_text)
    local value_x = stat_x + stat_w - value_w

    love.graphics.setColor(TEXT_COLOR)
    love.graphics.print(label, stat_x, y)

    if label == "HP" and (tonumber(block_value) or 0) > 0 then
        drawBlockInline(block_value or 0, value_x, y)
    end

    if pending_cost and pending_cost > 0 then
        local cost_text = "-" .. tostring(pending_cost)
        local cost_w = font:getWidth(cost_text)

        love.graphics.setColor(color)
        love.graphics.print(cost_text, value_x - cost_w - 14, y)
    end

    love.graphics.setColor(color)
    love.graphics.print(value_text, value_x, y)
end

local function getRuntimeStatSnapshot(unit, stat_id)
    local stat = unit and unit.runtime_stats and unit.runtime_stats[stat_id]

    if stat then
        return stat
    end

    local value = getBaseStat(unit, stat_id)

    return {
        current = value,
        maximum = value,
    }
end

local function getUnitPanelStats(unit, kind)
    if kind == "enemy" then
        return {
            hp = getRuntimeStatSnapshot(unit, "hp"),
            atk = getRuntimeStatSnapshot(unit, "atk"),
            spd = getRuntimeStatSnapshot(unit, "spd"),
            rng = getRuntimeStatSnapshot(unit, "rng"),
        }
    end

    if kind == "hazard" then
        return {
            hp = getRuntimeStatSnapshot(unit, "hp"),
            bp = getRuntimeStatSnapshot(unit, "bp"),
            atk = getRuntimeStatSnapshot(unit, "atk"),
            rng = getRuntimeStatSnapshot(unit, "rng"),
        }
    end

    return {
        ap = getRuntimeStatSnapshot(unit, "ap"),
        hp = getRuntimeStatSnapshot(unit, "hp"),
        lp = getRuntimeStatSnapshot(unit, "lp"),
    }
end

local function drawUnitInfoPanel(unit, kind, stats, pending_ap_cost, pending_lp_cost)
    if not unit then
        return
    end

    kind = kind or "agent"
    stats = stats or getUnitPanelStats(unit, kind)

    local block_value = block_logic.getBlock(unit)
    local stat_order = kind == "door" and DOOR_STAT_ORDER
        or kind == "hazard" and HAZARD_STAT_ORDER
        or kind == "enemy" and ENEMY_STAT_ORDER
        or AGENT_STAT_ORDER
    local fallback_label = kind == "door" and "Door" or kind == "hazard" and "Hazard" or kind == "enemy" and "Enemy" or "Agent"
    local stat_y = (kind == "enemy" or kind == "hazard") and ENEMY_STAT_Y or STAT_Y
    local content_x = kind == "door" and PANEL_X + PANEL_PAD or CONTENT_X
    local content_w = kind == "door" and PANEL_W - PANEL_PAD * 2 or CONTENT_W

    love.graphics.setColor(PANEL_COLOR)
    love.graphics.rectangle("fill", PANEL_X, PANEL_Y, PANEL_W, PANEL_H)

    if kind ~= "door" then
        drawPortrait(unit, kind)
    end

    if kind == "agent" then
        drawBurnClock(unit)
        drawAgentLevelBadge(unit)
        drawAgentXpGauge(unit)
    end

    love.graphics.setColor(TEXT_COLOR)
    love.graphics.print(unit.name or unit.id or fallback_label, content_x, CONTENT_Y)

    for index, stat in ipairs(stat_order) do
        drawStatValue(
            stat.label,
            stats[stat.id],
            STAT_COLORS[stat.id],
            index,
            stat.id == "ap" and pending_ap_cost or stat.id == "lp" and pending_lp_cost or nil,
            stat_y,
            kind ~= "door" and stat.id == "hp" and block_value or nil,
            content_x,
            content_w
        )
    end

    love.graphics.setColor(1, 1, 1, 1)
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

local function drawFullImageWindow(unit, kind, layout, dim_image)
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
        if dim_image then
            love.graphics.setColor(0, 0, 0, 0.58)
            love.graphics.rectangle("fill", layout.image_x, layout.image_y, layout.image_w, layout.image_h)
        end
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

    if dim_image then
        love.graphics.setColor(0, 0, 0, 0.58)
        love.graphics.rectangle("fill", layout.image_x, layout.image_y, layout.image_w, layout.image_h)
    end
end

local function getDeckButtonRect(layout)
    return {
        x = layout.image_x - DECK_BUTTON_GAP - DECK_BUTTON_SIZE,
        y = layout.image_y + (layout.image_h - DECK_BUTTON_SIZE) / 2,
        w = DECK_BUTTON_SIZE,
        h = DECK_BUTTON_SIZE,
    }
end

local function getTreeButtonRect(layout)
    local deck_rect = getDeckButtonRect(layout)
    return {
        x = deck_rect.x,
        y = deck_rect.y - DECK_BUTTON_GAP - DECK_BUTTON_SIZE,
        w = DECK_BUTTON_SIZE,
        h = DECK_BUTTON_SIZE,
    }
end

local function drawIconButton(rect, icon)
    love.graphics.setColor(MODAL_FILL_COLOR)
    love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
    love.graphics.setColor(MODAL_BORDER_COLOR)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h)
    love.graphics.setLineWidth(1)

    if not icon then
        return
    end

    local icon_size = rect.w - DECK_BUTTON_ICON_PAD * 2
    local scale = math.min(icon_size / icon:getWidth(), icon_size / icon:getHeight())

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(
        icon,
        rect.x + rect.w / 2,
        rect.y + rect.h / 2,
        0,
        scale,
        scale,
        icon:getWidth() / 2,
        icon:getHeight() / 2
    )
end

local function drawDeckButton(layout)
    drawIconButton(getDeckButtonRect(layout), getDeckIcon())
end

local function drawButtonBracketPulse(rect)
    local pulse = 1 + math.sin(love.timer.getTime() * TREE_BUTTON_BRACKET_PULSE_SPEED) * TREE_BUTTON_BRACKET_PULSE_SCALE
    local base_size = math.max(rect.w, rect.h) + TREE_BUTTON_BRACKET_PAD * 2
    local size = base_size * pulse
    local x = rect.x + rect.w / 2 - size / 2
    local y = rect.y + rect.h / 2 - size / 2
    local right = x + size
    local bottom = y + size
    local len = TREE_BUTTON_BRACKET_LEN

    love.graphics.setColor(XP_COLOR)
    love.graphics.setLineWidth(3)
    love.graphics.line(x, y, x + len, y)
    love.graphics.line(x, y, x, y + len)
    love.graphics.line(right, y, right - len, y)
    love.graphics.line(right, y, right, y + len)
    love.graphics.line(x, bottom, x + len, bottom)
    love.graphics.line(x, bottom, x, bottom - len)
    love.graphics.line(right, bottom, right - len, bottom)
    love.graphics.line(right, bottom, right, bottom - len)
    love.graphics.setLineWidth(1)
end

local function drawTreeButton(layout, agent)
    local rect = getTreeButtonRect(layout)

    drawIconButton(rect, getTreeIcon())

    if XP_levels.getSkillPoints(agent) > 0 then
        drawButtonBracketPulse(rect)
    end
end

local function drawModalAgentStatLabels(agent, layout)
    local labels = {
        ("STR %d"):format(getBaseStat(agent, "strength")),
        ("AGI %d"):format(getBaseStat(agent, "agility")),
        ("LEX %d"):format(getBaseStat(agent, "lex")),
    }
    local label_rects = getModalStatLabelRects(layout)
    local stat_points = XP_levels.getStatPoints(agent)

    if stat_points > 0 then
        local points_rect = getModalStatPointsRect(layout)
        local button_rects = getModalStatButtonRects(layout)

        love.graphics.setColor(XP_COLOR)
        love.graphics.rectangle("fill", points_rect.x, points_rect.y, points_rect.w, points_rect.h)
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.printf(
            tostring(stat_points),
            points_rect.x + 4,
            points_rect.y + 3,
            points_rect.w - 8,
            "center"
        )

        for _, rect in ipairs(button_rects) do
            love.graphics.setColor(XP_COLOR)
            love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
            love.graphics.setColor(0, 0, 0, 1)
            love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h)
            love.graphics.printf("+", rect.x, rect.y + 3, rect.w, "center")
        end
    end

    for index, label in ipairs(labels) do
        local rect = label_rects[index]

        love.graphics.setColor(MODAL_FILL_COLOR)
        love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
        love.graphics.setColor(MODAL_BORDER_COLOR)
        love.graphics.setLineWidth(MODAL_STAT_LABEL_OUTLINE_W)
        love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(TEXT_COLOR)
        love.graphics.printf(label, rect.x + 4, rect.y + 5, rect.w - 8, "center")
    end
end

local function drawEquipmentItem(item, x, y, w, h, alpha)
    local image = not luggage.isLuggage(item) and getEquipImage(item) or nil

    love.graphics.setColor(0.015, 0.014, 0.012, alpha or 1)
    love.graphics.rectangle("fill", x, y, w, h)

    if luggage.draw(item, x, y, w, h, {
        alpha = alpha or 1,
        font = love.graphics.getFont(),
    }) then
        -- Luggage uses a generated inventory-footprint grid instead of image art.
    elseif image then
        local scale = math.min(w / image:getWidth(), h / image:getHeight())

        love.graphics.setColor(1, 1, 1, alpha or 1)
        love.graphics.draw(
            image,
            x + w / 2,
            y + h / 2,
            0,
            scale,
            scale,
            image:getWidth() / 2,
            image:getHeight() / 2
        )
    else
        love.graphics.setColor(1, 1, 1, alpha or 1)
        love.graphics.printf(item and item.id or "", x + 2, y + h / 2 - 8, w - 4, "center")
    end

    love.graphics.setColor(MODAL_BORDER_COLOR[1], MODAL_BORDER_COLOR[2], MODAL_BORDER_COLOR[3], alpha or 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, w, h)
    love.graphics.setLineWidth(1)
end

local function getStatRequirementText(requirement)
    local stat = tostring(requirement.stat or ""):upper()

    return ("Requires %s %d"):format(stat, math.floor(tonumber(requirement.value) or 0))
end

local function getEquipmentPreviewLayout(layout)
    local panel_w = layout.image_w - EQUIP_PREVIEW_PAD * 4
    local panel_h = layout.image_h - EQUIP_PREVIEW_PAD * 4
    local panel_x = layout.image_x + (layout.image_w - panel_w) / 2
    local panel_y = layout.image_y + (layout.image_h - panel_h) / 2

    return {
        x = panel_x,
        y = panel_y,
        w = panel_w,
        h = panel_h,
        content_x = panel_x + EQUIP_PREVIEW_PAD,
        content_y = panel_y + EQUIP_PREVIEW_PAD,
        content_w = panel_w - EQUIP_PREVIEW_PAD * 2,
    }
end

local function getEquipmentPreviewLexRow(item, preview)
    local cards = equip_logic.getLexDeckDefinitionCards(item)
    local y = preview.content_y + EQUIP_PREVIEW_HEADER_H + EQUIP_PREVIEW_ROW_GAP
        + EQUIP_PREVIEW_IMAGE_SIZE + EQUIP_PREVIEW_ROW_GAP

    if item.stat_req and #item.stat_req > 0 then
        y = y + #item.stat_req * 22 + EQUIP_PREVIEW_ROW_GAP
    end

    if #cards == 0 then
        return {
            cards = cards,
            x = preview.content_x,
            y = y,
            w = preview.content_w,
            h = 0,
            visible_count = 0,
            start_x = preview.content_x,
        }
    end

    local w = preview.content_w
    local max_cols = math.max(1, math.floor((w + EQUIP_PREVIEW_THUMB_GAP) / (EQUIP_PREVIEW_THUMB_W + EQUIP_PREVIEW_THUMB_GAP)))
    local visible_count = math.min(#cards, max_cols)
    local row_w = visible_count * EQUIP_PREVIEW_THUMB_W + (visible_count - 1) * EQUIP_PREVIEW_THUMB_GAP

    return {
        cards = cards,
        x = preview.content_x,
        y = y,
        w = w,
        h = EQUIP_PREVIEW_THUMB_H,
        visible_count = visible_count,
        start_x = preview.content_x + (w - row_w) / 2,
    }
end

local function getEquipmentPreviewLexCardAt(item, layout, mouse_x, mouse_y)
    if not item then
        return nil
    end

    local row = getEquipmentPreviewLexRow(item, getEquipmentPreviewLayout(layout))

    if row.visible_count == 0
        or mouse_x < row.x
        or mouse_x > row.x + row.w
        or mouse_y < row.y
        or mouse_y > row.y + row.h
    then
        return nil
    end

    for index = 1, row.visible_count do
        local thumb_x = row.start_x + (index - 1) * (EQUIP_PREVIEW_THUMB_W + EQUIP_PREVIEW_THUMB_GAP)

        if mouse_x >= thumb_x and mouse_x <= thumb_x + EQUIP_PREVIEW_THUMB_W then
            return row.cards[index]
        end
    end

    return nil
end

local function drawEquipmentPreviewLexRow(item, preview)
    local row = getEquipmentPreviewLexRow(item, preview)

    if row.visible_count == 0 then
        return
    end

    for index = 1, row.visible_count do
        local thumb_x = row.start_x + (index - 1) * (EQUIP_PREVIEW_THUMB_W + EQUIP_PREVIEW_THUMB_GAP)

        love.graphics.setColor(0.035, 0.032, 0.028, 1)
        love.graphics.rectangle("fill", thumb_x, row.y, EQUIP_PREVIEW_THUMB_W, EQUIP_PREVIEW_THUMB_H)
        card_vis.drawCardPortrait(row.cards[index], thumb_x, row.y, EQUIP_PREVIEW_THUMB_W, EQUIP_PREVIEW_THUMB_H)
        love.graphics.setColor(MODAL_BORDER_COLOR)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", thumb_x, row.y, EQUIP_PREVIEW_THUMB_W, EQUIP_PREVIEW_THUMB_H)
        love.graphics.setLineWidth(1)
    end
end

local function drawEquipmentHoverPreview(item, layout)
    if not item then
        return
    end

    local preview = getEquipmentPreviewLayout(layout)
    local previous_font = love.graphics.getFont()
    local image = not luggage.isLuggage(item) and getEquipImage(item) or nil
    local content_x = preview.content_x
    local content_w = preview.content_w
    local cursor_y = preview.content_y

    love.graphics.setColor(MODAL_FILL_COLOR)
    love.graphics.rectangle("fill", preview.x, preview.y, preview.w, preview.h)
    love.graphics.setColor(MODAL_BORDER_COLOR)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", preview.x, preview.y, preview.w, preview.h)
    love.graphics.setLineWidth(1)

    love.graphics.setColor(TEXT_COLOR)
    love.graphics.printf(item.name or item.id or "Equipment", content_x, cursor_y + 5, content_w, "center")
    cursor_y = cursor_y + EQUIP_PREVIEW_HEADER_H + EQUIP_PREVIEW_ROW_GAP

    local image_x = content_x + (content_w - EQUIP_PREVIEW_IMAGE_SIZE) / 2

    love.graphics.setColor(0.015, 0.014, 0.012, 1)
    love.graphics.rectangle("fill", image_x, cursor_y, EQUIP_PREVIEW_IMAGE_SIZE, EQUIP_PREVIEW_IMAGE_SIZE)
    love.graphics.setColor(MODAL_BORDER_COLOR)
    love.graphics.rectangle("line", image_x, cursor_y, EQUIP_PREVIEW_IMAGE_SIZE, EQUIP_PREVIEW_IMAGE_SIZE)

    if luggage.draw(item, image_x, cursor_y, EQUIP_PREVIEW_IMAGE_SIZE, EQUIP_PREVIEW_IMAGE_SIZE, {
        font = previous_font,
    }) then
        -- Luggage uses a generated inventory-footprint grid instead of image art.
    elseif image then
        local scale = math.min(EQUIP_PREVIEW_IMAGE_SIZE / image:getWidth(), EQUIP_PREVIEW_IMAGE_SIZE / image:getHeight())

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(
            image,
            image_x + EQUIP_PREVIEW_IMAGE_SIZE / 2,
            cursor_y + EQUIP_PREVIEW_IMAGE_SIZE / 2,
            0,
            scale,
            scale,
            image:getWidth() / 2,
            image:getHeight() / 2
        )
    end

    cursor_y = cursor_y + EQUIP_PREVIEW_IMAGE_SIZE + EQUIP_PREVIEW_ROW_GAP

    if item.stat_req and #item.stat_req > 0 then
        for _, requirement in ipairs(item.stat_req) do
            love.graphics.setColor(TEXT_COLOR)
            love.graphics.printf(getStatRequirementText(requirement), content_x, cursor_y, content_w, "center")
            cursor_y = cursor_y + 22
        end

        cursor_y = cursor_y + EQUIP_PREVIEW_ROW_GAP
    end

    drawEquipmentPreviewLexRow(item, preview)

    love.graphics.setFont(previous_font)
end

local function drawEquipmentLexCardPreview(card, layout, agent)
    if not card then
        return
    end

    local card_w = card_vis.getCardWidth()
    local card_h = card_vis.getCardHeight(card)
    local right_x = layout.slot_x
    local right_w = layout.slot_w + MODAL_GAP + layout.deck_w
    local scale = math.min(1.1, (layout.image_h - EQUIP_PREVIEW_PAD * 2) / card_h)
    local x = right_x + (right_w - card_w * scale) / 2
    local y = layout.image_y + (layout.image_h - card_h * scale) / 2

    card_vis.drawScaledCard(card, x, y, scale, { unit = agent })
end

local function getInventoryItemRect(item, inventory)
    local col = item.inv_col or 1
    local row = item.inv_row or 1

    return {
        x = inventory.x + (col - 1) * (inventory.cell_size + INVENTORY_GAP),
        y = inventory.y + (row - 1) * (inventory.cell_size + INVENTORY_GAP),
        w = item.inv_w * inventory.cell_size + (item.inv_w - 1) * INVENTORY_GAP,
        h = item.inv_h * inventory.cell_size + (item.inv_h - 1) * INVENTORY_GAP,
    }
end

local function isDraggedItem(item)
    return equip_drag and equip_drag.item == item
end

local function drawEquipmentDragHighlights(agent, layout, external_item)
    if not external_item and (not equip_drag or equip_drag.agent ~= agent) then
        return
    end

    local item = external_item or equip_drag.item

    for _, rect in ipairs(getEquipSlotRects(layout)) do
        if equip_logic.canPlaceInSlot(agent, item, rect.index) then
            love.graphics.setColor(EQUIP_VALID_COLOR[1], EQUIP_VALID_COLOR[2], EQUIP_VALID_COLOR[3], 0.18)
            love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
            love.graphics.setColor(EQUIP_VALID_COLOR)
            love.graphics.setLineWidth(3)
            love.graphics.rectangle("line", rect.x + 2, rect.y + 2, rect.w - 4, rect.h - 4)
            love.graphics.setLineWidth(1)
        end
    end
end

local function drawEquipmentInventoryGhost(agent, layout, external_item)
    if not external_item and (not equip_drag or equip_drag.agent ~= agent) then
        return
    end

    local mouse_x, mouse_y = love.mouse.getPosition()
    local col, row = getInventoryCellAtPoint(layout, mouse_x, mouse_y)

    if not col or not row then
        return
    end

    local inventory = getInventoryLayout(layout)
    local item = external_item or equip_drag.item
    local valid = equip_logic.canPlaceInInventory(agent, item, col, row, item)
    local color = valid and EQUIP_GHOST_VALID_COLOR or EQUIP_GHOST_INVALID_COLOR
    local rect = {
        x = inventory.x + (col - 1) * (inventory.cell_size + INVENTORY_GAP),
        y = inventory.y + (row - 1) * (inventory.cell_size + INVENTORY_GAP),
        w = item.inv_w * inventory.cell_size + (item.inv_w - 1) * INVENTORY_GAP,
        h = item.inv_h * inventory.cell_size + (item.inv_h - 1) * INVENTORY_GAP,
    }

    love.graphics.setColor(color[1], color[2], color[3], 0.24)
    love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
    love.graphics.setColor(color[1], color[2], color[3], 0.92)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h)
    love.graphics.setLineWidth(1)
end

local function drawEquipment(agent, layout)
    local slots = equip_logic.getSlots(agent)
    local slot_rects = getEquipSlotRects(layout)
    local inventory = getInventoryLayout(layout)

    for _, rect in ipairs(slot_rects) do
        local item = slots[rect.index]

        if item and not isDraggedItem(item) then
            drawEquipmentItem(item, rect.x + 4, rect.y + 4, rect.w - 8, rect.h - 8, 1)
        end
    end

    for _, item in ipairs(equip_logic.getInventory(agent)) do
        if not isDraggedItem(item) then
            local rect = getInventoryItemRect(item, inventory)
            drawEquipmentItem(item, rect.x, rect.y, rect.w, rect.h, 1)
        end
    end
end

local function findEquipmentAtPoint(agent, layout, x, y)
    local slots = equip_logic.getSlots(agent)
    local slot_rects = getEquipSlotRects(layout)

    for _, rect in ipairs(slot_rects) do
        local item = slots[rect.index]

        if item and pointInRect(x, y, rect.x, rect.y, rect.w, rect.h) then
            return item
        end
    end

    local inventory = getInventoryLayout(layout)
    local items = equip_logic.getInventory(agent)

    for index = #items, 1, -1 do
        local item = items[index]
        local rect = getInventoryItemRect(item, inventory)

        if pointInRect(x, y, rect.x, rect.y, rect.w, rect.h) then
            return item
        end
    end

    return nil
end

local function drawDraggedEquipment()
    if not equip_drag then
        return
    end

    local mouse_x, mouse_y = love.mouse.getPosition()
    local w = equip_drag.w or SLOT_BOX_W
    local h = equip_drag.h or SLOT_BOX_H

    drawEquipmentItem(equip_drag.item, mouse_x - w / 2, mouse_y - h / 2, w, h, 0.88)
end

local function drawSlotWindow(agent, layout)
    local section_h = (layout.slot_h - FATE_SECTION_GAP) / 2
    local slot_section_x = layout.slot_x
    local slot_section_y = layout.slot_y
    local lower_section_x = layout.slot_x
    local lower_section_y = layout.slot_y + section_h + FATE_SECTION_GAP
    local slot_rects = getEquipSlotRects(layout)
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

    drawModalAgentStatLabels(agent, layout)

    for _, rect in ipairs(slot_rects) do
        local slot_name = (agent.slots and agent.slots[rect.index]) or ""

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("fill", rect.label_x, rect.label_y, SLOT_BOX_W, SLOT_LABEL_H)
        love.graphics.rectangle("line", rect.label_x, rect.label_y, SLOT_BOX_W, SLOT_LABEL_H)
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.printf(slot_name, rect.label_x + 2, rect.label_y + 6, SLOT_BOX_W - 4, "center")

        love.graphics.setColor(0.04, 0.038, 0.034, 1)
        love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
        love.graphics.setColor(MODAL_BORDER_COLOR)
        love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h)
    end

    love.graphics.setFont(previous_font)

    local inventory = getInventoryLayout(layout)

    for row = 0, INVENTORY_ROWS - 1 do
        for col = 0, INVENTORY_COLS - 1 do
            local x = inventory.x + col * (inventory.cell_size + INVENTORY_GAP)
            local y = inventory.y + row * (inventory.cell_size + INVENTORY_GAP)

            love.graphics.setColor(0.04, 0.038, 0.034, 1)
            love.graphics.rectangle("fill", x, y, inventory.cell_size, inventory.cell_size)
            love.graphics.setColor(MODAL_BORDER_COLOR)
            love.graphics.rectangle("line", x, y, inventory.cell_size, inventory.cell_size)
        end
    end

    drawEquipmentDragHighlights(agent, layout)
    drawEquipmentInventoryGhost(agent, layout)
    drawEquipment(agent, layout)
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

    if action_deck_viewer.isOpen() then
        action_deck_viewer.draw()
        return
    end

    local layout = (modal_kind == "enemy" or modal_kind == "hazard") and getEnemyModalLayout() or getModalLayout()
    local hovered_equipment = nil
    local preview_equipment = nil
    local hovered_preview_card = nil

    if modal_kind ~= "enemy" and modal_kind ~= "hazard" and layout.slot_x and not equip_drag then
        local mouse_x, mouse_y = love.mouse.getPosition()

        hovered_equipment = findEquipmentAtPoint(modal_unit, layout, mouse_x, mouse_y)
        preview_equipment = pinned_equipment or hovered_equipment
        hovered_preview_card = getEquipmentPreviewLexCardAt(preview_equipment, layout, mouse_x, mouse_y)
    else
        preview_equipment = nil
    end

    local preview_card_key = hovered_preview_card and (hovered_preview_card.id or hovered_preview_card.name) or nil

    if preview_card_key ~= hovered_preview_card_key then
        hovered_preview_card_key = preview_card_key

        if preview_card_key then
            sfx_logic.playNamed("cardhover")
        end
    end

    love.graphics.setColor(MODAL_BACKDROP_COLOR)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())

    drawFullImageWindow(modal_unit, modal_kind, layout, preview_equipment ~= nil)

    if modal_kind ~= "enemy" and modal_kind ~= "hazard" then
        if modal_unit.skill_trees then
            drawTreeButton(layout, modal_unit)
        end

        drawDeckButton(layout)
        drawSlotWindow(modal_unit, layout)
        drawEquipmentHoverPreview(preview_equipment, layout)
    end

    drawFateDeckWindow(modal_unit, layout)
    drawEquipmentLexCardPreview(hovered_preview_card, layout, modal_unit)
    drawDraggedEquipment()

    love.graphics.setColor(1, 1, 1, 1)
end

function agent_uix.draw()
    if modal_unit then
        drawFateModal()
        return
    end

    local unit, kind = agent_logic.getSelectedUnit()

    if not unit then
        return
    end

    local stats = agent_logic.getSelectedStats()
    local preview = agent_logic.getMovementPreview()
    local dragged_card = card_play.getDraggedCard()
    local pending_ap_cost = kind == "agent" and preview and preview.cost or nil
    local pending_lp_cost = nil

    if kind == "agent" and dragged_card then
        local card_cost = math.max(0, math.floor(tonumber(dragged_card.cost) or 0))

        if dragged_card.lexurgy then
            pending_ap_cost = nil
            pending_lp_cost = card_cost
        else
            pending_ap_cost = card_cost
        end
    end

    drawUnitInfoPanel(unit, kind, stats, pending_ap_cost, pending_lp_cost)

    if kind ~= "door" then
        drawFateModal()
    end
end

function agent_uix.drawOpenModalInfoPanel()
    if not modal_unit then
        return false
    end

    drawUnitInfoPanel(modal_unit, modal_kind or "agent")

    return true
end

function agent_uix.isDeckViewerOpen()
    return action_deck_viewer.isOpen()
end

function agent_uix.setModalOffset(y)
    modal_offset_y = tonumber(y) or 0
end

function agent_uix.setEquipmentCardDrawEnabled(enabled)
    agent_uix.equipment_card_draw_enabled = enabled ~= false
end

function agent_uix.openModal(unit, kind)
    if not unit then
        return false
    end

    modal_unit = unit
    modal_kind = kind or "agent"
    pinned_equipment = nil
    hovered_preview_card_key = nil
    action_deck_viewer.close()
    sfx_logic.playNamed("token_select")

    return true
end

function agent_uix.placeItemInOpenModalInventory(item, x, y)
    if not modal_unit or modal_kind == "enemy" or modal_kind == "hazard" then
        return false
    end

    local layout = getModalLayout()
    local col, row = getInventoryCellAtPoint(layout, x, y)

    if not col or not row then
        return false
    end

    return equip_logic.moveToInventory(modal_unit, item, col, row)
end

function agent_uix.placeItemInOpenModalSlot(item, x, y)
    if not modal_unit or modal_kind == "enemy" or modal_kind == "hazard" then
        return false
    end

    local layout = getModalLayout()

    for _, rect in ipairs(getEquipSlotRects(layout)) do
        if pointInRect(x, y, rect.x, rect.y, rect.w, rect.h) then
            return equip_logic.moveToSlot(modal_unit, item, rect.index, {
                draw_card = agent_uix.equipment_card_draw_enabled,
            })
        end
    end

    return false
end

function agent_uix.drawOpenModalInventoryGhost(item)
    if not modal_unit or modal_kind == "enemy" or modal_kind == "hazard" or not item then
        return false
    end

    drawEquipmentInventoryGhost(modal_unit, getModalLayout(), item)

    return true
end

function agent_uix.drawOpenModalSlotHighlights(item)
    if not modal_unit or modal_kind == "enemy" or modal_kind == "hazard" or not item then
        return false
    end

    drawEquipmentDragHighlights(modal_unit, getModalLayout(), item)

    return true
end

function agent_uix.takeDraggedItemForRail(accepts_item)
    if not equip_drag or not modal_unit or modal_kind == "enemy" or modal_kind == "hazard" then
        return nil
    end

    local item = equip_drag.item

    if accepts_item and not accepts_item(item) then
        return nil
    end

    equip_drag = nil

    if equip_logic.removeFromAgent(modal_unit, item) then
        pinned_equipment = nil
        hovered_preview_card_key = nil
        return item
    end

    return nil
end

function agent_uix.getDraggedEquipmentItem()
    return equip_drag and equip_drag.item or nil
end

function agent_uix.mousepressed(x, y, button)
    if modal_unit then
        if action_deck_viewer.mousepressed(x, y, button) then
            return true
        end

        if button == 2 and pinned_equipment then
            pinned_equipment = nil
            hovered_preview_card_key = nil
            return true
        end

        if button ~= 1 then
            return false
        end

        local layout = (modal_kind == "enemy" or modal_kind == "hazard") and getEnemyModalLayout() or getModalLayout()
        local in_image = pointInRect(x, y, layout.image_x, layout.image_y, layout.image_w, layout.image_h)
        local in_slot = layout.slot_x and pointInRect(x, y, layout.slot_x, layout.slot_y, layout.slot_w, layout.slot_h)
        local in_deck = pointInRect(x, y, layout.deck_x, layout.deck_y, layout.deck_w, layout.deck_h)
        local deck_button = modal_kind ~= "enemy" and modal_kind ~= "hazard" and getDeckButtonRect(layout) or nil
        local tree_button = modal_kind ~= "enemy" and modal_kind ~= "hazard" and modal_unit.skill_trees
            and getTreeButtonRect(layout) or nil
        local in_deck_button = deck_button and pointInRect(x, y, deck_button.x, deck_button.y, deck_button.w, deck_button.h)
        local in_tree_button = tree_button and pointInRect(x, y, tree_button.x, tree_button.y, tree_button.w, tree_button.h)
        local stat_button = nil
        local in_stat_controls = false
        local equipment_item = nil

        if modal_kind ~= "enemy" and modal_kind ~= "hazard" and layout.slot_x then
            local label_rect = pointInAnyRect(x, y, getModalStatLabelRects(layout))
            local points_rect = XP_levels.getStatPoints(modal_unit) > 0 and getModalStatPointsRect(layout) or nil

            stat_button = XP_levels.getStatPoints(modal_unit) > 0 and pointInAnyRect(x, y, getModalStatButtonRects(layout)) or nil
            equipment_item = findEquipmentAtPoint(modal_unit, layout, x, y)
            in_stat_controls = label_rect ~= nil
                or stat_button ~= nil
                or (points_rect and pointInRect(x, y, points_rect.x, points_rect.y, points_rect.w, points_rect.h))
        end

        if pinned_equipment and not equipment_item then
            local preview = getEquipmentPreviewLayout(layout)

            if not pointInRect(x, y, preview.x, preview.y, preview.w, preview.h) then
                pinned_equipment = nil
                hovered_preview_card_key = nil
                return true
            end
        end

        if equipment_item and equip_logic.canDragItem(equipment_item) then
            local inventory = getInventoryLayout(layout)
            local rect = equipment_item.location == "inventory" and getInventoryItemRect(equipment_item, inventory)
                or pointInAnyRect(x, y, getEquipSlotRects(layout))

            equip_drag = {
                agent = modal_unit,
                item = equipment_item,
                w = rect and rect.w or SLOT_BOX_W,
                h = rect and rect.h or SLOT_BOX_H,
                start_x = x,
                start_y = y,
            }
        elseif equipment_item then
            pinned_equipment = equipment_item
            hovered_preview_card_key = nil
        elseif stat_button then
            if XP_levels.spendStatPoint(modal_unit, stat_button.stat_id) then
                sfx_logic.playNamed("token_select")
            end
        elseif in_deck_button then
            sfx_logic.playNamed("token_select")
            action_deck_viewer.open(modal_unit)
        elseif in_tree_button then
            sfx_logic.playNamed("token_select")
            action_deck_viewer.open(modal_unit, "tree")
        elseif not in_image and not in_slot and not in_deck and not in_stat_controls then
            modal_unit = nil
            modal_kind = nil
            pinned_equipment = nil
            hovered_preview_card_key = nil
        end

        return true
    end

    if button ~= 1 then
        return false
    end

    local unit, kind = agent_logic.getSelectedUnit()

    if unit and kind ~= "door" and pointInRect(x, y, PORTRAIT_BOX_X, PORTRAIT_BOX_Y, PORTRAIT_BOX_SIZE, PORTRAIT_BOX_SIZE) then
        modal_unit = unit
        modal_kind = kind
        pinned_equipment = nil
        hovered_preview_card_key = nil
        sfx_logic.playNamed("token_select")
        return true
    end

    return false
end

function agent_uix.mousereleased(x, y, button)
    if button ~= 1 or not equip_drag then
        return false
    end

    local drag = equip_drag
    equip_drag = nil

    if not modal_unit or modal_unit ~= drag.agent or modal_kind == "enemy" or modal_kind == "hazard" then
        return true
    end

    local moved = math.sqrt((x - (drag.start_x or x)) ^ 2 + (y - (drag.start_y or y)) ^ 2)

    if moved <= EQUIP_PREVIEW_CLICK_DRAG_THRESHOLD then
        pinned_equipment = drag.item
        hovered_preview_card_key = nil
        return true
    end

    local layout = getModalLayout()

    for _, rect in ipairs(getEquipSlotRects(layout)) do
        if pointInRect(x, y, rect.x, rect.y, rect.w, rect.h) then
            if equip_logic.moveToSlot(drag.agent, drag.item, rect.index, {
                draw_card = agent_uix.equipment_card_draw_enabled,
            }) then
                sfx_logic.playNamed("equip")
            end
            return true
        end
    end

    local col, row = getInventoryCellAtPoint(layout, x, y)

    if col and row then
        if equip_logic.moveToInventory(drag.agent, drag.item, col, row) then
            sfx_logic.playNamed("cardhover")
        end
    end

    return true
end

function agent_uix.closeModal()
    equip_drag = nil
    pinned_equipment = nil
    hovered_preview_card_key = nil

    if action_deck_viewer.close() then
        return true
    end

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

function agent_uix.wheelmoved(x, y)
    return action_deck_viewer.wheelmoved(x, y)
end

return agent_uix

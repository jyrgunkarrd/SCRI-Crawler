local image_loader = require("src.assets.image_loader")
local equip_logic = require("src.sys.equip_logic")

local reward_uix = {}

local TILE_MIN_W = 132
local TILE_H = 58
local TILE_PADDING = 8
local VALUE_RIGHT_PADDING = 14
local ICON_SIZE = 42
local TILE_COLOR = { 0, 0, 0, 0.96 }
local BORDER_COLOR = { 1, 1, 1, 1 }
local VALUE_COLOR = { 0, 1, 167 / 255, 1 }
local SCRATCH_ICON_PATH = "assets/images/icons/scratch.webp"
local REWARD_ITEM_CARD_W = 154
local REWARD_ITEM_IMAGE_SIZE = 86
local REWARD_ITEM_IMAGE_PADDING = 5
local REWARD_ITEM_LABEL_GAP = 7
local REWARD_ITEM_LABEL_LINES = 2
local REWARD_ITEM_SEPARATOR_W = 54
local REWARD_ITEM_FILL_COLOR = { 0, 0, 0, 0.96 }
local REWARD_ITEM_DIM_ALPHA = 0.28
local REWARD_ITEM_X_COLOR = { 254 / 255, 0, 111 / 255, 1 }
local REWARD_ITEM_X_INSET = 8
local REWARD_ITEM_X_WIDTH = 6

local scratch_image = nil
local equipment_images = {}

local function normalizeScratch(value)
    return math.max(0, math.floor(tonumber(value) or 0))
end

local function getScratchImage()
    if not scratch_image then
        scratch_image = image_loader.newImage(SCRATCH_ICON_PATH)
    end

    return scratch_image
end

local function normalizeEquipmentId(id)
    if id == nil then
        return nil
    end

    id = tostring(id)

    if id == "" then
        return nil
    end

    return id
end

local function getEquipmentImage(id)
    id = normalizeEquipmentId(id)

    if not id then
        return nil
    elseif equipment_images[id] == false then
        return nil
    elseif equipment_images[id] then
        return equipment_images[id]
    end

    local ok, image = pcall(image_loader.newImage, ("assets/images/equip/%s.webp"):format(id))

    equipment_images[id] = ok and image or false

    return ok and image or nil
end

local function pointInRect(x, y, rect)
    return rect
        and x >= rect.x
        and x <= rect.x + rect.w
        and y >= rect.y
        and y <= rect.y + rect.h
end

local function getRewardItemName(item)
    return item and item.definition and item.definition.name
        or item and item.id
        or "UNKNOWN"
end

local function getRewardItemLabelLineCount(font, item)
    local _, lines = font:getWrap(getRewardItemName(item), REWARD_ITEM_CARD_W)

    return math.max(REWARD_ITEM_LABEL_LINES, #lines)
end

local function getRewardItemRowHeight(font, first, second)
    local line_count = REWARD_ITEM_LABEL_LINES
    local line_height = font:getHeight() * font:getLineHeight()

    if first then
        line_count = math.max(line_count, getRewardItemLabelLineCount(font, first))
    end

    if second then
        line_count = math.max(line_count, getRewardItemLabelLineCount(font, second))
    end

    return REWARD_ITEM_IMAGE_SIZE
        + REWARD_ITEM_LABEL_GAP
        + line_height * line_count
end

local function getRewardItemImageRect(center_x, y)
    return {
        x = center_x - REWARD_ITEM_IMAGE_SIZE / 2,
        y = y,
        w = REWARD_ITEM_IMAGE_SIZE,
        h = REWARD_ITEM_IMAGE_SIZE,
    }
end

local function drawRewardItemX(rect, alpha)
    local inset = REWARD_ITEM_X_INSET

    love.graphics.setColor(
        REWARD_ITEM_X_COLOR[1],
        REWARD_ITEM_X_COLOR[2],
        REWARD_ITEM_X_COLOR[3],
        REWARD_ITEM_X_COLOR[4] * alpha
    )
    love.graphics.setLineWidth(REWARD_ITEM_X_WIDTH)
    love.graphics.line(rect.x + inset, rect.y + inset, rect.x + rect.w - inset, rect.y + rect.h - inset)
    love.graphics.line(rect.x + rect.w - inset, rect.y + inset, rect.x + inset, rect.y + rect.h - inset)
    love.graphics.setLineWidth(1)
end

local function drawRewardItem(definition, id, center_x, y, font, alpha, dimmed)
    local card_x = center_x - REWARD_ITEM_CARD_W / 2
    local image_rect = getRewardItemImageRect(center_x, y)
    local image = getEquipmentImage(id)
    local name = definition and definition.name or id or "UNKNOWN"
    local image_alpha = alpha * (dimmed and REWARD_ITEM_DIM_ALPHA or 1)

    love.graphics.setColor(
        REWARD_ITEM_FILL_COLOR[1],
        REWARD_ITEM_FILL_COLOR[2],
        REWARD_ITEM_FILL_COLOR[3],
        REWARD_ITEM_FILL_COLOR[4] * alpha
    )
    love.graphics.rectangle("fill", image_rect.x, image_rect.y, image_rect.w, image_rect.h)
    love.graphics.setColor(1, 1, 1, image_alpha)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", image_rect.x, image_rect.y, image_rect.w, image_rect.h)
    love.graphics.setLineWidth(1)

    if image then
        local available_size = REWARD_ITEM_IMAGE_SIZE - REWARD_ITEM_IMAGE_PADDING * 2
        local scale = math.min(available_size / image:getWidth(), available_size / image:getHeight())
        local draw_w = image:getWidth() * scale
        local draw_h = image:getHeight() * scale

        love.graphics.setColor(1, 1, 1, image_alpha)
        love.graphics.draw(
            image,
            center_x - draw_w / 2,
            y + (REWARD_ITEM_IMAGE_SIZE - draw_h) / 2,
            0,
            scale,
            scale
        )
    else
        love.graphics.setColor(1, 1, 1, image_alpha)
        love.graphics.printf(
            id or "?",
            image_rect.x,
            y + (REWARD_ITEM_IMAGE_SIZE - font:getHeight()) / 2,
            REWARD_ITEM_IMAGE_SIZE,
            "center"
        )
    end

    if dimmed then
        love.graphics.setColor(0, 0, 0, 0.58 * alpha)
        love.graphics.rectangle("fill", image_rect.x, image_rect.y, image_rect.w, image_rect.h)
        drawRewardItemX(image_rect, alpha)
    end

    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.printf(
        name,
        card_x,
        y + REWARD_ITEM_IMAGE_SIZE + REWARD_ITEM_LABEL_GAP,
        REWARD_ITEM_CARD_W,
        "center"
    )

    return image_rect
end

local function drawRewardItemPair(first, second, separator, center_x, y, options)
    options = options or {}

    local previous_font = love.graphics.getFont()
    local font = options.font or previous_font
    local alpha = math.max(0, math.min(1, tonumber(options.alpha) or 1))
    local offset = (REWARD_ITEM_CARD_W + REWARD_ITEM_SEPARATOR_W) / 2

    love.graphics.setFont(font)
    local first_rect = drawRewardItem(
        first.definition, first.id, center_x - offset, y, font, alpha, options.dim_first == true
    )
    local second_rect = drawRewardItem(
        second.definition, second.id, center_x + offset, y, font, alpha, options.dim_second == true
    )
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.printf(
        separator,
        center_x - REWARD_ITEM_SEPARATOR_W / 2,
        y + (REWARD_ITEM_IMAGE_SIZE - font:getHeight()) / 2,
        REWARD_ITEM_SEPARATOR_W,
        "center"
    )
    love.graphics.setFont(previous_font)
    love.graphics.setColor(1, 1, 1, 1)

    return {
        x = center_x - REWARD_ITEM_CARD_W - REWARD_ITEM_SEPARATOR_W / 2,
        y = y,
        w = REWARD_ITEM_CARD_W * 2 + REWARD_ITEM_SEPARATOR_W,
        h = getRewardItemRowHeight(font, first, second),
        first = first_rect,
        second = second_rect,
    }
end

function reward_uix.getScratchTileRect(value, center_x, y, font)
    local value_text = tostring(normalizeScratch(value))
    local value_w = font:getWidth(value_text)
    local tile_w = math.max(
        TILE_MIN_W,
        TILE_PADDING + ICON_SIZE + TILE_PADDING + value_w + VALUE_RIGHT_PADDING
    )

    return {
        x = center_x - tile_w / 2,
        y = y,
        w = tile_w,
        h = TILE_H,
        value_text = value_text,
        value_w = value_w,
    }
end

function reward_uix.drawScratchTile(value, center_x, y, options)
    options = options or {}

    local previous_font = love.graphics.getFont()
    local font = options.font or previous_font
    local alpha = math.max(0, math.min(1, tonumber(options.alpha) or 1))
    local rect = reward_uix.getScratchTileRect(value, center_x, y, font)
    local icon_x = rect.x + TILE_PADDING
    local icon_y = rect.y + (rect.h - ICON_SIZE) / 2
    local text_area_x = icon_x + ICON_SIZE + TILE_PADDING
    local text_area_w = rect.x + rect.w - VALUE_RIGHT_PADDING - text_area_x
    local text_x = text_area_x + (text_area_w - rect.value_w) / 2
    local text_y = rect.y + (rect.h - font:getHeight()) / 2
    local icon = getScratchImage()

    love.graphics.setFont(font)
    love.graphics.setColor(TILE_COLOR[1], TILE_COLOR[2], TILE_COLOR[3], TILE_COLOR[4] * alpha)
    love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
    love.graphics.setColor(BORDER_COLOR[1], BORDER_COLOR[2], BORDER_COLOR[3], BORDER_COLOR[4] * alpha)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h)
    love.graphics.setLineWidth(1)

    if icon then
        local scale = math.min(ICON_SIZE / icon:getWidth(), ICON_SIZE / icon:getHeight())

        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.draw(icon, icon_x, icon_y, 0, scale, scale)
    end

    love.graphics.setColor(VALUE_COLOR[1], VALUE_COLOR[2], VALUE_COLOR[3], VALUE_COLOR[4] * alpha)
    love.graphics.print(rect.value_text, text_x, text_y)
    love.graphics.setFont(previous_font)
    love.graphics.setColor(1, 1, 1, 1)

    return rect
end

function reward_uix.getTileHeight()
    return TILE_H
end

function reward_uix.getRewardItemRowHeight(font)
    return getRewardItemRowHeight(font or love.graphics.getFont())
end

function reward_uix.getRewardItemPairRects(center_x, y)
    local offset = (REWARD_ITEM_CARD_W + REWARD_ITEM_SEPARATOR_W) / 2

    return {
        first = getRewardItemImageRect(center_x - offset, y),
        second = getRewardItemImageRect(center_x + offset, y),
    }
end

function reward_uix.getEquipmentRewardPair(rewards)
    rewards = rewards or {}

    local equip_a = normalizeEquipmentId(rewards.equip_a or rewards.equip_A)
    local equip_b = normalizeEquipmentId(rewards.equip_b or rewards.equip_B)

    if not equip_a or not equip_b then
        return nil
    end

    return {
        { id = equip_a, definition = equip_logic.getDefinition(equip_a) },
        { id = equip_b, definition = equip_logic.getDefinition(equip_b) },
    }
end

function reward_uix.getRumorAdvancement(rewards)
    rewards = rewards or {}

    local rumor_id = normalizeEquipmentId(rewards.rumor)
    local rumor = rumor_id and equip_logic.getDefinition(rumor_id) or nil
    local next_rumor_id = rumor and normalizeEquipmentId(rumor.ex_rumor) or nil

    if not rumor or not next_rumor_id then
        return nil
    end

    return {
        { id = next_rumor_id, definition = equip_logic.getDefinition(next_rumor_id) },
        { id = rumor_id, definition = rumor },
    }
end

function reward_uix.getRumorAdvancementRowHeight(rewards, font)
    local pair = reward_uix.getRumorAdvancement(rewards)

    if not pair then
        return 0
    end

    return getRewardItemRowHeight(font or love.graphics.getFont(), pair[1], pair[2])
end

function reward_uix.drawEquipmentRewardRow(rewards, center_x, y, options)
    local pair = reward_uix.getEquipmentRewardPair(rewards)

    if not pair then
        return nil
    end

    options = options or {}

    if options.dim_opposite_on_hover then
        local mouse_x, mouse_y = love.mouse.getPosition()
        local rects = reward_uix.getRewardItemPairRects(center_x, y)

        if pointInRect(mouse_x, mouse_y, rects.first) then
            options.dim_second = true
        elseif pointInRect(mouse_x, mouse_y, rects.second) then
            options.dim_first = true
        end
    end

    return drawRewardItemPair(pair[1], pair[2], "OR", center_x, y, options)
end

function reward_uix.drawRumorAdvancementRow(rewards, center_x, y, options)
    local pair = reward_uix.getRumorAdvancement(rewards)

    if not pair then
        return nil
    end

    options = options or {}
    options.dim_first = true

    return drawRewardItemPair(pair[1], pair[2], ">", center_x, y, options)
end

return reward_uix

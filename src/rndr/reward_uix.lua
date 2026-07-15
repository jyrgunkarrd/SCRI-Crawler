local image_loader = require("src.assets.image_loader")

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

local scratch_image = nil

local function normalizeScratch(value)
    return math.max(0, math.floor(tonumber(value) or 0))
end

local function getScratchImage()
    if not scratch_image then
        scratch_image = image_loader.newImage(SCRATCH_ICON_PATH)
    end

    return scratch_image
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

return reward_uix

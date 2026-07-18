local equip_logic = require("src.sys.equip_logic")
local image_loader = require("src.assets.image_loader")
local luggage = require("src.sys.luggage")
local sfx_logic = require("src.sys.sfx_logic")

local mission_consumables = {}

local XP_GAUGE_X = 24
local XP_GAUGE_Y = 24 + 190 + 8
local XP_GAUGE_W = 460
local XP_GAUGE_H = 28
local COLUMNS = 10
local BUTTON_SIZE = 40
local BUTTON_GAP = 6
local GRID_TOP_GAP = 8
local TOOLTIP_GAP = 6
local TOOLTIP_PAD = 10
local TOOLTIP_MAX_W = 280
local TOOLTIP_FONT_SIZE = 13
local BUTTON_FILL_COLOR = { 0.015, 0.014, 0.012, 1 }
local OUTLINE_COLOR = { 1, 1, 1, 1 }
local HOVER_COLOR = { 1, 0.8275, 0.3529, 1 }
local TOOLTIP_FILL_COLOR = { 0, 0, 0, 0.94 }
local images = {}
local missing_images = {}
local tooltip_font = nil

local function pointInRect(x, y, rect)
    return x >= rect.x and x <= rect.x + rect.w
        and y >= rect.y and y <= rect.y + rect.h
end

local function getImage(item)
    if not item or not item.id or luggage.isLuggage(item) then
        return nil
    end

    if images[item.id] then
        return images[item.id]
    end

    if missing_images[item.id] then
        return nil
    end

    local path = item.image_path or ("assets/images/equip/%s.webp"):format(item.id)
    local ok, image = pcall(image_loader.newImage, path)

    if not ok then
        missing_images[item.id] = true
        return nil
    end

    images[item.id] = image

    return image
end


local function getButtonRects(agent)
    local items = equip_logic.getConsumables(agent)
    local grid_w = COLUMNS * BUTTON_SIZE + (COLUMNS - 1) * BUTTON_GAP
    local start_x = XP_GAUGE_X + (XP_GAUGE_W - grid_w) / 2
    local start_y = XP_GAUGE_Y + XP_GAUGE_H + GRID_TOP_GAP
    local rects = {}

    for index, item in ipairs(items) do
        local column = (index - 1) % COLUMNS
        local row = math.floor((index - 1) / COLUMNS)

        rects[#rects + 1] = {
            item = item,
            x = start_x + column * (BUTTON_SIZE + BUTTON_GAP),
            y = start_y + row * (BUTTON_SIZE + BUTTON_GAP),
            w = BUTTON_SIZE,
            h = BUTTON_SIZE,
        }
    end

    return rects
end

local function drawButton(rect)
    local item = rect.item
    local image = getImage(item)

    love.graphics.setColor(BUTTON_FILL_COLOR)
    love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h)

    if image then
        local scale = math.min(rect.w / image:getWidth(), rect.h / image:getHeight())

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(
            image,
            rect.x + rect.w / 2,
            rect.y + rect.h / 2,
            0,
            scale,
            scale,
            image:getWidth() / 2,
            image:getHeight() / 2
        )
    else
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf(item.id or "", rect.x + 2, rect.y + (rect.h - love.graphics.getFont():getHeight()) / 2, rect.w - 4, "center")
    end

    love.graphics.setColor(OUTLINE_COLOR)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h)
    love.graphics.setLineWidth(1)
end

local function drawTooltip(rect)
    local text = tostring(rect.item and rect.item.previewtext or "")

    if text == "" then
        return
    end

    tooltip_font = tooltip_font or love.graphics.newFont("assets/fonts/Furore.otf", TOOLTIP_FONT_SIZE)

    local text_w = math.min(TOOLTIP_MAX_W, math.max(120, tooltip_font:getWidth(text)))
    local _, lines = tooltip_font:getWrap(text, text_w)
    local box_w = text_w + TOOLTIP_PAD * 2
    local box_h = math.max(1, #lines) * tooltip_font:getHeight() + TOOLTIP_PAD * 2
    local box_x = math.max(4, math.min(
        love.graphics.getWidth() - box_w - 4,
        rect.x + (rect.w - box_w) / 2
    ))
    local box_y = rect.y - TOOLTIP_GAP - box_h
    local previous_font = love.graphics.getFont()

    love.graphics.setColor(TOOLTIP_FILL_COLOR)
    love.graphics.rectangle("fill", box_x, box_y, box_w, box_h)
    love.graphics.setColor(OUTLINE_COLOR)
    love.graphics.rectangle("line", box_x, box_y, box_w, box_h)
    love.graphics.setFont(tooltip_font)
    love.graphics.printf(text, box_x + TOOLTIP_PAD, box_y + TOOLTIP_PAD, text_w, "center")
    love.graphics.setFont(previous_font)
end

function mission_consumables.draw(agent)
    if not agent then
        return
    end

    local mouse_x, mouse_y = love.mouse.getPosition()
    local hovered = nil

    for _, rect in ipairs(getButtonRects(agent)) do
        drawButton(rect)

        if pointInRect(mouse_x, mouse_y, rect) then
            hovered = rect
            love.graphics.setColor(HOVER_COLOR)
            love.graphics.setLineWidth(3)
            love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h)
            love.graphics.setLineWidth(1)
        end
    end

    if hovered then
        drawTooltip(hovered)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function mission_consumables.mousepressed(agent, x, y, button)
    if not agent or button ~= 1 then
        return false
    end

    for _, rect in ipairs(getButtonRects(agent)) do
        if pointInRect(x, y, rect) then
            if equip_logic.useConsumable(agent, rect.item) then
                sfx_logic.playNamed("equip")
            end

            return true
        end
    end

    return false
end

return mission_consumables

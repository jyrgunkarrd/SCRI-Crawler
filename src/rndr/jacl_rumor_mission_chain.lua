local image_loader = require("src.assets.image_loader")
local map_preview = require("src.rndr.jacl_map_preview")

local rumor_chain = {}

local COLUMN_RESERVE = 150
local COLUMN_MAX_W = 126
local COLUMN_MARGIN = 8
local COLUMN_PAD = 8
local THUMB_SIZE = 86
local AGENT_LABEL_BOTTOM_GAP = 6
local NAME_H = 34
local NAME_GAP = 6
local ITEM_GAP = 14
local SCROLL_STEP = 72
local COLUMN_COLOR = { 0, 0, 0, 0.82 }
local THUMB_COLOR = { 0.015, 0.014, 0.012, 1 }
local OUTLINE_COLOR = { 1, 1, 1, 0.92 }
local MUTED_COLOR = { 1, 1, 1, 0.58 }
local HOVER_COLOR = { 165 / 255, 0, 74 / 255, 1 }

local images = {}
local missing_images = {}

local function pointInRect(x, y, rect)
    return rect and x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

local function getImage(entry)
    local key = entry and (entry.id or entry.image_path)

    if not key or missing_images[key] then
        return nil
    end

    if images[key] then
        return images[key]
    end

    local ok, loaded = pcall(image_loader.newImage, entry.image_path)

    if not ok then
        missing_images[key] = true
        return nil
    end

    images[key] = loaded

    return loaded
end


function rumor_chain.getPreviewReserve(entries)
    return entries and #entries > 0 and COLUMN_RESERVE or 0
end

function rumor_chain.getLayout(state, screen_h, preview_options)
    local preview_layout = map_preview.getLayout(state, screen_h, preview_options or {})
    local backing_x = state and state.jacl_backing_rect and state.jacl_backing_rect.x
        or preview_layout.x + preview_layout.w + COLUMN_RESERVE
    local gap_left = preview_layout.x + preview_layout.w
    local gap_w = math.max(0, backing_x - gap_left)
    local width = math.max(0, math.min(COLUMN_MAX_W, gap_w - COLUMN_MARGIN * 2))

    return {
        x = gap_left + (gap_w - width) / 2,
        y = preview_layout.y,
        w = width,
        h = preview_layout.h,
    }
end

local function buildItems(entries, layout, scroll_y, font)
    local items = {}
    local cursor_y = layout.y + COLUMN_PAD - (scroll_y or 0)
    local previous_slot = nil

    for _, entry in ipairs(entries or {}) do
        local slot_label = nil
        local slot_label_h = 0

        if entry.slot_index ~= previous_slot then
            local agent_name = entry.agent and (entry.agent.name or entry.agent.id) or ""
            local _, wrapped_lines = font:getWrap(agent_name, math.max(1, layout.w - 8))

            slot_label = agent_name
            slot_label_h = math.max(1, #wrapped_lines) * font:getHeight() + AGENT_LABEL_BOTTOM_GAP
            cursor_y = cursor_y + slot_label_h
            previous_slot = entry.slot_index
        end

        local thumb_x = layout.x + (layout.w - THUMB_SIZE) / 2
        local thumb_rect = {
            x = thumb_x,
            y = cursor_y,
            w = THUMB_SIZE,
            h = THUMB_SIZE,
        }

        items[#items + 1] = {
            entry = entry,
            slot_label = slot_label,
            slot_label_y = cursor_y - slot_label_h,
            thumb = thumb_rect,
            name_y = cursor_y + THUMB_SIZE + NAME_GAP,
        }
        cursor_y = cursor_y + THUMB_SIZE + NAME_GAP + NAME_H + ITEM_GAP
    end

    return items, math.max(0, cursor_y + (scroll_y or 0) - layout.y + COLUMN_PAD)
end

local function clampScroll(state, entries, layout, font)
    local _, content_h = buildItems(entries, layout, 0, font)
    local max_scroll = math.max(0, content_h - layout.h)

    state.rumor_mission_scroll_y = math.max(0, math.min(state.rumor_mission_scroll_y or 0, max_scroll))

    return max_scroll
end

function rumor_chain.getHovered(state, entries, screen_h, preview_options)
    if not entries or #entries == 0 then
        return nil
    end

    local layout = rumor_chain.getLayout(state, screen_h, preview_options)

    if layout.w <= 0 or layout.h <= 0 then
        return nil
    end

    local font = preview_options and preview_options.font or love.graphics.getFont()

    clampScroll(state, entries, layout, font)

    local mouse_x, mouse_y = love.mouse.getPosition()

    if not pointInRect(mouse_x, mouse_y, layout) then
        return nil
    end

    for _, item in ipairs(buildItems(entries, layout, state.rumor_mission_scroll_y, font)) do
        if pointInRect(mouse_x, mouse_y, item.thumb) then
            return item.entry
        end
    end

    return nil
end

function rumor_chain.wheelmoved(state, entries, screen_h, preview_options, x, y)
    if not entries or #entries == 0 then
        return false
    end

    local layout = rumor_chain.getLayout(state, screen_h, preview_options)
    local mouse_x, mouse_y = love.mouse.getPosition()
    local font = preview_options and preview_options.font or love.graphics.getFont()

    if layout.w <= 0 or layout.h <= 0 or not pointInRect(mouse_x, mouse_y, layout) then
        return false
    end

    local max_scroll = clampScroll(state, entries, layout, font)
    local wheel_delta = y ~= 0 and y or -x

    state.rumor_mission_scroll_y = math.max(
        0,
        math.min((state.rumor_mission_scroll_y or 0) - wheel_delta * SCROLL_STEP, max_scroll)
    )

    return true
end

function rumor_chain.draw(state, entries, screen_h, preview_options, options)
    if not entries or #entries == 0 then
        return
    end

    options = options or {}

    local layout = rumor_chain.getLayout(state, screen_h, preview_options)

    if layout.w <= 0 or layout.h <= 0 then
        return
    end

    local mouse_x, mouse_y = love.mouse.getPosition()
    local font = options.font or love.graphics.getFont()
    clampScroll(state, entries, layout, font)

    local items = buildItems(entries, layout, state.rumor_mission_scroll_y, font)

    love.graphics.setColor(COLUMN_COLOR)
    love.graphics.rectangle("fill", layout.x, layout.y, layout.w, layout.h)
    love.graphics.setColor(options.outline_color or OUTLINE_COLOR)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", layout.x, layout.y, layout.w, layout.h)
    love.graphics.setLineWidth(1)
    love.graphics.setScissor(layout.x, layout.y, layout.w, layout.h)

    for _, item in ipairs(items) do
        local entry = item.entry
        local image = getImage(entry)
        local hovered = pointInRect(mouse_x, mouse_y, item.thumb)

        if item.slot_label then
            love.graphics.setFont(font)
            love.graphics.setColor(MUTED_COLOR)
            love.graphics.printf(item.slot_label, layout.x + 4, item.slot_label_y + 2, layout.w - 8, "center")
        end

        love.graphics.setColor(THUMB_COLOR)
        love.graphics.rectangle("fill", item.thumb.x, item.thumb.y, item.thumb.w, item.thumb.h)

        if image then
            local scale = math.min(item.thumb.w / image:getWidth(), item.thumb.h / image:getHeight())

            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(
                image,
                item.thumb.x + item.thumb.w / 2,
                item.thumb.y + item.thumb.h / 2,
                0,
                scale,
                scale,
                image:getWidth() / 2,
                image:getHeight() / 2
            )
        else
            love.graphics.setFont(font)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.printf(entry.id or "", item.thumb.x, item.thumb.y + (item.thumb.h - font:getHeight()) / 2, item.thumb.w, "center")
        end

        love.graphics.setColor(hovered and HOVER_COLOR or (options.outline_color or OUTLINE_COLOR))
        love.graphics.setLineWidth(hovered and 3 or 2)
        love.graphics.rectangle("line", item.thumb.x, item.thumb.y, item.thumb.w, item.thumb.h)
        love.graphics.setLineWidth(1)
        love.graphics.setFont(font)
        love.graphics.setColor(1, 1, 1, 0.92)
        love.graphics.printf(entry.name or entry.id or "", layout.x + 4, item.name_y, layout.w - 8, "center")
    end

    love.graphics.setScissor()
    love.graphics.setColor(1, 1, 1, 1)
end

return rumor_chain

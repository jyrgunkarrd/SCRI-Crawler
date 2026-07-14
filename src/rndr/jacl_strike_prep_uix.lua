local strike_prep = require("src.sys.JACL_strk_prep")

local strike_uix = {}

local BUTTON_W = 310
local BUTTON_H = 42
local BUTTON_GAP = 18
local PANEL_GAP = 8
local PANEL_PAD = 10
local SLOT_SIZE = 80
local SLOT_GAP = 12
local PORTRAIT_RADIUS = 54
local PANEL_COLOR = { 0, 0, 0, 0.88 }
local SLOT_COLOR = { 0.035, 0.033, 0.03, 1 }
local DROP_COLOR = { 0.4078, 0.6824, 0.5804, 0.22 }
local OUTLINE_COLOR = { 1, 1, 1, 0.92 }
local SLOT_OUTLINE_COLOR = { 1, 1, 1, 0.62 }
local EMPTY_COLOR = { 1, 1, 1, 0.52 }

local function pointInRect(x, y, rect)
    return x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

local function getPanelLayout(state, roster_layout)
    local panel_w = PANEL_PAD * 2 + SLOT_SIZE * 4 + SLOT_GAP * 3
    local panel_h = PANEL_PAD * 2 + SLOT_SIZE
    local panel_x = (love.graphics.getWidth() - panel_w) / 2
    local roster_bottom = roster_layout.y + roster_layout.h
    local backing_top = state and state.jacl_backing_rect and state.jacl_backing_rect.y
        or roster_bottom + panel_h + PANEL_GAP * 2
    local gap_top = roster_bottom + PANEL_GAP
    local gap_bottom = backing_top - PANEL_GAP
    local panel_y = gap_top + math.max(0, gap_bottom - gap_top - panel_h) / 2

    return {
        x = panel_x,
        y = panel_y,
        w = panel_w,
        h = panel_h,
    }
end

local function getSlotRects(state, roster_layout)
    local layout = getPanelLayout(state, roster_layout)
    local rects = {}

    for index = 1, 4 do
        rects[index] = {
            x = layout.x + PANEL_PAD + (index - 1) * (SLOT_SIZE + SLOT_GAP),
            y = layout.y + PANEL_PAD,
            w = SLOT_SIZE,
            h = SLOT_SIZE,
        }
    end

    return rects
end

function strike_uix.getSlotAtPoint(state, roster_layout, x, y)
    for index, rect in ipairs(getSlotRects(state, roster_layout)) do
        if pointInRect(x, y, rect) then
            return index
        end
    end

    return nil
end

function strike_uix.drawPanel(state, roster_layout, options)
    if not strike_prep.isActive() then
        return
    end

    options = options or {}

    local layout = getPanelLayout(state, roster_layout)
    local slots = strike_prep.getSlots()
    local drag_agent = strike_prep.getDragAgent()

    love.graphics.setColor(PANEL_COLOR)
    love.graphics.rectangle("fill", layout.x, layout.y, layout.w, layout.h)
    love.graphics.setColor(options.outline_color or OUTLINE_COLOR)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", layout.x, layout.y, layout.w, layout.h)
    love.graphics.setLineWidth(1)

    local slot_rects = getSlotRects(state, roster_layout)

    for index = 1, 4 do
        local rect = slot_rects[index]
        local agent = slots[index]

        love.graphics.setColor(SLOT_COLOR)
        love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h)

        if drag_agent then
            love.graphics.setColor(DROP_COLOR)
            love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
        end

        love.graphics.setColor(options.slot_outline_color or SLOT_OUTLINE_COLOR)
        love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h)

        if agent then
            if options.draw_agent_portrait then
                options.draw_agent_portrait(agent, rect.x + rect.w / 2, rect.y + rect.h / 2, SLOT_SIZE * 0.39)
            end
        else
            love.graphics.setFont(options.font or love.graphics.getFont())
            love.graphics.setColor(options.empty_color or EMPTY_COLOR)
            love.graphics.printf(tostring(index), rect.x, rect.y + (rect.h - (options.font or love.graphics.getFont()):getHeight()) / 2, rect.w, "center")
        end
    end
end

function strike_uix.drawDrag(options)
    local agent = strike_prep.getDragAgent()

    if not agent then
        return
    end

    options = options or {}

    if options.draw_agent_portrait then
        local mouse_x, mouse_y = love.mouse.getPosition()

        options.draw_agent_portrait(agent, mouse_x, mouse_y, options.radius or PORTRAIT_RADIUS)
    end
end

local function drawActionButton(state, backing_rect, label, font)
    local rect = {
        x = backing_rect.x + (backing_rect.w - BUTTON_W) / 2,
        y = backing_rect.y + backing_rect.h + BUTTON_GAP,
        w = BUTTON_W,
        h = BUTTON_H,
    }
    local mouse_x, mouse_y = love.mouse.getPosition()
    local hovered = pointInRect(mouse_x, mouse_y, rect)

    love.graphics.setColor(hovered and 1 or 0, hovered and 1 or 0, hovered and 1 or 0, 1)
    love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h)
    love.graphics.setLineWidth(1)

    love.graphics.setFont(font)
    love.graphics.setColor(hovered and 0 or 1, hovered and 0 or 1, hovered and 0 or 1, 1)
    love.graphics.printf(
        label,
        rect.x,
        rect.y + (rect.h - font:getHeight()) / 2,
        rect.w,
        "center"
    )

    return rect
end

function strike_uix.drawButtons(state, backing_rect, options)
    options = options or {}
    state.strike_button_rect = nil
    state.launch_button_rect = nil

    if options.modal_open then
        return
    end

    if strike_prep.isActive() then
        if strike_prep.hasSlottedAgents() then
            state.launch_button_rect = drawActionButton(state, backing_rect, "Launch Strike", options.font)
        end

        return
    end

    state.strike_button_rect = drawActionButton(state, backing_rect, "Prepare Strike Package", options.font)
end

function strike_uix.buildLaunchOptions(map_path)
    local agents_by_start = {}
    local slots = strike_prep.getSlots()

    for slot_index = 1, 4 do
        local agent = slots[slot_index]

        if agent then
            agents_by_start[slot_index] = agent
        end
    end

    return {
        map_path = map_path or "assets/maps/devmap.lua",
        agents_by_start = agents_by_start,
    }
end

return strike_uix

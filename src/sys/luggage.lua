local luggage = {}
local mission_active = false

local FILLED_COLOR = { 0, 1, 167 / 255, 1 }
local EMPTY_COLOR = { 1, 1, 1, 1 }
local FILLED_TEXT_COLOR = { 0, 0, 0, 1 }

local function positiveInteger(value, fallback)
    return math.max(1, math.floor(tonumber(value) or fallback or 1))
end

function luggage.isLuggage(item)
    return tostring(item and item.category or ""):lower() == "luggage"
end

function luggage.getGridSize(item)
    local inv_size = item and item.inv_size or nil

    if type(inv_size) == "table" then
        return positiveInteger(inv_size.W or inv_size.w or inv_size.width),
            positiveInteger(inv_size.H or inv_size.h or inv_size.height)
    end

    return positiveInteger(item and item.inv_w), positiveInteger(item and item.inv_h)
end

function luggage.getMultiplier(item)
    return positiveInteger(item and item.mult)
end

function luggage.getCapacity(item)
    local columns, rows = luggage.getGridSize(item)

    return columns * rows
end

function luggage.getFilledCellCount(item)
    return math.min(
        luggage.getCapacity(item),
        math.max(0, math.floor(tonumber(item and item.luggage_filled) or 0))
    )
end

function luggage.setMissionActive(active)
    mission_active = active == true
end

function luggage.isMissionActive()
    return mission_active
end

local function fillPriority(a, b)
    local a_mult = luggage.getMultiplier(a)
    local b_mult = luggage.getMultiplier(b)

    if a_mult ~= b_mult then
        return a_mult > b_mult
    end

    local a_row = tonumber(a and a.inv_row) or math.huge
    local b_row = tonumber(b and b.inv_row) or math.huge

    if a_row ~= b_row then
        return a_row < b_row
    end

    local a_col = tonumber(a and a.inv_col) or math.huge
    local b_col = tonumber(b and b.inv_col) or math.huge

    if a_col ~= b_col then
        return a_col < b_col
    end

    return tostring(a and (a.uid or a.id) or "") < tostring(b and (b.uid or b.id) or "")
end

function luggage.captureXp(agent, amount)
    if not mission_active or not agent then
        return 0
    end

    local remaining = math.max(0, math.floor(tonumber(amount) or 0))
    local captured = 0
    local items = {}
    local inventory = agent.equipment_runtime and agent.equipment_runtime.inventory or {}

    for _, item in ipairs(inventory) do
        if luggage.isLuggage(item) and luggage.getFilledCellCount(item) < luggage.getCapacity(item) then
            items[#items + 1] = item
        end
    end

    table.sort(items, fillPriority)

    for _, item in ipairs(items) do
        if remaining <= 0 then
            break
        end

        local filled = luggage.getFilledCellCount(item)
        local available = luggage.getCapacity(item) - filled
        local contribution = math.min(remaining, available)

        item.luggage_filled = filled + contribution
        remaining = remaining - contribution
        captured = captured + contribution
    end

    return captured
end

function luggage.draw(item, x, y, w, h, options)
    if not luggage.isLuggage(item) then
        return false
    end

    options = options or {}

    local columns, rows = luggage.getGridSize(item)
    local alpha = tonumber(options.alpha) or 1
    local padding = tonumber(options.padding) or math.max(4, math.min(w, h) * 0.10)
    local gap = tonumber(options.gap) or math.max(2, math.min(w, h) * 0.025)
    local available_w = math.max(1, w - padding * 2 - gap * (columns - 1))
    local available_h = math.max(1, h - padding * 2 - gap * (rows - 1))
    local cell_size = math.max(1, math.min(available_w / columns, available_h / rows))
    local grid_w = cell_size * columns + gap * (columns - 1)
    local grid_h = cell_size * rows + gap * (rows - 1)
    local grid_x = x + (w - grid_w) / 2
    local grid_y = y + (h - grid_h) / 2
    local filled_cells = luggage.getFilledCellCount(item)
    local font = options.font or love.graphics.getFont()
    local label = tostring(luggage.getMultiplier(item))
    local label_w = font:getWidth(label)
    local label_h = font:getHeight()
    local text_scale = math.max(
        0.01,
        math.min(1, (cell_size - 4) / math.max(label_w, 1), (cell_size - 4) / math.max(label_h, 1))
    )
    local previous_font = love.graphics.getFont()
    local previous_line_width = love.graphics.getLineWidth()
    local red, green, blue, previous_alpha = love.graphics.getColor()

    love.graphics.setFont(font)
    love.graphics.setLineWidth(tonumber(options.line_width) or 2)

    for row = 1, rows do
        for column = 1, columns do
            local cell_index = (row - 1) * columns + column
            local filled = cell_index <= filled_cells
            local box_x = grid_x + (column - 1) * (cell_size + gap)
            local box_y = grid_y + (row - 1) * (cell_size + gap)
            local draw_w = label_w * text_scale
            local draw_h = label_h * text_scale

            if filled then
                love.graphics.setColor(FILLED_COLOR[1], FILLED_COLOR[2], FILLED_COLOR[3], alpha)
                love.graphics.rectangle("fill", box_x, box_y, cell_size, cell_size)
            end

            local outline_color = filled and FILLED_COLOR or EMPTY_COLOR

            love.graphics.setColor(outline_color[1], outline_color[2], outline_color[3], alpha)
            love.graphics.rectangle("line", box_x, box_y, cell_size, cell_size)
            local text_color = filled and FILLED_TEXT_COLOR or EMPTY_COLOR

            love.graphics.setColor(text_color[1], text_color[2], text_color[3], alpha)
            love.graphics.print(
                label,
                box_x + (cell_size - draw_w) / 2,
                box_y + (cell_size - draw_h) / 2,
                0,
                text_scale,
                text_scale
            )
        end
    end

    love.graphics.setFont(previous_font)
    love.graphics.setLineWidth(previous_line_width)
    love.graphics.setColor(red, green, blue, previous_alpha)

    return true
end

return luggage

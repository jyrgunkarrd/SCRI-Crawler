local map_tiles = require("src.rndr.map_tiles")

local map_preview = {}

local PREVIEW_X = 34
local PREVIEW_W = 495
local PREVIEW_PAD = 16
local LABEL_H = 54
local LABEL_GAP = 2
local PREVIEW_COLOR = { 0, 0, 0, 0.82 }
local TILE_COLOR = { 0.33, 0.49, 0.42, 1 }
local CORRIDOR_COLOR = { 0.27, 0.39, 0.35, 1 }
local START_FILL_COLOR = { 1, 1, 1, 0.96 }
local START_TEXT_COLOR = { 0, 0, 0, 1 }
local DOOR_COLOR = { 1, 1, 1, 0.34 }
local REWARD_VALUE_COLOR = { 0, 1, 167 / 255, 1 }
local REWARD_LABEL_GAP = 16
local HEX_SIZE = 54

local function buildHexPoints(center_x, center_y, radius)
    local points = {}

    for index = 0, 5 do
        local angle = math.rad(-90 + index * 60)
        points[#points + 1] = center_x + radius * math.cos(angle)
        points[#points + 1] = center_y + radius * math.sin(angle)
    end

    return points
end

local function normalizeStartNumbers(tiles)
    local max_start = 0

    for _, tile in ipairs(tiles) do
        if type(tile.start) == "number" then
            max_start = math.max(max_start, tile.start)
        end
    end

    for _, tile in ipairs(tiles) do
        if tile.start and type(tile.start) ~= "number" then
            max_start = max_start + 1
            tile.start = max_start
        end
    end
end

function map_preview.load(path)
    path = path or "assets/maps/devmap.lua"

    local chunk, load_error = love.filesystem.load(path)

    if not chunk then
        print("Unable to load JACL strike prep map preview: " .. tostring(load_error))
        return nil
    end

    local ok, map_file = pcall(chunk)

    if not ok then
        print("Unable to run JACL strike prep map preview: " .. tostring(map_file))
        return nil
    end

    local tiles = {}

    for index, tile in ipairs(map_file.tiles or {}) do
        tiles[index] = {
            q = tile.q,
            r = tile.r,
            start = tile.start,
            corridor = tile.corridor,
            color = tile.color,
        }
    end

    normalizeStartNumbers(tiles)

    return {
        id = map_file.id,
        name = map_file.name,
        recommended_level = map_file.recommended_level,
        rewards = type(map_file.rewards) == "table" and map_file.rewards or {},
        path = path,
        tiles = tiles,
        doors = map_file.doors or {},
    }
end

function map_preview.getLayout(state, screen_h, options)
    options = options or {}
    local roster_y = options.roster_y or 14
    local roster_h = options.roster_h or 168
    local label_y = roster_y + roster_h + 22
    local y = label_y + LABEL_H + LABEL_GAP
    local h = math.max(0, screen_h - y - 54)
    local max_w = state and state.jacl_backing_rect
        and state.jacl_backing_rect.x - PREVIEW_X - 24 - (options.right_reserve or 0)
        or PREVIEW_W
    local w = math.max(0, math.min(PREVIEW_W, max_w))

    return {
        x = PREVIEW_X,
        y = y,
        w = w,
        h = h,
        label_x = PREVIEW_X,
        label_y = label_y,
        label_w = w,
        label_h = LABEL_H,
    }
end

local function getTileCenter(tile, min_x, min_y, origin_x, origin_y, scale)
    local tile_x, tile_y = map_tiles.axialToPixel(tile.q, tile.r)

    return origin_x + (tile_x - min_x) * scale, origin_y + (tile_y - min_y) * scale
end

function map_preview.draw(state, room, screen_h, options)
    if not room or not room.tiles then
        return
    end

    options = options or {}

    local layout = map_preview.getLayout(state, screen_h, options)

    if layout.w <= 0 or layout.h <= 0 then
        return
    end

    local min_x, min_y, max_x, max_y = map_tiles.getBounds(room)
    local map_w = math.max(max_x - min_x, 1)
    local map_h = math.max(max_y - min_y, 1)
    local inner_x = layout.x + PREVIEW_PAD
    local inner_y = layout.y + PREVIEW_PAD
    local inner_w = math.max(0, layout.w - PREVIEW_PAD * 2)
    local inner_h = math.max(0, layout.h - PREVIEW_PAD * 2)

    if inner_w <= 0 or inner_h <= 0 then
        return
    end

    local scale = math.min(inner_w / map_w, inner_h / map_h)
    local origin_x = inner_x + (inner_w - map_w * scale) / 2
    local origin_y = inner_y + (inner_h - map_h * scale) / 2
    local map_name = room.name and room.name ~= "" and room.name or room.id or "Unknown Map"
    local recommended_level = room.recommended_level and tostring(room.recommended_level) or "Unrated"
    local label = ("%s\nRecommended Level: %s"):format(map_name, recommended_level)
    local font = options.font or love.graphics.getFont()
    local title_color = options.title_color or { 1, 1, 1, 1 }
    local outline_color = options.outline_color or { 1, 1, 1, 0.92 }
    local scratch_reward = room.rewards and room.rewards.scratch or nil
    local reward_value = scratch_reward ~= nil and tostring(scratch_reward) or "0"

    if reward_value == "" then
        reward_value = "0"
    end

    local reward_prefix = "Reward: "
    local reward_prefix_w = font:getWidth(reward_prefix)
    local reward_value_w = font:getWidth(reward_value)
    local reward_w = reward_prefix_w + reward_value_w
    local reward_x = layout.label_x + layout.label_w - reward_w
    local reward_y = layout.label_y + (layout.label_h - font:getHeight()) / 2
    local left_label_w = math.max(1, layout.label_w - reward_w - REWARD_LABEL_GAP)

    love.graphics.setFont(font)
    love.graphics.setColor(title_color)
    love.graphics.printf(label, layout.label_x, layout.label_y, left_label_w, "left")
    love.graphics.print(reward_prefix, reward_x, reward_y)
    love.graphics.setColor(REWARD_VALUE_COLOR)
    love.graphics.print(reward_value, reward_x + reward_prefix_w, reward_y)

    love.graphics.setColor(PREVIEW_COLOR)
    love.graphics.rectangle("fill", layout.x, layout.y, layout.w, layout.h)
    love.graphics.setColor(outline_color)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", layout.x, layout.y, layout.w, layout.h)
    love.graphics.setLineWidth(1)

    love.graphics.setScissor(inner_x, inner_y, inner_w, inner_h)

    for _, tile in ipairs(room.tiles) do
        local center_x, center_y = getTileCenter(tile, min_x, min_y, origin_x, origin_y, scale)

        if tile.color then
            love.graphics.setColor(tile.color)
        elseif tile.corridor then
            love.graphics.setColor(CORRIDOR_COLOR)
        else
            love.graphics.setColor(TILE_COLOR)
        end

        love.graphics.polygon("fill", buildHexPoints(center_x, center_y, HEX_SIZE * scale))

        if tile.start then
            local start_label = tostring(tile.start)
            local marker_radius = math.max(11, HEX_SIZE * scale * 0.52)

            love.graphics.setColor(START_FILL_COLOR)
            love.graphics.polygon("fill", buildHexPoints(center_x, center_y, marker_radius))
            love.graphics.setColor(START_TEXT_COLOR)
            love.graphics.setFont(font)
            love.graphics.print(start_label, center_x - font:getWidth(start_label) / 2, center_y - font:getHeight() / 2)
        end
    end

    love.graphics.setColor(DOOR_COLOR)
    love.graphics.setLineWidth(2)

    for _, door in ipairs(room.doors or {}) do
        if door.a and door.b then
            local ax, ay = getTileCenter(door.a, min_x, min_y, origin_x, origin_y, scale)
            local bx, by = getTileCenter(door.b, min_x, min_y, origin_x, origin_y, scale)

            love.graphics.line(ax, ay, bx, by)
        end
    end

    love.graphics.setLineWidth(1)
    love.graphics.setScissor()
end

return map_preview

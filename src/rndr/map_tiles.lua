local map_tiles = {}

local HEX_SIZE = 54
local SQRT_3 = math.sqrt(3)
local TILE_COLOR = { 0.33, 0.49, 0.42, 1 }
local CORRIDOR_COLOR = { 0.27, 0.39, 0.35, 1 }

local function axialToPixel(q, r)
    return HEX_SIZE * SQRT_3 * (q + r / 2), HEX_SIZE * 1.5 * r
end

local function buildHexPoints(center_x, center_y)
    local points = {}

    for index = 0, 5 do
        local angle = math.rad(-90 + index * 60)
        points[#points + 1] = center_x + HEX_SIZE * math.cos(angle)
        points[#points + 1] = center_y + HEX_SIZE * math.sin(angle)
    end

    return points
end

local function getBounds(room)
    local min_x = math.huge
    local min_y = math.huge
    local max_x = -math.huge
    local max_y = -math.huge

    for _, tile in ipairs(room.tiles) do
        local x, y = axialToPixel(tile.q, tile.r)

        min_x = math.min(min_x, x - HEX_SIZE)
        min_y = math.min(min_y, y - HEX_SIZE)
        max_x = math.max(max_x, x + HEX_SIZE)
        max_y = math.max(max_y, y + HEX_SIZE)
    end

    return min_x, min_y, max_x, max_y
end

local function getCenteredOffset(room)
    local min_x, min_y, max_x, max_y = getBounds(room)
    local room_width = max_x - min_x
    local room_height = max_y - min_y
    local screen_width = love.graphics.getWidth()
    local screen_height = love.graphics.getHeight()

    return (screen_width - room_width) / 2 - min_x, (screen_height - room_height) / 2 - min_y
end

function map_tiles.axialToPixel(q, r)
    return axialToPixel(q, r)
end

function map_tiles.buildHexPoints(center_x, center_y)
    return buildHexPoints(center_x, center_y)
end

function map_tiles.getCenteredOffset(room)
    return getCenteredOffset(room)
end

function map_tiles.getBounds(room)
    return getBounds(room)
end

function map_tiles.draw(room, camera_x, camera_y)
    if not room or not room.tiles then
        return
    end

    local offset_x, offset_y = getCenteredOffset(room)
    offset_x = offset_x + (camera_x or 0)
    offset_y = offset_y + (camera_y or 0)

    for _, tile in ipairs(room.tiles) do
        local x, y = axialToPixel(tile.q, tile.r)

        if tile.corridor then
            love.graphics.setColor(CORRIDOR_COLOR)
        else
            love.graphics.setColor(TILE_COLOR)
        end

        love.graphics.polygon("fill", buildHexPoints(x + offset_x, y + offset_y))
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return map_tiles

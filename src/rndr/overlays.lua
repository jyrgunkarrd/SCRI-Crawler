local map_tiles = require("src.rndr.map_tiles")

local overlays = {}

local HOVER_COLOR = { 1, 1, 1, 0.16 }
local EXIT_MARKER_COLOR = { 0.88, 0.78, 0.48, 0.9 }
local EXIT_MARKER_RADIUS = 13
local DOOR_FILL_COLOR = { 1, 1, 1, 1 }
local DOOR_OUTLINE_COLOR = { 0.025, 0.02, 0.018, 1 }
local DOOR_RADIUS = 14

local function getDrawOffset(room, camera_x, camera_y)
    local offset_x, offset_y = map_tiles.getCenteredOffset(room)

    return offset_x + (camera_x or 0), offset_y + (camera_y or 0)
end

local function pointInPolygon(x, y, points)
    local inside = false
    local point_count = #points / 2
    local previous = point_count

    for current = 1, point_count do
        local current_x = points[current * 2 - 1]
        local current_y = points[current * 2]
        local previous_x = points[previous * 2 - 1]
        local previous_y = points[previous * 2]

        local crosses_y = current_y > y ~= (previous_y > y)

        if crosses_y then
            local intersection_x = (previous_x - current_x) * (y - current_y) / (previous_y - current_y) + current_x

            if x < intersection_x then
                inside = not inside
            end
        end

        previous = current
    end

    return inside
end

local function getHoveredTile(room, mouse_x, mouse_y, camera_x, camera_y)
    local offset_x, offset_y = getDrawOffset(room, camera_x, camera_y)

    for _, tile in ipairs(room.tiles) do
        local x, y = map_tiles.axialToPixel(tile.q, tile.r)
        local points = map_tiles.buildHexPoints(x + offset_x, y + offset_y)

        if pointInPolygon(mouse_x, mouse_y, points) then
            return tile, points
        end
    end

    return nil
end

function overlays.drawDoors(room, camera_x, camera_y)
    if not room or not room.doors then
        return
    end

    local offset_x, offset_y = getDrawOffset(room, camera_x, camera_y)

    for _, door in ipairs(room.doors) do
        if door.a and door.b then
            local ax, ay = map_tiles.axialToPixel(door.a.q, door.a.r)
            local bx, by = map_tiles.axialToPixel(door.b.q, door.b.r)
            local midpoint_x = (ax + bx) / 2 + offset_x
            local midpoint_y = (ay + by) / 2 + offset_y

            love.graphics.setColor(DOOR_FILL_COLOR)
            love.graphics.circle("fill", midpoint_x, midpoint_y, DOOR_RADIUS)
            love.graphics.setColor(DOOR_OUTLINE_COLOR)
            love.graphics.setLineWidth(3)
            love.graphics.circle("line", midpoint_x, midpoint_y, DOOR_RADIUS)
        end
    end

    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

function overlays.drawExitMarkers(room, camera_x, camera_y)
    if not room or not room.exit_markers then
        return
    end

    local offset_x, offset_y = getDrawOffset(room, camera_x, camera_y)

    love.graphics.setColor(EXIT_MARKER_COLOR)

    for _, marker in ipairs(room.exit_markers) do
        local exit_x, exit_y = map_tiles.axialToPixel(marker.exit_tile.q, marker.exit_tile.r)
        local corridor_x, corridor_y = map_tiles.axialToPixel(marker.corridor_tile.q, marker.corridor_tile.r)
        local marker_x = (exit_x + corridor_x) / 2 + offset_x
        local marker_y = (exit_y + corridor_y) / 2 + offset_y

        love.graphics.circle("fill", marker_x, marker_y, EXIT_MARKER_RADIUS)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function overlays.drawHover(room, camera_x, camera_y)
    if not room or not room.tiles then
        return
    end

    local mouse_x, mouse_y = love.mouse.getPosition()
    local _, points = getHoveredTile(room, mouse_x, mouse_y, camera_x, camera_y)

    if not points then
        return
    end

    love.graphics.setColor(HOVER_COLOR)
    love.graphics.polygon("fill", points)
    love.graphics.setColor(1, 1, 1, 1)
end

return overlays

local map_tiles = require("src.rndr.map_tiles")

local overlays = {}

local HOVER_COLOR = { 1, 1, 1, 0.16 }
local EXIT_MARKER_COLOR = { 0.88, 0.78, 0.48, 0.9 }
local EXIT_MARKER_RADIUS = 13
local DOOR_FILL_COLOR = { 1, 1, 1, 1 }
local DOOR_OUTLINE_COLOR = { 0.025, 0.02, 0.018, 1 }
local DOOR_RADIUS = 14
local MOVE_COLOR = { 0.8431, 0.9098, 0.0039, 1 }
local MOVE_PULSE_SPEED = 3.2
local MOVE_ALPHA_BASE = 0.12
local MOVE_ALPHA_PULSE = 0.08
local GHOST_ALPHA = 0.48
local GHOST_RADIUS = 42
local COST_BOX_PAD_X = 8
local COST_BOX_PAD_Y = 5

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

function overlays.drawMovementRange(room, camera_x, camera_y, movement_range)
    if not room or not movement_range then
        return
    end

    local offset_x, offset_y = getDrawOffset(room, camera_x, camera_y)
    local pulse = (math.sin(love.timer.getTime() * MOVE_PULSE_SPEED) + 1) / 2

    love.graphics.setColor(MOVE_COLOR[1], MOVE_COLOR[2], MOVE_COLOR[3], MOVE_ALPHA_BASE + MOVE_ALPHA_PULSE * pulse)

    for _, entry in pairs(movement_range) do
        local x, y = map_tiles.axialToPixel(entry.tile.q, entry.tile.r)

        love.graphics.polygon("fill", map_tiles.buildHexPoints(x + offset_x, y + offset_y))
    end

    love.graphics.setColor(1, 1, 1, 1)
end

local function drawGhostPortrait(agent, center_x, center_y)
    local image = map_tiles.getAgentPortrait(agent)

    if not image then
        return
    end

    local points = map_tiles.buildHexPoints(center_x, center_y, GHOST_RADIUS)
    local scale = (GHOST_RADIUS * 2) / math.min(image:getWidth(), image:getHeight())

    love.graphics.stencil(function()
        love.graphics.polygon("fill", points)
    end, "replace", 1)

    love.graphics.setStencilTest("equal", 1)
    love.graphics.setColor(1, 1, 1, GHOST_ALPHA)
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

    love.graphics.setColor(0, 0, 0, 0.72)
    love.graphics.setLineWidth(3)
    love.graphics.polygon("line", points)
    love.graphics.setLineWidth(1)
end

local function drawMovementCost(cost, center_x, center_y)
    local text = tostring(cost)
    local font = love.graphics.getFont()
    local text_w = font:getWidth(text)
    local text_h = font:getHeight()
    local box_w = text_w + COST_BOX_PAD_X * 2
    local box_h = text_h + COST_BOX_PAD_Y * 2
    local box_x = center_x - box_w / 2
    local box_y = center_y + GHOST_RADIUS * 0.36

    love.graphics.setColor(0, 0, 0, 0.9)
    love.graphics.rectangle("fill", box_x, box_y, box_w, box_h)
    love.graphics.setColor(MOVE_COLOR)
    love.graphics.print(text, box_x + COST_BOX_PAD_X, box_y + COST_BOX_PAD_Y - 1)
end

function overlays.drawMovementPreview(room, camera_x, camera_y, preview, agent)
    if not room or not preview or not preview.tile or not agent then
        return
    end

    local offset_x, offset_y = getDrawOffset(room, camera_x, camera_y)
    local path_points = {}

    for _, tile in ipairs(preview.path or {}) do
        local x, y = map_tiles.axialToPixel(tile.q, tile.r)

        path_points[#path_points + 1] = x + offset_x
        path_points[#path_points + 1] = y + offset_y
    end

    if #path_points >= 4 then
        love.graphics.setColor(0, 0, 0, 0.78)
        love.graphics.setLineWidth(7)
        love.graphics.line(path_points)
        love.graphics.setColor(MOVE_COLOR)
        love.graphics.setLineWidth(3)
        love.graphics.line(path_points)
        love.graphics.setLineWidth(1)
    end

    local ghost_x, ghost_y = map_tiles.axialToPixel(preview.tile.q, preview.tile.r)
    ghost_x = ghost_x + offset_x
    ghost_y = ghost_y + offset_y

    drawGhostPortrait(agent, ghost_x, ghost_y)
    drawMovementCost(preview.cost, ghost_x, ghost_y)
    love.graphics.setColor(1, 1, 1, 1)
end

return overlays

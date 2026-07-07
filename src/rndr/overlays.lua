local map_tiles = require("src.rndr.map_tiles")
local door_room_logic = require("src.sys.door_room_logic")

local overlays = {}

local HOVER_COLOR = { 1, 1, 1, 0.16 }
local EXIT_MARKER_COLOR = { 0.88, 0.78, 0.48, 0.9 }
local EXIT_MARKER_RADIUS = 13
local DOOR_LOCKED_FILL_COLOR = { 1, 0, 0.2863, 1 }
local DOOR_UNLOCKED_FILL_COLOR = { 0.4078, 0.6824, 0.5804, 1 }
local DOOR_OUTLINE_COLOR = { 0.025, 0.02, 0.018, 1 }
local DOOR_RADIUS = 14
local DOOR_SELECTED_PULSE_SPEED = 3.6
local DOOR_SELECTED_PULSE_AMOUNT = 0.12
local DOOR_DAMAGE_PULSE_SECONDS = 0.32
local DOOR_DAMAGE_PULSE_START_RADIUS = 18
local DOOR_DAMAGE_PULSE_END_RADIUS = 42
local DOOR_DAMAGE_PULSE_WIDTH = 5
local DOOR_HP_PULSE_COLOR = { 1, 0, 0.2863, 1 }
local DOOR_BP_PULSE_COLOR = { 0.4078, 0.6824, 0.5804, 1 }
local MOVE_COLOR = { 1, 1, 1, 1 }
local ZOC_COLOR = { 0.6118, 0, 0.0431, 1 }
local CARD_TARGET_COLOR = { 1, 0.2902, 0.4902, 1 }
local ENEMY_THREAT_COLOR = { 0.9961, 0, 0.4353, 1 }
local OVERLAY_BACKING_COLOR = { 0, 0, 0, 0.58 }
local MOVE_ALPHA = 1
local ZOC_ALPHA = 1
local CARD_RANGE_ALPHA = MOVE_ALPHA
local CARD_TARGET_ALPHA = MOVE_ALPHA
local OVERLAY_OUTLINE_COLOR = { 0, 0, 0, 0.92 }
local OVERLAY_OUTLINE_W = 3
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

local function tileKey(tile)
    return tostring(tile.q) .. "," .. tostring(tile.r)
end

local function buildTileLookup(room)
    local lookup = {}

    for _, tile in ipairs(room.tiles or {}) do
        lookup[tileKey(tile)] = tile
    end

    return lookup
end

local function getAdjacentTiles(lookup, tile)
    local directions = {
        { q = 1, r = 0 },
        { q = 1, r = -1 },
        { q = 0, r = -1 },
        { q = -1, r = 0 },
        { q = -1, r = 1 },
        { q = 0, r = 1 },
    }
    local adjacent = {}

    for _, direction in ipairs(directions) do
        local neighbor = lookup[tostring(tile.q + direction.q) .. "," .. tostring(tile.r + direction.r)]

        if neighbor then
            adjacent[#adjacent + 1] = neighbor
        end
    end

    return adjacent
end

local function drawStableHighlight(points, color, alpha)
    love.graphics.setColor(OVERLAY_BACKING_COLOR)
    love.graphics.polygon("fill", points)
    love.graphics.setColor(color[1], color[2], color[3], alpha)
    love.graphics.polygon("fill", points)
    love.graphics.setColor(OVERLAY_OUTLINE_COLOR)
    love.graphics.setLineWidth(OVERLAY_OUTLINE_W)
    love.graphics.polygon("line", points)
    love.graphics.setLineWidth(1)
end

local function drawDoorDamagePulses(door, center_x, center_y)
    if not door.damage_pulses then
        return
    end

    local now = love.timer.getTime()

    for index = #door.damage_pulses, 1, -1 do
        local pulse = door.damage_pulses[index]
        local elapsed = now - (pulse.started_at or now)

        if elapsed >= DOOR_DAMAGE_PULSE_SECONDS then
            table.remove(door.damage_pulses, index)
        else
            local t = math.max(0, math.min(elapsed / DOOR_DAMAGE_PULSE_SECONDS, 1))
            local eased = 1 - (1 - t) * (1 - t) * (1 - t)
            local radius = DOOR_DAMAGE_PULSE_START_RADIUS
                + (DOOR_DAMAGE_PULSE_END_RADIUS - DOOR_DAMAGE_PULSE_START_RADIUS) * eased
            local alpha = 1 - t
            local color = pulse.stat == "bp" and DOOR_BP_PULSE_COLOR or DOOR_HP_PULSE_COLOR

            love.graphics.setColor(color[1], color[2], color[3], alpha)
            love.graphics.setLineWidth(DOOR_DAMAGE_PULSE_WIDTH)
            love.graphics.circle("line", center_x, center_y, radius, 96)
            love.graphics.setLineWidth(1)
        end
    end
end

function overlays.drawDoors(room, camera_x, camera_y, selected_door)
    if not room or not room.doors then
        return
    end

    for _, door in ipairs(room.doors) do
        if door.a and door.b then
            local midpoint_x, midpoint_y = door_room_logic.getDoorCenter(room, door, camera_x, camera_y)
            local pulse_scale = door == selected_door
                and (1 + math.sin(love.timer.getTime() * DOOR_SELECTED_PULSE_SPEED) * DOOR_SELECTED_PULSE_AMOUNT)
                or 1
            local radius = DOOR_RADIUS * pulse_scale

            drawDoorDamagePulses(door, midpoint_x, midpoint_y)
            love.graphics.setColor(door_room_logic.isUnlocked(door) and DOOR_UNLOCKED_FILL_COLOR or DOOR_LOCKED_FILL_COLOR)
            love.graphics.circle("fill", midpoint_x, midpoint_y, radius)
            love.graphics.setColor(DOOR_OUTLINE_COLOR)
            love.graphics.setLineWidth(3)
            love.graphics.circle("line", midpoint_x, midpoint_y, radius)
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

    for _, entry in pairs(movement_range) do
        local x, y = map_tiles.axialToPixel(entry.tile.q, entry.tile.r)

        drawStableHighlight(
            map_tiles.buildHexPoints(x + offset_x, y + offset_y),
            MOVE_COLOR,
            MOVE_ALPHA
        )
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function overlays.drawEnemySelectionRange(room, camera_x, camera_y, overlay)
    if not room or not overlay then
        return
    end

    local offset_x, offset_y = getDrawOffset(room, camera_x, camera_y)

    for _, entry in pairs(overlay.movement or {}) do
        local x, y = map_tiles.axialToPixel(entry.tile.q, entry.tile.r)

        drawStableHighlight(
            map_tiles.buildHexPoints(x + offset_x, y + offset_y),
            MOVE_COLOR,
            MOVE_ALPHA
        )
    end

    for _, entry in pairs(overlay.threat or {}) do
        local x, y = map_tiles.axialToPixel(entry.tile.q, entry.tile.r)

        drawStableHighlight(
            map_tiles.buildHexPoints(x + offset_x, y + offset_y),
            ENEMY_THREAT_COLOR,
            MOVE_ALPHA
        )
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function overlays.drawEnemyZonesOfControl(room, camera_x, camera_y, movement_range)
    if not room or not room.tiles or not movement_range or not next(movement_range) then
        return
    end

    local offset_x, offset_y = getDrawOffset(room, camera_x, camera_y)
    local lookup = buildTileLookup(room)
    local highlighted = {}

    for _, tile in ipairs(room.tiles) do
        if tile.enemy then
            for _, adjacent in ipairs(getAdjacentTiles(lookup, tile)) do
                local key = tileKey(adjacent)

                if movement_range[key] and not highlighted[key] and door_room_logic.canTraverseBetween(room, tile, adjacent) then
                    local x, y = map_tiles.axialToPixel(adjacent.q, adjacent.r)

                    drawStableHighlight(
                        map_tiles.buildHexPoints(x + offset_x, y + offset_y),
                        ZOC_COLOR,
                        ZOC_ALPHA
                    )
                    highlighted[key] = true
                end
            end
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function overlays.drawCardPlayRange(room, camera_x, camera_y, overlay)
    if not room or not overlay then
        return
    end

    local offset_x, offset_y = getDrawOffset(room, camera_x, camera_y)

    for _, tile in pairs(overlay.range_tiles or {}) do
        local x, y = map_tiles.axialToPixel(tile.q, tile.r)

        drawStableHighlight(
            map_tiles.buildHexPoints(x + offset_x, y + offset_y),
            MOVE_COLOR,
            CARD_RANGE_ALPHA
        )
    end

    for _, tile in pairs(overlay.target_tiles or {}) do
        local x, y = map_tiles.axialToPixel(tile.q, tile.r)

        drawStableHighlight(
            map_tiles.buildHexPoints(x + offset_x, y + offset_y),
            CARD_TARGET_COLOR,
            CARD_TARGET_ALPHA
        )
    end

    for _, door in pairs(overlay.target_doors or {}) do
        local x, y = door_room_logic.getDoorCenter(room, door, camera_x, camera_y)

        if x and y then
            love.graphics.setColor(OVERLAY_BACKING_COLOR)
            love.graphics.circle("fill", x, y, DOOR_RADIUS + 8, 96)
            love.graphics.setColor(CARD_TARGET_COLOR[1], CARD_TARGET_COLOR[2], CARD_TARGET_COLOR[3], CARD_TARGET_ALPHA)
            love.graphics.circle("fill", x, y, DOOR_RADIUS + 8, 96)
            love.graphics.setColor(OVERLAY_OUTLINE_COLOR)
            love.graphics.setLineWidth(OVERLAY_OUTLINE_W)
            love.graphics.circle("line", x, y, DOOR_RADIUS + 8, 96)
            love.graphics.setLineWidth(1)
        end
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

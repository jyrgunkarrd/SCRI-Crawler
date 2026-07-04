local map_tiles = require("src.rndr.map_tiles")

local camera = {
    x = 0,
    y = 0,
    dragging = false,
}

local PAN_SPEED = 700
local EDGE_MARGIN = 160

local function clamp(value, min_value, max_value)
    return math.max(min_value, math.min(max_value, value))
end

local function getClampRange(room)
    local min_x, min_y, max_x, max_y = map_tiles.getBounds(room)
    local offset_x, offset_y = map_tiles.getCenteredOffset(room)
    local screen_width = love.graphics.getWidth()
    local screen_height = love.graphics.getHeight()
    local centered_min_x = min_x + offset_x
    local centered_max_x = max_x + offset_x
    local centered_min_y = min_y + offset_y
    local centered_max_y = max_y + offset_y

    return EDGE_MARGIN - centered_max_x,
        screen_width - EDGE_MARGIN - centered_min_x,
        EDGE_MARGIN - centered_max_y,
        screen_height - EDGE_MARGIN - centered_min_y
end

function camera.reset()
    camera.x = 0
    camera.y = 0
    camera.dragging = false
end

function camera.clampToRoom(room)
    if not room or not room.tiles then
        return
    end

    local min_x, max_x, min_y, max_y = getClampRange(room)

    camera.x = clamp(camera.x, min_x, max_x)
    camera.y = clamp(camera.y, min_y, max_y)
end

function camera.update(dt, room)
    local dx = 0
    local dy = 0

    if love.keyboard.isDown("a", "left") then
        dx = dx + PAN_SPEED * dt
    end

    if love.keyboard.isDown("d", "right") then
        dx = dx - PAN_SPEED * dt
    end

    if love.keyboard.isDown("w", "up") then
        dy = dy + PAN_SPEED * dt
    end

    if love.keyboard.isDown("s", "down") then
        dy = dy - PAN_SPEED * dt
    end

    camera.x = camera.x + dx
    camera.y = camera.y + dy

    camera.clampToRoom(room)
end

function camera.mousepressed(button)
    if button == 1 or button == 2 or button == 3 then
        camera.dragging = true
    end
end

function camera.mousereleased(button)
    if button == 1 or button == 2 or button == 3 then
        camera.dragging = false
    end
end

function camera.mousemoved(dx, dy, room)
    if not camera.dragging then
        return
    end

    camera.x = camera.x + dx
    camera.y = camera.y + dy

    camera.clampToRoom(room)
end

function camera.getOffset()
    return camera.x, camera.y
end

return camera

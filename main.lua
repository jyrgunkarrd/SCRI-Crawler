local map_pieces = require("data.map_pieces")
local map_build = require("src.sys.map_build")
local map_tiles = require("src.rndr.map_tiles")
local overlays = require("src.rndr.overlays")
local camera = require("src.rndr.camera")

local room

local function findMapPiece(id)
    for _, piece in ipairs(map_pieces) do
        if piece.id == id then
            return piece
        end
    end

    error(("Map piece '%s' was not found."):format(id))
end

function love.load()
    love.math.setRandomSeed(os.time())
    love.graphics.setBackgroundColor(0.055, 0.058, 0.068)

    local start_definition = findMapPiece("START")
    room = map_build.buildRoom(start_definition, map_pieces)
    camera.reset()
end

function love.update(dt)
    camera.update(dt, room)
end

function love.draw()
    local camera_x, camera_y = camera.getOffset()

    map_tiles.draw(room, camera_x, camera_y)
    overlays.drawExitMarkers(room, camera_x, camera_y)
    overlays.drawHover(room, camera_x, camera_y)
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    elseif key == "r" then
        room = map_build.buildRoom(findMapPiece("START"), map_pieces)
        camera.reset()
    end
end

function love.mousepressed(_, _, button)
    camera.mousepressed(button)
end

function love.mousereleased(_, _, button)
    camera.mousereleased(button)
end

function love.mousemoved(_, _, dx, dy)
    camera.mousemoved(dx, dy, room)
end

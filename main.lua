local function hasArg(name)
    if not arg then
        return false
    end

    for _, value in ipairs(arg) do
        if value == name then
            return true
        end
    end

    return false
end

if hasArg("--portrait-tool") then
    local portrait_editor = require("tools.hex_portrait_editor")

    function love.load()
        portrait_editor.load()
    end

    function love.update(dt)
        portrait_editor.update(dt)
    end

    function love.draw()
        portrait_editor.draw()
    end

    function love.keypressed(key, scancode, isrepeat)
        portrait_editor.keypressed(key, scancode, isrepeat)
    end

    function love.mousepressed(x, y, button, istouch, presses)
        portrait_editor.mousepressed(x, y, button, istouch, presses)
    end

    function love.mousereleased(x, y, button, istouch, presses)
        portrait_editor.mousereleased(x, y, button, istouch, presses)
    end

    function love.mousemoved(x, y, dx, dy, istouch)
        portrait_editor.mousemoved(x, y, dx, dy, istouch)
    end

    function love.wheelmoved(x, y)
        portrait_editor.wheelmoved(x, y)
    end

    return
end

if hasArg("--map-editor") then
    local map_editor = require("tools.map_editor")

    function love.load()
        map_editor.load()
    end

    function love.update(dt)
        map_editor.update(dt)
    end

    function love.draw()
        map_editor.draw()
    end

    function love.keypressed(key, scancode, isrepeat)
        map_editor.keypressed(key, scancode, isrepeat)
    end

    function love.keyreleased(key, scancode)
        map_editor.keyreleased(key, scancode)
    end

    function love.mousepressed(x, y, button, istouch, presses)
        map_editor.mousepressed(x, y, button, istouch, presses)
    end

    function love.mousereleased(x, y, button, istouch, presses)
        map_editor.mousereleased(x, y, button, istouch, presses)
    end

    function love.mousemoved(x, y, dx, dy, istouch)
        map_editor.mousemoved(x, y, dx, dy, istouch)
    end

    function love.wheelmoved(x, y)
        map_editor.wheelmoved(x, y)
    end

    return
end

local map_pieces = require("data.map_pieces")
local map_build = require("src.sys.map_build")
local map_tiles = require("src.rndr.map_tiles")
local overlays = require("src.rndr.overlays")
local camera = require("src.rndr.camera")

local room
local MAP_FILE_PATH = "data.map_files.map_001"

local function findMapPiece(id)
    for _, piece in ipairs(map_pieces) do
        if piece.id == id then
            return piece
        end
    end

    error(("Map piece '%s' was not found."):format(id))
end

local function buildProceduralRoom()
    return map_build.buildRoom(findMapPiece("START"), map_pieces)
end

local function loadMapFile()
    local ok, map_file = pcall(require, MAP_FILE_PATH)

    if not ok then
        print("Unable to load map file, falling back to procedural map: " .. tostring(map_file))
        return buildProceduralRoom()
    end

    local tiles = {}

    for index, tile in ipairs(map_file.tiles or {}) do
        tiles[index] = {
            q = tile.q,
            r = tile.r,
            chamber = true,
            start = tile.start,
            corridor = tile.corridor,
            palette = tile.palette,
            swatch = tile.swatch,
            color = tile.color,
        }
    end

    return {
        id = map_file.id or "map_001",
        target_count = #tiles,
        chamber_tiles = tiles,
        exit_markers = {},
        doors = map_file.doors or {},
        tiles = tiles,
    }
end

function love.load()
    love.math.setRandomSeed(os.time())
    love.graphics.setDefaultFilter("linear", "linear", 1)
    love.graphics.setBackgroundColor(0.055, 0.058, 0.068)

    room = loadMapFile()
    camera.reset()
end

function love.update(dt)
    camera.update(dt, room)
end

function love.draw()
    local camera_x, camera_y = camera.getOffset()

    map_tiles.draw(room, camera_x, camera_y)
    overlays.drawDoors(room, camera_x, camera_y)
    overlays.drawExitMarkers(room, camera_x, camera_y)
    overlays.drawHover(room, camera_x, camera_y)
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    elseif key == "r" then
        package.loaded[MAP_FILE_PATH] = nil
        room = loadMapFile()
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

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

    function love.textinput(text)
        map_editor.textinput(text)
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

local states_core = require("src.states.states_core")

function love.load()
    states_core.load("JACL")
end

function love.update(dt)
    states_core.update(dt)
end

function love.draw()
    states_core.draw()
end

function love.keypressed(...)
    states_core.keypressed(...)
end

function love.mousepressed(...)
    states_core.mousepressed(...)
end

function love.mousereleased(...)
    states_core.mousereleased(...)
end

function love.mousemoved(...)
    states_core.mousemoved(...)
end

function love.wheelmoved(...)
    states_core.wheelmoved(...)
end

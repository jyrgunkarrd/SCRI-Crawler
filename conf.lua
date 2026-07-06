function love.conf(t)
    local tool_mode = nil

    if arg then
        for _, value in ipairs(arg) do
            if value == "--portrait-tool" then
                tool_mode = "portrait"
            elseif value == "--map-editor" then
                tool_mode = "map_editor"
            end
        end
    end

    t.identity = "scri-diablo"
    t.version = "11.5"
    t.console = false

    if tool_mode then
        t.window.title = tool_mode == "map_editor" and "SCRI Diablo Map Editor" or "SCRI Diablo Hex Portrait Editor"
        t.window.width = 1280
        t.window.height = 900
        t.window.fullscreen = false
        t.window.resizable = true
    else
        t.window.title = "SCRI Diablo"
        t.window.width = 1920
        t.window.height = 1080
        t.window.fullscreen = true
        t.window.fullscreentype = "exclusive"
        t.window.resizable = false
    end

    t.window.vsync = 1
    t.window.msaa = 4
end

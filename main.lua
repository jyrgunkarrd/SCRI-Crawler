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
local agent_logic = require("src.sys.agent_logic")
local agent_uix = require("src.rndr.agent_uix")
local deck_hand_vis = require("src.rndr.deck_hand_vis")

local room
local DEV_MAP_CONFIG_PATH = "data.dev_map"
local DEV_SQUAD_PATH = "data.dev_squad"
local AGENTS_PATH = "data.agents"

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

local function tileSort(a, b)
    if a.r == b.r then
        return a.q < b.q
    end

    return a.r < b.r
end

local function getAgentDefinitionMap()
    package.loaded[AGENTS_PATH] = nil

    local ok, agent_definitions = pcall(require, AGENTS_PATH)
    local agents_by_id = {}

    if not ok then
        print("Unable to load agent definitions: " .. tostring(agent_definitions))
        return agents_by_id
    end

    for _, agent in ipairs(agent_definitions) do
        agents_by_id[agent.id] = agent
    end

    return agents_by_id
end

local function getDevSquadAgentIds()
    package.loaded[DEV_SQUAD_PATH] = nil

    local ok, dev_squad = pcall(require, DEV_SQUAD_PATH)

    if not ok then
        print("Unable to load dev squad: " .. tostring(dev_squad))
        return {}
    end

    return dev_squad.playeragents or {}
end

local function populatePlayerAgents(target_room)
    local agents_by_id = getAgentDefinitionMap()
    local agent_ids = getDevSquadAgentIds()
    local start_tiles = {}

    for _, tile in ipairs(target_room.tiles or {}) do
        tile.agent = nil

        if tile.start then
            start_tiles[#start_tiles + 1] = tile
        end
    end

    table.sort(start_tiles, tileSort)

    for index, agent_id in ipairs(agent_ids) do
        local tile = start_tiles[index]
        local agent = agents_by_id[agent_id]

        if not tile then
            print("No start tile available for agent '" .. tostring(agent_id) .. "'.")
            break
        end

        if not agent then
            print("Unknown agent id in dev squad: " .. tostring(agent_id))
        else
            agent_logic.ensureRuntimeStats(agent)
            tile.agent = agent
        end
    end
end

local function getDevMapPath()
    package.loaded[DEV_MAP_CONFIG_PATH] = nil

    local ok, config = pcall(require, DEV_MAP_CONFIG_PATH)

    if not ok then
        print("Unable to load dev map config: " .. tostring(config))
        return nil
    end

    local map = type(config) == "table" and config.map or config

    if type(map) ~= "string" or map == "" then
        print("Dev map config is missing a map name.")
        return nil
    end

    if map:match("%.lua$") then
        return map
    end

    if map:match("/") then
        return map .. ".lua"
    end

    return "assets/maps/" .. map .. ".lua"
end

local function loadMapFile()
    local map_path = getDevMapPath()

    if not map_path then
        local fallback_room = buildProceduralRoom()
        populatePlayerAgents(fallback_room)
        return fallback_room
    end

    local chunk, load_error = love.filesystem.load(map_path)

    if not chunk then
        print("Unable to load map file '" .. map_path .. "', falling back to procedural map: " .. tostring(load_error))
        local fallback_room = buildProceduralRoom()
        populatePlayerAgents(fallback_room)
        return fallback_room
    end

    local ok, map_file = pcall(chunk)

    if not ok then
        print("Unable to run map file '" .. map_path .. "', falling back to procedural map: " .. tostring(map_file))
        local fallback_room = buildProceduralRoom()
        populatePlayerAgents(fallback_room)
        return fallback_room
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

    local loaded_room = {
        id = map_file.id or "map_001",
        path = map_path,
        target_count = #tiles,
        chamber_tiles = tiles,
        exit_markers = {},
        doors = map_file.doors or {},
        tiles = tiles,
    }

    populatePlayerAgents(loaded_room)

    return loaded_room
end

function love.load()
    love.math.setRandomSeed(os.time())
    love.graphics.setDefaultFilter("linear", "linear", 1)
    love.graphics.setFont(love.graphics.newFont("assets/fonts/Furore.otf", 20))
    love.graphics.setBackgroundColor(0.055, 0.058, 0.068)

    room = loadMapFile()
    agent_logic.clearSelection()
    deck_hand_vis.load()
    camera.reset()
end

function love.update(dt)
    camera.update(dt, room)
    local camera_x, camera_y = camera.getOffset()

    agent_logic.update(dt, room, camera_x, camera_y, agent_uix.isModalOpen())
end

function love.draw()
    local camera_x, camera_y = camera.getOffset()
    local modal_open = agent_uix.isModalOpen()

    map_tiles.drawBase(room, camera_x, camera_y)
    if not modal_open then
        overlays.drawMovementRange(room, camera_x, camera_y, agent_logic.getMovementRange())
    end
    if not modal_open then
        overlays.drawHover(room, camera_x, camera_y)
    end
    local movement_animation = agent_logic.getMovementAnimation()

    map_tiles.drawPortraits(
        room,
        camera_x,
        camera_y,
        agent_logic.getSelectedTile(),
        movement_animation and movement_animation.agent or nil
    )
    map_tiles.drawMovingAgent(room, camera_x, camera_y, movement_animation)
    if not modal_open then
        overlays.drawMovementPreview(room, camera_x, camera_y, agent_logic.getMovementPreview(), agent_logic.getSelectedAgent())
    end
    map_tiles.drawSelectionShout(room, camera_x, camera_y, agent_logic.getSelectedTile(), agent_logic.getSelectionShout())
    overlays.drawDoors(room, camera_x, camera_y)
    overlays.drawExitMarkers(room, camera_x, camera_y)
    agent_uix.draw()

    if not modal_open then
        deck_hand_vis.draw()
    end
end

function love.keypressed(key)
    if key == "escape" then
        if not agent_uix.closeModal() then
            love.event.quit()
        end
    elseif key == "r" then
        agent_uix.closeModal()
        room = loadMapFile()
        agent_logic.clearSelection()
        deck_hand_vis.reload()
        camera.reset()
    elseif key == "," then
        agent_logic.selectAdjacentAgent(room, -1)
    elseif key == "." then
        agent_logic.selectAdjacentAgent(room, 1)
    end
end

function love.mousepressed(x, y, button)
    if agent_uix.mousepressed(x, y, button) then
        return
    end

    if agent_uix.isModalOpen() then
        return
    end

    local camera_x, camera_y = camera.getOffset()

    if not agent_logic.handleMousePressed(room, x, y, button, camera_x, camera_y) then
        camera.mousepressed(button)
    end
end

function love.mousereleased(_, _, button)
    camera.mousereleased(button)
end

function love.mousemoved(_, _, dx, dy)
    camera.mousemoved(dx, dy, room)
end

function love.wheelmoved(x, y)
    if not agent_uix.isModalOpen() then
        deck_hand_vis.wheelmoved(x, y)
    end
end

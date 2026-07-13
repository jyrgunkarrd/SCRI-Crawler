local map_pieces = require("data.map_pieces")
local map_build = require("src.sys.map_build")
local map_tiles = require("src.rndr.map_tiles")
local overlays = require("src.rndr.overlays")
local camera = require("src.rndr.camera")
local agent_logic = require("src.sys.agent_logic")
local agent_uix = require("src.rndr.agent_uix")
local deck_hand_vis = require("src.rndr.deck_hand_vis")
local event_spawn = require("src.sys.event_spawn")
local card_play = require("src.sys.card_play")
local action_vis = require("src.rndr.action_vis")
local phase_track = require("src.rndr.phase_track")
local phase_rules = require("src.sys.phase_rules")
local sfx_logic = require("src.sys.sfx_logic")
local enemy_ai = require("src.sys.enemy_ai")
local door_room_logic = require("src.sys.door_room_logic")
local jacl_state = require("src.states.jacl_state")

local states_core = {
    states = {},
    current = nil,
    current_name = nil,
}

local DEV_MAP_CONFIG_PATH = "data.dev_map"
local DEV_SQUAD_PATH = "data.dev_squad"
local AGENTS_PATH = "data.agents"

local mission = {
    name = "mission",
    room = nil,
}

local function playPhaseStartSfx(phase)
    if phase == phase_rules.PHASE_MISSION then
        sfx_logic.playNamed("mission_phase")
    elseif phase == phase_rules.PHASE_SERMON then
        if not sfx_logic.playNamed("sermon_phase") then
            sfx_logic.playNamed("srmon_phase")
        end
    end
end

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
    local placed_agents = {}

    for _, tile in ipairs(target_room.tiles or {}) do
        tile.agent = nil
        tile.enemy = nil

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
            placed_agents[#placed_agents + 1] = agent
        end
    end

    agent_logic.initializeActionHands(placed_agents)
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
            spawn_event = tile.spawn_event,
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

    door_room_logic.initialize(loaded_room)
    populatePlayerAgents(loaded_room)

    return loaded_room
end

local function triggerPlayerRoomSpawns(target_room)
    if event_spawn.triggerForPlayerRooms(target_room) then
        agent_logic.refreshMovementRange(target_room)
    end
end

local function resetMission()
    mission.room = loadMapFile()
    event_spawn.initialize(mission.room)
    triggerPlayerRoomSpawns(mission.room)
    agent_logic.clearSelection()
    deck_hand_vis.reload()
    map_tiles.clearAnimations()
    phase_rules.load()
    camera.reset()
end

function mission:enter()
    love.math.setRandomSeed(os.time())
    love.graphics.setDefaultFilter("linear", "linear", 1)
    love.graphics.setFont(love.graphics.newFont("assets/fonts/Furore.otf", 20))
    love.graphics.setBackgroundColor(0.055, 0.058, 0.068)

    self.room = loadMapFile()
    event_spawn.initialize(self.room)
    triggerPlayerRoomSpawns(self.room)
    agent_logic.clearSelection()
    deck_hand_vis.load()
    map_tiles.clearAnimations()
    phase_rules.load()
    camera.reset()
end

function mission:update(dt)
    camera.update(dt, self.room)
    local camera_x, camera_y = camera.getOffset()
    local mission_phase = phase_rules.isMissionPhase()
    local phase_before_update = phase_rules.getCurrentPhase()

    if phase_rules.isStartPhase() then
        agent_logic.refreshAgents(self.room)
    end

    agent_logic.update(dt, self.room, camera_x, camera_y, agent_uix.isModalOpen() or not mission_phase)
    triggerPlayerRoomSpawns(self.room)
    map_tiles.update(dt)
    action_vis.update(dt)
    enemy_ai.update(dt)

    if not action_vis.isActive() and not agent_logic.getMovementAnimation() and not enemy_ai.isMoving() then
        local hazard_event = enemy_ai.takePendingHazardEvent()

        if hazard_event then
            if hazard_event.eliminated
                and (agent_logic.getSelectedAgent() == hazard_event.target
                    or agent_logic.getSelectedEnemy() == hazard_event.target)
            then
                agent_logic.clearSelection()
            end

            action_vis.start(hazard_event)
        end
    end

    if phase_rules.update(dt) then
        local current_phase = phase_rules.getCurrentPhase()

        playPhaseStartSfx(current_phase)

        if phase_before_update ~= phase_rules.PHASE_START and current_phase == phase_rules.PHASE_START then
            agent_logic.drawAgentHands(self.room)
        end

        if not phase_rules.isMissionPhase() then
            card_play.cancelDrag()
        end
    end

    if phase_rules.isSermonPhase() and not action_vis.isActive() and not enemy_ai.isMoving() then
        local event = enemy_ai.takeNextAction(self.room)

        if event then
            if event.eliminated and agent_logic.getSelectedAgent() == event.target then
                agent_logic.clearSelection()
            else
                agent_logic.refreshMovementRange(self.room)
            end

            action_vis.start(event)
        elseif not enemy_ai.hasReadyEnemies(self.room) then
            agent_logic.refreshMovementRange(self.room)
            if phase_rules.advanceSermon() then
                agent_logic.discardAgentHands(self.room)
            end
        end
    end
end

function mission:draw()
    local camera_x, camera_y = camera.getOffset()
    local modal_open = agent_uix.isModalOpen()
    local mission_phase = phase_rules.isMissionPhase()

    map_tiles.drawBase(self.room, camera_x, camera_y)
    if not modal_open and mission_phase then
        if card_play.isDragging() then
            overlays.drawCardPlayRange(self.room, camera_x, camera_y, card_play.getOverlay(self.room))
        else
            overlays.drawMovementRange(self.room, camera_x, camera_y, agent_logic.getMovementRange())
            overlays.drawEnemyZonesOfControl(self.room, camera_x, camera_y, agent_logic.getMovementRange())
        end
    end
    if not modal_open and not card_play.isDragging() and agent_logic.getSelectedEnemy() then
        overlays.drawEnemySelectionRange(self.room, camera_x, camera_y, agent_logic.getEnemyOverlay())
    end
    if not modal_open then
        overlays.drawHover(self.room, camera_x, camera_y)
    end
    local movement_animation = agent_logic.getMovementAnimation()
    local enemy_movement_animation = enemy_ai.getMovementAnimation()
    local active_movement_animation = movement_animation or enemy_movement_animation

    map_tiles.drawPortraits(
        self.room,
        camera_x,
        camera_y,
        agent_logic.getSelectedTile(),
        active_movement_animation and active_movement_animation.agent or nil,
        active_movement_animation and active_movement_animation.kind or "agent"
    )
    map_tiles.drawMovingAgent(self.room, camera_x, camera_y, active_movement_animation)
    if not modal_open and mission_phase and not card_play.isDragging() then
        overlays.drawMovementPreview(
            self.room,
            camera_x,
            camera_y,
            agent_logic.getMovementPreview(),
            agent_logic.getSelectedAgent()
        )
    end
    map_tiles.drawSelectionShout(self.room, camera_x, camera_y, agent_logic.getSelectedTile(), agent_logic.getSelectionShout())
    overlays.drawDoors(self.room, camera_x, camera_y, agent_logic.getSelectedDoor())
    overlays.drawExitMarkers(self.room, camera_x, camera_y)
    phase_track.draw(phase_rules.getRound(), phase_rules.getCurrentPhase(), phase_rules.isRoundFlashActive())
    agent_uix.draw()

    if not modal_open and mission_phase then
        deck_hand_vis.draw()
    end

    action_vis.draw()
end

function mission:keypressed(key)
    if key == "escape" then
        if card_play.isDragging() then
            card_play.cancelDrag()
        elseif not agent_uix.closeModal() then
            love.event.quit()
        end
    elseif key == "r" then
        agent_uix.closeModal()
        card_play.cancelDrag()
        agent_logic.clearSelection()
        resetMission()
    elseif key == "space" then
        if phase_rules.advanceMission() then
            playPhaseStartSfx(phase_rules.getCurrentPhase())
            enemy_ai.refreshEnemies(self.room)
            card_play.cancelDrag()
        end
    elseif key == "," then
        agent_logic.selectAdjacentAgent(self.room, -1)
    elseif key == "." then
        agent_logic.selectAdjacentAgent(self.room, 1)
    end
end

function mission:mousepressed(x, y, button)
    if agent_uix.mousepressed(x, y, button) then
        return
    end

    if agent_uix.isModalOpen() then
        return
    end

    local camera_x, camera_y = camera.getOffset()

    if phase_rules.isMissionPhase() and deck_hand_vis.mousepressed(self.room, button) then
        return
    end

    if not agent_logic.handleMousePressed(self.room, x, y, button, camera_x, camera_y) then
        camera.mousepressed(button)
    end
end

function mission:mousereleased(x, y, button)
    local camera_x, camera_y = camera.getOffset()

    if agent_uix.mousereleased(x, y, button) then
        return
    end

    if phase_rules.isMissionPhase() and deck_hand_vis.mousereleased(self.room, x, y, button, camera_x, camera_y) then
        return
    elseif button == 1 and card_play.isDragging() then
        card_play.cancelDrag()
    end

    camera.mousereleased(button)
end

function mission:mousemoved(_, _, dx, dy)
    camera.mousemoved(dx, dy, self.room)
end

function mission:wheelmoved(x, y)
    if agent_uix.isModalOpen() then
        agent_uix.wheelmoved(x, y)
    elseif phase_rules.isMissionPhase() then
        deck_hand_vis.wheelmoved(x, y)
    end
end

function states_core.register(name, state)
    if type(name) ~= "string" or name == "" then
        error("State name must be a non-empty string.")
    end

    if type(state) ~= "table" then
        error("State '" .. name .. "' must be a table.")
    end

    states_core.states[name] = state
end

function states_core.switch(name, ...)
    local next_state = states_core.states[name]

    if not next_state then
        error("Unknown state: " .. tostring(name))
    end

    if states_core.current and states_core.current.leave then
        states_core.current:leave(name)
    end

    local previous_name = states_core.current_name
    states_core.current = next_state
    states_core.current_name = name

    if next_state.enter then
        next_state:enter(previous_name, ...)
    end
end

function states_core.getCurrentName()
    return states_core.current_name
end

function states_core.getCurrent()
    return states_core.current
end

function states_core.load(initial_state)
    states_core.switch(initial_state or "JACL")
end

function states_core.update(dt)
    if states_core.current and states_core.current.update then
        states_core.current:update(dt)
    end
end

function states_core.draw()
    if states_core.current and states_core.current.draw then
        states_core.current:draw()
    end
end

function states_core.keypressed(...)
    if states_core.current and states_core.current.keypressed then
        states_core.current:keypressed(...)
    end
end

function states_core.mousepressed(...)
    if states_core.current and states_core.current.mousepressed then
        states_core.current:mousepressed(...)
    end
end

function states_core.mousereleased(...)
    if states_core.current and states_core.current.mousereleased then
        states_core.current:mousereleased(...)
    end
end

function states_core.mousemoved(...)
    if states_core.current and states_core.current.mousemoved then
        states_core.current:mousemoved(...)
    end
end

function states_core.wheelmoved(...)
    if states_core.current and states_core.current.wheelmoved then
        states_core.current:wheelmoved(...)
    end
end

states_core.register("JACL", jacl_state)
states_core.register("mission", mission)

return states_core

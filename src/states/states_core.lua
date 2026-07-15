local map_pieces = require("data.map_pieces")
local map_build = require("src.sys.map_build")
local map_tiles = require("src.rndr.map_tiles")
local overlays = require("src.rndr.overlays")
local camera = require("src.rndr.camera")
local agent_logic = require("src.sys.agent_logic")
local equip_logic = require("src.sys.equip_logic")
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
local mission_completion = require("src.sys.mission_completion")
local rumor_missions = require("src.sys.rumor_missions")
local luggage = require("src.sys.luggage")
local reward_uix = require("src.rndr.reward_uix")
local cache_rail = require("src.rndr.jacl_equipment_cache_rail")
local jacl_state = require("src.states.jacl_state")

local states_core = {
    states = {},
    current = nil,
    current_name = nil,
    transition = nil,
}

local unpackValues = table.unpack or unpack
local SHUTTER_CLOSE_SECONDS = 0.20
local SHUTTER_HOLD_SECONDS = 0.10
local SHUTTER_OPEN_SECONDS = 0.20
local SHUTTER_COLOR = { 0, 0, 0, 1 }
local SHUTTER_ACCENT_COLOR = { 165 / 255, 0, 74 / 255, 1 }
local SHUTTER_TEXT_COLOR = { 1, 1, 1, 1 }

local DEV_MAP_CONFIG_PATH = "data.dev_map"
local DEV_SQUAD_PATH = "data.dev_squad"
local AGENTS_PATH = "data.agents"

local mission = {
    name = "mission",
    room = nil,
    agents = {},
    completion_tracker = nil,
    completion_modal_open = false,
}

local MISSION_COMPLETE_BACKDROP_COLOR = { 0, 0, 0, 0.80 }
local MISSION_COMPLETE_FILL_COLOR = { 0, 0, 0, 0.96 }
local MISSION_COMPLETE_BORDER_COLOR = { 1, 1, 1, 1 }
local MISSION_COMPLETE_TEXT_COLOR = { 1, 1, 1, 1 }
local MISSION_COMPLETE_BOX_W = 460
local MISSION_COMPLETE_BOX_H = 104
local MISSION_REWARD_TILE_GAP = 14
local MISSION_RUMOR_BOX_GAP = 20

local function pointInRect(x, y, rect)
    return rect
        and x >= rect.x
        and x <= rect.x + rect.w
        and y >= rect.y
        and y <= rect.y + rect.h
end

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
    local a_start = type(a.start) == "number" and a.start or nil
    local b_start = type(b.start) == "number" and b.start or nil

    if a_start and b_start and a_start ~= b_start then
        return a_start < b_start
    elseif a_start ~= b_start then
        return a_start ~= nil
    end

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

local function populatePlayerAgents(target_room, agents_by_start)
    local agents_by_id = getAgentDefinitionMap()
    local agent_ids = getDevSquadAgentIds()
    local start_tiles = {}
    local placed_agents = {}
    local start_tile_by_number = {}

    for _, tile in ipairs(target_room.tiles or {}) do
        tile.agent = nil
        tile.enemy = nil

        if tile.start then
            start_tiles[#start_tiles + 1] = tile

            if type(tile.start) == "number" then
                start_tile_by_number[tile.start] = tile
            end
        end
    end

    table.sort(start_tiles, tileSort)

    if agents_by_start then
        for slot_index = 1, 4 do
            local agent = agents_by_start[slot_index]
            local tile = start_tile_by_number[slot_index] or start_tiles[slot_index]

            if agent and not tile then
                print("No start tile available for strike slot " .. tostring(slot_index) .. ".")
            elseif agent then
                agent_logic.ensureRuntimeStats(agent)
                tile.agent = agent
                placed_agents[#placed_agents + 1] = agent
            end
        end

        agent_logic.prepareActionHands(placed_agents)
        return
    end

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

    agent_logic.prepareActionHands(placed_agents)
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

local function loadMapFile(options)
    options = options or {}

    local map_path = options.map_path or getDevMapPath()

    if not map_path then
        local fallback_room = buildProceduralRoom()
        populatePlayerAgents(fallback_room, options.agents_by_start)
        return fallback_room
    end

    local chunk, load_error = love.filesystem.load(map_path)

    if not chunk then
        print("Unable to load map file '" .. map_path .. "', falling back to procedural map: " .. tostring(load_error))
        local fallback_room = buildProceduralRoom()
        populatePlayerAgents(fallback_room, options.agents_by_start)
        return fallback_room
    end

    local ok, map_file = pcall(chunk)

    if not ok then
        print("Unable to run map file '" .. map_path .. "', falling back to procedural map: " .. tostring(map_file))
        local fallback_room = buildProceduralRoom()
        populatePlayerAgents(fallback_room, options.agents_by_start)
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
            boss_spawner = tile.boss_spawner,
            palette = tile.palette,
            swatch = tile.swatch,
            color = tile.color,
        }
    end

    local loaded_room = {
        id = map_file.id or "map_001",
        name = map_file.name,
        recommended_level = map_file.recommended_level,
        rewards = type(map_file.rewards) == "table" and map_file.rewards or {},
        path = map_path,
        target_count = #tiles,
        chamber_tiles = tiles,
        exit_markers = {},
        doors = map_file.doors or {},
        tiles = tiles,
    }

    door_room_logic.initialize(loaded_room)
    populatePlayerAgents(loaded_room, options.agents_by_start)

    return loaded_room
end

local function triggerPlayerRoomSpawns(target_room)
    if event_spawn.triggerForPlayerRooms(target_room) then
        agent_logic.refreshMovementRange(target_room)
    end
end

local function collectMissionAgents(room)
    local agents = {}

    for _, tile in ipairs(room and room.tiles or {}) do
        if tile.agent then
            agents[#agents + 1] = tile.agent
        end
    end

    return agents
end

local function normalizeScratchReward(value)
    return math.max(0, math.floor(tonumber(value) or 0))
end

local function accumulateMissionReward(state)
    if state.completion_reward_added then
        return state.completion_reward_total or 0
    end

    local mission_reward = normalizeScratchReward(state.room and state.room.rewards and state.room.rewards.scratch)

    state.completion_reward_total = normalizeScratchReward(state.completion_reward_total) + mission_reward
    state.completion_reward_added = true
    state.launch_options = state.launch_options or {}
    state.launch_options.accumulated_scratch_reward = state.completion_reward_total

    return state.completion_reward_total
end

local function buildMissionRewardSummary(state)
    return {
        scratch = normalizeScratchReward(state.completion_reward_total),
        agents = state.launch_options and state.launch_options.agents_by_start or state.agents or {},
    }
end

local function resolveMissionRumorReward(state)
    if state.completion_rumor_resolved then
        return state.completion_rumor_replacement
    end

    state.completion_rumor_resolved = true

    local rewards = state.room and state.room.rewards or {}
    local advancement = reward_uix.getRumorAdvancement(rewards)

    if not advancement then
        return nil
    end

    local retired_id = advancement[1].id
    local reward_id = advancement[2].id
    local checked_agents = {}

    local function replaceForAgent(agent)
        if not agent or checked_agents[agent] then
            return nil
        end

        checked_agents[agent] = true

        for _, item in ipairs(equip_logic.getInventory(agent)) do
            if item.id == retired_id then
                return equip_logic.replaceInventoryItem(agent, item, reward_id)
            end
        end

        return nil
    end

    for slot_index = 1, 4 do
        local agent = state.launch_options
            and state.launch_options.agents_by_start
            and state.launch_options.agents_by_start[slot_index]
        local replacement = replaceForAgent(agent)

        if replacement then
            state.completion_rumor_replacement = replacement
            return replacement
        end
    end

    for _, agent in ipairs(state.agents or {}) do
        local replacement = replaceForAgent(agent)

        if replacement then
            state.completion_rumor_replacement = replacement
            return replacement
        end
    end

    return nil
end

local function findEquipmentRewardOwner(state, owner_id)
    if not owner_id then
        return nil
    end

    for slot_index = 1, 4 do
        local agent = state.launch_options
            and state.launch_options.agents_by_start
            and state.launch_options.agents_by_start[slot_index]

        if agent and agent.id == owner_id then
            return agent
        end
    end

    for _, agent in ipairs(jacl_state.roster_agents or {}) do
        if agent.id == owner_id then
            return agent
        end
    end

    return nil
end

local function grantMissionEquipmentReward(state, reward)
    local definition = reward and (reward.definition or equip_logic.getDefinition(reward.id)) or nil
    local owner = findEquipmentRewardOwner(state, definition and definition.owner)

    if not definition or not owner then
        print(("Unable to grant mission equipment reward '%s': owner '%s' was not found."):format(
            tostring(reward and reward.id),
            tostring(definition and definition.owner)
        ))
        return false
    end

    return cache_rail.addEquipmentReward(owner, definition.id)
end

local function advanceFromMissionCompletion(state)
    local next_launch = rumor_missions.advanceLaunch(state.launch_options)

    if next_launch then
        states_core.restart("mission", next_launch)
    else
        states_core.switch("JACL", {
            rewards = buildMissionRewardSummary(state),
        })
    end
end

local function resetMission()
    mission.room = loadMapFile(mission.launch_options)
    event_spawn.initialize(mission.room)
    mission.completion_tracker = mission_completion.initialize(mission.room)
    mission.completion_modal_open = false
    mission.completion_rumor_resolved = false
    mission.completion_rumor_replacement = nil
    mission.completion_equipment_rects = nil
    mission.completion_equipment_claimed = false
    triggerPlayerRoomSpawns(mission.room)
    mission.agents = collectMissionAgents(mission.room)
    agent_logic.clearSelection()
    deck_hand_vis.reload()
    map_tiles.clearAnimations()
    phase_rules.load()
    camera.reset()
end

function mission:enter(_, launch_options)
    self.launch_options = launch_options or {}
    self.completion_reward_total = normalizeScratchReward(self.launch_options.accumulated_scratch_reward)
    self.completion_reward_added = false
    self.completion_rumor_resolved = false
    self.completion_rumor_replacement = nil
    self.completion_equipment_rects = nil
    self.completion_equipment_claimed = false
    luggage.setMissionActive(true)
    love.math.setRandomSeed(os.time())
    love.graphics.setDefaultFilter("linear", "linear", 1)
    self.completion_font = self.completion_font or love.graphics.newFont("assets/fonts/Furore.otf", 20)
    love.graphics.setFont(self.completion_font)
    love.graphics.setBackgroundColor(0.055, 0.058, 0.068)

    self.room = loadMapFile(self.launch_options)
    event_spawn.initialize(self.room)
    self.completion_tracker = mission_completion.initialize(self.room)
    self.completion_modal_open = false
    triggerPlayerRoomSpawns(self.room)
    self.agents = collectMissionAgents(self.room)
    agent_logic.clearSelection()
    deck_hand_vis.load()
    map_tiles.clearAnimations()
    phase_rules.load()
    camera.reset()
end

function mission:leave(next_state)
    if next_state ~= "mission" then
        luggage.setMissionActive(false)
    end

    if next_state ~= "JACL" then
        return
    end

    for _, agent in ipairs(self.agents or {}) do
        agent_logic.prepareDecksForStateTransition(agent)
        agent_logic.refreshAgentAp(agent)
    end
end

function mission:update(dt)
    if self.completion_modal_open then
        return
    end

    camera.update(dt, self.room)
    local camera_x, camera_y = camera.getOffset()
    local mission_phase = phase_rules.isMissionPhase()
    local phase_before_update = phase_rules.getCurrentPhase()

    if phase_rules.isStartPhase() then
        agent_logic.refreshAgents(self.room)
    end

    agent_logic.update(dt, self.room, camera_x, camera_y, agent_uix.isModalOpen() or not mission_phase)
    triggerPlayerRoomSpawns(self.room)
    mission_completion.update(self.completion_tracker, self.room)
    map_tiles.update(dt)
    action_vis.update(dt)

    if mission_completion.update(self.completion_tracker, self.room) and not action_vis.isActive() then
        card_play.cancelDrag()
        agent_logic.clearSelection()
        accumulateMissionReward(self)
        resolveMissionRumorReward(self)
        sfx_logic.playNamed("missioncomplete")
        self.completion_modal_open = true
        return
    end

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

local function drawMissionCompleteModal(state)
    local screen_w = love.graphics.getWidth()
    local screen_h = love.graphics.getHeight()
    local box_x = (screen_w - MISSION_COMPLETE_BOX_W) / 2
    local box_y = (screen_h - MISSION_COMPLETE_BOX_H) / 2
    local previous_font = love.graphics.getFont()
    local font = state.completion_font or previous_font
    local label = "MISSION COMPLETE"
    local rewards = state.room and state.room.rewards or {}
    local rumor_advancement = reward_uix.getRumorAdvancement(rewards)
    local rumor_advancement_h = reward_uix.getRumorAdvancementRowHeight(rewards, font)
    local equipment_rewards = reward_uix.getEquipmentRewardPair(rewards)
    local scratch_y = box_y + MISSION_COMPLETE_BOX_H + MISSION_REWARD_TILE_GAP
    local equipment_y = scratch_y + reward_uix.getTileHeight() + MISSION_REWARD_TILE_GAP

    love.graphics.setFont(font)

    love.graphics.setColor(MISSION_COMPLETE_BACKDROP_COLOR)
    love.graphics.rectangle("fill", 0, 0, screen_w, screen_h)
    love.graphics.setColor(MISSION_COMPLETE_FILL_COLOR)
    love.graphics.rectangle("fill", box_x, box_y, MISSION_COMPLETE_BOX_W, MISSION_COMPLETE_BOX_H)
    love.graphics.setColor(MISSION_COMPLETE_BORDER_COLOR)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", box_x, box_y, MISSION_COMPLETE_BOX_W, MISSION_COMPLETE_BOX_H)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(MISSION_COMPLETE_TEXT_COLOR)
    love.graphics.print(
        label,
        box_x + (MISSION_COMPLETE_BOX_W - font:getWidth(label)) / 2,
        box_y + (MISSION_COMPLETE_BOX_H - font:getHeight()) / 2
    )

    if rumor_advancement then
        reward_uix.drawRumorAdvancementRow(
            rewards,
            screen_w / 2,
            box_y - MISSION_RUMOR_BOX_GAP - rumor_advancement_h,
            { font = font }
        )
    end

    reward_uix.drawScratchTile(
        state.completion_reward_total,
        screen_w / 2,
        scratch_y,
        { font = font }
    )

    if equipment_rewards then
        state.completion_equipment_rects = reward_uix.drawEquipmentRewardRow(
            rewards,
            screen_w / 2,
            equipment_y,
            {
                font = font,
                dim_opposite_on_hover = true,
            }
        )
    else
        state.completion_equipment_rects = nil
    end

    love.graphics.setFont(previous_font)
    love.graphics.setColor(1, 1, 1, 1)
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

    if self.completion_modal_open then
        drawMissionCompleteModal(self)
    end
end

function mission:keypressed(key)
    if self.completion_modal_open then
        return
    end

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
    if self.completion_modal_open then
        if button == 1 and not self.completion_equipment_claimed then
            local equipment_rewards = reward_uix.getEquipmentRewardPair(self.room and self.room.rewards)

            if equipment_rewards then
                local rects = self.completion_equipment_rects
                local selected_index = rects and pointInRect(x, y, rects.first) and 1
                    or rects and pointInRect(x, y, rects.second) and 2
                    or nil

                if selected_index and grantMissionEquipmentReward(self, equipment_rewards[selected_index]) then
                    self.completion_equipment_claimed = true
                    advanceFromMissionCompletion(self)
                end
            else
                advanceFromMissionCompletion(self)
            end
        end

        return
    end

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
    if self.completion_modal_open then
        return
    end

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
    if self.completion_modal_open then
        return
    end

    camera.mousemoved(dx, dy, self.room)
end

function mission:wheelmoved(x, y)
    if self.completion_modal_open then
        return
    end

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

local function performStateSwitch(name, args, arg_count)
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
        next_state:enter(previous_name, unpackValues(args or {}, 1, arg_count or 0))
    end
end

local function getTransitionLabel(from_name, to_name)
    if from_name == "JACL" and to_name == "mission" then
        return "STRIKE DEPLOYED"
    elseif from_name == "mission" and to_name == "mission" then
        return "NEXT MISSION"
    elseif from_name == "mission" and to_name == "JACL" then
        return "RETURNING TO JACL"
    end

    return ""
end

local function startTransition(name, allow_same_state, ...)
    if not states_core.current then
        performStateSwitch(name, { ... }, select("#", ...))
        return true
    end

    if states_core.transition or (name == states_core.current_name and not allow_same_state) then
        return false
    end

    if states_core.current_name == "mission" and name == "JACL" then
        sfx_logic.playNamed("missionend")
    end

    states_core.transition = {
        phase = "closing",
        elapsed = 0,
        from_name = states_core.current_name,
        next_name = name,
        args = { ... },
        arg_count = select("#", ...),
        label = getTransitionLabel(states_core.current_name, name),
    }

    return true
end

function states_core.switch(name, ...)
    return startTransition(name, false, ...)
end

function states_core.restart(name, ...)
    return startTransition(name, true, ...)
end

local function updateTransition(dt)
    local transition = states_core.transition

    if not transition then
        return
    end

    transition.elapsed = transition.elapsed + dt

    if transition.phase == "closing" and transition.elapsed >= SHUTTER_CLOSE_SECONDS then
        performStateSwitch(transition.next_name, transition.args, transition.arg_count)
        transition.phase = "holding"
        transition.elapsed = 0
    elseif transition.phase == "holding" and transition.elapsed >= SHUTTER_HOLD_SECONDS then
        transition.phase = "opening"
        transition.elapsed = 0
    elseif transition.phase == "opening" and transition.elapsed >= SHUTTER_OPEN_SECONDS then
        states_core.transition = nil

        if states_core.current and states_core.current.transitionComplete then
            states_core.current:transitionComplete(transition.from_name)
        end
    end
end

local function getShutterCoverage(transition)
    if transition.phase == "closing" then
        return math.min(1, transition.elapsed / SHUTTER_CLOSE_SECONDS)
    elseif transition.phase == "opening" then
        return 1 - math.min(1, transition.elapsed / SHUTTER_OPEN_SECONDS)
    end

    return 1
end

local function drawTransition()
    local transition = states_core.transition

    if not transition then
        return
    end

    local screen_w = love.graphics.getWidth()
    local screen_h = love.graphics.getHeight()
    local coverage = getShutterCoverage(transition)
    local panel_h = screen_h * 0.5 * coverage
    local top_edge = panel_h
    local bottom_edge = screen_h - panel_h

    love.graphics.setColor(SHUTTER_COLOR)
    love.graphics.rectangle("fill", 0, 0, screen_w, panel_h)
    love.graphics.rectangle("fill", 0, bottom_edge, screen_w, panel_h)

    if coverage > 0 then
        love.graphics.setColor(SHUTTER_ACCENT_COLOR)
        love.graphics.setLineWidth(3)
        love.graphics.line(0, top_edge, screen_w, top_edge)
        love.graphics.line(0, bottom_edge, screen_w, bottom_edge)
        love.graphics.setLineWidth(1)
    end

    if transition.label ~= "" and coverage > 0.65 then
        local font = love.graphics.getFont()
        local alpha = math.min(1, (coverage - 0.65) / 0.35)
        local text_w = font:getWidth(transition.label)
        local text_h = font:getHeight()
        local text_x = (screen_w - text_w) / 2
        local text_y = (screen_h - text_h) / 2

        love.graphics.setColor(0, 0, 0, alpha)
        love.graphics.rectangle("fill", text_x - 14, text_y - 8, text_w + 28, text_h + 16)
        love.graphics.setColor(
            SHUTTER_TEXT_COLOR[1],
            SHUTTER_TEXT_COLOR[2],
            SHUTTER_TEXT_COLOR[3],
            alpha
        )
        love.graphics.print(
            transition.label,
            text_x,
            text_y
        )
    end

    love.graphics.setColor(1, 1, 1, 1)
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

    updateTransition(dt)
end

function states_core.draw()
    if states_core.current and states_core.current.draw then
        states_core.current:draw()
    end

    drawTransition()
end

function states_core.keypressed(...)
    if states_core.transition then
        return
    end

    if states_core.current and states_core.current.keypressed then
        states_core.current:keypressed(...)
    end
end

function states_core.textinput(...)
    if states_core.transition then
        return
    end

    if states_core.current and states_core.current.textinput then
        states_core.current:textinput(...)
    end
end

function states_core.mousepressed(...)
    if states_core.transition then
        return
    end

    if states_core.current and states_core.current.mousepressed then
        states_core.current:mousepressed(...)
    end
end

function states_core.mousereleased(...)
    if states_core.transition then
        return
    end

    if states_core.current and states_core.current.mousereleased then
        states_core.current:mousereleased(...)
    end
end

function states_core.mousemoved(...)
    if states_core.transition then
        return
    end

    if states_core.current and states_core.current.mousemoved then
        states_core.current:mousemoved(...)
    end
end

function states_core.wheelmoved(...)
    if states_core.transition then
        return
    end

    if states_core.current and states_core.current.wheelmoved then
        states_core.current:wheelmoved(...)
    end
end

states_core.register("JACL", jacl_state)
states_core.register("mission", mission)

return states_core

local map_tiles = require("src.rndr.map_tiles")
local pathfinding = require("src.sys.pathfinding")
local sfx_logic = require("src.sys.sfx_logic")
local fate_logic = require("src.sys.fate_logic")
local action_deck_logic = require("src.sys.action_deck_logic")
local burn_logic = require("src.sys.burn_logic")
local block_logic = require("src.sys.block_logic")
local door_room_logic = require("src.sys.door_room_logic")
local enemy_ai = require("src.sys.enemy_ai")
local XP_levels = require("src.sys.XP_levels")
local equip_logic = require("src.sys.equip_logic")

local agent_logic = {
    selected_tile = nil,
    selected_agent = nil,
    selected_enemy = nil,
    selected_hazard = nil,
    selected_door = nil,
    shout = nil,
    movement = {
        range = {},
        preview = nil,
        animation = nil,
    },
    enemy_overlay = {
        movement = {},
        threat = {},
    },
}

local SHOUT_CHARS_PER_SECOND = 58
local SHOUT_MIN_TYPE_SECONDS = 0.08
local SHOUT_HOLD_SECONDS = 0.75
local MOVE_ANIMATION_SECONDS = 0.18
local ACTION_DECKS_PATH = "data.action_decks"
local CARD_INDEX_PATH = "data.cards.index"
local ACTION_HAND_SIZE = 6

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

local function getDrawOffset(room, camera_x, camera_y)
    local offset_x, offset_y = map_tiles.getCenteredOffset(room)

    return offset_x + (camera_x or 0), offset_y + (camera_y or 0)
end

local function getTileAtPoint(room, x, y, camera_x, camera_y)
    if not room or not room.tiles then
        return nil
    end

    local offset_x, offset_y = getDrawOffset(room, camera_x, camera_y)

    for _, tile in ipairs(room.tiles) do
        local tile_x, tile_y = map_tiles.axialToPixel(tile.q, tile.r)
        local points = map_tiles.buildHexPoints(tile_x + offset_x, tile_y + offset_y)

        if pointInPolygon(x, y, points) then
            return tile
        end
    end

    return nil
end

local function getStatValue(agent, stat_name)
    if not agent or not agent.stats then
        return 0
    end

    for _, stat in ipairs(agent.stats) do
        if stat[stat_name] ~= nil then
            return stat[stat_name]
        end
    end

    return 0
end

local function getRuntimeStat(agent, stat_name)
    agent.runtime_stats = agent.runtime_stats or {}

    if agent.runtime_stats[stat_name] then
        return agent.runtime_stats[stat_name]
    end

    local maximum = getStatValue(agent, stat_name)

    if maximum <= 0 then
        return {
            current = 0,
            maximum = 0,
        }
    end

    agent.runtime_stats[stat_name] = {
        current = maximum,
        maximum = maximum,
    }

    return agent.runtime_stats[stat_name]
end

local function buildLookup(items)
    local lookup = {}

    for _, item in ipairs(items or {}) do
        if item.id then
            lookup[item.id] = item
        end
    end

    return lookup
end

local function getActionDeckLookup()
    package.loaded[ACTION_DECKS_PATH] = nil

    local ok, action_decks = pcall(require, ACTION_DECKS_PATH)

    if not ok then
        print("Unable to load action decks: " .. tostring(action_decks))
        return {}
    end

    return buildLookup(action_decks)
end

local function getCardIndex()
    package.loaded[CARD_INDEX_PATH] = nil

    local ok, card_index = pcall(require, CARD_INDEX_PATH)

    if not ok then
        print("Unable to load card index: " .. tostring(card_index))
        return { byId = {} }
    end

    return card_index
end

local function getActionArtLookup(agent)
    local lookup = {}

    for _, override in ipairs(agent.actions_art or {}) do
        if override.cardid and override.art then
            lookup[override.cardid] = override.art
        end
    end

    return lookup
end

local function isOccupiedDestination(tile, selected_tile)
    return tile ~= selected_tile and (tile.agent or tile.enemy)
end

local function getCurrentAp(agent)
    return getRuntimeStat(agent, "ap").current
end

local function buildEnemyZoneLookup(room)
    local zone = {}

    for _, tile in ipairs(room.tiles or {}) do
        if tile.enemy then
            for _, neighbor in ipairs(pathfinding.getNeighbors(room, tile)) do
                if door_room_logic.canTraverseBetween(room, tile, neighbor) then
                    zone[pathfinding.tileKey(neighbor)] = true
                end
            end
        end
    end

    return zone
end

local function buildMovementPassability(room, start_tile)
    local enemy_zone = buildEnemyZoneLookup(room)
    local start_key = pathfinding.tileKey(start_tile)

    return function(neighbor, current)
        if not door_room_logic.canTraverseBetween(room, current, neighbor) then
            return false
        end

        if neighbor.enemy then
            return false
        end

        local current_key = pathfinding.tileKey(current)

        if current_key ~= start_key and enemy_zone[current_key] then
            return false
        end

        return true
    end
end

local function buildEnemyMovementPassability(room, start_tile)
    return function(tile, current)
        if current and not door_room_logic.canTraverseBetween(room, current, tile) then
            return false
        end

        if tile == start_tile then
            return true
        end

        return not tile.agent
    end
end

local function buildRangePassability(room)
    return function(tile, current)
        return door_room_logic.canTraverseBetween(room, current, tile)
    end
end

local function refreshEnemyOverlay(room)
    agent_logic.enemy_overlay.movement = {}
    agent_logic.enemy_overlay.threat = {}

    if not room or not agent_logic.selected_enemy or not agent_logic.selected_tile then
        return
    end

    local speed = math.max(0, math.floor(tonumber(getStatValue(agent_logic.selected_enemy, "spd")) or 0))
    local range = math.max(0, math.floor(tonumber(getStatValue(agent_logic.selected_enemy, "rng")) or 0))
    local selected_key = pathfinding.tileKey(agent_logic.selected_tile)
    local reachable = pathfinding.findReachable(room, agent_logic.selected_tile, speed, {
        isPassable = buildEnemyMovementPassability(room, agent_logic.selected_tile),
    })

    for key, entry in pairs(reachable) do
        if key ~= selected_key and not entry.tile.enemy then
            agent_logic.enemy_overlay.movement[key] = entry
        end
    end

    for _, entry in pairs(reachable) do
        if entry.tile == agent_logic.selected_tile or not entry.tile.enemy then
            local threatened = pathfinding.findReachable(room, entry.tile, range, {
                isPassable = buildRangePassability(room),
            })

            for _, range_entry in pairs(threatened) do
                local tile = range_entry.tile
                local key = pathfinding.tileKey(tile)

                if key ~= selected_key and not agent_logic.enemy_overlay.movement[key] then
                    agent_logic.enemy_overlay.threat[key] = {
                        tile = tile,
                    }
                end
            end
        end
    end
end

local function refreshMovementRange(room)
    agent_logic.movement.range = {}
    agent_logic.movement.preview = nil
    agent_logic.enemy_overlay.movement = {}
    agent_logic.enemy_overlay.threat = {}

    if agent_logic.selected_enemy then
        refreshEnemyOverlay(room)
        return
    end

    if not room or not agent_logic.selected_agent or not agent_logic.selected_tile then
        return
    end

    local current_ap = math.max(0, math.floor(getCurrentAp(agent_logic.selected_agent)))
    local reachable = pathfinding.findReachable(room, agent_logic.selected_tile, current_ap, {
        isPassable = buildMovementPassability(room, agent_logic.selected_tile),
    })
    local selected_key = pathfinding.tileKey(agent_logic.selected_tile)

    for key, entry in pairs(reachable) do
        if key ~= selected_key and not isOccupiedDestination(entry.tile, agent_logic.selected_tile) then
            agent_logic.movement.range[key] = entry
        end
    end
end

local function updateMovementPreview(room, camera_x, camera_y)
    agent_logic.movement.preview = nil

    if not room or not agent_logic.selected_agent or not agent_logic.selected_tile or agent_logic.movement.animation then
        return
    end

    local mouse_x, mouse_y = love.mouse.getPosition()
    local hovered_tile = getTileAtPoint(room, mouse_x, mouse_y, camera_x, camera_y)

    if not hovered_tile then
        return
    end

    local range_entry = agent_logic.movement.range[pathfinding.tileKey(hovered_tile)]

    if not range_entry then
        return
    end

    local path = pathfinding.findPath(room, agent_logic.selected_tile, hovered_tile, {
        isPassable = buildMovementPassability(room, agent_logic.selected_tile),
    })

    if not path then
        return
    end

    agent_logic.movement.preview = {
        tile = hovered_tile,
        path = path,
        cost = range_entry.cost,
    }
end

local function tileSort(a, b)
    if a.tile.r == b.tile.r then
        return a.tile.q < b.tile.q
    end

    return a.tile.r < b.tile.r
end

local function getActiveAgentTiles(room)
    local agent_tiles = {}

    for _, tile in ipairs(room.tiles or {}) do
        if tile.agent and getCurrentAp(tile.agent) > 0 then
            agent_tiles[#agent_tiles + 1] = {
                agent = tile.agent,
                tile = tile,
            }
        end
    end

    table.sort(agent_tiles, tileSort)

    return agent_tiles
end

function agent_logic.clearSelection()
    agent_logic.selected_tile = nil
    agent_logic.selected_agent = nil
    agent_logic.selected_enemy = nil
    agent_logic.selected_hazard = nil
    agent_logic.selected_door = nil
    agent_logic.shout = nil
    agent_logic.movement.range = {}
    agent_logic.movement.preview = nil
    agent_logic.movement.animation = nil
    agent_logic.enemy_overlay.movement = {}
    agent_logic.enemy_overlay.threat = {}
end

function agent_logic.selectAgent(agent, tile, room)
    local shout_text = agent.shout_select or ""
    local type_seconds = math.max(#shout_text / SHOUT_CHARS_PER_SECOND, SHOUT_MIN_TYPE_SECONDS)

    agent_logic.selected_agent = agent
    agent_logic.selected_enemy = nil
    agent_logic.selected_hazard = nil
    agent_logic.selected_door = nil
    agent_logic.selected_tile = tile
    agent_logic.shout = {
        text = shout_text,
        elapsed = 0,
        type_seconds = type_seconds,
        duration = type_seconds + SHOUT_HOLD_SECONDS,
    }
    agent_logic.enemy_overlay.movement = {}
    agent_logic.enemy_overlay.threat = {}
    refreshMovementRange(room)
    sfx_logic.playAgentSelect(agent)
end

function agent_logic.selectEnemy(enemy, tile, room)
    agent_logic.selected_agent = nil
    agent_logic.selected_enemy = enemy
    agent_logic.selected_hazard = nil
    agent_logic.selected_door = nil
    agent_logic.selected_tile = tile
    agent_logic.shout = nil
    agent_logic.movement.range = {}
    agent_logic.movement.preview = nil
    refreshEnemyOverlay(room)
    sfx_logic.playNamed("token_select")
end

function agent_logic.selectHazard(hazard, tile)
    agent_logic.selected_agent = nil
    agent_logic.selected_enemy = nil
    agent_logic.selected_hazard = hazard
    agent_logic.selected_door = nil
    agent_logic.selected_tile = tile
    agent_logic.shout = nil
    agent_logic.movement.range = {}
    agent_logic.movement.preview = nil
    agent_logic.enemy_overlay.movement = {}
    agent_logic.enemy_overlay.threat = {}
    sfx_logic.playNamed("token_select")
end

function agent_logic.selectDoor(door)
    agent_logic.selected_agent = nil
    agent_logic.selected_enemy = nil
    agent_logic.selected_hazard = nil
    agent_logic.selected_door = door
    agent_logic.selected_tile = nil
    agent_logic.shout = nil
    agent_logic.movement.range = {}
    agent_logic.movement.preview = nil
    agent_logic.enemy_overlay.movement = {}
    agent_logic.enemy_overlay.threat = {}
    sfx_logic.playNamed("token_select")
end

function agent_logic.update(dt, room, camera_x, camera_y, suppress_movement)
    if agent_logic.movement.animation then
        local animation = agent_logic.movement.animation

        animation.elapsed = animation.elapsed + dt

        if animation.elapsed >= animation.duration then
            agent_logic.movement.animation = nil
        end
    end

    if agent_logic.shout then
        agent_logic.shout.elapsed = agent_logic.shout.elapsed + dt

        if agent_logic.shout.elapsed >= agent_logic.shout.duration then
            agent_logic.shout = nil
        end
    end

    if suppress_movement then
        agent_logic.movement.preview = nil
    else
        updateMovementPreview(room, camera_x, camera_y)
    end
end

function agent_logic.handleMousePressed(room, x, y, button, camera_x, camera_y)
    if button == 2 then
        local preview = agent_logic.movement.preview

        if preview and agent_logic.selected_agent and agent_logic.selected_tile and not agent_logic.movement.animation then
            local ap = getRuntimeStat(agent_logic.selected_agent, "ap")

            if preview.cost <= ap.current then
                local from_tile = agent_logic.selected_tile

                agent_logic.movement.animation = {
                    agent = agent_logic.selected_agent,
                    from = { q = from_tile.q, r = from_tile.r },
                    to = { q = preview.tile.q, r = preview.tile.r },
                    elapsed = 0,
                    duration = MOVE_ANIMATION_SECONDS,
                }

                agent_logic.selected_tile.agent = nil
                preview.tile.agent = agent_logic.selected_agent
                agent_logic.selected_tile = preview.tile
                ap.current = math.max(0, ap.current - preview.cost)
                enemy_ai.triggerHazardsForPath(room, agent_logic.selected_agent, "agent", preview.path)
                refreshMovementRange(room)
                updateMovementPreview(room, camera_x, camera_y)
                sfx_logic.playMove()
                return true
            end
        end

        return false
    end

    if button ~= 1 then
        return false
    end

    local door = door_room_logic.getDoorAtPoint(room, x, y, camera_x, camera_y)

    if door then
        agent_logic.selectDoor(door)
        return true
    end

    local tile = getTileAtPoint(room, x, y, camera_x, camera_y)

    if tile and tile.agent then
        agent_logic.selectAgent(tile.agent, tile, room)
    elseif tile and tile.enemy then
        agent_logic.selectEnemy(tile.enemy, tile, room)
    elseif tile and tile.hazard then
        agent_logic.selectHazard(tile.hazard, tile)
    else
        agent_logic.clearSelection()
    end

    return true
end

function agent_logic.selectAdjacentAgent(room, direction)
    local agent_tiles = getActiveAgentTiles(room)

    if #agent_tiles == 0 then
        agent_logic.clearSelection()
        return false
    end

    local current_index = nil

    for index, entry in ipairs(agent_tiles) do
        if entry.tile == agent_logic.selected_tile then
            current_index = index
            break
        end
    end

    if not current_index then
        current_index = direction > 0 and 0 or 1
    end

    local next_index = ((current_index - 1 + direction) % #agent_tiles) + 1
    local next_entry = agent_tiles[next_index]

    agent_logic.selectAgent(next_entry.agent, next_entry.tile, room)

    return true
end

function agent_logic.getSelectedAgent()
    return agent_logic.selected_agent
end

function agent_logic.getSelectedEnemy()
    return agent_logic.selected_enemy
end

function agent_logic.getSelectedHazard()
    return agent_logic.selected_hazard
end

function agent_logic.getSelectedDoor()
    return agent_logic.selected_door
end

function agent_logic.getSelectedUnit()
    if agent_logic.selected_agent then
        return agent_logic.selected_agent, "agent"
    end

    if agent_logic.selected_enemy then
        return agent_logic.selected_enemy, "enemy"
    end

    if agent_logic.selected_hazard then
        return agent_logic.selected_hazard, "hazard"
    end

    if agent_logic.selected_door then
        return agent_logic.selected_door, "door"
    end

    return nil, nil
end

function agent_logic.getSelectedTile()
    return agent_logic.selected_tile
end

function agent_logic.getSelectionShout()
    local shout = agent_logic.shout

    if not shout or shout.text == "" then
        return nil
    end

    local typed_ratio = math.min(shout.elapsed / shout.type_seconds, 1)
    local visible_count = math.max(1, math.floor(#shout.text * typed_ratio))

    return {
        text = shout.text:sub(1, visible_count),
        done = visible_count >= #shout.text,
    }
end

function agent_logic.getMovementRange()
    return agent_logic.movement.range
end

function agent_logic.getEnemyOverlay()
    return agent_logic.enemy_overlay
end

function agent_logic.getMovementPreview()
    return agent_logic.movement.preview
end

function agent_logic.getMovementAnimation()
    return agent_logic.movement.animation
end

function agent_logic.getSelectedStats()
    local agent = agent_logic.getSelectedAgent()
    local enemy = agent_logic.getSelectedEnemy()
    local hazard = agent_logic.getSelectedHazard()
    local door = agent_logic.getSelectedDoor()

    if enemy then
        return {
            hp = getRuntimeStat(enemy, "hp"),
            atk = getRuntimeStat(enemy, "atk"),
            spd = getRuntimeStat(enemy, "spd"),
            rng = getRuntimeStat(enemy, "rng"),
        }
    end

    if hazard then
        return {
            hp = getRuntimeStat(hazard, "hp"),
            bp = getRuntimeStat(hazard, "bp"),
            atk = getRuntimeStat(hazard, "atk"),
            rng = getRuntimeStat(hazard, "rng"),
        }
    end

    if door then
        return door_room_logic.getStats(door)
    end

    return {
        ap = getRuntimeStat(agent, "ap"),
        hp = getRuntimeStat(agent, "hp"),
        lp = getRuntimeStat(agent, "lp"),
    }
end

function agent_logic.ensureRuntimeStats(agent)
    getRuntimeStat(agent, "ap")
    getRuntimeStat(agent, "hp")
    getRuntimeStat(agent, "lp")
    block_logic.clearBlock(agent)
    fate_logic.initializeFateDeck(agent)
    XP_levels.initializeAgent(agent)
    equip_logic.initializeAgent(agent)
end

function agent_logic.refreshAgents(room)
    local refreshed = false

    for _, tile in ipairs(room and room.tiles or {}) do
        if tile.agent then
            local ap = getRuntimeStat(tile.agent, "ap")

            if ap.maximum > 0 and ap.current < ap.maximum then
                ap.current = ap.maximum
                refreshed = true
            end
        end
    end

    if refreshed then
        refreshMovementRange(room)
    end

    return refreshed
end

function agent_logic.refreshExhaustedAgents(room)
    return agent_logic.refreshAgents(room)
end

function agent_logic.discardAgentHands(room)
    for _, tile in ipairs(room and room.tiles or {}) do
        if tile.agent then
            action_deck_logic.discardHand(tile.agent)
        end
    end
end

function agent_logic.drawAgentHands(room)
    for _, tile in ipairs(room and room.tiles or {}) do
        if tile.agent then
            local agent = tile.agent
            local _, reason = burn_logic.drawHand(agent, room, ACTION_HAND_SIZE)

            if reason == "eliminated" and agent_logic.selected_agent == agent then
                agent_logic.clearSelection()
            else
                equip_logic.drawFromEquippedLexDecks(agent)
            end
        end
    end
end

function agent_logic.initializeActionHand(agent, action_deck_lookup, card_index)
    if not agent then
        return
    end

    action_deck_lookup = action_deck_lookup or getActionDeckLookup()
    card_index = card_index or getCardIndex()

    agent.action_draw_pile = action_deck_logic.buildDrawPile(
        agent,
        action_deck_lookup,
        card_index,
        getActionArtLookup(agent)
    )
    agent.action_discard_pile = {}
    agent.action_hand = {}
    burn_logic.initializeAgent(agent)
    burn_logic.drawCards(agent, nil, ACTION_HAND_SIZE)
    equip_logic.drawFromEquippedLexDecks(agent)
end

function agent_logic.initializeActionHands(agents)
    local action_deck_lookup = getActionDeckLookup()
    local card_index = getCardIndex()

    for _, agent in ipairs(agents or {}) do
        agent_logic.initializeActionHand(agent, action_deck_lookup, card_index)
    end
end

function agent_logic.ensureEnemyRuntimeStats(enemy)
    getRuntimeStat(enemy, "hp")
    getRuntimeStat(enemy, "atk")
    getRuntimeStat(enemy, "spd")
    getRuntimeStat(enemy, "rng")
    block_logic.clearBlock(enemy)
end

function agent_logic.refreshMovementRange(room)
    refreshMovementRange(room)
end

return agent_logic

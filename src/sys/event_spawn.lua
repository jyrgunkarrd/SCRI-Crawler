local pathfinding = require("src.sys.pathfinding")

local event_spawn = {}

local SPAWN_INDEX_PATH = "data.spawns.index"
local DIRECTIONS = {
    { q = 1, r = 0 },
    { q = 1, r = -1 },
    { q = 0, r = -1 },
    { q = -1, r = 0 },
    { q = -1, r = 1 },
    { q = 0, r = 1 },
}

local function cloneValue(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}

    for key, child in pairs(value) do
        copy[key] = cloneValue(child)
    end

    return copy
end

local function getSpawnDefinitions()
    package.loaded[SPAWN_INDEX_PATH] = nil

    local ok, spawn_index = pcall(require, SPAWN_INDEX_PATH)

    if not ok then
        print("Unable to load spawn index: " .. tostring(spawn_index))
        return {}
    end

    return spawn_index.byId or {}
end

local function getRoomState(room)
    room.event_spawn = room.event_spawn or {
        initialized = false,
        spawned_count = 0,
        missing_logged = {},
        triggered_spawners = {},
        triggered_components = {},
    }

    return room.event_spawn
end

local function buildTileLookup(room)
    local lookup = {}

    for _, tile in ipairs(room.tiles or {}) do
        lookup[pathfinding.tileKey(tile)] = tile
    end

    return lookup
end

local function isSameAreaKind(a, b)
    local a_is_corridor = not not a.corridor
    local b_is_corridor = not not b.corridor

    return a_is_corridor == b_is_corridor
end

local function getNeighborTiles(lookup, tile)
    local neighbors = {}

    for _, direction in ipairs(DIRECTIONS) do
        local neighbor = lookup[pathfinding.tileKey(tile.q + direction.q, tile.r + direction.r)]

        if neighbor then
            neighbors[#neighbors + 1] = neighbor
        end
    end

    return neighbors
end

local function buildComponents(room)
    local lookup = buildTileLookup(room)
    local visited = {}
    local components = {}
    local component_by_tile = {}

    for _, tile in ipairs(room.tiles or {}) do
        local start_key = pathfinding.tileKey(tile)

        if not visited[start_key] then
            local component_id = #components + 1
            local component = {
                id = component_id,
                tiles = {},
                spawners = {},
            }
            local frontier = { tile }
            local head = 1

            visited[start_key] = true

            while frontier[head] do
                local current = frontier[head]
                local current_key = pathfinding.tileKey(current)
                head = head + 1

                current.room_component = component_id
                component_by_tile[current_key] = component_id
                component.tiles[#component.tiles + 1] = current

                if current.spawn_event then
                    component.spawners[#component.spawners + 1] = current
                end

                for _, neighbor in ipairs(getNeighborTiles(lookup, current)) do
                    local neighbor_key = pathfinding.tileKey(neighbor)

                    if not visited[neighbor_key] and isSameAreaKind(current, neighbor) then
                        visited[neighbor_key] = true
                        frontier[#frontier + 1] = neighbor
                    end
                end
            end

            components[component_id] = component
        end
    end

    return components, component_by_tile
end

local function isTileFreeForSpawn(tile)
    return tile and not tile.agent and not tile.enemy and not tile.hazard
end

local function findSpawnTile(component, spawner_tile)
    if isTileFreeForSpawn(spawner_tile) then
        return spawner_tile
    end

    local best_tile = nil
    local best_cost = math.huge

    for _, tile in ipairs(component.tiles) do
        if isTileFreeForSpawn(tile) then
            local path, cost = pathfinding.findPath({ tiles = component.tiles }, spawner_tile, tile)

            if path and cost and cost < best_cost then
                best_tile = tile
                best_cost = cost
            end
        end
    end

    return best_tile
end

local function triggerSpawner(room, component, spawner_tile, definitions)
    local state = getRoomState(room)
    local spawner_key = pathfinding.tileKey(spawner_tile)

    if state.triggered_spawners[spawner_key] then
        return
    end

    state.triggered_spawners[spawner_key] = true

    local spawn_id = spawner_tile.spawn_event
    local definition = definitions[spawn_id]

    if not definition then
        if not state.missing_logged[spawn_id] then
            print("Unknown spawn event id: " .. tostring(spawn_id))
            state.missing_logged[spawn_id] = true
        end

        return
    end

    local spawn_tile = findSpawnTile(component, spawner_tile)

    if not spawn_tile then
        print("No free tile available for spawn event id: " .. tostring(spawn_id))
        return
    end

    local spawn = cloneValue(definition)
    spawn.spawn_id = spawn_id
    spawn.instance_id = ("%s_%03d"):format(spawn_id, state.spawned_count + 1)

    if spawn.hazard then
        spawn_tile.hazard = spawn
    else
        spawn.boss = not not spawner_tile.boss_spawner
        spawn_tile.enemy = spawn
    end

    state.spawned_count = state.spawned_count + 1

    return true
end

local function triggerComponent(room, component_id)
    local state = getRoomState(room)

    if state.triggered_components[component_id] then
        return false
    end

    local component = state.components and state.components[component_id]

    if not component then
        return false
    end

    state.triggered_components[component_id] = true

    if #component.spawners == 0 then
        return false
    end

    local definitions = state.definitions or {}
    local spawned = false

    for _, spawner_tile in ipairs(component.spawners) do
        spawned = triggerSpawner(room, component, spawner_tile, definitions) or spawned
    end

    return spawned
end

function event_spawn.initialize(room)
    if not room or not room.tiles then
        return
    end

    local state = getRoomState(room)
    state.initialized = true
    state.definitions = getSpawnDefinitions()
    state.components, state.component_by_tile = buildComponents(room)
end

function event_spawn.triggerForPlayerRooms(room)
    if not room or not room.tiles then
        return false
    end

    local state = getRoomState(room)
    local spawned = false

    if not state.initialized then
        event_spawn.initialize(room)
    end

    for _, tile in ipairs(room.tiles) do
        if tile.agent then
            local component_id = state.component_by_tile and state.component_by_tile[pathfinding.tileKey(tile)]

            if component_id then
                spawned = triggerComponent(room, component_id) or spawned
            end
        end
    end

    return spawned
end

return event_spawn

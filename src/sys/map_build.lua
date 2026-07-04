local map_build = {}

local SQRT_3 = math.sqrt(3)

local DIRECTIONS = {
    { id = "E", q = 1, r = 0 },
    { id = "NE", q = 1, r = -1 },
    { id = "NW", q = 0, r = -1 },
    { id = "W", q = -1, r = 0 },
    { id = "SW", q = -1, r = 1 },
    { id = "SE", q = 0, r = 1 },
}

local EXIT_VECTORS = {
    N = { x = 0, y = -1 },
    NE = { x = 1, y = -1 },
    E = { x = 1, y = 0 },
    SE = { x = 1, y = 1 },
    S = { x = 0, y = 1 },
    SW = { x = -1, y = 1 },
    W = { x = -1, y = 0 },
    NW = { x = -1, y = -1 },
}

local DIRECTION_ALIASES = {
    NORTH = "N",
    NORTHEAST = "NE",
    EAST = "E",
    SOUTHEAST = "SE",
    SOUTH = "S",
    SOUTHWEST = "SW",
    WEST = "W",
    NORTHWEST = "NW",
}

local function tileKey(q, r)
    return q .. "," .. r
end

local function axialToPixel(q, r)
    return SQRT_3 * (q + r / 2), 1.5 * r
end

local function addFrontier(frontier, occupied, q, r)
    local key = tileKey(q, r)

    if not occupied[key] and not frontier[key] then
        frontier[key] = { q = q, r = r }
    end
end

local function pushNeighborFrontier(frontier, occupied, tile)
    for _, direction in ipairs(DIRECTIONS) do
        addFrontier(frontier, occupied, tile.q + direction.q, tile.r + direction.r)
    end
end

local function pickFrontierTile(frontier)
    local choices = {}

    for _, tile in pairs(frontier) do
        choices[#choices + 1] = tile
    end

    return choices[love.math.random(#choices)]
end

local function getTargetHexCount(definition)
    local min_hex = assert(definition.min_hex, "Map piece is missing min_hex.")
    local max_hex = assert(definition.max_hex, "Map piece is missing max_hex.")

    if min_hex > max_hex then
        min_hex, max_hex = max_hex, min_hex
    end

    return love.math.random(min_hex, max_hex)
end

local function normalizeDirection(direction)
    local normalized = tostring(direction):upper()

    return DIRECTION_ALIASES[normalized] or normalized
end

local function normalizeExit(exit)
    if type(exit) == "table" then
        local direction = assert(exit.direction or exit.dir or exit[1], "Exit table is missing a direction.")

        return exit, normalizeDirection(direction)
    end

    return {}, normalizeDirection(exit)
end

local function getExitVector(direction)
    return assert(EXIT_VECTORS[direction], ("Unsupported exit direction '%s'."):format(direction))
end

local function getNearestHexDirection(vector)
    local best_direction = DIRECTIONS[1]
    local best_dot = -math.huge

    for _, direction in ipairs(DIRECTIONS) do
        local x, y = axialToPixel(direction.q, direction.r)
        local dot = x * vector.x + y * vector.y

        if dot > best_dot then
            best_dot = dot
            best_direction = direction
        end
    end

    return best_direction
end

local function getAdjacentDirection(direction, turn)
    for index, candidate in ipairs(DIRECTIONS) do
        if candidate.id == direction.id then
            local next_index = ((index - 1 + turn) % #DIRECTIONS) + 1

            return DIRECTIONS[next_index]
        end
    end

    return direction
end

local function findExitTile(chamber_tiles, direction, used_exit_tiles)
    local vector = getExitVector(direction)
    local best_tile = chamber_tiles[1]
    local best_dot = -math.huge
    local fallback_tile = chamber_tiles[1]
    local fallback_dot = -math.huge

    for _, tile in ipairs(chamber_tiles) do
        local x, y = axialToPixel(tile.q, tile.r)
        local dot = x * vector.x + y * vector.y
        local key = tileKey(tile.q, tile.r)

        if dot > fallback_dot then
            fallback_dot = dot
            fallback_tile = tile
        end

        if not used_exit_tiles[key] and dot > best_dot then
            best_dot = dot
            best_tile = tile
        end
    end

    if best_dot == -math.huge then
        return fallback_tile, vector
    end

    return best_tile, vector
end

local function findMapPiece(definitions, id)
    if not definitions then
        return nil
    end

    for _, definition in ipairs(definitions) do
        if definition.id == id then
            return definition
        end
    end

    return nil
end

local function getCorridorDefinition(definitions, exit)
    return findMapPiece(definitions, exit.corridor_id or "CORRIDOR") or {
        id = "CORRIDOR",
        corridor = true,
        min_hex = exit.min_hex or 2,
        max_hex = exit.max_hex or 5,
        flex = exit.flex or 3,
    }
end

local function addCorridor(room, occupied, exit_tile, exit, direction_vector, definitions)
    local corridor_definition = getCorridorDefinition(definitions, exit)
    local length = getTargetHexCount({
        min_hex = exit.min_hex or corridor_definition.min_hex,
        max_hex = exit.max_hex or corridor_definition.max_hex,
    })
    local flex = exit.flex or corridor_definition.flex or length
    local direction = getNearestHexDirection(direction_vector)
    local bent_direction = getAdjacentDirection(direction, love.math.random(0, 1) == 0 and -1 or 1)
    local q = exit_tile.q
    local r = exit_tile.r
    local first_corridor_tile = nil

    for index = 1, length do
        local growth_direction = index > flex and bent_direction or direction

        q = q + growth_direction.q
        r = r + growth_direction.r

        local key = tileKey(q, r)

        if occupied[key] then
            break
        end

        local tile = {
            q = q,
            r = r,
            corridor = true,
            source_exit = exit.direction,
        }

        first_corridor_tile = first_corridor_tile or tile
        occupied[key] = true
        room.tiles[#room.tiles + 1] = tile
    end

    return first_corridor_tile
end

local function addExitsAndCorridors(room, occupied, definition, definitions)
    if not definition.exits then
        return
    end

    local used_exit_tiles = {}

    for _, exit in ipairs(definition.exits) do
        local exit_definition, direction = normalizeExit(exit)
        local exit_tile, direction_vector = findExitTile(room.chamber_tiles, direction, used_exit_tiles)
        local key = tileKey(exit_tile.q, exit_tile.r)

        exit_tile.exit = true
        exit_tile.exit_directions = exit_tile.exit_directions or {}
        exit_tile.exit_directions[#exit_tile.exit_directions + 1] = direction
        exit_tile.exit_direction = exit_tile.exit_direction or direction
        exit_definition.direction = direction
        used_exit_tiles[key] = true

        local corridor_start = addCorridor(room, occupied, exit_tile, exit_definition, direction_vector, definitions)

        if corridor_start then
            room.exit_markers[#room.exit_markers + 1] = {
                direction = direction,
                exit_tile = exit_tile,
                corridor_tile = corridor_start,
            }
        end
    end
end

function map_build.buildRoom(definition, definitions)
    assert(definition, "A map piece definition is required.")

    local target_count = getTargetHexCount(definition)
    local tiles = {
        { q = 0, r = 0, chamber = true },
    }
    local occupied = {
        [tileKey(0, 0)] = true,
    }
    local frontier = {}

    pushNeighborFrontier(frontier, occupied, tiles[1])

    while #tiles < target_count do
        local next_tile = pickFrontierTile(frontier)
        local key = tileKey(next_tile.q, next_tile.r)

        frontier[key] = nil
        occupied[key] = true
        next_tile.chamber = true
        tiles[#tiles + 1] = next_tile

        pushNeighborFrontier(frontier, occupied, next_tile)
    end

    local all_tiles = {}

    for index, tile in ipairs(tiles) do
        all_tiles[index] = tile
    end

    local room = {
        id = definition.id,
        target_count = target_count,
        chamber_tiles = tiles,
        exit_markers = {},
        tiles = all_tiles,
    }

    addExitsAndCorridors(room, occupied, definition, definitions)

    return room
end

return map_build

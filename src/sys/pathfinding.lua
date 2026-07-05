local pathfinding = {}

local DIRECTIONS = {
    { q = 1, r = 0 },
    { q = 1, r = -1 },
    { q = 0, r = -1 },
    { q = -1, r = 0 },
    { q = -1, r = 1 },
    { q = 0, r = 1 },
}

local function tileKey(q, r)
    return tostring(q) .. "," .. tostring(r)
end

local function buildLookup(room)
    local lookup = {}

    for _, tile in ipairs(room.tiles or {}) do
        lookup[tileKey(tile.q, tile.r)] = tile
    end

    return lookup
end

local function hexDistance(a, b)
    local aq = a.q
    local ar = a.r
    local as = -aq - ar
    local bq = b.q
    local br = b.r
    local bs = -bq - br

    return math.max(math.abs(aq - bq), math.abs(ar - br), math.abs(as - bs))
end

local function getLowestOpen(open_set, f_score)
    local best_index = 1
    local best_tile = open_set[1]
    local best_score = f_score[tileKey(best_tile.q, best_tile.r)] or math.huge

    for index = 2, #open_set do
        local tile = open_set[index]
        local score = f_score[tileKey(tile.q, tile.r)] or math.huge

        if score < best_score then
            best_index = index
            best_tile = tile
            best_score = score
        end
    end

    table.remove(open_set, best_index)

    return best_tile
end

local function reconstructPath(came_from, current)
    local path = { current }
    local current_key = tileKey(current.q, current.r)

    while came_from[current_key] do
        current = came_from[current_key]
        table.insert(path, 1, current)
        current_key = tileKey(current.q, current.r)
    end

    return path
end

function pathfinding.tileKey(tile_or_q, r)
    if type(tile_or_q) == "table" then
        return tileKey(tile_or_q.q, tile_or_q.r)
    end

    return tileKey(tile_or_q, r)
end

function pathfinding.getNeighbors(room, tile)
    local lookup = buildLookup(room)
    local neighbors = {}

    for _, direction in ipairs(DIRECTIONS) do
        local neighbor = lookup[tileKey(tile.q + direction.q, tile.r + direction.r)]

        if neighbor then
            neighbors[#neighbors + 1] = neighbor
        end
    end

    return neighbors
end

function pathfinding.findPath(room, start_tile, goal_tile, options)
    if not room or not start_tile or not goal_tile then
        return nil
    end

    options = options or {}

    local lookup = buildLookup(room)
    local start_key = tileKey(start_tile.q, start_tile.r)
    local goal_key = tileKey(goal_tile.q, goal_tile.r)
    local open_set = { start_tile }
    local open_lookup = { [start_key] = true }
    local came_from = {}
    local g_score = { [start_key] = 0 }
    local f_score = { [start_key] = hexDistance(start_tile, goal_tile) }

    while #open_set > 0 do
        local current = getLowestOpen(open_set, f_score)
        local current_key = tileKey(current.q, current.r)
        open_lookup[current_key] = nil

        if current_key == goal_key then
            return reconstructPath(came_from, current), g_score[current_key]
        end

        for _, direction in ipairs(DIRECTIONS) do
            local neighbor = lookup[tileKey(current.q + direction.q, current.r + direction.r)]

            if neighbor and (not options.isPassable or options.isPassable(neighbor, current, goal_tile)) then
                local neighbor_key = tileKey(neighbor.q, neighbor.r)
                local tentative_g = g_score[current_key] + 1

                if tentative_g < (g_score[neighbor_key] or math.huge) then
                    came_from[neighbor_key] = current
                    g_score[neighbor_key] = tentative_g
                    f_score[neighbor_key] = tentative_g + hexDistance(neighbor, goal_tile)

                    if not open_lookup[neighbor_key] then
                        open_set[#open_set + 1] = neighbor
                        open_lookup[neighbor_key] = true
                    end
                end
            end
        end
    end

    return nil
end

function pathfinding.findReachable(room, start_tile, max_cost, options)
    if not room or not start_tile or max_cost <= 0 then
        return {}
    end

    options = options or {}

    local lookup = buildLookup(room)
    local start_key = tileKey(start_tile.q, start_tile.r)
    local reachable = {
        [start_key] = {
            tile = start_tile,
            cost = 0,
        },
    }
    local frontier = { start_tile }
    local head = 1

    while frontier[head] do
        local current = frontier[head]
        local current_key = tileKey(current.q, current.r)
        local current_cost = reachable[current_key].cost
        head = head + 1

        if current_cost < max_cost then
            for _, direction in ipairs(DIRECTIONS) do
                local neighbor = lookup[tileKey(current.q + direction.q, current.r + direction.r)]

                if neighbor and (not options.isPassable or options.isPassable(neighbor, current)) then
                    local neighbor_key = tileKey(neighbor.q, neighbor.r)
                    local next_cost = current_cost + 1

                    if next_cost <= max_cost and (not reachable[neighbor_key] or next_cost < reachable[neighbor_key].cost) then
                        reachable[neighbor_key] = {
                            tile = neighbor,
                            cost = next_cost,
                        }
                        frontier[#frontier + 1] = neighbor
                    end
                end
            end
        end
    end

    return reachable
end

return pathfinding

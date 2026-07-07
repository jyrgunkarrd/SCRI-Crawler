local map_tiles = require("src.rndr.map_tiles")
local sfx_logic = require("src.sys.sfx_logic")

local door_room_logic = {}

local DOOR_DEFINITIONS_PATH = "data.doors"
local DOOR_HIT_RADIUS = 22

local function tileKey(tile)
    return tostring(tile.q) .. "," .. tostring(tile.r)
end

local function normalizeId(id)
    return tostring(id or ""):upper()
end

local function copyStats(stats)
    local copied = {}

    for _, stat in ipairs(stats or {}) do
        local entry = {}

        for key, value in pairs(stat) do
            entry[key] = value
        end

        copied[#copied + 1] = entry
    end

    return copied
end

local function buildLookup(items)
    local lookup = {}

    for _, item in ipairs(items or {}) do
        if item.id then
            lookup[normalizeId(item.id)] = item
        end
    end

    return lookup
end

local function getDoorLookup()
    package.loaded[DOOR_DEFINITIONS_PATH] = nil

    local ok, doors = pcall(require, DOOR_DEFINITIONS_PATH)

    if not ok then
        print("Unable to load door definitions: " .. tostring(doors))
        return {}
    end

    return buildLookup(doors)
end

local function getStatValue(door, stat_name)
    if not door or not door.stats then
        return 0
    end

    for _, stat in ipairs(door.stats) do
        if stat[stat_name] ~= nil then
            return tonumber(stat[stat_name]) or 0
        end
    end

    return 0
end

function door_room_logic.getRuntimeStat(door, stat_name)
    local maximum = getStatValue(door, stat_name)

    door.runtime_stats = door.runtime_stats or {}

    if not door.runtime_stats[stat_name] then
        door.runtime_stats[stat_name] = {
            current = maximum,
            maximum = maximum,
        }
    end

    return door.runtime_stats[stat_name]
end

function door_room_logic.ensureRuntimeStats(door)
    door_room_logic.getRuntimeStat(door, "hp")
    door_room_logic.getRuntimeStat(door, "bp")
    door.unlocked = door.unlocked or false
end

function door_room_logic.initialize(room)
    if not room then
        return
    end

    local lookup = getDoorLookup()

    for _, door in ipairs(room.doors or {}) do
        local definition_id = door.door_event or door.id
        local definition = lookup[normalizeId(definition_id)]

        if definition then
            door.id = definition.id
            door.name = definition.name
            door.stats = copyStats(definition.stats)
        elseif definition_id and definition_id ~= "" then
            print("Unknown door id: " .. tostring(definition_id))
            door.id = definition_id
            door.name = door.name or tostring(definition_id)
            door.stats = door.stats or {
                { hp = 1 },
                { bp = 1 },
            }
        end

        door.unlocked = false
        door_room_logic.ensureRuntimeStats(door)
    end
end

function door_room_logic.isUnlocked(door)
    return door and door.unlocked == true
end

function door_room_logic.isLocked(door)
    return door ~= nil and not door_room_logic.isUnlocked(door)
end

function door_room_logic.getDoorBetween(room, a, b)
    if not room or not a or not b then
        return nil
    end

    local a_key = tileKey(a)
    local b_key = tileKey(b)

    for _, door in ipairs(room.doors or {}) do
        if door.a and door.b then
            local door_a_key = tileKey(door.a)
            local door_b_key = tileKey(door.b)

            if (door_a_key == a_key and door_b_key == b_key)
                or (door_a_key == b_key and door_b_key == a_key)
            then
                return door
            end
        end
    end

    return nil
end

function door_room_logic.isRoomCorridorBoundary(a, b)
    if not a or not b then
        return false
    end

    local a_is_corridor = not not a.corridor
    local b_is_corridor = not not b.corridor

    return a_is_corridor ~= b_is_corridor
end

function door_room_logic.canTraverseBetween(room, a, b)
    if not door_room_logic.isRoomCorridorBoundary(a, b) then
        return true
    end

    local door = door_room_logic.getDoorBetween(room, a, b)

    return door_room_logic.isUnlocked(door)
end

function door_room_logic.getStats(door)
    if not door then
        return {}
    end

    return {
        hp = door_room_logic.getRuntimeStat(door, "hp"),
        bp = door_room_logic.getRuntimeStat(door, "bp"),
    }
end

function door_room_logic.unlock(door)
    if door then
        door.unlocked = true
    end
end

local function queueDamagePulse(door, stat_name)
    if not door or not love or not love.timer then
        return
    end

    door.damage_pulses = door.damage_pulses or {}
    door.damage_pulses[#door.damage_pulses + 1] = {
        stat = stat_name,
        started_at = love.timer.getTime(),
    }
end

local function applyDamageToStat(door, stat_name, amount)
    local damage = math.max(0, math.floor(tonumber(amount) or 0))

    if not door or damage <= 0 or door_room_logic.isUnlocked(door) then
        return {
            damaged = false,
            unlocked = door_room_logic.isUnlocked(door),
            final_damage = 0,
        }
    end

    local stat = door_room_logic.getRuntimeStat(door, stat_name)
    local previous = stat.current

    stat.current = math.max(0, stat.current - damage)

    if stat.current < previous then
        queueDamagePulse(door, stat_name)

        if stat_name == "bp" then
            sfx_logic.playNamed("bypass")
        else
            sfx_logic.playNamed("dmg")
        end
    end

    if stat.current <= 0 then
        door_room_logic.unlock(door)
    end

    return {
        damaged = stat.current < previous,
        unlocked = door_room_logic.isUnlocked(door),
        final_damage = damage,
    }
end

function door_room_logic.damageHp(door, amount)
    return applyDamageToStat(door, "hp", amount)
end

function door_room_logic.damageBp(door, amount)
    return applyDamageToStat(door, "bp", amount)
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

function door_room_logic.getDoorDistance(tile, door)
    if not tile or not door or not door.a or not door.b then
        return math.huge
    end

    return math.min(hexDistance(tile, door.a), hexDistance(tile, door.b))
end

function door_room_logic.getDrawOffset(room, camera_x, camera_y)
    local offset_x, offset_y = map_tiles.getCenteredOffset(room)

    return offset_x + (camera_x or 0), offset_y + (camera_y or 0)
end

function door_room_logic.getDoorCenter(room, door, camera_x, camera_y)
    if not room or not door or not door.a or not door.b then
        return nil, nil
    end

    local offset_x, offset_y = door_room_logic.getDrawOffset(room, camera_x, camera_y)
    local ax, ay = map_tiles.axialToPixel(door.a.q, door.a.r)
    local bx, by = map_tiles.axialToPixel(door.b.q, door.b.r)

    return (ax + bx) / 2 + offset_x, (ay + by) / 2 + offset_y
end

function door_room_logic.getDoorAtPoint(room, x, y, camera_x, camera_y)
    local best_door = nil
    local best_distance = math.huge

    for _, door in ipairs(room and room.doors or {}) do
        local center_x, center_y = door_room_logic.getDoorCenter(room, door, camera_x, camera_y)

        if center_x and center_y then
            local dx = x - center_x
            local dy = y - center_y
            local distance = math.sqrt(dx * dx + dy * dy)

            if distance <= DOOR_HIT_RADIUS and distance < best_distance then
                best_door = door
                best_distance = distance
            end
        end
    end

    return best_door
end

return door_room_logic

local map_tiles = require("src.rndr.map_tiles")
local sfx_logic = require("src.sys.sfx_logic")

local agent_logic = {
    selected_tile = nil,
    selected_agent = nil,
    shout = nil,
}

local SHOUT_CHARS_PER_SECOND = 58
local SHOUT_MIN_TYPE_SECONDS = 0.08
local SHOUT_HOLD_SECONDS = 0.65

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
    local maximum = getStatValue(agent, stat_name)

    if maximum <= 0 then
        return {
            current = 0,
            maximum = 0,
        }
    end

    agent.runtime_stats = agent.runtime_stats or {}

    if not agent.runtime_stats[stat_name] then
        agent.runtime_stats[stat_name] = {
            current = maximum,
            maximum = maximum,
        }
    end

    return agent.runtime_stats[stat_name]
end

function agent_logic.clearSelection()
    agent_logic.selected_tile = nil
    agent_logic.selected_agent = nil
    agent_logic.shout = nil
end

function agent_logic.selectAgent(agent, tile)
    local shout_text = agent.shout_select or ""
    local type_seconds = math.max(#shout_text / SHOUT_CHARS_PER_SECOND, SHOUT_MIN_TYPE_SECONDS)

    agent_logic.selected_agent = agent
    agent_logic.selected_tile = tile
    agent_logic.shout = {
        text = shout_text,
        elapsed = 0,
        type_seconds = type_seconds,
        duration = type_seconds + SHOUT_HOLD_SECONDS,
    }
    sfx_logic.playAgentSelect(agent)
end

function agent_logic.update(dt)
    if not agent_logic.shout then
        return
    end

    agent_logic.shout.elapsed = agent_logic.shout.elapsed + dt

    if agent_logic.shout.elapsed >= agent_logic.shout.duration then
        agent_logic.shout = nil
    end
end

function agent_logic.handleMousePressed(room, x, y, button, camera_x, camera_y)
    if button ~= 1 then
        return false
    end

    local tile = getTileAtPoint(room, x, y, camera_x, camera_y)

    if tile and tile.agent then
        agent_logic.selectAgent(tile.agent, tile)
    else
        agent_logic.clearSelection()
    end

    return true
end

function agent_logic.getSelectedAgent()
    return agent_logic.selected_agent
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

function agent_logic.getSelectedStats()
    local agent = agent_logic.getSelectedAgent()

    return {
        ap = getRuntimeStat(agent, "ap"),
        hp = getRuntimeStat(agent, "hp"),
        lp = getRuntimeStat(agent, "lp"),
    }
end

return agent_logic

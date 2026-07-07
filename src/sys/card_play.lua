local map_tiles = require("src.rndr.map_tiles")
local agent_logic = require("src.sys.agent_logic")
local pathfinding = require("src.sys.pathfinding")
local fate_logic = require("src.sys.fate_logic")
local action_deck_logic = require("src.sys.action_deck_logic")
local burn_logic = require("src.sys.burn_logic")
local block_logic = require("src.sys.block_logic")

local card_play = {
    drag = nil,
}

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

local function getStatValue(unit, stat_name)
    if not unit or not unit.stats then
        return 0
    end

    for _, stat in ipairs(unit.stats) do
        if stat[stat_name] ~= nil then
            return tonumber(stat[stat_name]) or 0
        end
    end

    return 0
end

local function getRuntimeStat(unit, stat_name)
    local maximum = getStatValue(unit, stat_name)

    unit.runtime_stats = unit.runtime_stats or {}

    if not unit.runtime_stats[stat_name] then
        unit.runtime_stats[stat_name] = {
            current = maximum,
            maximum = maximum,
        }
    end

    return unit.runtime_stats[stat_name]
end

local function getCurrentAp(agent)
    return getRuntimeStat(agent, "ap").current
end

local function getPlayFunc(card)
    return card and card.play_func or {}
end

local function getCardCost(card)
    return math.max(0, math.floor(tonumber(card and card.cost) or 0))
end

local function getRange(card)
    return math.max(0, math.floor(tonumber(getPlayFunc(card).rng) or 0))
end

local function getDamage(card)
    return math.max(0, math.floor(tonumber(getPlayFunc(card).dmg) or 0))
end

local function getBlock(card)
    return math.max(0, math.floor(tonumber(getPlayFunc(card).blk) or 0))
end

local function hasDamage(card)
    return getPlayFunc(card).dmg ~= nil
end

local function hasBlock(card)
    return getPlayFunc(card).blk ~= nil
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

local function matchesTarget(card, tile, source_tile)
    local target = getPlayFunc(card).targ

    if target == "self" then
        return tile == source_tile and tile and tile.agent ~= nil
    end

    if target == "enemy" then
        return tile and tile.enemy ~= nil
    end

    if target == "agent" then
        return tile and tile.agent ~= nil
    end

    return false
end

local function getTargetUnit(card, tile, source_agent)
    local target = getPlayFunc(card).targ

    if target == "self" then
        return source_agent
    end

    if target == "enemy" then
        return tile and tile.enemy or nil
    end

    if target == "agent" then
        return tile and tile.agent or nil
    end

    return nil
end

local function eliminateTarget(room, target_tile, target_unit)
    if target_tile.enemy == target_unit then
        target_tile.enemy = nil

        if agent_logic.getSelectedEnemy and agent_logic.getSelectedEnemy() == target_unit then
            agent_logic.clearSelection()
        end
    elseif target_tile.agent == target_unit then
        map_tiles.startAgentElimination(target_unit, target_tile, { play_sound = false })
        target_tile.agent = nil
        agent_logic.clearSelection()
    end
end

local function damageTarget(room, target_tile, target_unit, damage)
    local original_damage = math.max(0, math.floor(tonumber(damage) or 0))
    local blocked_amount = 0

    damage, blocked_amount = block_logic.absorbDamage(target_unit, damage)

    if damage <= 0 or not target_unit then
        return {
            damaged = false,
            eliminated = false,
            burned = false,
            blocked = target_unit ~= nil and (blocked_amount > 0 or original_damage <= 0),
            final_damage = 0,
        }
    end

    local hp = getRuntimeStat(target_unit, "hp")
    local was_alive = hp.current > 0

    hp.current = math.max(0, hp.current - damage)

    if hp.current <= 0 then
        if target_tile.agent == target_unit then
            local survived_burn = burn_logic.resolveHpCollapse(target_unit, room, { play_elimination_sound = false })

            return {
                damaged = was_alive and damage > 0,
                eliminated = not survived_burn,
                burned = survived_burn,
                blocked = false,
                final_damage = damage,
            }
        end

        eliminateTarget(room, target_tile, target_unit)
    end

    return {
        damaged = was_alive and damage > 0,
        eliminated = was_alive and hp.current <= 0,
        burned = false,
        blocked = false,
        final_damage = damage,
    }
end

local function removeCardFromHand(agent, hand_index)
    action_deck_logic.discardFromHand(agent, hand_index)
end

function card_play.canPay(agent, card)
    return agent
        and not action_deck_logic.isCardFatigued(agent, card)
        and getCurrentAp(agent) >= getCardCost(card)
end

function card_play.startDrag(agent, source_tile, card, hand_index)
    if not agent or not source_tile or not card or not hand_index then
        return false
    end

    if not card_play.canPay(agent, card) then
        return false
    end

    card_play.drag = {
        agent = agent,
        source_tile = source_tile,
        card = card,
        hand_index = hand_index,
    }

    return true
end

function card_play.cancelDrag()
    card_play.drag = nil
end

function card_play.isDragging()
    return card_play.drag ~= nil
end

function card_play.getDraggedCard()
    return card_play.drag and card_play.drag.card or nil
end

function card_play.getOverlay(room)
    local drag = card_play.drag

    if not drag or not room or not room.tiles then
        return nil
    end

    local range = getRange(drag.card)
    local range_tiles = {}
    local target_tiles = {}

    for _, tile in ipairs(room.tiles) do
        if hexDistance(drag.source_tile, tile) <= range then
            range_tiles[pathfinding.tileKey(tile)] = tile

            if matchesTarget(drag.card, tile, drag.source_tile) then
                target_tiles[pathfinding.tileKey(tile)] = tile
            end
        end
    end

    return {
        range_tiles = range_tiles,
        target_tiles = target_tiles,
    }
end

function card_play.release(room, x, y, camera_x, camera_y)
    local drag = card_play.drag
    card_play.drag = nil

    if not drag or not card_play.canPay(drag.agent, drag.card) then
        return false, nil
    end

    local target_tile = getTileAtPoint(room, x, y, camera_x, camera_y)

    if not target_tile
        or hexDistance(drag.source_tile, target_tile) > getRange(drag.card)
        or not matchesTarget(drag.card, target_tile, drag.source_tile)
    then
        return false, nil
    end

    local target_unit = getTargetUnit(drag.card, target_tile, drag.agent)
    local target_kind = target_tile.enemy == target_unit and "enemy" or "agent"
    local ap = getRuntimeStat(drag.agent, "ap")

    ap.current = math.max(0, ap.current - getCardCost(drag.card))

    if hasBlock(drag.card) then
        block_logic.addBlock(target_unit, getBlock(drag.card))
        removeCardFromHand(drag.agent, drag.hand_index)
        agent_logic.refreshMovementRange(room)
        return true, nil
    end

    local damage = getDamage(drag.card)
    local fate_card = nil

    if hasDamage(drag.card) then
        damage, fate_card = fate_logic.applyDamageModifier(drag.agent, damage)
    end

    local result = damageTarget(room, target_tile, target_unit, damage)
    removeCardFromHand(drag.agent, drag.hand_index)
    agent_logic.refreshMovementRange(room)

    return true, {
        agent = drag.agent,
        target = target_unit,
        target_kind = target_kind,
        card = drag.card,
        fate_card = fate_card,
        damage = result.final_damage or damage,
        damaged = result.damaged,
        eliminated = result.eliminated,
        burned = result.burned,
        blocked = result.blocked,
        failed = fate_card and fate_card.fail or false,
    }
end

return card_play

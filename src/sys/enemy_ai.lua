local fate_logic = require("src.sys.fate_logic")
local pathfinding = require("src.sys.pathfinding")
local map_tiles = require("src.rndr.map_tiles")
local burn_logic = require("src.sys.burn_logic")
local block_logic = require("src.sys.block_logic")
local door_room_logic = require("src.sys.door_room_logic")
local corpse_logic = require("src.sys.corpse_logic")

local enemy_ai = {}

local ENEMY_ACTION_IMAGE_DIR = "assets/images/en_act"
local MOVE_ANIMATION_SECONDS = 0.18
local movement_animation = nil
local pending_attack_event = nil
local pending_hazard_events = {}

local function getStatValue(unit, stat_name)
    if not unit or not unit.stats then
        return 0
    end

    for _, stat in ipairs(unit.stats) do
        if stat[stat_name] ~= nil then
            return fate_logic.getScaledStatValue(unit, stat_name, stat[stat_name])
        end
    end

    return 0
end

local function getActionValue(unit, action, value_name)
    local value = tonumber(action and action[value_name]) or 0
    local unit_action_scale = unit and unit.level_scale and (unit.level_scale.en_act or unit.level_scale.actions)
    local action_scale = action and action.level_scale

    if (unit_action_scale and unit_action_scale[value_name] == true)
        or (action_scale and action_scale[value_name] == true)
    then
        value = value * fate_logic.getFateScale(unit)
    end

    return value
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

local function getAgentTiles(room)
    local agents = {}

    for _, tile in ipairs(room and room.tiles or {}) do
        if tile.agent then
            agents[#agents + 1] = tile
        end
    end

    return agents
end

local function getEnemyTiles(room)
    local enemies = {}

    for _, tile in ipairs(room and room.tiles or {}) do
        if tile.enemy then
            enemies[#enemies + 1] = tile
        end
    end

    table.sort(enemies, function(a, b)
        if a.r == b.r then
            return a.q < b.q
        end

        return a.r < b.r
    end)

    return enemies
end

local function getCurrentHp(agent)
    return getRuntimeStat(agent, "hp").current
end

local isPassableForEnemy
local isRangePassable

local function findTargetTile(room, enemy_tile)
    local best_tile = nil
    local best_distance = math.huge
    local best_hp = math.huge

    for _, tile in ipairs(getAgentTiles(room)) do
        local _, path_cost = pathfinding.findPath(room, enemy_tile, tile, {
            isPassable = isPassableForEnemy(room, enemy_tile),
        })

        if path_cost then
            local hp = getCurrentHp(tile.agent)

            if path_cost < best_distance or (path_cost == best_distance and hp < best_hp) then
                best_tile = tile
                best_distance = path_cost
                best_hp = hp
            end
        end
    end

    return best_tile
end

function isPassableForEnemy(room, enemy_tile)
    return function(tile, current, goal_tile)
        if current and not door_room_logic.canTraverseBetween(room, current, tile) then
            return false
        end

        if tile == enemy_tile or tile == goal_tile then
            return true
        end

        return not tile.agent and not tile.hazard
    end
end

function isRangePassable(room)
    return function(tile, current)
        return door_room_logic.canTraverseBetween(room, current, tile)
    end
end

local function isTileInRange(room, origin_tile, target_tile, range)
    if not origin_tile or not target_tile then
        return false
    end

    if pathfinding.tileKey(origin_tile) == pathfinding.tileKey(target_tile) then
        return true
    end

    local _, cost = pathfinding.findPath(room, origin_tile, target_tile, {
        isPassable = isRangePassable(room),
    })

    return cost ~= nil and cost <= range
end

local function getFurthestOpenStep(path, speed, fallback_tile)
    local max_index = math.min(#path, speed + 1)

    for index = max_index, 1, -1 do
        local tile = path[index]

        if tile == fallback_tile or (not tile.agent and not tile.enemy and not tile.hazard) then
            return tile
        end
    end

    return fallback_tile
end

local function findBestApproach(room, enemy_tile, target_tile, speed, range)
    local best_path = nil
    local best_cost = math.huge

    for _, tile in ipairs(room and room.tiles or {}) do
        if isTileInRange(room, tile, target_tile, range) and (tile == enemy_tile or (not tile.agent and not tile.enemy and not tile.hazard)) then
            local path, cost = pathfinding.findPath(room, enemy_tile, tile, {
                isPassable = isPassableForEnemy(room, enemy_tile),
            })

            if path and cost and cost < best_cost then
                best_path = path
                best_cost = cost
            end
        end
    end

    if not best_path then
        local path = pathfinding.findPath(room, enemy_tile, target_tile, {
            isPassable = isPassableForEnemy(room, enemy_tile),
        })
        best_path = path
    end

    if not best_path then
        return enemy_tile
    end

    return getFurthestOpenStep(best_path, speed, enemy_tile), best_path
end

local function chooseAction(enemy)
    local actions = enemy and enemy.en_act or {}
    local total_weight = 0

    for _, action in ipairs(actions) do
        total_weight = total_weight + math.max(0, tonumber(action.weight) or 0)
    end

    if total_weight <= 0 then
        return actions[1]
    end

    local roll = love.math.random() * total_weight
    local cursor = 0

    for _, action in ipairs(actions) do
        cursor = cursor + math.max(0, tonumber(action.weight) or 0)

        if roll <= cursor then
            return action
        end
    end

    return actions[#actions]
end

local function getActionId(action)
    if not action then
        return nil
    end

    return action.id or action.act or action.act1 or action[1]
end

local function isAgentInRoom(room, target)
    for _, tile in ipairs(room and room.tiles or {}) do
        if tile.agent == target then
            return true
        end
    end

    return false
end

local function applyDamage(room, target, damage)
    local original_damage = math.max(0, math.floor(tonumber(damage) or 0))
    local blocked_amount = 0

    damage, blocked_amount = block_logic.absorbDamage(target, damage)

    if damage <= 0 then
        return false, false, false, blocked_amount > 0 or original_damage <= 0, 0
    end

    local hp = getRuntimeStat(target, "hp")
    local previous = hp.current

    hp.current = math.max(0, hp.current - damage)
    local damaged = hp.current < previous

    if hp.current <= 0 then
        if not isAgentInRoom(room, target) then
            return damaged, true, false, false, damage
        end

        local survived_burn = burn_logic.resolveHpCollapse(target, room, { play_elimination_sound = false })

        return damaged, not survived_burn, survived_burn, false, damage
    end

    return damaged, false, false, false, damage
end

local function removeEliminatedEnemy(room, enemy)
    for _, tile in ipairs(room and room.tiles or {}) do
        if tile.enemy == enemy then
            corpse_logic.replaceEnemy(tile, enemy)
            return
        end
    end
end

local function getEnemyTile(room, enemy)
    for _, tile in ipairs(room and room.tiles or {}) do
        if tile.enemy == enemy then
            return tile
        end
    end

    return nil
end

local function removeEliminatedAgent(room, agent)
    for _, tile in ipairs(room and room.tiles or {}) do
        if tile.agent == agent then
            map_tiles.startAgentElimination(agent, tile, { play_sound = false })
            tile.agent = nil
            return
        end
    end
end

local function buildAttackEvent(enemy, target, action, damage, fate_card, damaged, eliminated, burned, blocked, source_kind, target_kind)
    local action_id = getActionId(action)

    return {
        agent = enemy,
        agent_kind = source_kind or "enemy",
        target = target,
        target_kind = target_kind or "agent",
        card = {
            id = action_id,
            name = action_id,
            image_dir = ENEMY_ACTION_IMAGE_DIR,
        },
        fate_card = fate_card,
        damage = damage,
        damaged = damaged,
        eliminated = eliminated,
        burned = burned,
        blocked = blocked,
        failed = fate_card and fate_card.fail or false,
    }
end

local function queueHazardAttack(room, hazard_tile, target, target_kind)
    local hazard = hazard_tile and hazard_tile.hazard

    if not hazard or hazard.triggered then
        return false
    end

    hazard.triggered = true
    fate_logic.initializeFateDeck(hazard)

    local action = chooseAction(hazard) or {}
    local base_damage = getStatValue(hazard, "atk") + math.max(0, getActionValue(hazard, action, "dmg"))
    local damage, fate_card = fate_logic.applyDamageModifier(hazard, base_damage)
    local damaged, eliminated, burned, blocked, final_damage = applyDamage(room, target, damage)

    local deferred_enemy_elimination_tile = nil

    if eliminated then
        if target_kind == "agent" then
            removeEliminatedAgent(room, target)
        elseif target_kind == "enemy" then
            deferred_enemy_elimination_tile = getEnemyTile(room, target)
        end
    end

    local event = buildAttackEvent(
        hazard,
        target,
        action,
        final_damage or damage,
        fate_card,
        damaged,
        eliminated,
        burned,
        blocked,
        "hazard",
        target_kind
    )
    event.hazard_tile = hazard_tile
    event.remove_hazard_after = true
    event.deferred_enemy_elimination_tile = deferred_enemy_elimination_tile

    pending_hazard_events[#pending_hazard_events + 1] = event

    return true
end

function enemy_ai.triggerHazardsForPath(room, unit, kind, path)
    if not room or not unit or not path then
        return false
    end

    for index = 2, #path do
        local tile = path[index]

        if tile and tile.hazard then
            return queueHazardAttack(room, tile, unit, kind)
        end
    end

    return false
end

function enemy_ai.takePendingHazardEvent()
    if #pending_hazard_events == 0 then
        return nil
    end

    return table.remove(pending_hazard_events, 1)
end

function enemy_ai.takeNextAction(room)
    if pending_attack_event then
        local event = pending_attack_event
        pending_attack_event = nil
        return event
    end

    for _, enemy_tile in ipairs(getEnemyTiles(room)) do
        local enemy = enemy_tile.enemy

        if not enemy.exhausted then
            fate_logic.initializeFateDeck(enemy)

            local target_tile = findTargetTile(room, enemy_tile)

            if not target_tile then
                enemy.exhausted = true
                return nil
            end

            local speed = math.max(0, math.floor(getStatValue(enemy, "spd")))
            local range = math.max(1, math.floor(getStatValue(enemy, "rng")))
            local destination, movement_path = findBestApproach(room, enemy_tile, target_tile, speed, range)

            if destination ~= enemy_tile and not destination.agent and not destination.enemy and not destination.hazard then
                movement_animation = {
                    agent = enemy,
                    kind = "enemy",
                    from = { q = enemy_tile.q, r = enemy_tile.r },
                    to = { q = destination.q, r = destination.r },
                    elapsed = 0,
                    duration = MOVE_ANIMATION_SECONDS,
                }
                enemy_tile.enemy = nil
                destination.enemy = enemy
                enemy_tile = destination
                enemy_ai.triggerHazardsForPath(room, enemy, "enemy", movement_path)
            end

            target_tile = findTargetTile(room, enemy_tile)

            if not target_tile or not isTileInRange(room, enemy_tile, target_tile, range) then
                enemy.exhausted = true
                return nil
            end

            local action = chooseAction(enemy)
            local base_damage = getStatValue(enemy, "atk") + math.max(0, getActionValue(enemy, action, "dmg"))
            local target = target_tile.agent
            local damage, fate_card = fate_logic.applyDamageModifier(enemy, base_damage)
            local damaged, eliminated, burned, blocked, final_damage = applyDamage(room, target, damage)

            if eliminated then
                removeEliminatedAgent(room, target)
            end

            enemy.exhausted = true

            local event = buildAttackEvent(enemy, target, action, final_damage or damage, fate_card, damaged, eliminated, burned, blocked)

            if movement_animation then
                pending_attack_event = event
                return nil
            end

            return event
        end
    end

    return nil
end

function enemy_ai.update(dt)
    if not movement_animation then
        return
    end

    movement_animation.elapsed = movement_animation.elapsed + dt

    if movement_animation.elapsed >= movement_animation.duration then
        movement_animation = nil
    end
end

function enemy_ai.isMoving()
    return movement_animation ~= nil
end

function enemy_ai.getMovementAnimation()
    return movement_animation
end

function enemy_ai.hasReadyEnemies(room)
    if pending_attack_event then
        return true
    end

    for _, tile in ipairs(room and room.tiles or {}) do
        if tile.enemy and not tile.enemy.exhausted then
            return true
        end
    end

    return false
end

function enemy_ai.refreshEnemies(room)
    for _, tile in ipairs(room and room.tiles or {}) do
        if tile.enemy then
            tile.enemy.exhausted = false
        end
    end
end

return enemy_ai

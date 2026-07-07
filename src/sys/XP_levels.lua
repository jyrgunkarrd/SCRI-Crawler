local sfx_logic = require("src.sys.sfx_logic")

local XP_levels = {}

local MAX_LEVEL = 50
local STAT_POINTS_PER_LEVEL = 8
local LP_PER_LEX = 2
local ZERO_LP_LEX_UNLOCK = 20

function XP_levels.xpToNext(level)
    local effectiveLevel = math.max(1, math.floor(tonumber(level) or 0))

    return math.floor((2 * (effectiveLevel ^ 1.5)) + 0.5)
end

local function getBaseStatValue(agent, stat_id)
    for _, stat in ipairs(agent and agent.stats or {}) do
        if stat[stat_id] ~= nil then
            return math.floor(tonumber(stat[stat_id]) or 0)
        end
    end

    return 0
end

local function getHpStat(agent)
    if not agent then
        return nil
    end

    agent.runtime_stats = agent.runtime_stats or {}

    if not agent.runtime_stats.hp then
        local maximum = 0

        for _, stat in ipairs(agent.stats or {}) do
            if stat.hp ~= nil then
                maximum = tonumber(stat.hp) or 0
                break
            end
        end

        agent.runtime_stats.hp = {
            current = maximum,
            maximum = maximum,
        }
    end

    return agent.runtime_stats.hp
end

local function getRuntimeStat(agent, stat_id)
    if not agent then
        return nil
    end

    agent.runtime_stats = agent.runtime_stats or {}

    if not agent.runtime_stats[stat_id] then
        local maximum = 0

        for _, stat in ipairs(agent.stats or {}) do
            if stat[stat_id] ~= nil then
                maximum = tonumber(stat[stat_id]) or 0
                break
            end
        end

        agent.runtime_stats[stat_id] = {
            current = maximum,
            maximum = maximum,
        }
    end

    return agent.runtime_stats[stat_id]
end

local function applyHpGrowth(agent)
    local growth = math.max(0, math.floor(tonumber(agent and agent.hpgrowth) or 0))
    local hp = getHpStat(agent)

    if not hp then
        return
    end

    hp.maximum = math.max(0, math.floor(tonumber(hp.maximum) or 0)) + growth
    hp.current = hp.maximum
end

local function addStatPoints(agent, amount)
    if not agent then
        return
    end

    agent.stat_points = math.max(0, math.floor(tonumber(agent.stat_points) or 0))
        + math.max(0, math.floor(tonumber(amount) or 0))
end

local function getStatEntry(agent, stat_id)
    if not agent or not stat_id then
        return nil
    end

    agent.stats = agent.stats or {}

    for _, stat in ipairs(agent.stats) do
        if stat[stat_id] ~= nil then
            return stat
        end
    end

    local stat = { [stat_id] = 0 }
    agent.stats[#agent.stats + 1] = stat

    return stat
end

local function applyLexLpGrowth(agent, old_lex, new_lex)
    local lp = getRuntimeStat(agent, "lp")

    if not lp then
        return
    end

    if getBaseStatValue(agent, "lp") <= 0 then
        if new_lex < ZERO_LP_LEX_UNLOCK then
            return
        end

        if old_lex < ZERO_LP_LEX_UNLOCK then
            lp.maximum = math.max(1, math.floor(tonumber(lp.maximum) or 0))
            lp.current = math.max(1, math.floor(tonumber(lp.current) or 0))
            return
        end
    end

    lp.maximum = math.max(0, math.floor(tonumber(lp.maximum) or 0)) + LP_PER_LEX
    lp.current = math.max(0, math.floor(tonumber(lp.current) or 0)) + LP_PER_LEX
end

function XP_levels.getMaxLevel()
    return MAX_LEVEL
end

function XP_levels.getStatPointsPerLevel()
    return STAT_POINTS_PER_LEVEL
end

function XP_levels.isMaxLevel(agent)
    return math.max(0, math.floor(tonumber(agent and agent.level) or 0)) >= MAX_LEVEL
end

function XP_levels.initializeAgent(agent)
    if not agent then
        return
    end

    agent.level = math.min(MAX_LEVEL, math.max(0, math.floor(tonumber(agent.level) or 0)))
    agent.xp = math.max(0, math.floor(tonumber(agent.xp) or 0))
    agent.stat_points = math.max(0, math.floor(tonumber(agent.stat_points) or 0))

    while agent.level < MAX_LEVEL and agent.xp >= XP_levels.xpToNext(agent.level) do
        agent.xp = agent.xp - XP_levels.xpToNext(agent.level)
        agent.level = agent.level + 1
        applyHpGrowth(agent)
        addStatPoints(agent, STAT_POINTS_PER_LEVEL)
    end

    if agent.level >= MAX_LEVEL then
        agent.level = MAX_LEVEL
        agent.xp = 0
    end
end

function XP_levels.getLevel(agent)
    XP_levels.initializeAgent(agent)

    return agent and agent.level or 0
end

function XP_levels.getXp(agent)
    XP_levels.initializeAgent(agent)

    return agent and agent.xp or 0
end

function XP_levels.getXpToNext(agent)
    if XP_levels.isMaxLevel(agent) then
        return 0
    end

    return XP_levels.xpToNext(XP_levels.getLevel(agent))
end

function XP_levels.getReward(target)
    return math.max(0, math.floor(tonumber(target and target.xpreward) or 0))
end

function XP_levels.getStatPoints(agent)
    XP_levels.initializeAgent(agent)

    return math.max(0, math.floor(tonumber(agent and agent.stat_points) or 0))
end

function XP_levels.spendStatPoint(agent, stat_id)
    if stat_id ~= "strength" and stat_id ~= "agility" and stat_id ~= "lex" then
        return false
    end

    XP_levels.initializeAgent(agent)

    if XP_levels.getStatPoints(agent) <= 0 then
        return false
    end

    local stat = getStatEntry(agent, stat_id)

    if not stat then
        return false
    end

    local old_value = math.floor(tonumber(stat[stat_id]) or 0)

    stat[stat_id] = old_value + 1

    if stat_id == "lex" then
        applyLexLpGrowth(agent, old_value, stat[stat_id])
    end

    agent.stat_points = XP_levels.getStatPoints(agent) - 1

    return true
end

function XP_levels.addXp(agent, amount)
    if not agent then
        return 0
    end

    XP_levels.initializeAgent(agent)

    if XP_levels.isMaxLevel(agent) then
        return 0
    end

    local xp = math.max(0, math.floor(tonumber(amount) or 0))
    local levels_gained = 0

    while xp > 0 and agent.level < MAX_LEVEL do
        local needed = XP_levels.xpToNext(agent.level)
        local remaining = needed - agent.xp

        if xp >= remaining then
            xp = xp - remaining
            agent.level = agent.level + 1
            agent.xp = 0
            applyHpGrowth(agent)
            addStatPoints(agent, STAT_POINTS_PER_LEVEL)
            levels_gained = levels_gained + 1
        else
            agent.xp = agent.xp + xp
            xp = 0
        end
    end

    if agent.level >= MAX_LEVEL then
        agent.level = MAX_LEVEL
        agent.xp = 0
    end

    if levels_gained > 0 then
        sfx_logic.playNamed("lvlup")
    end

    return levels_gained
end

function XP_levels.awardDefeat(agent, target)
    if not agent or not target or target.xp_awarded then
        return 0
    end

    local reward = XP_levels.getReward(target)

    if reward <= 0 then
        return 0
    end

    target.xp_awarded = true
    XP_levels.addXp(agent, reward)

    return reward
end

return XP_levels

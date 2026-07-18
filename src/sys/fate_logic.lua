local fate_logic = {}

local FATE_STACKS_PATH = "data.fate_stacks"
local FATE_TILES_PATH = "data.fate_tiles"
local FATIGUE_TILE_ID = "BSCFATIGUE"
local FATIGUE_DISPLAY_ORDER = 0
local TOTAL_FATE_UPGRADES = 17
local MAX_PHYSICAL_INVESTMENT = 400
local FATE_SCALE_BANDS = {
    { min = 0, max = 4, scale = 1 },
    { min = 5, max = 13, scale = 2 },
    { min = 14, max = 23, scale = 3 },
    { min = 24, max = 32, scale = 4 },
    { min = 33, max = 41, scale = 5 },
    { min = 42, max = 50, scale = 6 },
}

local function buildLookup(items)
    local lookup = {}

    for _, item in ipairs(items or {}) do
        lookup[item.id] = item
    end

    return lookup
end

local function getStackLookup()
    return buildLookup(require(FATE_STACKS_PATH))
end

local function getTileLookup()
    return buildLookup(require(FATE_TILES_PATH))
end

local function getStatValue(agent, stat_id)
    for _, stat in ipairs(agent and agent.stats or {}) do
        if stat[stat_id] ~= nil then
            return math.floor(tonumber(stat[stat_id]) or 0)
        end
    end

    return 0
end

local function getUnitLevel(unit)
    if not unit then
        return 0
    end

    return math.max(0, math.floor(tonumber(unit.lv ~= nil and unit.lv or unit.level) or 0))
end

function fate_logic.getFateScale(unit)
    local level = getUnitLevel(unit)

    for _, band in ipairs(FATE_SCALE_BANDS) do
        if level >= band.min and level <= band.max then
            return band.scale
        end
    end

    if level > FATE_SCALE_BANDS[#FATE_SCALE_BANDS].max then
        return FATE_SCALE_BANDS[#FATE_SCALE_BANDS].scale
    end

    return 1
end

function fate_logic.shouldScaleStat(unit, stat_id)
    return unit
        and unit.level_scale
        and unit.level_scale.stats
        and unit.level_scale.stats[stat_id] == true
end

function fate_logic.getScaledStatValue(unit, stat_id, value)
    local stat_value = tonumber(value) or 0

    if fate_logic.shouldScaleStat(unit, stat_id) then
        stat_value = stat_value * fate_logic.getFateScale(unit)
    end

    if unit and unit.lv ~= nil then
        local level = getUnitLevel(unit)

        if stat_id == "hp" then
            stat_value = stat_value + math.max(0, math.floor(tonumber(unit.hpgrowth) or 0)) * level
        elseif stat_id == "bp" then
            stat_value = stat_value + math.max(0, math.floor(tonumber(unit.bpgrowth) or 0)) * level
        end
    end

    return stat_value
end

function fate_logic.getFateUpgradeSteps(agent)
    local strength = getStatValue(agent, "strength")
    local agility = getStatValue(agent, "agility")
    local physical = strength + agility
    local steps = math.floor((physical * TOTAL_FATE_UPGRADES) / MAX_PHYSICAL_INVESTMENT)

    return math.min(TOTAL_FATE_UPGRADES, math.max(0, steps))
end

function fate_logic.getPositiveFateCounts(agent)
    local steps = fate_logic.getFateUpgradeSteps(agent)
    local zero_to_one = math.min(6, steps)
    local one_to_two = math.min(11, math.max(0, steps - 6))
    local plus_zero = 6 - zero_to_one
    local plus_one = 5 + zero_to_one - one_to_two
    local plus_two = 1 + one_to_two

    return plus_zero, plus_one, plus_two
end

local function getProgressedQuantity(agent, stack_tile, card)
    if not card or card.neg or card.fail or card.crit then
        return math.max(0, math.floor(stack_tile.quantity or 0))
    end

    local plus_zero, plus_one, plus_two = fate_logic.getPositiveFateCounts(agent)

    if stack_tile.slot == "BSC0" then
        return plus_zero
    elseif stack_tile.slot == "BSC1" then
        return plus_one
    elseif stack_tile.slot == "BSC2" then
        return plus_two
    end

    return math.max(0, math.floor(stack_tile.quantity or 0))
end

local function shuffle(items)
    for index = #items, 2, -1 do
        local swap_index = love.math.random(index)

        items[index], items[swap_index] = items[swap_index], items[index]
    end
end

local function formatCardValue(card, value)
    if card.fail then
        return "FAIL", "fail"
    end

    if card.crit then
        return "CRIT", "crit"
    end

    if card.neg then
        return "-" .. tostring(value or 0), "neg"
    end

    return "+" .. tostring(value or 0), "pos"
end

local function buildRuntimeCard(card, display_order, fate_scale)
    local scale = math.max(1, math.floor(tonumber(fate_scale) or 1))
    local base_value = tonumber(card.value) or 0
    local value = base_value * scale
    local value_text, value_kind = formatCardValue(card, value)

    return {
        id = card.id,
        display_order = display_order,
        base_value = base_value,
        value = value,
        fate_scale = scale,
        value_text = value_text,
        value_kind = value_kind,
        neg = card.neg,
        fail = card.fail,
        crit = card.crit,
    }
end

local function stackCards(cards)
    local stacks = {}
    local result = {}

    for _, card in ipairs(cards or {}) do
        if not stacks[card.id] then
            local stack = buildRuntimeCard(card)
            stack.quantity = 0
            stack.display_order = card.id == FATIGUE_TILE_ID
                and FATIGUE_DISPLAY_ORDER
                or card.display_order or math.huge
            stacks[card.id] = stack
            result[#result + 1] = stack
        end

        stacks[card.id].quantity = stacks[card.id].quantity + 1
    end

    table.sort(result, function(a, b)
        if a.display_order == b.display_order then
            return tostring(a.id) < tostring(b.id)
        end

        return a.display_order < b.display_order
    end)

    return result
end

local function reshuffleDiscardIntoDeck(agent)
    if not agent.fate_runtime or not agent.fate_runtime.discard or #agent.fate_runtime.discard == 0 then
        return
    end

    for _, card in ipairs(agent.fate_runtime.discard) do
        agent.fate_runtime.deck[#agent.fate_runtime.deck + 1] = card
    end

    agent.fate_runtime.discard = {}
    shuffle(agent.fate_runtime.deck)
end

function fate_logic.reshuffleDiscardIntoDeck(agent)
    if not agent or not agent.fate_runtime or not agent.fate_runtime.discard
        or #agent.fate_runtime.discard == 0
    then
        return false
    end

    reshuffleDiscardIntoDeck(agent)

    return true
end

function fate_logic.initializeFateDeck(agent)
    if not agent or not agent.fate then
        return
    end

    local progression_steps = fate_logic.getFateUpgradeSteps(agent)
    local fate_scale = fate_logic.getFateScale(agent)

    if agent.fate_runtime
        and agent.fate_runtime.progression_steps == progression_steps
        and agent.fate_runtime.fate_scale == fate_scale
    then
        return
    end

    local stack = getStackLookup()[agent.fate]

    if not stack then
        print("Unknown fate stack id: " .. tostring(agent.fate))
        agent.fate_runtime = {
            deck = {},
            discard = {},
        }
        return
    end

    local tile_lookup = getTileLookup()
    local deck = {}

    for index, stack_tile in ipairs(stack.tiles or {}) do
        local card = tile_lookup[stack_tile.slot]

        if card then
            for _ = 1, getProgressedQuantity(agent, stack_tile, card) do
                deck[#deck + 1] = buildRuntimeCard(card, index, fate_scale)
            end
        else
            print("Unknown fate tile id: " .. tostring(stack_tile.slot))
        end
    end

    for tile_id, quantity in pairs(agent.fate_extra_tiles or {}) do
        local card = tile_lookup[tile_id]

        if card then
            local display_order = tile_id == FATIGUE_TILE_ID
                and FATIGUE_DISPLAY_ORDER
                or #deck + 1

            for _ = 1, math.max(0, math.floor(tonumber(quantity) or 0)) do
                deck[#deck + 1] = buildRuntimeCard(card, display_order, fate_scale)
            end
        end
    end

    shuffle(deck)

    agent.fate_runtime = {
        deck = deck,
        discard = {},
        progression_steps = progression_steps,
        fate_scale = fate_scale,
    }
end

function fate_logic.addTiles(agent, tile_id, quantity)
    quantity = math.max(0, math.floor(tonumber(quantity) or 0))

    if not agent or not agent.fate or quantity == 0 then
        return false
    end

    local card = getTileLookup()[tile_id]

    if not card then
        return false
    end

    fate_logic.initializeFateDeck(agent)

    agent.fate_extra_tiles = agent.fate_extra_tiles or {}
    agent.fate_extra_tiles[tile_id] = math.max(
        0,
        math.floor(tonumber(agent.fate_extra_tiles[tile_id]) or 0)
    ) + quantity

    local fate_scale = fate_logic.getFateScale(agent)
    local display_order = tile_id == FATIGUE_TILE_ID
        and FATIGUE_DISPLAY_ORDER
        or #(agent.fate_runtime and agent.fate_runtime.deck or {}) + 1

    agent.fate_runtime = agent.fate_runtime or { deck = {}, discard = {} }
    agent.fate_runtime.deck = agent.fate_runtime.deck or {}

    for _ = 1, quantity do
        agent.fate_runtime.deck[#agent.fate_runtime.deck + 1] = buildRuntimeCard(
            card,
            display_order,
            fate_scale
        )
    end

    shuffle(agent.fate_runtime.deck)

    return true
end

function fate_logic.drawFateCard(agent)
    fate_logic.initializeFateDeck(agent)

    if not agent or not agent.fate_runtime then
        return nil
    end

    if #agent.fate_runtime.deck == 0 then
        reshuffleDiscardIntoDeck(agent)
    end

    local card = table.remove(agent.fate_runtime.deck)

    if not card then
        return nil
    end

    agent.fate_runtime.discard[#agent.fate_runtime.discard + 1] = card

    if card.fail or card.crit then
        reshuffleDiscardIntoDeck(agent)
    end

    return card
end

function fate_logic.applyDamageModifier(agent, damage)
    local card = fate_logic.drawFateCard(agent)
    local modified_damage = math.max(0, math.floor(tonumber(damage) or 0))

    if not card then
        return modified_damage, nil
    end

    if card.fail then
        modified_damage = 0
    elseif card.crit then
        modified_damage = (modified_damage + card.value) * card.value
    elseif card.neg then
        modified_damage = math.max(0, modified_damage - card.value)
    else
        modified_damage = modified_damage + card.value
    end

    return modified_damage, card
end

function fate_logic.getAgentDeck(agent)
    if not agent or not agent.fate then
        return {}
    end

    fate_logic.initializeFateDeck(agent)

    return stackCards(agent.fate_runtime and agent.fate_runtime.deck or {})
end

function fate_logic.getAgentDiscard(agent)
    if not agent or not agent.fate then
        return {}
    end

    fate_logic.initializeFateDeck(agent)

    return stackCards(agent.fate_runtime and agent.fate_runtime.discard or {})
end

return fate_logic

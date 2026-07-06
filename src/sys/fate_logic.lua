local fate_logic = {}

local FATE_STACKS_PATH = "data.fate_stacks"
local FATE_TILES_PATH = "data.fate_tiles"

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

local function shuffle(items)
    for index = #items, 2, -1 do
        local swap_index = love.math.random(index)

        items[index], items[swap_index] = items[swap_index], items[index]
    end
end

local function formatCardValue(card)
    if card.fail then
        return "FAIL", "fail"
    end

    if card.crit then
        return "CRIT", "crit"
    end

    if card.neg then
        return "-" .. tostring(card.value or 0), "neg"
    end

    return "+" .. tostring(card.value or 0), "pos"
end

local function buildRuntimeCard(card)
    local value_text, value_kind = formatCardValue(card)

    return {
        id = card.id,
        value = tonumber(card.value) or 0,
        value_text = value_text,
        value_kind = value_kind,
        neg = card.neg,
        fail = card.fail,
        crit = card.crit,
    }
end

local function stackCards(cards)
    local stacks = {}
    local order = {}

    for _, card in ipairs(cards or {}) do
        if not stacks[card.id] then
            local stack = buildRuntimeCard(card)
            stack.quantity = 0
            stacks[card.id] = stack
            order[#order + 1] = card.id
        end

        stacks[card.id].quantity = stacks[card.id].quantity + 1
    end

    local result = {}

    for _, card_id in ipairs(order) do
        result[#result + 1] = stacks[card_id]
    end

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

function fate_logic.initializeFateDeck(agent)
    if not agent or not agent.fate then
        return
    end

    if agent.fate_runtime then
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

    for _, stack_tile in ipairs(stack.tiles or {}) do
        local card = tile_lookup[stack_tile.slot]

        if card then
            for _ = 1, math.max(0, math.floor(stack_tile.quantity or 0)) do
                deck[#deck + 1] = buildRuntimeCard(card)
            end
        else
            print("Unknown fate tile id: " .. tostring(stack_tile.slot))
        end
    end

    shuffle(deck)

    agent.fate_runtime = {
        deck = deck,
        discard = {},
    }
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

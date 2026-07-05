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

function fate_logic.getAgentDeck(agent)
    if not agent or not agent.fate then
        return {}
    end

    local stack = getStackLookup()[agent.fate]

    if not stack then
        print("Unknown fate stack id: " .. tostring(agent.fate))
        return {}
    end

    local tile_lookup = getTileLookup()
    local deck = {}

    for _, stack_tile in ipairs(stack.tiles or {}) do
        local card = tile_lookup[stack_tile.slot]

        if card then
            local value_text, value_kind = formatCardValue(card)

            deck[#deck + 1] = {
                id = card.id,
                quantity = stack_tile.quantity or 0,
                value = card.value or 0,
                value_text = value_text,
                value_kind = value_kind,
                neg = card.neg,
                fail = card.fail,
                crit = card.crit,
            }
        else
            print("Unknown fate tile id: " .. tostring(stack_tile.slot))
        end
    end

    return deck
end

return fate_logic

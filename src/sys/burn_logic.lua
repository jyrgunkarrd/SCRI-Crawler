local action_deck_logic = require("src.sys.action_deck_logic")

local burn_logic = {}

local HAND_SIZE = 6
local MAX_BURN_LEVEL = 5

local function slotKey(slot)
    return tostring(slot)
end

local function shuffle(cards)
    for index = #cards, 2, -1 do
        local swap_index = love.math.random(index)

        cards[index], cards[swap_index] = cards[swap_index], cards[index]
    end
end

local function moveDiscardIntoDrawPile(agent)
    agent.action_draw_pile = agent.action_draw_pile or {}
    agent.action_discard_pile = agent.action_discard_pile or {}

    while #agent.action_discard_pile > 0 do
        agent.action_draw_pile[#agent.action_draw_pile + 1] = table.remove(agent.action_discard_pile)
    end

    shuffle(agent.action_draw_pile)
end

local function fatigueEligibleSlots(agent)
    local burn_level = burn_logic.getBurnLevel(agent)

    agent.fatigued_slots = agent.fatigued_slots or {}

    for _, pile in ipairs({
        agent.action_draw_pile or {},
        agent.action_hand or {},
        agent.action_discard_pile or {},
    }) do
        for _, card in ipairs(pile) do
            if card.action_slot and card.burn_rating and card.burn_rating <= burn_level then
                agent.fatigued_slots[slotKey(card.action_slot)] = card.burn_rating
            end
        end
    end
end

local function eliminateAgent(agent, room)
    agent.eliminated = true

    for _, tile in ipairs(room and room.tiles or {}) do
        if tile.agent == agent then
            tile.agent = nil
            return true
        end
    end

    return false
end

local function hasAvailableDrawCard(agent)
    for _, card in ipairs(agent and agent.action_draw_pile or {}) do
        if not action_deck_logic.isCardFatigued(agent, card) then
            return true
        end
    end

    return false
end

function burn_logic.getBurnLevel(agent)
    return math.max(0, math.floor(tonumber(agent and agent.burn_level) or 0))
end

function burn_logic.initializeAgent(agent)
    if not agent then
        return
    end

    agent.burn_level = 0
    agent.fatigued_slots = {}
end

function burn_logic.accumulateBurn(agent, room)
    if not agent then
        return false, "missing_agent"
    end

    local current_burn = burn_logic.getBurnLevel(agent)

    if current_burn >= MAX_BURN_LEVEL then
        eliminateAgent(agent, room)
        return false, "eliminated"
    end

    agent.burn_level = current_burn + 1
    action_deck_logic.discardHand(agent)
    moveDiscardIntoDrawPile(agent)
    fatigueEligibleSlots(agent)

    return true, "burned"
end

function burn_logic.drawCards(agent, room, count)
    if not agent then
        return 0, "missing_agent"
    end

    agent.action_hand = agent.action_hand or {}
    agent.action_draw_pile = agent.action_draw_pile or {}
    agent.action_discard_pile = agent.action_discard_pile or {}
    agent.fatigued_slots = agent.fatigued_slots or {}

    local drawn = 0
    local needed = count or HAND_SIZE

    while drawn < needed do
        if not hasAvailableDrawCard(agent) then
            local ok, reason = burn_logic.accumulateBurn(agent, room)

            if not ok then
                return drawn, reason
            end

            needed = HAND_SIZE
            drawn = 0
        end

        local card = action_deck_logic.drawOneAvailableCard(agent)

        if not card then
            local ok, reason = burn_logic.accumulateBurn(agent, room)

            if not ok then
                return drawn, reason
            end

            needed = HAND_SIZE
            drawn = 0
        else
            drawn = drawn + 1
        end
    end

    return drawn, "drawn"
end

function burn_logic.drawHand(agent, room, hand_size)
    if not agent then
        return 0, "missing_agent"
    end

    agent.action_hand = {}

    return burn_logic.drawCards(agent, room, hand_size or HAND_SIZE)
end

return burn_logic

local action_deck_logic = {}

local BURN_SLOT_COUNTS = {
    { burn = 1, count = 18 },
    { burn = 2, count = 12 },
    { burn = 3, count = 12 },
    { burn = 4, count = 12 },
    { burn = 5, count = 6 },
}

local TOTAL_SLOT_COUNT = 60

local function getSlotKey(slot)
    if slot == nil then
        return nil
    end

    return tostring(slot)
end

local function cloneCardForSlot(card, deck_id, slot, art_id)
    local clone = {}

    for key, value in pairs(card) do
        clone[key] = value
    end

    clone.base_id = card.id
    clone.art_id = art_id
    clone.action_deck_id = deck_id
    clone.action_slot = slot.index
    clone.burn_rating = slot.burn

    return clone
end

function action_deck_logic.buildSlots(card_id)
    local slots = {}
    local index = 1

    for _, band in ipairs(BURN_SLOT_COUNTS) do
        for _ = 1, band.count do
            slots[#slots + 1] = {
                index = index,
                burn = band.burn,
                card = card_id,
            }
            index = index + 1
        end
    end

    return slots
end

function action_deck_logic.buildSplitSlots(card_ids)
    local slots = {}
    local index = 1

    for _, band in ipairs(BURN_SLOT_COUNTS) do
        for _ = 1, band.count do
            local card_index = ((index - 1) % #card_ids) + 1

            slots[#slots + 1] = {
                index = index,
                burn = band.burn,
                card = card_ids[card_index],
            }
            index = index + 1
        end
    end

    return slots
end

function action_deck_logic.buildDrawPile(agent, action_deck_lookup, card_index, action_art_lookup)
    local draw_pile = {}
    action_art_lookup = action_art_lookup or {}

    for _, deck_id in ipairs(agent.actions or {}) do
        local deck = action_deck_lookup[deck_id]

        if not deck then
            print("Unknown action deck id: " .. tostring(deck_id))
        else
            for _, slot in ipairs(deck.slots or {}) do
                local card_id = slot.card or slot.slot
                local card = card_index.byId[card_id]

                if not card then
                    print("Unknown action card id: " .. tostring(card_id))
                else
                    draw_pile[#draw_pile + 1] = cloneCardForSlot(card, deck_id, slot, action_art_lookup[card.id])
                end
            end
        end
    end

    return draw_pile
end

function action_deck_logic.isSlotFatigued(agent, slot)
    local key = getSlotKey(slot)

    return key ~= nil and agent and agent.fatigued_slots and agent.fatigued_slots[key] ~= nil
end

function action_deck_logic.isCardFatigued(agent, card)
    return card and action_deck_logic.isSlotFatigued(agent, card.action_slot)
end

function action_deck_logic.drawOneAvailableCard(agent)
    agent.action_hand = agent.action_hand or {}
    agent.action_draw_pile = agent.action_draw_pile or {}

    local available = {}

    for index, card in ipairs(agent.action_draw_pile) do
        if not action_deck_logic.isCardFatigued(agent, card) then
            available[#available + 1] = index
        end
    end

    if #available == 0 then
        return nil
    end

    local pile_index = available[love.math.random(#available)]
    local card = table.remove(agent.action_draw_pile, pile_index)

    agent.action_hand[#agent.action_hand + 1] = card

    return card
end

function action_deck_logic.drawCards(agent, count)
    agent.action_hand = agent.action_hand or {}
    agent.action_draw_pile = agent.action_draw_pile or {}

    local drawn = 0

    for _ = 1, count do
        if not action_deck_logic.drawOneAvailableCard(agent) then
            return drawn
        end

        drawn = drawn + 1
    end

    return drawn
end

function action_deck_logic.discardHand(agent)
    if not agent or not agent.action_hand then
        return
    end

    agent.action_discard_pile = agent.action_discard_pile or {}

    for index = #agent.action_hand, 1, -1 do
        local card = agent.action_hand[index]

        if not action_deck_logic.isCardFatigued(agent, card) then
            agent.action_discard_pile[#agent.action_discard_pile + 1] = table.remove(agent.action_hand, index)
        end
    end
end

function action_deck_logic.discardFromHand(agent, hand_index)
    if not agent or not agent.action_hand or not hand_index then
        return nil
    end

    local card = agent.action_hand[hand_index]

    if action_deck_logic.isCardFatigued(agent, card) then
        return nil
    end

    card = table.remove(agent.action_hand, hand_index)

    if card then
        agent.action_discard_pile = agent.action_discard_pile or {}
        agent.action_discard_pile[#agent.action_discard_pile + 1] = card
    end

    return card
end

function action_deck_logic.getTotalSlotCount()
    return TOTAL_SLOT_COUNT
end

return action_deck_logic

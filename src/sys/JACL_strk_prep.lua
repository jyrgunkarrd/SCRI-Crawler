local strike_prep = {
    active = false,
    slots = { nil, nil, nil, nil },
    drag_agent = nil,
    drag_origin_slot = nil,
}

local SLOT_COUNT = 4

function strike_prep.isActive()
    return strike_prep.active
end

function strike_prep.enter()
    strike_prep.active = true
    strike_prep.drag_agent = nil
    strike_prep.drag_origin_slot = nil
end

function strike_prep.exit()
    strike_prep.active = false
    strike_prep.drag_agent = nil
    strike_prep.drag_origin_slot = nil

    for index = 1, SLOT_COUNT do
        strike_prep.slots[index] = nil
    end
end

function strike_prep.getSlots()
    return strike_prep.slots
end

function strike_prep.hasSlottedAgents()
    for index = 1, SLOT_COUNT do
        if strike_prep.slots[index] then
            return true
        end
    end

    return false
end

function strike_prep.startDrag(agent)
    if not strike_prep.active or not agent then
        return false
    end

    strike_prep.drag_agent = agent
    strike_prep.drag_origin_slot = nil

    return true
end

function strike_prep.startDragFromSlot(slot_index)
    if not strike_prep.active or not slot_index or slot_index < 1 or slot_index > SLOT_COUNT then
        return false
    end

    local agent = strike_prep.slots[slot_index]

    if not agent then
        return false
    end

    strike_prep.slots[slot_index] = nil
    strike_prep.drag_agent = agent
    strike_prep.drag_origin_slot = slot_index

    return true
end

function strike_prep.getDragAgent()
    return strike_prep.drag_agent
end

function strike_prep.clearDrag()
    strike_prep.drag_agent = nil
    strike_prep.drag_origin_slot = nil
end

function strike_prep.cancelDrag()
    if strike_prep.drag_agent and strike_prep.drag_origin_slot then
        strike_prep.slots[strike_prep.drag_origin_slot] = strike_prep.drag_agent
    end

    strike_prep.clearDrag()
end

function strike_prep.returnDraggedToRoster()
    strike_prep.clearDrag()
end

function strike_prep.containsAgent(agent)
    if not agent then
        return false
    end

    for index = 1, SLOT_COUNT do
        local slotted_agent = strike_prep.slots[index]

        if slotted_agent == agent then
            return true
        end
    end

    return false
end

function strike_prep.placeDraggedAgent(slot_index)
    local agent = strike_prep.drag_agent

    if not strike_prep.active or not agent or not slot_index or slot_index < 1 or slot_index > SLOT_COUNT then
        strike_prep.clearDrag()
        return false
    end

    for index = 1, SLOT_COUNT do
        local slotted_agent = strike_prep.slots[index]

        if slotted_agent == agent then
            strike_prep.slots[index] = nil
        end
    end

    strike_prep.slots[slot_index] = agent
    strike_prep.drag_agent = nil
    strike_prep.drag_origin_slot = nil

    return true
end

function strike_prep.filterRosterAgents(agents)
    if not strike_prep.active then
        return agents or {}
    end

    local filtered = {}

    for _, agent in ipairs(agents or {}) do
        if not strike_prep.containsAgent(agent) and strike_prep.drag_agent ~= agent then
            filtered[#filtered + 1] = agent
        end
    end

    return filtered
end

return strike_prep

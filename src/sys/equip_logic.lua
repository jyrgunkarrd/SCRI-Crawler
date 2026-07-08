local equip_logic = {}

local EQUIP_DIR = "data/equip"
local EQUIP_REQUIRE_PREFIX = "data.equip."
local INVENTORY_COLS = 10
local INVENTORY_ROWS = 4

local definition_lookup = nil
local next_uid = 1

local function getDirectoryItems(path)
    if love and love.filesystem and love.filesystem.getDirectoryItems then
        return love.filesystem.getDirectoryItems(path)
    end

    return {}
end

local function normalizeSlots(definition)
    local source = definition.slots or definition.slot or {}
    local slots = {}

    for _, slot in ipairs(source) do
        slots[#slots + 1] = tostring(slot)
    end

    return slots
end

local function normalizeStatRequirements(definition)
    local requirements = {}

    for _, requirement in ipairs(definition.stat_req or {}) do
        for stat_id, value in pairs(requirement) do
            requirements[#requirements + 1] = {
                stat = tostring(stat_id),
                value = math.floor(tonumber(value) or 0),
            }
        end
    end

    return requirements
end

local function getAgentStatValue(agent, stat_id)
    for _, stat in ipairs(agent and agent.stats or {}) do
        if stat[stat_id] ~= nil then
            return math.floor(tonumber(stat[stat_id]) or 0)
        end
    end

    return 0
end

local function buildFootprint(inv_size)
    if type(inv_size) == "table" then
        local width = math.max(1, math.floor(tonumber(inv_size.W or inv_size.w or inv_size.width) or 1))
        local height = math.max(1, math.floor(tonumber(inv_size.H or inv_size.h or inv_size.height) or 1))

        return width, height
    end

    local size = math.max(1, math.floor(tonumber(inv_size) or 1))
    local width = math.max(1, math.ceil(math.sqrt(size)))
    local height = math.ceil(size / width)

    return width, height
end

local function cloneItem(definition)
    local width, height = buildFootprint(definition.inv_size)
    local item = {
        uid = next_uid,
        id = definition.id,
        name = definition.name or definition.id,
        slots = normalizeSlots(definition),
        stat_req = normalizeStatRequirements(definition),
        inv_size = width * height,
        inv_w = width,
        inv_h = height,
        lock_in = definition.lock_in == true,
        image_path = ("assets/images/equip/%s.webp"):format(definition.id),
    }

    next_uid = next_uid + 1

    return item
end

function equip_logic.getDefinitions()
    if definition_lookup then
        return definition_lookup
    end

    definition_lookup = {}

    for _, filename in ipairs(getDirectoryItems(EQUIP_DIR)) do
        local module_name = filename:match("^(.*)%.lua$")

        if module_name then
            package.loaded[EQUIP_REQUIRE_PREFIX .. module_name] = nil
            local ok, definitions = pcall(require, EQUIP_REQUIRE_PREFIX .. module_name)

            if ok then
                for _, definition in ipairs(definitions or {}) do
                    if definition.id then
                        definition_lookup[definition.id] = definition
                    end
                end
            else
                print("Unable to load equipment definitions '" .. filename .. "': " .. tostring(definitions))
            end
        end
    end

    return definition_lookup
end

function equip_logic.getDefinition(id)
    return equip_logic.getDefinitions()[id]
end

local function ensureRuntime(agent)
    agent.equipment_runtime = agent.equipment_runtime or {
        slots = {},
        inventory = {},
    }

    return agent.equipment_runtime
end

local function removeFromCurrentLocation(agent, item)
    local runtime = ensureRuntime(agent)

    for index, equipped in pairs(runtime.slots) do
        if equipped == item then
            runtime.slots[index] = nil
        end
    end

    for index = #runtime.inventory, 1, -1 do
        if runtime.inventory[index] == item then
            table.remove(runtime.inventory, index)
        end
    end
end

local function isSameItem(a, b)
    return a and b and a.uid == b.uid
end

local function getOccupiedCells(agent, ignored_item)
    local runtime = ensureRuntime(agent)
    local occupied = {}

    for _, item in ipairs(runtime.inventory) do
        if not isSameItem(item, ignored_item) then
            for row = item.inv_row or 1, (item.inv_row or 1) + item.inv_h - 1 do
                for col = item.inv_col or 1, (item.inv_col or 1) + item.inv_w - 1 do
                    occupied[row .. ":" .. col] = true
                end
            end
        end
    end

    return occupied
end

function equip_logic.canPlaceInInventory(agent, item, col, row, ignored_item)
    if not agent or not item then
        return false
    end

    col = math.floor(tonumber(col) or 0)
    row = math.floor(tonumber(row) or 0)

    if col < 1 or row < 1 or col + item.inv_w - 1 > INVENTORY_COLS or row + item.inv_h - 1 > INVENTORY_ROWS then
        return false
    end

    local occupied = getOccupiedCells(agent, ignored_item or item)

    for check_row = row, row + item.inv_h - 1 do
        for check_col = col, col + item.inv_w - 1 do
            if occupied[check_row .. ":" .. check_col] then
                return false
            end
        end
    end

    return true
end

function equip_logic.canPlaceInSlot(agent, item, slot_index)
    if not agent or not item or not slot_index then
        return false
    end

    local slot_name = agent.slots and agent.slots[slot_index]

    if not slot_name then
        return false
    end

    local valid_slot = false

    for _, allowed_slot in ipairs(item.slots or {}) do
        if allowed_slot == slot_name then
            valid_slot = true
            break
        end
    end

    if not valid_slot then
        return false
    end

    for _, requirement in ipairs(item.stat_req or {}) do
        if getAgentStatValue(agent, requirement.stat) < requirement.value then
            return false
        end
    end

    return true
end

function equip_logic.moveToInventory(agent, item, col, row)
    if item and item.location == "slot" and item.locked_in then
        return false
    end

    if not equip_logic.canPlaceInInventory(agent, item, col, row, item) then
        return false
    end

    local runtime = ensureRuntime(agent)

    removeFromCurrentLocation(agent, item)
    item.location = "inventory"
    item.inv_col = math.floor(col)
    item.inv_row = math.floor(row)
    item.slot_index = nil
    runtime.inventory[#runtime.inventory + 1] = item

    return true
end

function equip_logic.moveToSlot(agent, item, slot_index)
    if not equip_logic.canPlaceInSlot(agent, item, slot_index) then
        return false
    end

    local runtime = ensureRuntime(agent)

    if runtime.slots[slot_index] and runtime.slots[slot_index] ~= item then
        return false
    end

    removeFromCurrentLocation(agent, item)
    item.location = "slot"
    item.slot_index = slot_index
    item.inv_col = nil
    item.inv_row = nil
    item.locked_in = item.lock_in == true
    runtime.slots[slot_index] = item

    return true
end

function equip_logic.canDragItem(item)
    return item and not (item.location == "slot" and item.locked_in)
end

local function placeInFirstInventorySpace(agent, item)
    for row = 1, INVENTORY_ROWS do
        for col = 1, INVENTORY_COLS do
            if equip_logic.moveToInventory(agent, item, col, row) then
                return true
            end
        end
    end

    return false
end

function equip_logic.initializeAgent(agent)
    if not agent then
        return
    end

    if agent.equipment_runtime then
        return
    end

    ensureRuntime(agent)

    for _, equip_id in ipairs(agent.start_equip or {}) do
        local definition = equip_logic.getDefinition(equip_id)

        if definition then
            placeInFirstInventorySpace(agent, cloneItem(definition))
        else
            print("Unknown start equipment id: " .. tostring(equip_id))
        end
    end
end

function equip_logic.getInventory(agent)
    equip_logic.initializeAgent(agent)

    return agent and agent.equipment_runtime and agent.equipment_runtime.inventory or {}
end

function equip_logic.getSlots(agent)
    equip_logic.initializeAgent(agent)

    return agent and agent.equipment_runtime and agent.equipment_runtime.slots or {}
end

function equip_logic.getInventorySize()
    return INVENTORY_COLS, INVENTORY_ROWS
end

return equip_logic

local equip_logic = {}

local EQUIP_DIR = "data/equip"
local EQUIP_REQUIRE_PREFIX = "data.equip."
local EQUIP_INDEX_PATH = "data.equip.index"
local CARD_INDEX_PATH = "data.cards.index"
local INVENTORY_COLS = 10
local INVENTORY_ROWS = 4

local definition_lookup = nil
local card_index = nil
local next_uid = 1
local removeFromCurrentLocation

local function getDirectoryItems(path)
    if love and love.filesystem and love.filesystem.getDirectoryItems then
        return love.filesystem.getDirectoryItems(path)
    end

    return {}
end

local function shuffle(items)
    for index = #items, 2, -1 do
        local swap_index = love.math.random(index)

        items[index], items[swap_index] = items[swap_index], items[index]
    end
end

local function getCardIndex()
    if card_index then
        return card_index
    end

    local ok, loaded = pcall(require, CARD_INDEX_PATH)

    if not ok then
        print("Unable to load card index for equipment: " .. tostring(loaded))
        card_index = { byId = {} }
    else
        card_index = loaded
    end

    return card_index
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
        category = definition.category,
        slots = normalizeSlots(definition),
        stat_req = normalizeStatRequirements(definition),
        inv_size = width * height,
        inv_w = width,
        inv_h = height,
        lock_in = definition.lock_in == true,
        lex_deck_ids = definition.lex_deck or {},
        lex_draw_pile = {},
        lex_discard_pile = {},
        image_path = ("assets/images/equip/%s.webp"):format(definition.id),
    }

    next_uid = next_uid + 1

    return item
end

local function cloneLexurgyCard(card, item)
    local clone = {}

    for key, value in pairs(card or {}) do
        clone[key] = value
    end

    clone.base_id = card and card.id or nil
    clone.lexurgy = true
    clone.lex_source = item

    return clone
end

local function hasLexDeck(item)
    return item and item.lex_deck_ids and #item.lex_deck_ids > 0
end

local function buildLexDeck(item)
    if not hasLexDeck(item) then
        return
    end

    local cards = getCardIndex()
    item.lex_draw_pile = {}
    item.lex_discard_pile = item.lex_discard_pile or {}

    for _, card_id in ipairs(item.lex_deck_ids or {}) do
        local card = cards.byId[card_id]

        if card then
            item.lex_draw_pile[#item.lex_draw_pile + 1] = cloneLexurgyCard(card, item)
        else
            print("Unknown lexurgy card id: " .. tostring(card_id))
        end
    end

    shuffle(item.lex_draw_pile)
    item.lex_initialized = true
end

local function reshuffleLexDiscard(item)
    item.lex_draw_pile = item.lex_draw_pile or {}
    item.lex_discard_pile = item.lex_discard_pile or {}

    while #item.lex_discard_pile > 0 do
        item.lex_draw_pile[#item.lex_draw_pile + 1] = table.remove(item.lex_discard_pile)
    end

    shuffle(item.lex_draw_pile)
end

function equip_logic.getDefinitions()
    if definition_lookup then
        return definition_lookup
    end

    local ok, index = pcall(require, EQUIP_INDEX_PATH)

    if ok and type(index) == "table" and type(index.byId) == "table" then
        definition_lookup = index.byId
        return definition_lookup
    end

    print("Unable to load equipment index: " .. tostring(index))
    definition_lookup = {}

    for _, filename in ipairs(getDirectoryItems(EQUIP_DIR)) do
        local module_name = filename:match("^(.*)%.lua$")

        if module_name and module_name ~= "index" then
            package.loaded[EQUIP_REQUIRE_PREFIX .. module_name] = nil
            local loaded_ok, definitions = pcall(require, EQUIP_REQUIRE_PREFIX .. module_name)

            if loaded_ok then
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

function equip_logic.createItem(definition_or_id)
    local definition = type(definition_or_id) == "table" and definition_or_id
        or equip_logic.getDefinition(definition_or_id)

    if not definition then
        return nil
    end

    return cloneItem(definition)
end

function equip_logic.removeFromAgent(agent, item)
    if not agent or not item then
        return false
    end

    removeFromCurrentLocation(agent, item)

    item.location = nil
    item.slot_index = nil
    item.inv_col = nil
    item.inv_row = nil

    return true
end

local function ensureRuntime(agent)
    agent.equipment_runtime = agent.equipment_runtime or {
        slots = {},
        inventory = {},
    }

    return agent.equipment_runtime
end

function removeFromCurrentLocation(agent, item)
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

    if item.lock_in == true then
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

    if hasLexDeck(item) then
        if not item.lex_initialized then
            buildLexDeck(item)
        else
            shuffle(item.lex_draw_pile or {})
        end

        equip_logic.drawLexurgyCard(agent, item)
    end

    return true
end

function equip_logic.canDragItem(item)
    return item ~= nil
end

function equip_logic.hasLexurgyCardInHand(agent)
    for _, card in ipairs(agent and agent.action_hand or {}) do
        if card.lexurgy then
            return true
        end
    end

    return false
end

function equip_logic.hasLexurgyCardFromItemInHand(agent, item)
    if not agent or not item then
        return false
    end

    for _, card in ipairs(agent.action_hand or {}) do
        if card.lexurgy and card.lex_source == item then
            return true
        end
    end

    return false
end

function equip_logic.drawLexurgyCard(agent, item)
    if not agent or not hasLexDeck(item) then
        return nil
    end

    if not item.lex_initialized then
        buildLexDeck(item)
    end

    item.lex_draw_pile = item.lex_draw_pile or {}

    if #item.lex_draw_pile == 0 then
        reshuffleLexDiscard(item)
    end

    local card = table.remove(item.lex_draw_pile)

    if not card then
        return nil
    end

    card.lex_source = item
    agent.action_hand = agent.action_hand or {}
    agent.action_hand[#agent.action_hand + 1] = card

    return card
end

function equip_logic.drawFromEquippedLexDecks(agent)
    if not agent then
        return nil
    end

    local runtime = ensureRuntime(agent)
    local first_drawn = nil

    for slot_index = 1, #(agent.slots or {}) do
        local item = runtime.slots[slot_index]

        if hasLexDeck(item) and not equip_logic.hasLexurgyCardFromItemInHand(agent, item) then
            local card = equip_logic.drawLexurgyCard(agent, item)

            if card and not first_drawn then
                first_drawn = card
            end
        end
    end

    return first_drawn
end

function equip_logic.getEquippedLexurgyItems(agent)
    local items = {}

    if not agent then
        return items
    end

    local runtime = ensureRuntime(agent)

    for slot_index = 1, #(agent.slots or {}) do
        local item = runtime.slots[slot_index]

        if hasLexDeck(item) then
            if not item.lex_initialized then
                buildLexDeck(item)
            end

            items[#items + 1] = item
        end
    end

    return items
end

function equip_logic.getLexDrawCards(item)
    local cards = {}

    if not hasLexDeck(item) then
        return cards
    end

    if not item.lex_initialized then
        buildLexDeck(item)
    end

    for index = #(item.lex_draw_pile or {}), 1, -1 do
        cards[#cards + 1] = item.lex_draw_pile[index]
    end

    return cards
end

function equip_logic.getLexDiscardCards(item)
    local cards = {}

    for _, card in ipairs(item and item.lex_discard_pile or {}) do
        cards[#cards + 1] = card
    end

    return cards
end

function equip_logic.getLexDeckDefinitionCards(item)
    local cards = {}

    if not hasLexDeck(item) then
        return cards
    end

    local index = getCardIndex()

    for _, card_id in ipairs(item.lex_deck_ids or {}) do
        local card = index.byId[card_id]

        if card then
            cards[#cards + 1] = card
        end
    end

    return cards
end

function equip_logic.discardLexurgyCard(card)
    if not card or not card.lexurgy or not card.lex_source then
        return false
    end

    local item = card.lex_source

    item.lex_discard_pile = item.lex_discard_pile or {}
    item.lex_discard_pile[#item.lex_discard_pile + 1] = card

    return true
end

function equip_logic.discardLexurgyCardFromHand(agent, hand_index)
    if not agent or not agent.action_hand or not hand_index then
        return nil
    end

    local card = agent.action_hand[hand_index]

    if not card or not card.lexurgy then
        return nil
    end

    card = table.remove(agent.action_hand, hand_index)
    equip_logic.discardLexurgyCard(card)

    return card
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

local function placeInFirstValidSlot(agent, item)
    for slot_index = 1, #(agent and agent.slots or {}) do
        if equip_logic.moveToSlot(agent, item, slot_index) then
            return true
        end
    end

    return false
end

local function addStartingEquipment(agent, equip_id, prefer_slot)
    local definition = equip_logic.getDefinition(equip_id)

    if not definition then
        print("Unknown start equipment id: " .. tostring(equip_id))
        return
    end

    local item = cloneItem(definition)

    if prefer_slot and placeInFirstValidSlot(agent, item) then
        return
    end

    placeInFirstInventorySpace(agent, item)
end

function equip_logic.initializeAgent(agent)
    if not agent then
        return
    end

    if agent.equipment_runtime then
        return
    end

    ensureRuntime(agent)

    for _, equip_id in ipairs(agent.start_equip_slot or {}) do
        addStartingEquipment(agent, equip_id, true)
    end

    for _, equip_id in ipairs(agent.start_equip or {}) do
        addStartingEquipment(agent, equip_id, false)
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

local image_loader = require("src.assets.image_loader")
local equip_index = require("data.equip.index")
local equip_logic = require("src.sys.equip_logic")
local luggage = require("src.sys.luggage")
local agent_uix = require("src.rndr.agent_uix")
local sfx_logic = require("src.sys.sfx_logic")
local utf8 = require("utf8")

local cache_rail = {}

local X = 22
local H = 168
local PADDING_X = 18
local TITLE_W = 150
local PROMPT_H = 30
local PROMPT_BOTTOM_PAD = 16
local SEARCH_ICON = "\239\128\130"
local SEARCH_ICON_SIZE = 18
local SEARCH_ICON_GAP = 8
local PROMPT_PAD_X = 8
local ITEM_W = 116
local GAP = 16
local SCROLL_STEP = 46
local COLOR = { 0, 0, 0, 0.88 }
local OUTLINE_COLOR = { 1, 1, 1, 0.92 }
local DIVIDER_COLOR = { 1, 1, 1, 0.28 }
local TITLE_COLOR = { 1, 1, 1, 1 }
local NAME_COLOR = { 1, 1, 1, 0.9 }
local PROMPT_COLOR = { 0.035, 0.033, 0.03, 1 }
local PROMPT_FOCUSED_COLOR = { 0.07, 0.065, 0.056, 1 }
local PROMPT_OUTLINE_COLOR = { 1, 1, 1, 0.62 }
local PROMPT_TEXT_COLOR = { 1, 1, 1, 0.9 }
local PROMPT_CURSOR_COLOR = { 1, 1, 1, 0.82 }
local EMPTY_COLOR = { 1, 1, 1, 0.52 }
local Y_MARGIN = 14
local MODES = {
    { key = "rumors", label = "Rumors", letter = "R" },
    { key = "luggage", label = "Luggage", letter = "L" },
    { key = "consumables", label = "Consumables", letter = "C" },
    { key = "equipment", label = "Equipment", letter = "E" },
}
local MODE_LOOKUP = {}
local BUTTON_SIZE = 28
local BUTTON_GAP = 6
local BUTTON_CLUSTER_TOP = 50
local ITEM_IMAGE_SIZE = 82
local DRAG_IMAGE_SIZE = 78
local NAME_GAP = 8
local NAME_FONT_MAX = 15
local NAME_FONT_MIN = 8

for _, mode in ipairs(MODES) do
    MODE_LOOKUP[mode.key] = mode
end

local equip_images = {}
local missing_equip_images = {}

local function pointInRect(x, y, rect)
    return x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

local function normalizeSearchText(text)
    text = tostring(text or ""):lower()

    return text:match("^%s*(.-)%s*$")
end

local function isDraggableMode(mode_key)
    return mode_key == "rumors" or mode_key == "luggage" or mode_key == "consumables" or mode_key == "equipment"
end

local function isInventoryMode(mode_key)
    return mode_key == "rumors" or mode_key == "luggage" or mode_key == "consumables"
end

local function getSingularModeKey(mode_key)
    return tostring(mode_key or ""):gsub("s$", "")
end

local function itemMatchesMode(item, mode_key)
    local category = tostring(item and item.category or ""):lower()
    local mode = tostring(mode_key or ""):lower()

    return category == mode or category == getSingularModeKey(mode)
end

local function countAgentEquipmentById(agent)
    local counts = {}

    for _, item in ipairs(equip_logic.getInventory(agent)) do
        if item.id then
            counts[item.id] = (counts[item.id] or 0) + 1
        end
    end

    for _, item in pairs(equip_logic.getSlots(agent)) do
        if item.id then
            counts[item.id] = (counts[item.id] or 0) + 1
        end
    end

    return counts
end

local function buildAvailableIds(agent)
    local available = {}
    local placed_counts = countAgentEquipmentById(agent)

    for _, mode in ipairs(MODES) do
        available[mode.key] = {}

        for _, equip_id in ipairs(agent and agent.start_equip_cache and agent.start_equip_cache[mode.key] or {}) do
            if (placed_counts[equip_id] or 0) > 0 then
                placed_counts[equip_id] = placed_counts[equip_id] - 1
            else
                available[mode.key][#available[mode.key] + 1] = equip_id
            end
        end
    end

    return available
end

local function getAgentAvailableIds(agent)
    if not agent then
        return {}
    end

    if not agent.equipment_cache_runtime then
        agent.equipment_cache_runtime = buildAvailableIds(agent)
    end

    return agent.equipment_cache_runtime
end

local function removeId(state, mode_key, equip_id)
    local ids = state.cache_available_ids and state.cache_available_ids[mode_key] or {}

    for index, id in ipairs(ids) do
        if id == equip_id then
            table.remove(ids, index)
            return true
        end
    end

    return false
end

local function addId(state, mode_key, equip_id)
    if not state.cache_available_ids then
        state.cache_available_ids = {}
    end

    state.cache_available_ids[mode_key] = state.cache_available_ids[mode_key] or {}
    state.cache_available_ids[mode_key][#state.cache_available_ids[mode_key] + 1] = equip_id
end

local function getEquipImage(definition)
    if not definition or not definition.id then
        return nil
    end

    if equip_images[definition.id] then
        return equip_images[definition.id]
    end

    if missing_equip_images[definition.id] then
        return nil
    end

    local path = ("assets/images/equip/%s.webp"):format(definition.id)
    local ok, image = pcall(image_loader.newImage, path)

    if not ok then
        missing_equip_images[definition.id] = true
        return nil
    end

    equip_images[definition.id] = image

    return image
end

local function getLayout()
    local screen_w = love.graphics.getWidth()
    local y = love.graphics.getHeight() - Y_MARGIN - H
    local label_x = X + PADDING_X
    local prompt_y = y + H - PROMPT_BOTTOM_PAD - PROMPT_H
    local icon_w = SEARCH_ICON_SIZE
    local prompt_x = label_x + icon_w + SEARCH_ICON_GAP
    local prompt_w = TITLE_W - icon_w - SEARCH_ICON_GAP

    return {
        x = X,
        y = y,
        w = math.max(0, screen_w - X * 2),
        h = H,
        content_x = X + PADDING_X + TITLE_W + PADDING_X,
        content_y = y + 10,
        content_w = math.max(0, screen_w - X * 2 - PADDING_X * 3 - TITLE_W),
        content_h = H - 20,
        label_x = label_x,
        label_y = y + 18,
        label_w = TITLE_W,
        prompt_x = prompt_x,
        prompt_y = prompt_y,
        prompt_w = prompt_w,
        prompt_h = PROMPT_H,
        icon_x = label_x,
        icon_y = prompt_y + (PROMPT_H - SEARCH_ICON_SIZE) / 2,
        button_x = label_x + (TITLE_W - (BUTTON_SIZE * 2 + BUTTON_GAP)) / 2,
        button_y = y + BUTTON_CLUSTER_TOP,
    }
end

local function getModeLabel(mode_key)
    return (MODE_LOOKUP[mode_key] and MODE_LOOKUP[mode_key].label) or "Rumors"
end

local function getModeButtonRects(layout)
    local rects = {}

    for index, mode in ipairs(MODES) do
        local col = (index - 1) % 2
        local row = math.floor((index - 1) / 2)

        rects[#rects + 1] = {
            mode = mode,
            x = layout.button_x + col * (BUTTON_SIZE + BUTTON_GAP),
            y = layout.button_y + row * (BUTTON_SIZE + BUTTON_GAP),
            w = BUTTON_SIZE,
            h = BUTTON_SIZE,
        }
    end

    return rects
end

local function getDefinitions(state)
    local agent = state.cache_agent
    local mode_key = state.cache_mode or "rumors"
    local ids = state.cache_available_ids and state.cache_available_ids[mode_key]
        or agent and agent.start_equip_cache and agent.start_equip_cache[mode_key]
        or {}
    local category = equip_index.categorized and equip_index.categorized[mode_key] or nil
    local definitions = {}

    for _, equip_id in ipairs(ids) do
        local definition = category and category[equip_id] or equip_index.byId[equip_id]

        if definition then
            definitions[#definitions + 1] = definition
        end
    end

    return definitions
end

local function getFilteredDefinitions(state)
    local query = normalizeSearchText(state.cache_search_text)
    local definitions = getDefinitions(state)

    if query == "" then
        return definitions
    end

    local filtered = {}

    for _, definition in ipairs(definitions) do
        local name = tostring(definition.name or ""):lower()
        local id = tostring(definition.id or ""):lower()

        if name:find(query, 1, true) or id:find(query, 1, true) then
            filtered[#filtered + 1] = definition
        end
    end

    return filtered
end

local function getContentWidth(item_count)
    if item_count <= 0 then
        return 0
    end

    return item_count * ITEM_W + math.max(item_count - 1, 0) * GAP
end

local function clampScroll(scroll_x, layout, item_count)
    local max_scroll = math.max(0, getContentWidth(item_count) - layout.content_w)

    return math.max(0, math.min(scroll_x or 0, max_scroll))
end

local function getDefinitionAtPoint(state, x, y)
    local layout = getLayout()
    local definitions = getFilteredDefinitions(state)

    if not pointInRect(x, y, {
        x = layout.content_x,
        y = layout.content_y,
        w = layout.content_w,
        h = layout.content_h,
    }) then
        return nil
    end

    local local_x = x - layout.content_x + (state.cache_scroll_x or 0)
    local stride = ITEM_W + GAP
    local index = math.floor(local_x / stride) + 1
    local item_left = (index - 1) * stride

    if index < 1 or index > #definitions then
        return nil
    end

    if local_x < item_left or local_x > item_left + ITEM_W then
        return nil
    end

    return definitions[index]
end

local function getNameFont(state, label, max_w, max_h)
    label = label or ""
    state.cache_name_fonts = state.cache_name_fonts or {}

    for font_size = NAME_FONT_MAX, NAME_FONT_MIN, -1 do
        local font = state.cache_name_fonts[font_size]

        if not font then
            font = love.graphics.newFont("assets/fonts/Furore.otf", font_size)
            state.cache_name_fonts[font_size] = font
        end

        local _, wrapped_lines = font:getWrap(label, max_w)
        local line_count = math.max(#wrapped_lines, 1)

        if font:getHeight() * line_count <= max_h then
            return font, line_count
        end
    end

    local font = state.cache_name_fonts[NAME_FONT_MIN]

    if not font then
        font = love.graphics.newFont("assets/fonts/Furore.otf", NAME_FONT_MIN)
        state.cache_name_fonts[NAME_FONT_MIN] = font
    end

    local _, wrapped_lines = font:getWrap(label, max_w)

    return font, math.max(#wrapped_lines, 1)
end

local function drawSearchPrompt(state, layout)
    local prompt_color = state.cache_search_focused and PROMPT_FOCUSED_COLOR or PROMPT_COLOR
    local text = state.cache_search_text or ""

    love.graphics.setFont(state.roster_icon_font)
    love.graphics.setColor(TITLE_COLOR)
    love.graphics.print(SEARCH_ICON, layout.icon_x, layout.icon_y)

    love.graphics.setColor(prompt_color)
    love.graphics.rectangle("fill", layout.prompt_x, layout.prompt_y, layout.prompt_w, layout.prompt_h)
    love.graphics.setColor(PROMPT_OUTLINE_COLOR)
    love.graphics.rectangle("line", layout.prompt_x, layout.prompt_y, layout.prompt_w, layout.prompt_h)

    love.graphics.setFont(state.roster_prompt_font)
    love.graphics.setColor(PROMPT_TEXT_COLOR)

    local text_x = layout.prompt_x + PROMPT_PAD_X
    local text_y = layout.prompt_y + (layout.prompt_h - state.roster_prompt_font:getHeight()) / 2
    local max_text_w = layout.prompt_w - PROMPT_PAD_X * 2
    local visible_text = text

    while visible_text ~= "" and state.roster_prompt_font:getWidth(visible_text) > max_text_w do
        local offset = utf8.offset(visible_text, 2)

        if not offset then
            visible_text = ""
        else
            visible_text = visible_text:sub(offset)
        end
    end

    love.graphics.print(visible_text, text_x, text_y)

    if state.cache_search_focused and math.floor(love.timer.getTime() * 2) % 2 == 0 then
        local cursor_x = text_x + state.roster_prompt_font:getWidth(visible_text)

        love.graphics.setColor(PROMPT_CURSOR_COLOR)
        love.graphics.line(cursor_x + 2, layout.prompt_y + 6, cursor_x + 2, layout.prompt_y + layout.prompt_h - 6)
    end
end

local function drawModeButtons(state, layout)
    love.graphics.setFont(state.roster_font)

    for _, rect in ipairs(getModeButtonRects(layout)) do
        local selected = rect.mode.key == state.cache_mode

        love.graphics.setColor(selected and OUTLINE_COLOR or PROMPT_COLOR)
        love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
        love.graphics.setColor(PROMPT_OUTLINE_COLOR)
        love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h)
        love.graphics.setColor(selected and { 0, 0, 0, 1 } or TITLE_COLOR)
        love.graphics.printf(
            rect.mode.letter,
            rect.x,
            rect.y + (rect.h - state.roster_font:getHeight()) / 2,
            rect.w,
            "center"
        )
    end
end

local function drawDefinition(definition, item_x, layout, state)
    local image = not luggage.isLuggage(definition) and getEquipImage(definition) or nil
    local image_x = item_x + (ITEM_W - ITEM_IMAGE_SIZE) / 2
    local image_y = layout.content_y + 8

    love.graphics.setColor(0.015, 0.014, 0.012, 1)
    love.graphics.rectangle("fill", image_x, image_y, ITEM_IMAGE_SIZE, ITEM_IMAGE_SIZE)

    if luggage.draw(definition, image_x, image_y, ITEM_IMAGE_SIZE, ITEM_IMAGE_SIZE, {
        font = state.roster_font,
    }) then
        -- Luggage uses a generated inventory-footprint grid instead of image art.
    elseif image then
        local scale = math.min(ITEM_IMAGE_SIZE / image:getWidth(), ITEM_IMAGE_SIZE / image:getHeight())

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(
            image,
            image_x + ITEM_IMAGE_SIZE / 2,
            image_y + ITEM_IMAGE_SIZE / 2,
            0,
            scale,
            scale,
            image:getWidth() / 2,
            image:getHeight() / 2
        )
    else
        love.graphics.setFont(state.roster_font)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf(definition.id or "", image_x + 2, image_y + ITEM_IMAGE_SIZE / 2 - 8, ITEM_IMAGE_SIZE - 4, "center")
    end

    love.graphics.setColor(OUTLINE_COLOR)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", image_x, image_y, ITEM_IMAGE_SIZE, ITEM_IMAGE_SIZE)
    love.graphics.setLineWidth(1)

    local name = definition.name or definition.id
    local label_y = image_y + ITEM_IMAGE_SIZE + NAME_GAP
    local label_h = layout.content_y + layout.content_h - label_y
    local name_font = getNameFont(state, name, ITEM_W, label_h)

    love.graphics.setFont(name_font)
    love.graphics.setColor(NAME_COLOR)
    love.graphics.printf(name, item_x, label_y, ITEM_W, "center")
end

local function drawDropGhost(item, item_x, layout, state)
    if not item then
        return
    end

    local image = not luggage.isLuggage(item) and getEquipImage(item) or nil
    local image_x = item_x + (ITEM_W - ITEM_IMAGE_SIZE) / 2
    local image_y = layout.content_y + 8

    love.graphics.setColor(0.4078, 0.6824, 0.5804, 0.18)
    love.graphics.rectangle("fill", image_x, image_y, ITEM_IMAGE_SIZE, ITEM_IMAGE_SIZE)

    if luggage.draw(item, image_x, image_y, ITEM_IMAGE_SIZE, ITEM_IMAGE_SIZE, {
        alpha = 0.36,
        font = state.roster_font,
    }) then
        -- Luggage uses a generated inventory-footprint grid instead of image art.
    elseif image then
        local scale = math.min(ITEM_IMAGE_SIZE / image:getWidth(), ITEM_IMAGE_SIZE / image:getHeight())

        love.graphics.setColor(1, 1, 1, 0.36)
        love.graphics.draw(
            image,
            image_x + ITEM_IMAGE_SIZE / 2,
            image_y + ITEM_IMAGE_SIZE / 2,
            0,
            scale,
            scale,
            image:getWidth() / 2,
            image:getHeight() / 2
        )
    else
        love.graphics.setFont(state.roster_font)
        love.graphics.setColor(1, 1, 1, 0.36)
        love.graphics.printf(item.id or "", image_x + 2, image_y + ITEM_IMAGE_SIZE / 2 - 8, ITEM_IMAGE_SIZE - 4, "center")
    end

    love.graphics.setColor(0.4078, 0.6824, 0.5804, 0.92)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", image_x, image_y, ITEM_IMAGE_SIZE, ITEM_IMAGE_SIZE)
    love.graphics.setLineWidth(1)

    love.graphics.setFont(state.roster_font)
    love.graphics.setColor(NAME_COLOR[1], NAME_COLOR[2], NAME_COLOR[3], 0.52)
    love.graphics.printf(item.name or item.id or "", item_x, image_y + ITEM_IMAGE_SIZE + NAME_GAP, ITEM_W, "center")
end

function cache_rail.reset(state)
    state.cache_agent = nil
    state.cache_mode = "rumors"
    state.cache_scroll_x = 0
    state.cache_search_text = ""
    state.cache_search_focused = false
    state.cache_drag = nil
    state.cache_available_ids = {}
    state.cache_name_fonts = {}
end

function cache_rail.clearTransient(state)
    state.cache_agent = nil
    state.cache_search_focused = false
    state.cache_drag = nil
end

function cache_rail.openForAgent(state, agent)
    state.cache_agent = agent
    state.cache_mode = state.cache_mode or "rumors"
    state.cache_scroll_x = 0
    state.cache_search_text = ""
    state.cache_search_focused = false
    state.cache_drag = nil
    state.cache_available_ids = getAgentAvailableIds(agent)
end

function cache_rail.keypressed(state, key)
    if not state.cache_search_focused then
        return false
    end

    if key == "backspace" then
        local byte_offset = utf8.offset(state.cache_search_text, -1)

        if byte_offset then
            state.cache_search_text = state.cache_search_text:sub(1, byte_offset - 1)
            state.cache_scroll_x = 0
        end

        return true
    elseif key == "return" or key == "kpenter" then
        state.cache_search_focused = false
        return true
    end

    return false
end

function cache_rail.textinput(state, text)
    if not state.cache_search_focused then
        return false
    end

    state.cache_search_text = (state.cache_search_text or "") .. text
    state.cache_scroll_x = 0

    return true
end

function cache_rail.mousepressed(state, x, y, button)
    if not agent_uix.isModalOpen() or agent_uix.isDeckViewerOpen() or button ~= 1 then
        return false
    end

    local layout = getLayout()

    if not pointInRect(x, y, layout) then
        return false
    end

    for _, rect in ipairs(getModeButtonRects(layout)) do
        if pointInRect(x, y, rect) then
            state.cache_mode = rect.mode.key
            state.cache_scroll_x = 0
            state.cache_search_focused = false
            return true
        end
    end

    if pointInRect(x, y, {
        x = layout.prompt_x,
        y = layout.prompt_y,
        w = layout.prompt_w,
        h = layout.prompt_h,
    }) then
        state.cache_search_focused = true
        state.roster_search_focused = false
        return true
    end

    local definition = getDefinitionAtPoint(state, x, y)

    if definition then
        state.cache_search_focused = false

        if isDraggableMode(state.cache_mode) then
            state.cache_drag = {
                definition = definition,
                item = equip_logic.createItem(definition),
                start_x = x,
                start_y = y,
            }
        end

        return true
    end

    state.cache_search_focused = false
    return true
end

function cache_rail.mousereleased(state, x, y, button)
    if button == 1 and state.cache_drag then
        local drag = state.cache_drag
        state.cache_drag = nil

        if agent_uix.isModalOpen() and isDraggableMode(state.cache_mode) then
            local item = drag.item
            local placed = false

            if item and state.cache_mode == "equipment" then
                placed = agent_uix.placeItemInOpenModalSlot(item, x, y)
            elseif item and isInventoryMode(state.cache_mode) then
                placed = agent_uix.placeItemInOpenModalInventory(item, x, y)
            end

            if placed then
                removeId(state, state.cache_mode, drag.definition.id)
                sfx_logic.playNamed("equip")
                return true
            end
        end

        return true
    end

    if button == 1 and agent_uix.isModalOpen() and not agent_uix.isDeckViewerOpen() then
        local layout = getLayout()

        if pointInRect(x, y, layout) then
            local item = agent_uix.takeDraggedItemForRail(function(candidate)
                return itemMatchesMode(candidate, state.cache_mode)
            end)

            if item then
                addId(state, state.cache_mode, item.id)
                state.cache_scroll_x = 0
                sfx_logic.playNamed("equip")
                return true
            end
        end
    end

    return false
end

function cache_rail.wheelmoved(state, x, y)
    if not agent_uix.isModalOpen() or agent_uix.isDeckViewerOpen() then
        return false
    end

    local layout = getLayout()
    local mouse_x, mouse_y = love.mouse.getPosition()

    if not pointInRect(mouse_x, mouse_y, layout) then
        return false
    end

    local wheel_delta = y ~= 0 and y or -x

    state.cache_scroll_x = clampScroll(
        state.cache_scroll_x - wheel_delta * SCROLL_STEP,
        layout,
        #getFilteredDefinitions(state)
    )

    return true
end

function cache_rail.draw(state)
    if not agent_uix.isModalOpen() or not state.cache_agent then
        return
    end

    local layout = getLayout()
    local definitions = getFilteredDefinitions(state)

    state.cache_scroll_x = clampScroll(state.cache_scroll_x, layout, #definitions)

    love.graphics.setColor(COLOR)
    love.graphics.rectangle("fill", layout.x, layout.y, layout.w, layout.h)
    love.graphics.setColor(OUTLINE_COLOR)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", layout.x, layout.y, layout.w, layout.h)
    love.graphics.setLineWidth(1)

    love.graphics.setFont(state.roster_font)
    love.graphics.setColor(TITLE_COLOR)
    love.graphics.printf(getModeLabel(state.cache_mode), layout.label_x, layout.label_y, layout.label_w, "center")
    drawModeButtons(state, layout)
    drawSearchPrompt(state, layout)

    love.graphics.setColor(DIVIDER_COLOR)
    love.graphics.line(
        layout.content_x - PADDING_X / 2,
        layout.y + 14,
        layout.content_x - PADDING_X / 2,
        layout.y + layout.h - 14
    )

    love.graphics.setScissor(layout.content_x, layout.content_y, layout.content_w, layout.content_h)

    if #definitions == 0 then
        love.graphics.setFont(state.roster_font)
        love.graphics.setColor(EMPTY_COLOR)
        love.graphics.printf("No items found.", layout.content_x, layout.y + 68, layout.content_w, "center")
    end

    for index, definition in ipairs(definitions) do
        local item_x = layout.content_x - state.cache_scroll_x + (index - 1) * (ITEM_W + GAP)

        drawDefinition(definition, item_x, layout, state)
    end

    local dragged_item = not state.cache_drag and agent_uix.getDraggedEquipmentItem() or nil

    if dragged_item and itemMatchesMode(dragged_item, state.cache_mode) then
        local item_x = layout.content_x - state.cache_scroll_x + #definitions * (ITEM_W + GAP)

        drawDropGhost(dragged_item, item_x, layout, state)
    end

    love.graphics.setScissor()
end

function cache_rail.drawModalPlacementPreview(state)
    if state.cache_drag and state.cache_drag.item then
        if state.cache_mode == "equipment" then
            agent_uix.drawOpenModalSlotHighlights(state.cache_drag.item)
        else
            agent_uix.drawOpenModalInventoryGhost(state.cache_drag.item)
        end
    end
end

function cache_rail.drawDrag(state)
    local drag = state.cache_drag

    if not drag or not drag.definition then
        return
    end

    local mouse_x, mouse_y = love.mouse.getPosition()
    local image = not luggage.isLuggage(drag.definition) and getEquipImage(drag.definition) or nil
    local size = DRAG_IMAGE_SIZE
    local x = mouse_x - size / 2
    local y = mouse_y - size / 2

    love.graphics.setColor(0.015, 0.014, 0.012, 0.86)
    love.graphics.rectangle("fill", x, y, size, size)

    if luggage.draw(drag.definition, x, y, size, size, {
        alpha = 0.9,
        font = state.roster_font,
    }) then
        -- Luggage uses a generated inventory-footprint grid instead of image art.
    elseif image then
        local scale = math.min(size / image:getWidth(), size / image:getHeight())

        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.draw(
            image,
            mouse_x,
            mouse_y,
            0,
            scale,
            scale,
            image:getWidth() / 2,
            image:getHeight() / 2
        )
    else
        love.graphics.setFont(state.roster_font)
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.printf(drag.definition.id or "", x + 2, y + size / 2 - 8, size - 4, "center")
    end

    love.graphics.setColor(OUTLINE_COLOR)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, size, size)
    love.graphics.setLineWidth(1)
end

return cache_rail

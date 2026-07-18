local image_loader = require("src.assets.image_loader")
local officer_definitions = require("data.officers")
local sfx_logic = require("src.sys.sfx_logic")

local officers = {
    drag_agent = nil,
    drag_origin = nil,
    shout = nil,
}

local IMAGE_DIR = "assets/images/officers/"
local IMAGE_EXTENSIONS = { ".webp", ".png", ".jpg", ".jpeg" }
local UPGRADE_SLOT_ICON_PATH = "assets/images/icons/upgrade_slot.webp"
local UPGRADE_SLOT_ICON_PADDING = 8
local ORDERS_ICON_PATH = "assets/images/icons/orders.webp"
local ORDERS_HOVER_ICON_PATH = "assets/images/icons/orders_hover.webp"
local ORDERS_ICON_PADDING = 6
local LOCK_ICON_PATH = "assets/images/icons/lock.webp"
local LOCK_ICON_PADDING = 5
local AGENT_LOCK_BADGE_RADIUS_SCALE = 0.32
local AGENT_LOCK_BADGE_Y_SCALE = 0.72
local AGENT_LOCK_ICON_SCALE = 0.64
local POPULATION_EMPTY_ICON_PATH = "assets/images/icons/pop_empty.webp"
local POPULATION_FULL_ICON_PATH = "assets/images/icons/pop_full.webp"
local POPULATION_SLOT_COUNT = 10
local SHOUT_CHARS_PER_SECOND = 58
local SHOUT_MIN_TYPE_SECONDS = 0.08
local SHOUT_HOLD_SECONDS = 0.75
local SHOUT_BOX_H = 34
local SHOUT_BOX_PAD_X = 10
local SHOUT_PORTRAIT_GAP = 6
local SHOUT_BOX_COLOR = { 1, 1, 1, 0.96 }
local SHOUT_TEXT_COLOR = { 0, 0, 0, 1 }
local PANEL_EDGE_GAP = 10
local PANEL_PAD = 8
local SMALL_CELL_GAP = 5
local SLOT_SECTION_GAP = 12
local PANEL_COLOR = { 0, 0, 0, 0.88 }
local CELL_COLOR = { 0.035, 0.033, 0.03, 1 }
local OUTLINE_COLOR = { 1, 1, 1, 0.92 }
local DROP_COLOR = { 0.4078, 0.6824, 0.5804, 0.22 }
local upgrade_slot_icon = nil
local orders_icon = nil
local orders_hover_icon = nil
local population_empty_icon = nil
local population_full_icon = nil
local lock_icon = nil
local greyscale_shader = nil
local hovered_orders_officer = nil

local function getUpgradeSlotIcon()
    if not upgrade_slot_icon then
        upgrade_slot_icon = image_loader.newImage(UPGRADE_SLOT_ICON_PATH)
    end

    return upgrade_slot_icon
end

local function getOrdersIcon()
    if not orders_icon then
        orders_icon = image_loader.newImage(ORDERS_ICON_PATH)
    end

    return orders_icon
end

local function getOrdersHoverIcon()
    if not orders_hover_icon then
        orders_hover_icon = image_loader.newImage(ORDERS_HOVER_ICON_PATH)
    end

    return orders_hover_icon
end

local function getLockIcon()
    if not lock_icon then
        lock_icon = image_loader.newImage(LOCK_ICON_PATH)
    end

    return lock_icon
end

function officers.getGreyscaleShader()
    if not greyscale_shader then
        greyscale_shader = love.graphics.newShader([[
            vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
            {
                vec4 pixel = Texel(texture, texture_coords) * color;
                float grey = dot(pixel.rgb, vec3(0.299, 0.587, 0.114));
                return vec4(vec3(grey), pixel.a);
            }
        ]])
    end

    return greyscale_shader
end

local function getPopulationEmptyIcon()
    if not population_empty_icon then
        population_empty_icon = image_loader.newImage(POPULATION_EMPTY_ICON_PATH)
    end

    return population_empty_icon
end

local function getPopulationFullIcon()
    if not population_full_icon then
        population_full_icon = image_loader.newImage(POPULATION_FULL_ICON_PATH)
    end

    return population_full_icon
end

local function pointInRect(x, y, rect)
    return rect
        and x >= rect.x
        and x <= rect.x + rect.w
        and y >= rect.y
        and y <= rect.y + rect.h
end

local function findImagePath(id)
    local base_path = IMAGE_DIR .. tostring(id)

    for _, extension in ipairs(IMAGE_EXTENSIONS) do
        local path = base_path .. extension

        if love.filesystem.getInfo(path, "file") then
            return path
        end
    end

    return nil
end

local function buildDefinitionMap()
    local definitions_by_id = {}

    for _, definition in ipairs(officer_definitions) do
        if definition.id then
            definitions_by_id[definition.id] = definition
        end
    end

    return definitions_by_id
end

function officers.loadByIds(ids)
    local definitions_by_id = buildDefinitionMap()
    local loaded = {}

    for _, id in ipairs(ids) do
        local definition = definitions_by_id[id]

        if not definition then
            print("No officer definition found for id: " .. tostring(id))
        else
            local image_path = findImagePath(id)
            local image = nil

            if image_path then
                image = image_loader.newImage(image_path)
            else
                print("No officer image found for id: " .. tostring(id))
            end

            loaded[#loaded + 1] = {
                id = id,
                name = definition.name or id,
                office = definition.office or "",
                shout = definition.shout or "",
                image = image,
                image_path = image_path,
                panel_open = false,
                assigned_agent = nil,
                agent_locked = false,
                orders_locked = false,
                population = 0,
                population_initialized = false,
                orders = definition.orders or {},
            }
        end
    end

    return loaded
end

local function eachOfficer(officer_lists, callback)
    for _, officer_list in ipairs(officer_lists or {}) do
        for _, officer in ipairs(officer_list or {}) do
            local result = callback(officer)

            if result ~= nil then
                return result
            end
        end
    end

    return nil
end

function officers.initializePopulation(officer_lists, total_population)
    local officer_pool = {}
    local already_initialized = true

    eachOfficer(officer_lists, function(officer)
        officer_pool[#officer_pool + 1] = officer
        already_initialized = already_initialized and officer.population_initialized == true
    end)

    if #officer_pool == 0 or already_initialized then
        return false
    end

    for _, officer in ipairs(officer_pool) do
        officer.population = 0
        officer.population_initialized = true
    end

    local remaining = math.min(
        math.max(0, math.floor(tonumber(total_population) or 0)),
        #officer_pool * POPULATION_SLOT_COUNT
    )

    while remaining > 0 do
        local available = {}

        for _, officer in ipairs(officer_pool) do
            if officer.population < POPULATION_SLOT_COUNT then
                available[#available + 1] = officer
            end
        end

        if #available == 0 then
            break
        end

        local officer = available[love.math.random(#available)]

        officer.population = officer.population + 1
        remaining = remaining - 1
    end

    return true
end

function officers.triggerShout(officer)
    if not officer then
        return false
    end

    local shout_text = tostring(officer.shout or "")
    local type_seconds = math.max(#shout_text / SHOUT_CHARS_PER_SECOND, SHOUT_MIN_TYPE_SECONDS)

    officers.shout = shout_text ~= "" and {
        officer = officer,
        text = shout_text,
        elapsed = 0,
        type_seconds = type_seconds,
        duration = type_seconds + SHOUT_HOLD_SECONDS,
    } or nil
    sfx_logic.playOfficerVoice(officer)

    return true
end

function officers.update(dt)
    if not officers.shout then
        return
    end

    officers.shout.elapsed = officers.shout.elapsed + math.max(0, tonumber(dt) or 0)

    if officers.shout.elapsed >= officers.shout.duration then
        officers.shout = nil
    end
end

local function drawShout(font)
    local shout = officers.shout
    local portrait = shout and shout.officer and shout.officer.portrait_rect

    if not shout or not portrait or shout.text == "" then
        return
    end

    local typed_ratio = math.min(shout.elapsed / shout.type_seconds, 1)
    local visible_count = math.max(1, math.floor(#shout.text * typed_ratio))
    local visible_text = shout.text:sub(1, visible_count)
    local text_w = font:getWidth(visible_text)
    local box_w = text_w + SHOUT_BOX_PAD_X * 2
    local box_x = portrait.x + (portrait.w - box_w) / 2
    local box_y = portrait.y + portrait.h + SHOUT_PORTRAIT_GAP

    love.graphics.setFont(font)
    love.graphics.setColor(SHOUT_BOX_COLOR)
    love.graphics.rectangle("fill", box_x, box_y, box_w, SHOUT_BOX_H)
    love.graphics.setColor(SHOUT_TEXT_COLOR)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", box_x, box_y, box_w, SHOUT_BOX_H)
    love.graphics.setLineWidth(1)
    love.graphics.print(
        visible_text,
        box_x + SHOUT_BOX_PAD_X,
        box_y + (SHOUT_BOX_H - font:getHeight()) / 2
    )
end


local function getPanelLayout(officer, backing_rect)
    local portrait = officer and officer.portrait_rect

    if not portrait or not backing_rect then
        return nil
    end

    local portrait_center_x = portrait.x + portrait.w / 2
    local backing_center_x = backing_rect.x + backing_rect.w / 2
    local is_left = portrait_center_x < backing_center_x
    local panel_x = is_left and portrait.x + portrait.w + PANEL_EDGE_GAP
        or backing_rect.x + backing_rect.w + PANEL_EDGE_GAP
    local panel_right = is_left and backing_rect.x - PANEL_EDGE_GAP or portrait.x - PANEL_EDGE_GAP
    local panel_w = math.max(0, panel_right - panel_x)
    local panel_h = portrait.h
    local inner_w = math.max(0, panel_w - PANEL_PAD * 2)
    local large_size = math.min(panel_h - PANEL_PAD * 2, math.max(48, inner_w * 0.30))
    local vertical_cell_size = (panel_h - PANEL_PAD * 2 - SMALL_CELL_GAP) / 2
    local horizontal_cell_size = (inner_w - large_size - SLOT_SECTION_GAP - SMALL_CELL_GAP * 3) / 4
    local cell_size = math.max(10, math.min(vertical_cell_size, horizontal_cell_size))
    local small_grid_w = cell_size * 4 + SMALL_CELL_GAP * 3
    local small_grid_x = is_left and panel_x + PANEL_PAD
        or panel_x + panel_w - PANEL_PAD - small_grid_w
    local slot_x = is_left and panel_x + panel_w - PANEL_PAD - large_size
        or panel_x + PANEL_PAD
    local button_top = officer.label_rect and officer.label_rect.y or portrait.y - 40
    local button_size = math.min(panel_w, math.max(1, portrait.y - button_top))
    local button_x = is_left and panel_x or panel_x + panel_w - button_size
    local population_available_w = math.max(0, panel_w - button_size)
    local population_slot_size = math.min(button_size, population_available_w / POPULATION_SLOT_COUNT)
    local population_row_w = population_slot_size * POPULATION_SLOT_COUNT
    local population_row_x = panel_x + (panel_w - population_row_w) / 2

    return {
        x = panel_x,
        y = portrait.y,
        w = panel_w,
        h = panel_h,
        is_left = is_left,
        cell_size = cell_size,
        small_grid_x = small_grid_x,
        small_grid_y = portrait.y + PANEL_PAD,
        orders_button = {
            x = button_x,
            y = portrait.y - button_size,
            w = button_size,
            h = button_size,
        },
        population_row = {
            x = population_row_x,
            y = portrait.y - button_size,
            w = population_row_w,
            h = button_size,
            slot_size = population_slot_size,
        },
        slot = {
            x = slot_x,
            y = portrait.y + (panel_h - large_size) / 2,
            w = large_size,
            h = large_size,
        },
    }
end

function officers.getOrdersOfficerAtPoint(officer_lists, backing_rect, x, y)
    return eachOfficer(officer_lists, function(officer)
        if officer.panel_open and not officer.orders_locked then
            local layout = getPanelLayout(officer, backing_rect)

            if layout and pointInRect(x, y, layout.orders_button) then
                return officer
            end
        end
    end)
end

function officers.getOfficerVisualBounds(officer, backing_rect)
    local layout = getPanelLayout(officer, backing_rect)
    local portrait = officer and officer.portrait_rect
    local label = officer and officer.label_rect

    if not layout or not portrait then
        return nil
    end

    local left = math.min(layout.x, portrait.x, label and label.x or portrait.x)
    local top = math.min(layout.orders_button.y, label and label.y or portrait.y)
    local right = math.max(layout.x + layout.w, portrait.x + portrait.w, label and label.x + label.w or 0)
    local bottom = math.max(layout.y + layout.h, portrait.y + portrait.h)

    return {
        x = left,
        y = top,
        w = right - left,
        h = bottom - top,
    }
end

function officers.getOfficerAtPoint(officer_lists, x, y)
    return eachOfficer(officer_lists, function(officer)
        if pointInRect(x, y, officer.portrait_rect) then
            return officer
        end
    end)
end

function officers.togglePanel(officer)
    if not officer then
        return false
    end

    if officer.panel_open then
        if officer.assigned_agent then
            return false
        end

        officer.panel_open = false
    else
        officer.panel_open = true
    end

    return true
end

function officers.hasOpenPanel(officer_lists)
    return eachOfficer(officer_lists, function(officer)
        if officer.panel_open then
            return true
        end
    end) == true
end

function officers.getSlotOfficerAtPoint(officer_lists, backing_rect, x, y)
    return eachOfficer(officer_lists, function(officer)
        if officer.panel_open then
            local layout = getPanelLayout(officer, backing_rect)

            if layout and pointInRect(x, y, layout.slot) then
                return officer
            end
        end
    end)
end

function officers.startDrag(agent)
    if not agent or officers.drag_agent then
        return false
    end

    officers.drag_agent = agent
    officers.drag_origin = nil

    return true
end

function officers.startDragFromSlot(officer)
    if not officer
        or not officer.assigned_agent
        or officer.agent_locked
        or officers.drag_agent
    then
        return false
    end

    officers.drag_agent = officer.assigned_agent
    officers.drag_origin = officer
    officer.assigned_agent = nil

    return true
end

function officers.getDragAgent()
    return officers.drag_agent
end

function officers.cancelDrag()
    if officers.drag_origin and officers.drag_agent then
        officers.drag_origin.assigned_agent = officers.drag_agent
    end

    officers.drag_agent = nil
    officers.drag_origin = nil
end

function officers.returnDraggedToRoster()
    officers.drag_agent = nil
    officers.drag_origin = nil
end

function officers.placeDraggedAgent(officer)
    if not officer or not officer.panel_open or officer.assigned_agent or not officers.drag_agent then
        return false
    end

    officer.assigned_agent = officers.drag_agent
    officers.drag_agent = nil
    officers.drag_origin = nil

    return true
end

function officers.containsAgent(officer_lists, agent)
    if not agent then
        return false
    end

    return eachOfficer(officer_lists, function(officer)
        if officer.assigned_agent == agent then
            return true
        end
    end) == true
end

function officers.filterRosterAgents(officer_lists, agents)
    local filtered = {}

    for _, agent in ipairs(agents or {}) do
        if not officers.containsAgent(officer_lists, agent) and officers.drag_agent ~= agent then
            filtered[#filtered + 1] = agent
        end
    end

    return filtered
end

function officers.drawPanels(officer_lists, backing_rect, options)
    options = options or {}

    local slot_icon = getUpgradeSlotIcon()
    local panel_orders_icon = getOrdersIcon()
    local panel_orders_hover_icon = getOrdersHoverIcon()
    local panel_lock_icon = getLockIcon()
    local empty_population_icon = getPopulationEmptyIcon()
    local full_population_icon = getPopulationFullIcon()
    local mouse_x, mouse_y = love.mouse.getPosition()
    local current_hovered_orders_officer = nil

    eachOfficer(officer_lists, function(officer)
        if not officer.panel_open then
            return
        end

        local layout = getPanelLayout(officer, backing_rect)

        if not layout or layout.w <= 0 then
            return
        end

        love.graphics.setColor(PANEL_COLOR)
        love.graphics.rectangle("fill", layout.x, layout.y, layout.w, layout.h)
        love.graphics.setColor(options.outline_color or OUTLINE_COLOR)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", layout.x, layout.y, layout.w, layout.h)
        love.graphics.setLineWidth(1)

        local orders_button = layout.orders_button
        local orders_hovered = not officer.orders_locked and pointInRect(mouse_x, mouse_y, orders_button)
        local displayed_orders_icon = officer.orders_locked and panel_lock_icon
            or orders_hovered and panel_orders_hover_icon
            or panel_orders_icon

        if orders_hovered then
            current_hovered_orders_officer = officer
        end

        love.graphics.setColor(orders_hovered and 0 or 1, orders_hovered and 0 or 1, orders_hovered and 0 or 1, 1)
        love.graphics.rectangle("fill", orders_button.x, orders_button.y, orders_button.w, orders_button.h)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("line", orders_button.x, orders_button.y, orders_button.w, orders_button.h)

        if displayed_orders_icon then
            local icon_padding = officer.orders_locked and LOCK_ICON_PADDING or ORDERS_ICON_PADDING
            local available_size = math.max(1, orders_button.w - icon_padding * 2)
            local icon_scale = math.min(
                available_size / displayed_orders_icon:getWidth(),
                available_size / displayed_orders_icon:getHeight()
            )

            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(
                displayed_orders_icon,
                orders_button.x + orders_button.w / 2,
                orders_button.y + orders_button.h / 2,
                0,
                icon_scale,
                icon_scale,
                displayed_orders_icon:getWidth() / 2,
                displayed_orders_icon:getHeight() / 2
            )
        end

        if empty_population_icon and full_population_icon then
            local population_row = layout.population_row
            local population = math.max(0, math.min(
                POPULATION_SLOT_COUNT,
                math.floor(tonumber(officer.population) or 0)
            ))

            for index = 1, POPULATION_SLOT_COUNT do
                local population_icon = index <= population and full_population_icon or empty_population_icon
                local slot_x = population_row.x + (index - 1) * population_row.slot_size
                local slot_y = population_row.y + (population_row.h - population_row.slot_size) / 2
                local icon_scale = math.min(
                    population_row.slot_size / population_icon:getWidth(),
                    population_row.slot_size / population_icon:getHeight()
                )

                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.draw(
                    population_icon,
                    slot_x + population_row.slot_size / 2,
                    slot_y + population_row.slot_size / 2,
                    0,
                    icon_scale,
                    icon_scale,
                    population_icon:getWidth() / 2,
                    population_icon:getHeight() / 2
                )
            end
        end

        for index = 1, 8 do
            local column = (index - 1) % 4
            local row = math.floor((index - 1) / 4)
            local cell_x = layout.small_grid_x + column * (layout.cell_size + SMALL_CELL_GAP)
            local cell_y = layout.small_grid_y + row * (layout.cell_size + SMALL_CELL_GAP)

            love.graphics.setColor(CELL_COLOR)
            love.graphics.rectangle("fill", cell_x, cell_y, layout.cell_size, layout.cell_size)

            if slot_icon then
                local available_size = math.max(1, layout.cell_size - UPGRADE_SLOT_ICON_PADDING * 2)
                local icon_scale = math.min(
                    available_size / slot_icon:getWidth(),
                    available_size / slot_icon:getHeight()
                )

                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.draw(
                    slot_icon,
                    cell_x + layout.cell_size / 2,
                    cell_y + layout.cell_size / 2,
                    0,
                    icon_scale,
                    icon_scale,
                    slot_icon:getWidth() / 2,
                    slot_icon:getHeight() / 2
                )
            end

            love.graphics.setColor(options.outline_color or OUTLINE_COLOR)
            love.graphics.rectangle("line", cell_x, cell_y, layout.cell_size, layout.cell_size)
        end

        love.graphics.setColor(CELL_COLOR)
        love.graphics.rectangle("fill", layout.slot.x, layout.slot.y, layout.slot.w, layout.slot.h)

        if officers.drag_agent and not officer.assigned_agent then
            love.graphics.setColor(DROP_COLOR)
            love.graphics.rectangle("fill", layout.slot.x, layout.slot.y, layout.slot.w, layout.slot.h)
        end

        love.graphics.setColor(options.outline_color or OUTLINE_COLOR)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", layout.slot.x, layout.slot.y, layout.slot.w, layout.slot.h)
        love.graphics.setLineWidth(1)

        if officer.assigned_agent and options.draw_agent_portrait then
            local portrait_center_x = layout.slot.x + layout.slot.w / 2
            local portrait_center_y = layout.slot.y + layout.slot.h / 2
            local portrait_radius = layout.slot.w * 0.39
            local previous_shader = love.graphics.getShader()

            if officer.agent_locked then
                love.graphics.setShader(officers.getGreyscaleShader())
            end

            options.draw_agent_portrait(
                officer.assigned_agent,
                portrait_center_x,
                portrait_center_y,
                portrait_radius
            )

            if officer.agent_locked then
                love.graphics.setShader(previous_shader)

                local badge_radius = portrait_radius * AGENT_LOCK_BADGE_RADIUS_SCALE
                local badge_x = portrait_center_x
                local badge_y = portrait_center_y + portrait_radius * AGENT_LOCK_BADGE_Y_SCALE

                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.circle("fill", badge_x, badge_y, badge_radius)

                if panel_lock_icon then
                    local available_size = badge_radius * 2 * AGENT_LOCK_ICON_SCALE
                    local icon_scale = math.min(
                        available_size / panel_lock_icon:getWidth(),
                        available_size / panel_lock_icon:getHeight()
                    )

                    love.graphics.setColor(0, 0, 0, 1)
                    love.graphics.draw(
                        panel_lock_icon,
                        badge_x,
                        badge_y,
                        0,
                        icon_scale,
                        icon_scale,
                        panel_lock_icon:getWidth() / 2,
                        panel_lock_icon:getHeight() / 2
                    )
                end
            end
        end
    end)

    if current_hovered_orders_officer and current_hovered_orders_officer ~= hovered_orders_officer then
        sfx_logic.playNamed("cardhover")
    end

    hovered_orders_officer = current_hovered_orders_officer
    drawShout(options.font or love.graphics.getFont())
end

function officers.drawDrag(options)
    if not officers.drag_agent or not options or not options.draw_agent_portrait then
        return
    end

    local mouse_x, mouse_y = love.mouse.getPosition()

    options.draw_agent_portrait(officers.drag_agent, mouse_x, mouse_y, options.radius or 54)
end

return officers

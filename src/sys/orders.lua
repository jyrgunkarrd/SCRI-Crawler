local sfx_logic = require("src.sys.sfx_logic")
local equip_index = require("data.equip.index")
local image_loader = require("src.assets.image_loader")
local luggage = require("src.sys.luggage")
local econ = require("src.sys.econ")
local save_slots = require("src.sys.save_slots")
local calendar = require("src.sys.calendar")
local officers = require("src.sys.officers")

local orders = {
    officer = nil,
    title_font = nil,
    officer_font = nil,
    offerings = {},
    retask_rects = {},
    order_rects = {},
    option_rects = {},
    work_order = {},
    work_order_item_rects = {},
    work_order_rect = nil,
    work_order_scroll = 0,
    work_order_max_scroll = 0,
    preview_elapsed = 0,
    work_invoice_rect = nil,
    certify_rect = nil,
    certify_hovered = false,
    certify_wipe_elapsed = 0,
}

local FONT_PATH = "assets/fonts/Furore.otf"
local POPULATION_ICON_PATH = "assets/images/icons/pop_full.webp"
local SCRATCH_ICON_PATH = "assets/images/icons/scratch.webp"
local TITLE_FONT_SIZE = 20
local OFFICER_FONT_SIZE = 14
local BASE_WORK_PER_HOUR = 2
local CALENDAR_GAP = 8
local PANEL_PAD = 18
local WORK_TILE_TOP_GAP = 12
local WORK_TILE_H = 42
local OFFERING_TOP_GAP = 12
local OFFERING_COUNT = 5
local OFFERING_GAP = 8
local OFFERING_PAD = 8
local OFFERING_THUMB_MAX_SIZE = 92
local OFFERING_TEXT_GAP = 10
local OFFERING_OPTION_H = 24
local OFFERING_OPTION_GAP = 6
local OFFERING_ACTION_GAP = 6
local CHECKBOX_SIZE = 12
local WORK_ORDER_MAX_W = 300
local WORK_ORDER_EDGE_GAP = 18
local WORK_ORDER_SCREEN_MARGIN = 18
local WORK_ORDER_PAD = 12
local WORK_ORDER_TITLE_GAP = 10
local WORK_ORDER_ROW_H = 50
local WORK_ORDER_ROW_GAP = 6
local WORK_ORDER_THUMB_PAD = 5
local WORK_ORDER_TITLE_MARKER_COLOR = { 249 / 255, 161 / 255, 0, 1 }
local DISABLED_BRIGHTNESS = 0.28
local WARNING_FLASH_SECONDS = 0.42
local WARNING_GAP = 8
local WARNING_COLOR = { 249 / 255, 161 / 255, 1 / 255, 1 }
local INVOICE_H = 128
local INVOICE_GAP = 8
local INVOICE_PAD = 10
local INVOICE_SIGNATURE_H = 32
local INVOICE_CERTIFY_W = 104
local INVOICE_FIELD_GAP = 8
local INVOICE_SIGNATURE_COLOR = { 184 / 255, 184 / 255, 184 / 255, 1 }
local INVOICE_PAYABLE_COLOR = { 1, 0, 73 / 255, 1 }
local CERTIFY_FILL_COLOR = { 1, 0, 73 / 255, 1 }
local CERTIFY_SIGNATURE_WIPE_SECONDS = 0.42
local CERTIFY_SIGNATURE_LINE_WIDTH = 2
local DIM_COLOR = { 0, 0, 0, 0.72 }
local PANEL_COLOR = { 0, 0, 0, 0.97 }
local OUTLINE_COLOR = { 1, 1, 1, 1 }
local TEXT_COLOR = { 1, 1, 1, 1 }
local MUTED_TEXT_COLOR = { 1, 1, 1, 0.72 }
local COST_VALUE_COLOR = { 0, 1, 167 / 255, 1 }
local equipment_images = {}
local missing_equipment_images = {}
local population_icon = nil
local scratch_icon = nil

local function getReservedCount(offering_index)
    local count = 0

    for _, instance in ipairs(orders.work_order) do
        if instance.offering_index == offering_index then
            count = count + 1
        end
    end

    return count
end

local function removeWorkOrderInstance(instance_index)
    local instance = table.remove(orders.work_order, instance_index)

    if not instance then
        return false
    end

    local offering = orders.offerings[instance.offering_index]

    if offering and offering == instance.offering then
        offering.quantity = math.max(0, math.floor(tonumber(offering.quantity) or 0)) + 1

        if getReservedCount(instance.offering_index) == 0 then
            offering.options_locked = false
        end
    end

    orders.work_order_item_rects = {}

    if #orders.work_order == 0 then
        orders.work_order_rect = nil
        orders.work_order_scroll = 0
        orders.work_order_max_scroll = 0
        orders.work_invoice_rect = nil
        orders.certify_rect = nil
        orders.certify_hovered = false
        orders.certify_wipe_elapsed = 0
    end

    return true
end

local function restoreWorkOrder()
    for _, instance in ipairs(orders.work_order) do
        local offering = orders.offerings[instance.offering_index]

        if offering and offering == instance.offering then
            offering.quantity = math.max(0, math.floor(tonumber(offering.quantity) or 0)) + 1
            offering.options_locked = false
        end
    end

    orders.work_order = {}
    orders.work_order_item_rects = {}
    orders.work_order_rect = nil
    orders.work_order_scroll = 0
    orders.work_order_max_scroll = 0
    orders.work_invoice_rect = nil
    orders.certify_rect = nil
    orders.certify_hovered = false
    orders.certify_wipe_elapsed = 0
end

local function pointInRect(x, y, rect)
    return rect
        and x >= rect.x
        and x <= rect.x + rect.w
        and y >= rect.y
        and y <= rect.y + rect.h
end

local function getPopulationIcon()
    if not population_icon then
        population_icon = image_loader.newImage(POPULATION_ICON_PATH)
    end

    return population_icon
end


local function getScratchIcon()
    if not scratch_icon then
        scratch_icon = image_loader.newImage(SCRATCH_ICON_PATH)
    end

    return scratch_icon
end

local function drawInlineIcon(image, x, y, size, visual_scale, brightness)
    if not image then
        return
    end

    visual_scale = visual_scale or 1
    brightness = brightness or 1

    local scale = math.min(size / image:getWidth(), size / image:getHeight()) * visual_scale

    love.graphics.setColor(brightness, brightness, brightness, 1)
    love.graphics.draw(
        image,
        x + size / 2,
        y + size / 2,
        0,
        scale,
        scale,
        image:getWidth() / 2,
        image:getHeight() / 2
    )
end

local function normalizeCategory(value)
    return tostring(value or ""):lower()
end

local function formatNumber(value)
    value = tonumber(value) or 0

    local rounded = math.floor(value + 0.5)

    if math.abs(value - rounded) < 0.000001 then
        return tostring(rounded)
    end

    return (string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", ""))
end

local function getEffectiveOfferingValues(offering)
    local definition = offering and offering.definition or {}
    local work = math.max(0, tonumber(definition.work) or 0)
    local cost = math.max(0, tonumber(definition.cost) or 0)

    for option_index, option in ipairs(definition.options or {}) do
        if offering.selected_options and offering.selected_options[option_index] then
            work = work * (tonumber(option.work_mult) or 1)
            cost = cost * (tonumber(option.cost_mult) or 1)
        end
    end

    return math.ceil(work), math.ceil(cost)
end

local function snapshotSelectedOptions(offering)
    local selected = {}

    for option_index, option in ipairs(offering.definition and offering.definition.options or {}) do
        if offering.selected_options and offering.selected_options[option_index] then
            local option_name = type(option) == "table"
                and tostring(option.name or option.id or "Option")
                or tostring(option or "Option")

            selected[#selected + 1] = {
                index = option_index,
                name = option_name,
                work_mult = type(option) == "table" and tonumber(option.work_mult) or 1,
                cost_mult = type(option) == "table" and tonumber(option.cost_mult) or 1,
            }
        end
    end

    return selected
end

local function getEligibleDefinitions(officer)
    local targeted_categories = {}
    local eligible = {}

    for _, category in ipairs(officer and officer.orders or {}) do
        targeted_categories[normalizeCategory(category)] = true
    end

    for _, definition in ipairs(equip_index.all or {}) do
        if definition.order == true and targeted_categories[normalizeCategory(definition.category)] then
            eligible[#eligible + 1] = definition
        end
    end

    return eligible
end

local function randomAvailableQuantity(definition)
    local minimum = math.max(0, math.floor(tonumber(definition and definition.avail_min) or 0))
    local maximum = math.max(0, math.floor(tonumber(definition and definition.avail_max) or minimum))

    if maximum < minimum then
        minimum, maximum = maximum, minimum
    end

    return love.math.random(minimum, maximum)
end

local function createRandomOffering(eligible)
    if #eligible == 0 then
        return false
    end

    local definition = eligible[love.math.random(#eligible)]

    return {
        definition = definition,
        quantity = randomAvailableQuantity(definition),
        retask_cost = love.math.random(5, 10),
        selected_options = {},
        options_locked = false,
    }
end

local function getOrCreateOfferings(officer)
    local eligible = getEligibleDefinitions(officer)
    local offerings = officer.order_offerings or {}

    for index = 1, OFFERING_COUNT do
        if offerings[index] == nil then
            offerings[index] = createRandomOffering(eligible)
        end

        if type(offerings[index]) == "table" and offerings[index].retask_cost == nil then
            offerings[index].retask_cost = love.math.random(5, 10)
        end

        if type(offerings[index]) == "table" then
            offerings[index].selected_options = offerings[index].selected_options or {}
            offerings[index].options_locked = offerings[index].options_locked == true
        end
    end

    officer.order_offerings = offerings

    return offerings
end

local function refillOfficerOfferings(officer)
    local offerings = officer and officer.order_offerings

    if type(offerings) ~= "table" then
        return
    end

    local eligible = getEligibleDefinitions(officer)

    for index = 1, OFFERING_COUNT do
        if offerings[index] == false then
            offerings[index] = createRandomOffering(eligible)
        end
    end
end


local function getEquipmentImage(definition)
    local id = definition and definition.id

    if not id or missing_equipment_images[id] then
        return nil
    end

    if equipment_images[id] then
        return equipment_images[id]
    end

    local ok, image = pcall(image_loader.newImage, ("assets/images/equip/%s.webp"):format(id))

    if not ok then
        missing_equipment_images[id] = true
        return nil
    end

    equipment_images[id] = image

    return image
end

function orders.open(officer)
    if not officer or officer.orders_locked then
        return false
    end

    restoreWorkOrder()
    orders.officer = officer
    orders.offerings = getOrCreateOfferings(officer)
    orders.retask_rects = {}
    orders.order_rects = {}
    orders.option_rects = {}
    orders.work_order_item_rects = {}
    orders.title_font = orders.title_font or love.graphics.newFont(FONT_PATH, TITLE_FONT_SIZE)
    orders.officer_font = orders.officer_font or love.graphics.newFont(FONT_PATH, OFFICER_FONT_SIZE)
    sfx_logic.playNamed("lclick")

    return true
end

function orders.close()
    local was_open = orders.officer ~= nil

    restoreWorkOrder()
    orders.officer = nil
    orders.offerings = {}
    orders.retask_rects = {}
    orders.order_rects = {}
    orders.option_rects = {}
    orders.work_order_item_rects = {}

    return was_open
end

function orders.isOpen()
    return orders.officer ~= nil
end

function orders.getOfficer()
    return orders.officer
end

function orders.getOfferings()
    return orders.offerings
end

function orders.getWorkPerHour(officer)
    local population = math.max(0, math.floor(tonumber(officer and officer.population) or 0))

    return BASE_WORK_PER_HOUR + population
end

function orders.getCompletionPreview(calendar_state)
    if #orders.work_order == 0 or not calendar_state then
        return nil
    end

    local total_work = 0

    for _, instance in ipairs(orders.work_order) do
        total_work = total_work + math.max(
            0,
            tonumber(instance.effective_work)
                or tonumber(instance.definition and instance.definition.work)
                or 0
        )
    end

    local work_per_hour = math.max(1, orders.getWorkPerHour(orders.officer))
    local required_hours = math.max(1, math.ceil(total_work / work_per_hour))
    local current_hour = math.max(1, math.min(12, math.floor(tonumber(calendar_state.current_hour) or 1)))
    local target_index = current_hour + required_hours

    if required_hours > 24 or target_index > 24 then
        return {
            exceeds_window = true,
            required_hours = required_hours,
            total_work = total_work,
            work_per_hour = work_per_hour,
        }
    end

    return {
        exceeds_window = false,
        season = target_index <= 12 and "current" or "upcoming",
        hour = target_index <= 12 and target_index or target_index - 12,
        required_hours = required_hours,
        total_work = total_work,
        work_per_hour = work_per_hour,
        elapsed = orders.preview_elapsed,
    }
end

function orders.getInvoicePreview(calendar_state)
    if #orders.work_order == 0 or not calendar_state then
        return nil
    end

    local total_cost = 0

    for _, instance in ipairs(orders.work_order) do
        total_cost = total_cost + math.max(
            0,
            tonumber(instance.effective_cost)
                or tonumber(instance.definition and instance.definition.cost)
                or 0
        )
    end

    local discount = math.floor(total_cost / 10) * 5
    local current_hour = math.max(1, math.min(12, math.floor(tonumber(calendar_state.current_hour) or 1)))
    local target_index = current_hour + 12

    return {
        total_cost = total_cost,
        discount = discount,
        payable_hours = 12,
        season = target_index <= 12 and "current" or "upcoming",
        hour = target_index <= 12 and target_index or target_index - 12,
        elapsed = orders.preview_elapsed,
    }
end

function orders.certify(calendar_state)
    local officer = orders.officer
    local agent = officer and officer.assigned_agent
    local completion = orders.getCompletionPreview(calendar_state)
    local invoice = orders.getInvoicePreview(calendar_state)

    if not officer
        or not agent
        or #orders.work_order == 0
        or not completion
        or completion.exceeds_window
        or not invoice
    then
        return false
    end

    local items = {}

    for _, instance in ipairs(orders.work_order) do
        local definition = instance.definition or {}

        items[#items + 1] = {
            offering_index = instance.offering_index,
            equipment_id = definition.id,
            name = definition.name or definition.id or "Equipment",
            category = definition.category,
            work = math.max(0, tonumber(instance.effective_work) or tonumber(definition.work) or 0),
            cost = math.max(0, tonumber(instance.effective_cost) or tonumber(definition.cost) or 0),
            selected_options = instance.selected_options or {},
            definition = definition,
        }
    end

    local commitment = calendar.commitOrder(calendar_state, {
        save_slot = save_slots.getActiveSlot and save_slots.getActiveSlot() or nil,
        officer = {
            id = officer.id,
            name = officer.name,
            reference = officer,
        },
        agent = {
            id = agent.id,
            name = agent.name,
            reference = agent,
        },
        work_order = {
            items = items,
            total_work = completion.total_work,
            work_per_hour = completion.work_per_hour,
            required_hours = completion.required_hours,
        },
        invoice = {
            total_cost = invoice.total_cost,
            discount = invoice.discount,
            payable_hours = invoice.payable_hours,
            signature = save_slots.getActiveSignature(),
        },
        completion = {
            season = completion.season,
            hour = completion.hour,
            season_id = completion.season == "current"
                and calendar_state.current_season
                and calendar_state.current_season.id
                or calendar_state.upcoming_season and calendar_state.upcoming_season.id,
        },
        payable = {
            season = invoice.season,
            hour = invoice.hour,
            season_id = invoice.season == "current"
                and calendar_state.current_season
                and calendar_state.current_season.id
                or calendar_state.upcoming_season and calendar_state.upcoming_season.id,
        },
        issued_at = {
            season = "current",
            hour = math.max(1, math.min(12, math.floor(tonumber(calendar_state.current_hour) or 1))),
            season_id = calendar_state.current_season and calendar_state.current_season.id,
        },
    })

    if not commitment then
        return false
    end

    officer.agent_locked = true
    officer.orders_locked = true
    officer.committed_order_ids = officer.committed_order_ids or {}
    officer.committed_order_ids[#officer.committed_order_ids + 1] = commitment.id
    officers.triggerShout(officer)

    orders.work_order = {}
    orders.work_order_rect = nil
    orders.work_order_scroll = 0
    orders.work_order_max_scroll = 0
    orders.work_invoice_rect = nil
    orders.certify_rect = nil
    orders.certify_hovered = false
    orders.certify_wipe_elapsed = 0
    orders.officer = nil
    orders.offerings = {}
    orders.retask_rects = {}
    orders.order_rects = {}
    orders.option_rects = {}
    orders.work_order_item_rects = {}

    return true
end

function orders.update(dt)
    dt = math.max(0, tonumber(dt) or 0)
    orders.preview_elapsed = orders.preview_elapsed + dt

    local signature = orders.isOpen() and save_slots.getActiveSignature() or nil
    local mouse_x, mouse_y = love.mouse.getPosition()
    local hovered = signature and pointInRect(mouse_x, mouse_y, orders.certify_rect) or false

    if hovered then
        if not orders.certify_hovered then
            orders.certify_hovered = true
            orders.certify_wipe_elapsed = 0
            sfx_logic.playNamed("write")
        else
            orders.certify_wipe_elapsed = math.min(
                CERTIFY_SIGNATURE_WIPE_SECONDS,
                orders.certify_wipe_elapsed + dt
            )
        end
    else
        orders.certify_hovered = false
        orders.certify_wipe_elapsed = 0
    end
end

function orders.refillEmptyOfferings(officer_groups)
    for _, group in ipairs(officer_groups or {}) do
        for _, officer in ipairs(group or {}) do
            refillOfficerOfferings(officer)
        end
    end
end

function orders.getModalRect(backing_rect, calendar_bounds, top_y)
    if not backing_rect or not calendar_bounds then
        return nil
    end

    local modal_top = math.max(0, tonumber(top_y) or 0)
    local modal_bottom = math.max(modal_top, calendar_bounds.season_label_y - CALENDAR_GAP)

    return {
        x = backing_rect.x,
        y = modal_top,
        w = backing_rect.w,
        h = modal_bottom - modal_top,
    }
end

function orders.mousepressed(x, y, button, modal_rect, calendar_state)
    if not orders.isOpen() then
        return false
    end

    if button == 2 and #orders.work_order > 0 then
        restoreWorkOrder()
        return true
    end

    if button == 1 then
        if pointInRect(x, y, orders.certify_rect) then
            orders.certify(calendar_state)
            return true
        end

        for _, item_hit in ipairs(orders.work_order_item_rects) do
            if pointInRect(x, y, item_hit.rect) then
                if removeWorkOrderInstance(item_hit.instance_index) then
                    sfx_logic.playNamed("lclick")
                end

                return true
            end
        end

        for _, option_hit in ipairs(orders.option_rects) do
            if pointInRect(x, y, option_hit.rect) then
                local offering = orders.offerings[option_hit.offering_index]

                if offering and not offering.options_locked then
                    offering.selected_options = offering.selected_options or {}
                    offering.selected_options[option_hit.option_index] = not offering.selected_options[option_hit.option_index]
                end

                return true
            end
        end

        for index, rect in pairs(orders.order_rects) do
            if pointInRect(x, y, rect) then
                local offering = orders.offerings[index]
                local quantity = offering and math.max(0, math.floor(tonumber(offering.quantity) or 0)) or 0

                sfx_logic.playNamed("lclick")

                if orders.officer.assigned_agent and offering and quantity > 0 then
                    local effective_work, effective_cost = getEffectiveOfferingValues(offering)

                    offering.options_locked = true
                    offering.quantity = quantity - 1
                    orders.work_order[#orders.work_order + 1] = {
                        offering_index = index,
                        offering = offering,
                        definition = offering.definition,
                        effective_work = effective_work,
                        effective_cost = effective_cost,
                        selected_options = snapshotSelectedOptions(offering),
                    }
                end

                return true
            end
        end

        for index, rect in pairs(orders.retask_rects) do
            if pointInRect(x, y, rect) then
                local offering = orders.offerings[index]

                sfx_logic.playNamed("lclick")

                if offering and getReservedCount(index) == 0 and econ.spend(offering.retask_cost) then
                    orders.offerings[index] = false
                    orders.officer.order_offerings[index] = false
                    orders.retask_rects[index] = nil
                end

                return true
            end
        end
    end

    if pointInRect(x, y, orders.work_order_rect) then
        return true
    end

    if not pointInRect(x, y, modal_rect) then
        orders.close()
    end

    return true
end

function orders.wheelmoved(_, y)
    if not orders.isOpen() or orders.work_order_max_scroll <= 0 then
        return false
    end

    local mouse_x, mouse_y = love.mouse.getPosition()

    if not pointInRect(mouse_x, mouse_y, orders.work_order_rect) then
        return false
    end

    if y > 0 then
        orders.work_order_scroll = math.max(0, orders.work_order_scroll - 1)
    elseif y < 0 then
        orders.work_order_scroll = math.min(
            orders.work_order_max_scroll,
            orders.work_order_scroll + 1
        )
    end

    return y ~= 0
end

local function drawOfferingThumbnail(definition, x, y, size)
    local image = not luggage.isLuggage(definition) and getEquipmentImage(definition) or nil

    love.graphics.setColor(0.015, 0.014, 0.012, 1)
    love.graphics.rectangle("fill", x, y, size, size)

    if luggage.draw(definition, x, y, size, size, { font = orders.officer_font }) then
        -- Luggage uses its inventory-footprint thumbnail renderer.
    elseif image then
        local available_size = math.max(1, size - 8)
        local scale = math.min(available_size / image:getWidth(), available_size / image:getHeight())

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(
            image,
            x + size / 2,
            y + size / 2,
            0,
            scale,
            scale,
            image:getWidth() / 2,
            image:getHeight() / 2
        )
    else
        love.graphics.setColor(MUTED_TEXT_COLOR)
        love.graphics.printf(
            definition.id or "?",
            x,
            y + (size - orders.officer_font:getHeight()) / 2,
            size,
            "center"
        )
    end

    love.graphics.setColor(OUTLINE_COLOR)
    love.graphics.rectangle("line", x, y, size, size)
end

local function getOptionLabel(option)
    if type(option) == "table" then
        return tostring(option.name or option.id or "Option")
    end

    return tostring(option or "Option")
end

local function drawOfferingOptions(offering, offering_index, x, y)
    local options = offering.definition.options or {}

    if #options == 0 then
        return
    end

    local cursor_x = x

    for option_index, option in ipairs(options) do
        local label = getOptionLabel(option)
        local tile_w = CHECKBOX_SIZE + orders.officer_font:getWidth(label) + 24
        local tile_x = cursor_x
        local checkbox_x = tile_x + 6
        local checkbox_y = y + (OFFERING_OPTION_H - CHECKBOX_SIZE) / 2
        local enabled = not offering.options_locked
        local brightness = enabled and 1 or DISABLED_BRIGHTNESS
        local selected = offering.selected_options and offering.selected_options[option_index]

        love.graphics.setColor(0.035 * brightness, 0.033 * brightness, 0.03 * brightness, 1)
        love.graphics.rectangle("fill", tile_x, y, tile_w, OFFERING_OPTION_H)
        love.graphics.setColor(brightness, brightness, brightness, 1)
        love.graphics.rectangle("line", tile_x, y, tile_w, OFFERING_OPTION_H)

        if selected then
            love.graphics.rectangle("fill", checkbox_x, checkbox_y, CHECKBOX_SIZE, CHECKBOX_SIZE)
        end

        love.graphics.rectangle("line", checkbox_x, checkbox_y, CHECKBOX_SIZE, CHECKBOX_SIZE)
        love.graphics.setColor(brightness, brightness, brightness, 1)
        love.graphics.printf(
            label,
            checkbox_x + CHECKBOX_SIZE + 6,
            y + (OFFERING_OPTION_H - orders.officer_font:getHeight()) / 2,
            math.max(0, tile_w - CHECKBOX_SIZE - 18),
            "left"
        )

        if enabled then
            orders.option_rects[#orders.option_rects + 1] = {
                offering_index = offering_index,
                option_index = option_index,
                rect = {
                    x = tile_x,
                    y = y,
                    w = tile_w,
                    h = OFFERING_OPTION_H,
                },
            }
        end

        cursor_x = cursor_x + tile_w + OFFERING_OPTION_GAP
    end
end

local function drawOfferingActions(
    x,
    y,
    w,
    h,
    retask_cost,
    offering_index,
    order_enabled,
    retask_enabled
)
    local labels = { "Order", "Retask" }
    local button_w = (w - OFFERING_ACTION_GAP) / 2
    local text_y = y + (h - orders.officer_font:getHeight()) / 2

    for index, label in ipairs(labels) do
        local button_x = x + (index - 1) * (button_w + OFFERING_ACTION_GAP)
        local enabled = (index == 1 and order_enabled) or (index == 2 and retask_enabled)
        local brightness = enabled and 1 or DISABLED_BRIGHTNESS

        love.graphics.setColor(0.035 * brightness, 0.033 * brightness, 0.03 * brightness, 1)
        love.graphics.rectangle("fill", button_x, y, button_w, h)
        love.graphics.setColor(brightness, brightness, brightness, 1)
        love.graphics.rectangle("line", button_x, y, button_w, h)

        if index == 2 then
            if enabled then
                orders.retask_rects[offering_index] = {
                    x = button_x,
                    y = y,
                    w = button_w,
                    h = h,
                }
            end

            local icon_size = orders.officer_font:getHeight()
            local label_gap = 7
            local icon_gap = 5
            local cost_text = tostring(math.floor(tonumber(retask_cost) or 0))
            local content_w = orders.officer_font:getWidth(label)
                + label_gap
                + icon_size
                + icon_gap
                + orders.officer_font:getWidth(cost_text)
            local content_x = button_x + (button_w - content_w) / 2

            love.graphics.setColor(brightness, brightness, brightness, 1)
            love.graphics.print(label, content_x, text_y)
            content_x = content_x + orders.officer_font:getWidth(label) + label_gap
            drawInlineIcon(getScratchIcon(), content_x, text_y, icon_size, 1.25, brightness)
            content_x = content_x + icon_size + icon_gap
            love.graphics.setColor(
                COST_VALUE_COLOR[1] * brightness,
                COST_VALUE_COLOR[2] * brightness,
                COST_VALUE_COLOR[3] * brightness,
                1
            )
            love.graphics.print(cost_text, content_x, text_y)
        else
            if enabled then
                orders.order_rects[offering_index] = {
                    x = button_x,
                    y = y,
                    w = button_w,
                    h = h,
                }
            end

            love.graphics.setColor(brightness, brightness, brightness, 1)
            love.graphics.printf(label, button_x, text_y, button_w, "center")
        end
    end
end

local function drawOffering(offering, offering_index, x, y, w, h)
    love.graphics.setColor(0.02, 0.019, 0.017, 1)
    love.graphics.rectangle("fill", x, y, w, h)
    love.graphics.setColor(OUTLINE_COLOR)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, w, h)
    love.graphics.setLineWidth(1)

    if not offering then
        love.graphics.setColor(MUTED_TEXT_COLOR)
        love.graphics.printf(
            "...Retasking...",
            x + OFFERING_PAD,
            y + (h - orders.officer_font:getHeight()) / 2,
            w - OFFERING_PAD * 2,
            "center"
        )
        return
    end

    local definition = offering.definition
    local has_options = #(definition.options or {}) > 0
    local option_clearance = has_options and OFFERING_OPTION_H + OFFERING_OPTION_GAP or 0
    local thumb_size = math.max(1, math.min(
        OFFERING_THUMB_MAX_SIZE,
        h - OFFERING_PAD * 2 - option_clearance
    ))
    local thumb_x = x + OFFERING_PAD
    local thumb_y = y + OFFERING_PAD
    local content_x = thumb_x + thumb_size + OFFERING_TEXT_GAP
    local content_w = math.max(0, x + w - OFFERING_PAD - content_x)

    drawOfferingThumbnail(definition, thumb_x, thumb_y, thumb_size)

    love.graphics.setColor(TEXT_COLOR)
    love.graphics.printf(definition.name or definition.id or "Equipment", content_x, y + OFFERING_PAD, content_w, "left")

    local detail_y = y + OFFERING_PAD + orders.officer_font:getHeight() + 7
    local detail_icon_size = orders.officer_font:getHeight()
    local detail_icon_gap = 5
    local detail_section_gap = 16
    local effective_work, effective_cost = getEffectiveOfferingValues(offering)
    local work_text = "Work: " .. formatNumber(effective_work)
    local cost_text = formatNumber(effective_cost)
    local available_text = ("Available: %d"):format(math.floor(tonumber(offering.quantity) or 0))
    local detail_x = content_x

    drawInlineIcon(getPopulationIcon(), detail_x, detail_y, detail_icon_size)
    detail_x = detail_x + detail_icon_size + detail_icon_gap
    love.graphics.setColor(MUTED_TEXT_COLOR)
    love.graphics.print(work_text, detail_x, detail_y)
    detail_x = detail_x + orders.officer_font:getWidth(work_text) + detail_section_gap

    drawInlineIcon(getScratchIcon(), detail_x, detail_y, detail_icon_size, 1.25)
    detail_x = detail_x + detail_icon_size + detail_icon_gap
    love.graphics.setColor(COST_VALUE_COLOR)
    love.graphics.print(cost_text, detail_x, detail_y)
    detail_x = detail_x + orders.officer_font:getWidth(cost_text) + detail_section_gap

    love.graphics.setColor(MUTED_TEXT_COLOR)
    love.graphics.print(available_text, detail_x, detail_y)

    local options_y = y + h - OFFERING_PAD - (has_options and OFFERING_OPTION_H or 0)
    local actions_bottom = thumb_y + thumb_size
    local desired_actions_y = detail_y + orders.officer_font:getHeight() + OFFERING_ACTION_GAP
    local actions_y = math.min(desired_actions_y, actions_bottom - 1)
    local actions_h = actions_bottom - actions_y
    local order_enabled = orders.officer
        and orders.officer.assigned_agent ~= nil
        and math.max(0, math.floor(tonumber(offering.quantity) or 0)) > 0
    local retask_enabled = getReservedCount(offering_index) == 0

    drawOfferingActions(
        content_x,
        actions_y,
        content_w,
        actions_h,
        offering.retask_cost,
        offering_index,
        order_enabled,
        retask_enabled
    )

    drawOfferingOptions(
        offering,
        offering_index,
        thumb_x,
        options_y
    )
end

local function getWorkOrderRect(modal_rect, officer_bounds, calendar_bounds, screen_w, screen_h)
    if #orders.work_order == 0 then
        return nil
    end

    local modal_center_x = modal_rect.x + modal_rect.w / 2
    local officer_center_x = officer_bounds
        and officer_bounds.x + officer_bounds.w / 2
        or modal_rect.x - 1
    local officer_is_left = officer_center_x < modal_center_x
    local protected_left = modal_rect.x
    local protected_right = modal_rect.x + modal_rect.w

    if calendar_bounds and tonumber(calendar_bounds.x) and tonumber(calendar_bounds.w) then
        protected_left = math.min(protected_left, calendar_bounds.x)
        protected_right = math.max(protected_right, calendar_bounds.x + calendar_bounds.w)
    end

    local available_w
    local panel_x

    if officer_is_left then
        available_w = screen_w
            - WORK_ORDER_SCREEN_MARGIN
            - (protected_right + WORK_ORDER_EDGE_GAP)
        panel_x = protected_right + WORK_ORDER_EDGE_GAP
    else
        available_w = protected_left - WORK_ORDER_EDGE_GAP - WORK_ORDER_SCREEN_MARGIN
        panel_x = protected_left - WORK_ORDER_EDGE_GAP - math.min(WORK_ORDER_MAX_W, available_w)
    end

    local panel_w = math.max(1, math.min(WORK_ORDER_MAX_W, available_w))
    local title_h = orders.title_font:getHeight()
    local desired_h = WORK_ORDER_PAD * 2
        + title_h
        + WORK_ORDER_TITLE_GAP
        + #orders.work_order * WORK_ORDER_ROW_H
        + math.max(0, #orders.work_order - 1) * WORK_ORDER_ROW_GAP
    local panel_h = math.min(desired_h, screen_h - WORK_ORDER_SCREEN_MARGIN * 2)

    if not officer_is_left then
        panel_x = protected_left - WORK_ORDER_EDGE_GAP - panel_w
    end

    return {
        x = panel_x,
        y = (screen_h - panel_h) / 2,
        w = panel_w,
        h = panel_h,
    }
end

local function drawWorkOrder(modal_rect, officer_bounds, calendar_bounds, screen_w, screen_h)
    local panel_rect = getWorkOrderRect(
        modal_rect,
        officer_bounds,
        calendar_bounds,
        screen_w,
        screen_h
    )

    orders.work_order_rect = panel_rect
    orders.work_order_item_rects = {}

    if not panel_rect then
        return
    end

    love.graphics.setColor(PANEL_COLOR)
    love.graphics.rectangle("fill", panel_rect.x, panel_rect.y, panel_rect.w, panel_rect.h)
    love.graphics.setColor(OUTLINE_COLOR)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", panel_rect.x, panel_rect.y, panel_rect.w, panel_rect.h)
    love.graphics.setLineWidth(1)

    love.graphics.setFont(orders.title_font)
    local title_marker_size = orders.title_font:getHeight()

    love.graphics.setColor(WORK_ORDER_TITLE_MARKER_COLOR)
    love.graphics.rectangle(
        "fill",
        panel_rect.x + WORK_ORDER_PAD,
        panel_rect.y + WORK_ORDER_PAD,
        title_marker_size,
        title_marker_size
    )
    love.graphics.setColor(TEXT_COLOR)
    love.graphics.printf(
        "WORK ORDER",
        panel_rect.x + WORK_ORDER_PAD,
        panel_rect.y + WORK_ORDER_PAD,
        panel_rect.w - WORK_ORDER_PAD * 2,
        "center"
    )

    local row_y = panel_rect.y + WORK_ORDER_PAD + orders.title_font:getHeight() + WORK_ORDER_TITLE_GAP
    local panel_bottom = panel_rect.y + panel_rect.h - WORK_ORDER_PAD
    local row_stride = WORK_ORDER_ROW_H + WORK_ORDER_ROW_GAP
    local list_h = math.max(0, panel_bottom - row_y)
    local full_capacity = math.max(0, math.floor((list_h + WORK_ORDER_ROW_GAP) / row_stride))
    local overflowing = #orders.work_order > full_capacity
    local indicator_h = overflowing and orders.officer_font:getHeight() + WORK_ORDER_ROW_GAP or 0
    local visible_capacity = overflowing
        and math.max(1, math.floor((list_h - indicator_h + WORK_ORDER_ROW_GAP) / row_stride))
        or full_capacity
    local max_scroll = math.max(0, #orders.work_order - visible_capacity)

    orders.work_order_max_scroll = max_scroll
    orders.work_order_scroll = math.max(0, math.min(max_scroll, orders.work_order_scroll))

    love.graphics.setFont(orders.officer_font)

    local first_index = orders.work_order_scroll + 1
    local last_index = math.min(#orders.work_order, first_index + visible_capacity - 1)

    for instance_index = first_index, last_index do
        local instance = orders.work_order[instance_index]
        local row_x = panel_rect.x + WORK_ORDER_PAD
        local row_w = panel_rect.w - WORK_ORDER_PAD * 2
        local thumb_size = WORK_ORDER_ROW_H - WORK_ORDER_THUMB_PAD * 2
        local definition = instance.definition

        love.graphics.setColor(0.02, 0.019, 0.017, 1)
        love.graphics.rectangle("fill", row_x, row_y, row_w, WORK_ORDER_ROW_H)
        love.graphics.setColor(OUTLINE_COLOR)
        love.graphics.rectangle("line", row_x, row_y, row_w, WORK_ORDER_ROW_H)
        orders.work_order_item_rects[#orders.work_order_item_rects + 1] = {
            instance_index = instance_index,
            rect = {
                x = row_x,
                y = row_y,
                w = row_w,
                h = WORK_ORDER_ROW_H,
            },
        }
        drawOfferingThumbnail(
            definition,
            row_x + WORK_ORDER_THUMB_PAD,
            row_y + WORK_ORDER_THUMB_PAD,
            thumb_size
        )
        love.graphics.setColor(TEXT_COLOR)
        love.graphics.printf(
            definition.name or definition.id or "Equipment",
            row_x + WORK_ORDER_THUMB_PAD * 2 + thumb_size,
            row_y + (WORK_ORDER_ROW_H - orders.officer_font:getHeight()) / 2,
            math.max(0, row_w - thumb_size - WORK_ORDER_THUMB_PAD * 3),
            "left"
        )

        row_y = row_y + WORK_ORDER_ROW_H + WORK_ORDER_ROW_GAP
    end

    if overflowing then
        local remaining = math.max(0, #orders.work_order - last_index)
        local indicator = remaining > 0 and ("+%d MORE"):format(remaining) or "END OF WORK ORDER"

        love.graphics.setColor(MUTED_TEXT_COLOR)
        love.graphics.printf(
            indicator,
            panel_rect.x + WORK_ORDER_PAD,
            panel_bottom - orders.officer_font:getHeight(),
            panel_rect.w - WORK_ORDER_PAD * 2,
            "center"
        )
    end
end

local function drawCompletionWarning(preview, officer_bounds)
    if not preview or not preview.exceeds_window or not officer_bounds then
        return
    end

    local pulse = 0.5 + 0.5 * math.sin(
        orders.preview_elapsed * math.pi * 2 / WARNING_FLASH_SECONDS
    )
    local alpha = 0.25 + pulse * 0.75
    local warning_text = "ORDER CANNOT BE ISSUED — REQUIRED HOURS EXCEED THE 24-HOUR WINDOW"

    love.graphics.setFont(orders.officer_font)
    love.graphics.setColor(
        WARNING_COLOR[1],
        WARNING_COLOR[2],
        WARNING_COLOR[3],
        alpha
    )
    love.graphics.printf(
        warning_text,
        officer_bounds.x,
        officer_bounds.y + officer_bounds.h + WARNING_GAP,
        officer_bounds.w,
        "center"
    )
end

local function drawInvoiceScratchStat(label, value, x, y, w, alignment)
    local value_text = formatNumber(value)
    local icon_size = orders.officer_font:getHeight()
    local label_gap = 7
    local icon_gap = 5
    local content_w = orders.officer_font:getWidth(label)
        + label_gap
        + icon_size
        + icon_gap
        + orders.officer_font:getWidth(value_text)
    local content_x = alignment == "right" and x + w - content_w or x

    love.graphics.setColor(TEXT_COLOR)
    love.graphics.print(label, content_x, y)
    content_x = content_x + orders.officer_font:getWidth(label) + label_gap
    drawInlineIcon(getScratchIcon(), content_x, y, icon_size, 1.25)
    content_x = content_x + icon_size + icon_gap
    love.graphics.setColor(COST_VALUE_COLOR)
    love.graphics.print(value_text, content_x, y)
end

local function drawInvoiceSignature(signature, rect, progress)
    if not signature or type(signature.strokes) ~= "table" then
        return
    end

    local inset = 4
    local draw_rect = {
        x = rect.x + inset,
        y = rect.y + inset,
        w = math.max(1, rect.w - inset * 2),
        h = math.max(1, rect.h - inset * 2),
    }
    local eased_progress = 1 - (1 - math.max(0, math.min(1, progress))) ^ 2
    local scissor_x, scissor_y, scissor_w, scissor_h = love.graphics.getScissor()

    love.graphics.setScissor(rect.x, rect.y, rect.w * eased_progress, rect.h)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.setLineWidth(CERTIFY_SIGNATURE_LINE_WIDTH)

    for _, stroke in ipairs(signature.strokes) do
        if #stroke == 1 then
            local point = stroke[1]

            love.graphics.circle(
                "fill",
                draw_rect.x + point.x * draw_rect.w,
                draw_rect.y + point.y * draw_rect.h,
                CERTIFY_SIGNATURE_LINE_WIDTH / 2
            )
        elseif #stroke > 1 then
            local vertices = {}

            for _, point in ipairs(stroke) do
                vertices[#vertices + 1] = draw_rect.x + point.x * draw_rect.w
                vertices[#vertices + 1] = draw_rect.y + point.y * draw_rect.h
            end

            love.graphics.line(vertices)
        end
    end

    love.graphics.setLineWidth(1)

    if scissor_x then
        love.graphics.setScissor(scissor_x, scissor_y, scissor_w, scissor_h)
    else
        love.graphics.setScissor()
    end
end

local function drawWorkInvoice(invoice, completion_preview, officer_bounds)
    if not invoice or not officer_bounds then
        orders.work_invoice_rect = nil
        orders.certify_rect = nil
        orders.certify_hovered = false
        orders.certify_wipe_elapsed = 0
        return
    end

    local panel_rect = {
        x = officer_bounds.x,
        y = math.max(WORK_ORDER_SCREEN_MARGIN, officer_bounds.y - INVOICE_GAP - INVOICE_H),
        w = officer_bounds.w,
        h = INVOICE_H,
    }
    local stats_y = panel_rect.y + INVOICE_PAD + orders.title_font:getHeight() + 5
    local payable_y = stats_y + orders.officer_font:getHeight() + 5
    local signature_y = panel_rect.y + panel_rect.h - INVOICE_PAD - INVOICE_SIGNATURE_H
    local signature_w = math.max(
        1,
        panel_rect.w - INVOICE_PAD * 2 - INVOICE_CERTIFY_W - INVOICE_FIELD_GAP
    )
    local signature_rect = {
        x = panel_rect.x + INVOICE_PAD,
        y = signature_y,
        w = signature_w,
        h = INVOICE_SIGNATURE_H,
    }
    local certify_visible = not completion_preview or not completion_preview.exceeds_window
    local certify_rect = certify_visible and {
        x = signature_rect.x + signature_rect.w + INVOICE_FIELD_GAP,
        y = signature_y,
        w = INVOICE_CERTIFY_W,
        h = INVOICE_SIGNATURE_H,
    } or nil

    orders.work_invoice_rect = panel_rect
    orders.certify_rect = certify_rect

    if not certify_rect then
        orders.certify_hovered = false
        orders.certify_wipe_elapsed = 0
    end

    love.graphics.setColor(PANEL_COLOR)
    love.graphics.rectangle("fill", panel_rect.x, panel_rect.y, panel_rect.w, panel_rect.h)
    love.graphics.setColor(OUTLINE_COLOR)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", panel_rect.x, panel_rect.y, panel_rect.w, panel_rect.h)
    love.graphics.setLineWidth(1)

    love.graphics.setFont(orders.title_font)
    love.graphics.setColor(TEXT_COLOR)
    love.graphics.printf(
        "WORK INVOICE",
        panel_rect.x + INVOICE_PAD,
        panel_rect.y + INVOICE_PAD,
        panel_rect.w - INVOICE_PAD * 2,
        "center"
    )

    love.graphics.setFont(orders.officer_font)
    drawInvoiceScratchStat(
        "TOTAL COST:",
        invoice.total_cost,
        panel_rect.x + INVOICE_PAD,
        stats_y,
        (panel_rect.w - INVOICE_PAD * 2) / 2,
        "left"
    )
    drawInvoiceScratchStat(
        "DISCOUNT:",
        invoice.discount,
        panel_rect.x + panel_rect.w / 2,
        stats_y,
        panel_rect.w / 2 - INVOICE_PAD,
        "right"
    )

    local payable_text = ("PAYABLE IN %d HOURS"):format(invoice.payable_hours)
    local payable_triangle_size = orders.officer_font:getHeight() * 0.72
    local payable_triangle_gap = 7
    local payable_content_w = payable_triangle_size * 2
        + payable_triangle_gap * 2
        + orders.officer_font:getWidth(payable_text)
    local payable_x = panel_rect.x + (panel_rect.w - payable_content_w) / 2
    local payable_center_y = payable_y + orders.officer_font:getHeight() / 2

    love.graphics.setColor(INVOICE_PAYABLE_COLOR)
    love.graphics.polygon(
        "fill",
        payable_x + payable_triangle_size / 2,
        payable_center_y - payable_triangle_size / 2,
        payable_x,
        payable_center_y + payable_triangle_size / 2,
        payable_x + payable_triangle_size,
        payable_center_y + payable_triangle_size / 2
    )
    payable_x = payable_x + payable_triangle_size + payable_triangle_gap
    love.graphics.setColor(TEXT_COLOR)
    love.graphics.print(payable_text, payable_x, payable_y)
    payable_x = payable_x + orders.officer_font:getWidth(payable_text) + payable_triangle_gap
    love.graphics.setColor(INVOICE_PAYABLE_COLOR)
    love.graphics.polygon(
        "fill",
        payable_x + payable_triangle_size / 2,
        payable_center_y - payable_triangle_size / 2,
        payable_x,
        payable_center_y + payable_triangle_size / 2,
        payable_x + payable_triangle_size,
        payable_center_y + payable_triangle_size / 2
    )

    love.graphics.setColor(INVOICE_SIGNATURE_COLOR)
    love.graphics.rectangle(
        "fill",
        signature_rect.x,
        signature_rect.y,
        signature_rect.w,
        signature_rect.h
    )

    if certify_rect and orders.certify_hovered then
        drawInvoiceSignature(
            save_slots.getActiveSignature(),
            signature_rect,
            orders.certify_wipe_elapsed / CERTIFY_SIGNATURE_WIPE_SECONDS
        )
    end

    if certify_rect then
        love.graphics.setColor(CERTIFY_FILL_COLOR)
        love.graphics.rectangle(
            "fill",
            certify_rect.x,
            certify_rect.y,
            certify_rect.w,
            certify_rect.h
        )
        love.graphics.setColor(TEXT_COLOR)
        love.graphics.printf(
            "Certify",
            certify_rect.x,
            certify_rect.y + (certify_rect.h - orders.officer_font:getHeight()) / 2,
            certify_rect.w,
            "center"
        )
    end
end

local function drawOfferings(modal_rect, start_y)
    local bottom = modal_rect.y + modal_rect.h - PANEL_PAD
    local available_h = math.max(0, bottom - start_y - OFFERING_GAP * (OFFERING_COUNT - 1))
    local offering_h = available_h / OFFERING_COUNT
    local offering_x = modal_rect.x + PANEL_PAD
    local offering_w = modal_rect.w - PANEL_PAD * 2

    for index = 1, OFFERING_COUNT do
        drawOffering(
            orders.offerings[index],
            index,
            offering_x,
            start_y + (index - 1) * (offering_h + OFFERING_GAP),
            offering_w,
            offering_h
        )
    end
end

function orders.draw(options)
    if not orders.isOpen() then
        return
    end

    options = options or {}
    orders.retask_rects = {}
    orders.order_rects = {}
    orders.option_rects = {}
    orders.work_order_item_rects = {}

    local screen_w = options.screen_w or love.graphics.getWidth()
    local screen_h = options.screen_h or love.graphics.getHeight()
    local modal_rect = orders.getModalRect(options.backing_rect, options.calendar_bounds, options.modal_top)

    if not modal_rect then
        return
    end

    love.graphics.stencil(function()
        if options.officer_bounds then
            love.graphics.rectangle(
                "fill",
                options.officer_bounds.x,
                options.officer_bounds.y,
                options.officer_bounds.w,
                options.officer_bounds.h
            )
        end

        if options.calendar_bounds then
            love.graphics.rectangle(
                "fill",
                options.calendar_bounds.x,
                options.calendar_bounds.y,
                options.calendar_bounds.w,
                options.calendar_bounds.h
            )
        end
    end, "replace", 1)

    love.graphics.setStencilTest("equal", 0)
    love.graphics.setColor(DIM_COLOR)
    love.graphics.rectangle("fill", 0, 0, screen_w, screen_h)
    love.graphics.setStencilTest()

    love.graphics.setColor(PANEL_COLOR)
    love.graphics.rectangle("fill", modal_rect.x, modal_rect.y, modal_rect.w, modal_rect.h)
    love.graphics.setColor(OUTLINE_COLOR)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", modal_rect.x, modal_rect.y, modal_rect.w, modal_rect.h)
    love.graphics.setLineWidth(1)

    local officer = orders.officer
    local title = "ORDERS"
    local officer_label = officer.name or officer.id or "Officer"
    local title_y = modal_rect.y + PANEL_PAD
    local officer_y = title_y + orders.title_font:getHeight() + 8

    if officer.office and officer.office ~= "" then
        officer_label = officer_label .. " — " .. officer.office
    end

    love.graphics.setFont(orders.title_font)
    love.graphics.setColor(TEXT_COLOR)
    love.graphics.printf(
        title,
        modal_rect.x + PANEL_PAD,
        title_y,
        modal_rect.w - PANEL_PAD * 2,
        "center"
    )
    love.graphics.setFont(orders.officer_font)
    love.graphics.printf(
        officer_label,
        modal_rect.x + PANEL_PAD,
        officer_y,
        modal_rect.w - PANEL_PAD * 2,
        "center"
    )

    local work_tile_x = modal_rect.x + PANEL_PAD
    local work_tile_y = officer_y + orders.officer_font:getHeight() + WORK_TILE_TOP_GAP
    local work_tile_w = modal_rect.w - PANEL_PAD * 2
    local work_text = ("Work / Hour: %d"):format(orders.getWorkPerHour(officer))
    local work_icon_size = orders.officer_font:getHeight()
    local work_icon_gap = 6
    local work_content_w = work_icon_size + work_icon_gap + orders.officer_font:getWidth(work_text)
    local work_content_x = work_tile_x + (work_tile_w - work_content_w) / 2
    local work_content_y = work_tile_y + (WORK_TILE_H - work_icon_size) / 2

    love.graphics.setColor(0.035, 0.033, 0.03, 1)
    love.graphics.rectangle("fill", work_tile_x, work_tile_y, work_tile_w, WORK_TILE_H)
    love.graphics.setColor(OUTLINE_COLOR)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", work_tile_x, work_tile_y, work_tile_w, WORK_TILE_H)
    love.graphics.setLineWidth(1)
    drawInlineIcon(getPopulationIcon(), work_content_x, work_content_y, work_icon_size)
    love.graphics.setColor(TEXT_COLOR)
    love.graphics.print(
        work_text,
        work_content_x + work_icon_size + work_icon_gap,
        work_tile_y + (WORK_TILE_H - orders.officer_font:getHeight()) / 2
    )

    drawOfferings(modal_rect, work_tile_y + WORK_TILE_H + OFFERING_TOP_GAP)
    drawWorkOrder(
        modal_rect,
        options.officer_bounds,
        options.calendar_bounds,
        screen_w,
        screen_h
    )
    drawWorkInvoice(
        options.invoice_preview,
        options.completion_preview,
        options.officer_bounds
    )
    drawCompletionWarning(options.completion_preview, options.officer_bounds)

    love.graphics.setColor(1, 1, 1, 1)
end

return orders

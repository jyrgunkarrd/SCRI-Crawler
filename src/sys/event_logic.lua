local event_definitions = require("data.events")
local dev_contingencies = require("data.dev_contingencies")
local image_loader = require("src.assets.image_loader")
local econ = require("src.sys.econ")
local fate_logic = require("src.sys.fate_logic")
local sfx_logic = require("src.sys.sfx_logic")

local event_logic = {
    active_event = nil,
    active_kind = nil,
    active_commitment = nil,
    title_font = nil,
    text_font = nil,
    receipt_font = nil,
    last_trigger_key = nil,
    animation_elapsed = 0,
    active_elapsed = 0,
    invoice_button_rects = {},
    invoice_pay_enabled = false,
    receipt_panel_rect = nil,
    receipt_viewport_rect = nil,
    receipt_scroll = 0,
    receipt_max_scroll = 0,
    retribution_effect = nil,
}

local FONT_PATH = "assets/fonts/Furore.otf"
local PHASE_EVENT = "Event"
local GENERAL_EVENT_HOURS = {
    [2] = true,
    [7] = true,
}
local MODAL_MAX_W = 620
local MODAL_SCREEN_MARGIN = 48
local MODAL_PADDING = 24
local MODAL_TITLE_FONT_SIZE = 22
local MODAL_TEXT_FONT_SIZE = 16
local MODAL_TITLE_GAP = 20
local MODAL_ENTRY_H = 68
local MODAL_ENTRY_GAP = 10
local MODAL_ENTRY_PADDING = 14
local MODAL_DROP_DISTANCE = 24
local MODAL_DROP_SECONDS = 0.16
local MODAL_TEXT_WIPE_SECONDS = 0.14
local MODAL_COLOR = { 0, 0, 0, 1 }
local MODAL_ENTRY_COLOR = { 0.025, 0.025, 0.03, 1 }
local MODAL_OUTLINE_COLOR = { 1, 1, 1, 1 }
local MODAL_TEXT_COLOR = { 1, 1, 1, 1 }
local DIM_COLOR = { 0, 0, 0, 0.76 }
local MODAL_ANIMATION_SECONDS = MODAL_DROP_SECONDS + MODAL_TEXT_WIPE_SECONDS * 4
local INVOICE_MODAL_MAX_W = 920
local INVOICE_MODAL_H = 410
local INVOICE_PANEL_GAP = 14
local INVOICE_PANEL_PADDING = 20
local INVOICE_RECEIPT_FONT_SIZE = 13
local INVOICE_SECTION_GAP = 14
local INVOICE_SIGNATURE_H = 82
local INVOICE_BUTTON_H = 42
local INVOICE_BUTTON_GAP = 10
local INVOICE_RECEIPT_SCROLL_STEP = 44
local INVOICE_SIGNATURE_COLOR = { 184 / 255, 184 / 255, 184 / 255, 1 }
local INVOICE_PAY_TEXT_COLOR = { 0, 0, 0, 1 }
local INVOICE_DELINQUENCY_TEXT_COLOR = { 1, 1, 1, 1 }
local INVOICE_VALUE_COLOR = { 0, 1, 167 / 255, 1 }
local INVOICE_PAY_COLOR = { 0, 1, 167 / 255, 1 }
local INVOICE_DELINQUENCY_COLOR = { 203 / 255, 0, 14 / 255, 1 }
local INVOICE_WARNING_COLOR = { 1, 67 / 255, 65 / 255, 1 }
local INVOICE_DISABLED_BRIGHTNESS = 0.28
local INVOICE_WARNING_GAP = 10
local INVOICE_WARNING_FLASH_SECONDS = 0.42
local INVOICE_PANEL_DROP_SECONDS = 0.16
local INVOICE_PANEL_DROP_STAGGER = 0.10
local INVOICE_PANEL_ANIMATION_SECONDS = INVOICE_PANEL_DROP_SECONDS + INVOICE_PANEL_DROP_STAGGER
local DELINQUENCY_RISK_MIN = 25
local DELINQUENCY_RISK_MAX = 85
local ADDITIONAL_RETALIATION_CHANCE = 50
local RETALIATION_DAMAGE = 5
local RETALIATION_FATIGUE = 5
local RETRIBUTION_CONTINGENCY_COST = 2
local FATIGUE_TILE_ID = "BSCFATIGUE"
local RETRIBUTION_EFFECT_SECONDS = 0.55
local RETRIBUTION_PANEL_CLOSE_SECONDS = 0.12
local RETRIBUTION_FLASH_SECONDS = 0.20
local RETRIBUTION_EFFECT_COLOR = { 1, 67 / 255, 65 / 255, 1 }
local RETRIBUTION_SCREEN_COLOR = { 203 / 255, 0, 14 / 255, 1 }
local RETRIBUTION_CONTINGENCY_COLOR = { 36 / 255, 208 / 255, 1, 1 }
local SCRATCH_ICON_PATH = "assets/images/icons/scratch.webp"
local SCRATCH_ICON_VISUAL_SCALE = 1.25
local SCRATCH_VALUE_GAP = 5
local scratch_icon = nil

local function clamp01(value)
    return math.max(0, math.min(1, tonumber(value) or 0))
end

local function easeOutCubic(value)
    value = 1 - clamp01(value)

    return 1 - value * value * value
end

local function getAnimationDuration()
    return event_logic.active_kind == "invoice"
        and INVOICE_PANEL_ANIMATION_SECONDS
        or MODAL_ANIMATION_SECONDS
end

local function getWipeProgress(index)
    local start_time = MODAL_DROP_SECONDS + (index - 1) * MODAL_TEXT_WIPE_SECONDS

    return clamp01((event_logic.animation_elapsed - start_time) / MODAL_TEXT_WIPE_SECONDS)
end

local function drawWithHorizontalWipe(x, y, w, h, progress, draw_function)
    progress = easeOutCubic(progress)

    if progress <= 0 then
        return
    end

    if progress >= 1 then
        draw_function()
        return
    end

    love.graphics.push("all")
    love.graphics.setScissor(x, y, w * progress, h)
    draw_function()
    love.graphics.pop()
end

local function getEventList()
    if type(event_definitions) ~= "table" then
        return {}
    end

    return event_definitions.events or event_definitions
end

local function getTriggerKey(calendar_state)
    local season = calendar_state.current_season or {}
    local season_key = calendar_state.season_index or season.id or season.name or "season"

    return tostring(season_key) .. ":" .. tostring(calendar_state.current_hour)
end

local function ensureFonts()
    event_logic.title_font = event_logic.title_font
        or love.graphics.newFont(FONT_PATH, MODAL_TITLE_FONT_SIZE)
    event_logic.text_font = event_logic.text_font
        or love.graphics.newFont(FONT_PATH, MODAL_TEXT_FONT_SIZE)
    event_logic.receipt_font = event_logic.receipt_font
        or love.graphics.newFont(FONT_PATH, INVOICE_RECEIPT_FONT_SIZE)
end

local function getPendingInvoice(calendar_state)
    local hour = math.floor(tonumber(calendar_state and calendar_state.current_hour) or 0)

    for _, commitment in ipairs(calendar_state and calendar_state.commitments or {}) do
        local payable = commitment.payable

        if payable
            and payable.season == "current"
            and payable.hour == hour
            and not payable.resolved
            and type(commitment.invoice) == "table"
        then
            return commitment
        end
    end

    return nil
end

local function pointInRect(x, y, rect)
    return rect
        and x >= rect.x
        and x <= rect.x + rect.w
        and y >= rect.y
        and y <= rect.y + rect.h
end

local function formatAmount(value)
    value = math.max(0, tonumber(value) or 0)

    if math.abs(value - math.floor(value + 0.5)) < 0.000001 then
        return tostring(math.floor(value + 0.5))
    end

    return (string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", ""))
end

local function getScratchIcon()
    if not scratch_icon then
        scratch_icon = image_loader.newImage(SCRATCH_ICON_PATH)
    end

    return scratch_icon
end

local function drawScratchValue(value_text, x, y, w, alignment, font)
    value_text = tostring(value_text or "0")
    font = font or event_logic.text_font

    local icon = getScratchIcon()
    local icon_size = font:getHeight()
    local content_w = icon_size + SCRATCH_VALUE_GAP + font:getWidth(value_text)
    local content_x = x

    if alignment == "right" then
        content_x = x + w - content_w
    elseif alignment == "center" then
        content_x = x + (w - content_w) / 2
    end

    if icon then
        local scale = math.min(icon_size / icon:getWidth(), icon_size / icon:getHeight())
            * SCRATCH_ICON_VISUAL_SCALE

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(
            icon,
            content_x + icon_size / 2,
            y + icon_size / 2,
            0,
            scale,
            scale,
            icon:getWidth() / 2,
            icon:getHeight() / 2
        )
    end

    love.graphics.setFont(font)
    love.graphics.setColor(INVOICE_VALUE_COLOR)
    love.graphics.print(value_text, content_x + icon_size + SCRATCH_VALUE_GAP, y)
end

local function getInvoiceTotalOwed(commitment)
    local invoice = commitment and commitment.invoice or {}
    local total_cost = math.max(0, tonumber(invoice.total_cost) or 0)
    local discount = math.max(0, tonumber(invoice.discount) or 0)

    return math.max(0, total_cost - discount)
end

local function getCommitmentAgent(commitment)
    local agent = commitment and commitment.agent

    return agent and (agent.reference or agent) or nil
end

local function getCommitmentOfficer(commitment)
    local officer = commitment and commitment.officer

    return officer and (officer.reference or officer) or nil
end

local function unlockCommitment(commitment)
    local officer = getCommitmentOfficer(commitment)

    if officer then
        officer.agent_locked = false
        officer.orders_locked = false
    end
end

local function damageAgent(agent, damage)
    if not agent then
        return 0
    end

    agent.runtime_stats = agent.runtime_stats or {}

    if not agent.runtime_stats.hp then
        local maximum = 0

        for _, stat in ipairs(agent.stats or {}) do
            if stat.hp ~= nil then
                maximum = math.max(0, tonumber(stat.hp) or 0)
                break
            end
        end

        agent.runtime_stats.hp = { current = maximum, maximum = maximum }
    end

    local hp = agent.runtime_stats.hp
    local previous = math.max(0, tonumber(hp.current) or 0)

    hp.current = math.max(0, previous - math.max(0, tonumber(damage) or 0))

    return previous - hp.current
end


local function applyRetribution(commitment)
    local officer = getCommitmentOfficer(commitment)
    local agent = getCommitmentAgent(commitment)
    local population = math.max(0, math.floor(tonumber(officer and officer.population) or 0))
    local amount_owed = getInvoiceTotalOwed(commitment)
    local consequence_units = 1 + math.floor(amount_owed / 5)
    local retaliation_units = 1

    for _ = 2, consequence_units do
        if love.math.random(1, 100) <= ADDITIONAL_RETALIATION_CHANCE then
            retaliation_units = retaliation_units + 1
        end
    end

    local eliminated = math.min(population, retaliation_units)
    local unabsorbed_retaliation = retaliation_units - eliminated

    if officer then
        officer.population = population - eliminated
    end

    local damage = unabsorbed_retaliation * RETALIATION_DAMAGE
    local fatigue = unabsorbed_retaliation * RETALIATION_FATIGUE
    local damage_sustained = damageAgent(agent, damage)
    local previous_contingency = math.max(
        0,
        math.floor(tonumber(dev_contingencies.contingency) or 0)
    )
    local contingency_depleted = math.min(previous_contingency, RETRIBUTION_CONTINGENCY_COST)

    dev_contingencies.contingency = previous_contingency - contingency_depleted

    if fatigue > 0 then
        fate_logic.addTiles(agent, FATIGUE_TILE_ID, fatigue)
    end

    return {
        occurred = true,
        amount_owed = amount_owed,
        consequence_units = consequence_units,
        retaliation_units = retaliation_units,
        population_eliminated = eliminated,
        unabsorbed_retaliation = unabsorbed_retaliation,
        damage = damage_sustained,
        fatigue_tiles = fatigue,
        contingency_depleted = contingency_depleted,
    }
end

local function resolveInvoiceAction(calendar_state, action)
    local commitment = event_logic.active_commitment
    local invoice = commitment and commitment.invoice

    if not commitment or not invoice then
        return false
    end

    if action == "pay" then
        local amount = getInvoiceTotalOwed(commitment)

        if not econ.spend(amount) then
            return false
        end

        sfx_logic.playNamed("cash")

        invoice.resolution = {
            kind = "paid",
            amount = amount,
        }
    elseif action == "delinquency" then
        local risk = math.max(
            DELINQUENCY_RISK_MIN,
            math.min(DELINQUENCY_RISK_MAX, math.floor(tonumber(invoice.delinquency_risk) or 0))
        )
        local amount_owed = getInvoiceTotalOwed(commitment)
        local retribution = love.math.random(1, 100) <= risk

        sfx_logic.playNamed(retribution and "retribution" or "skip_pay")

        invoice.resolution = retribution
            and applyRetribution(commitment)
            or {
                occurred = false,
                amount_owed = amount_owed,
                consequence_units = 1 + math.floor(amount_owed / 5),
                retaliation_units = 0,
                population_eliminated = 0,
                unabsorbed_retaliation = 0,
                damage = 0,
                fatigue_tiles = 0,
                contingency_depleted = 0,
            }
        invoice.resolution.kind = "delinquency"
        invoice.resolution.risk = risk

        if retribution then
            event_logic.retribution_effect = {
                elapsed = 0,
                result = invoice.resolution,
                officer = getCommitmentOfficer(commitment),
                agent = getCommitmentAgent(commitment),
            }
        end
    else
        return false
    end

    event_logic.dismiss(calendar_state)

    return true
end

function event_logic.newSeasonSchedule()
    local schedule = {}

    for hour in pairs(GENERAL_EVENT_HOURS) do
        schedule[hour] = true
    end

    return schedule
end

function event_logic.initializeCalendar(calendar_state)
    if not calendar_state then
        return nil
    end

    calendar_state.general_events = calendar_state.general_events or {}
    calendar_state.general_events.current = calendar_state.general_events.current
        or event_logic.newSeasonSchedule()
    calendar_state.general_events.upcoming = calendar_state.general_events.upcoming
        or event_logic.newSeasonSchedule()

    return calendar_state.general_events
end

function event_logic.hasGeneralEvent(calendar_state, season_side, hour)
    local schedules = event_logic.initializeCalendar(calendar_state)
    local schedule = schedules and schedules[season_side or "current"]

    return schedule and schedule[math.floor(tonumber(hour) or 0)] == true or false
end

function event_logic.advanceSeason(calendar_state)
    local schedules = event_logic.initializeCalendar(calendar_state)

    schedules.current = schedules.upcoming or event_logic.newSeasonSchedule()
    schedules.upcoming = event_logic.newSeasonSchedule()
end

function event_logic.resolveCurrentEvent(calendar_state)
    local schedules = event_logic.initializeCalendar(calendar_state)

    if not schedules then
        return false
    end

    local hour = math.floor(tonumber(calendar_state.current_hour) or 0)

    if schedules.current[hour] ~= true then
        return false
    end

    schedules.current[hour] = nil

    return true
end

function event_logic.update(calendar_state, dt)
    if event_logic.retribution_effect then
        event_logic.retribution_effect.elapsed = math.min(
            RETRIBUTION_EFFECT_SECONDS,
            event_logic.retribution_effect.elapsed + math.max(0, tonumber(dt) or 0)
        )

        return false
    end

    if event_logic.active_event then
        event_logic.active_elapsed = event_logic.active_elapsed + math.max(0, tonumber(dt) or 0)
        event_logic.animation_elapsed = math.min(
            getAnimationDuration(),
            event_logic.animation_elapsed + math.max(0, tonumber(dt) or 0)
        )

        return false
    end

    if not calendar_state or calendar_state.current_phase ~= PHASE_EVENT then
        return false
    end

    if event_logic.hasGeneralEvent(calendar_state, "current", calendar_state.current_hour) then
        local trigger_key = getTriggerKey(calendar_state)

        if event_logic.last_trigger_key ~= trigger_key then
            event_logic.last_trigger_key = trigger_key

            local events = getEventList()

            if #events > 0 then
                event_logic.active_event = events[love.math.random(#events)]
                event_logic.active_kind = "general"
                event_logic.active_commitment = nil
                event_logic.animation_elapsed = 0
                event_logic.active_elapsed = 0
                event_logic.invoice_button_rects = {}
                event_logic.invoice_pay_enabled = false
                event_logic.receipt_panel_rect = nil
                event_logic.receipt_viewport_rect = nil
                event_logic.receipt_scroll = 0
                event_logic.receipt_max_scroll = 0

                return true
            end
        end
    end

    local invoice_commitment = getPendingInvoice(calendar_state)

    if not invoice_commitment then
        return false
    end

    event_logic.active_event = invoice_commitment.invoice
    event_logic.active_kind = "invoice"
    event_logic.active_commitment = invoice_commitment
    event_logic.active_event.delinquency_risk = math.max(
        DELINQUENCY_RISK_MIN,
        math.min(
            DELINQUENCY_RISK_MAX,
            math.floor(
                tonumber(event_logic.active_event.delinquency_risk)
                    or love.math.random(DELINQUENCY_RISK_MIN, DELINQUENCY_RISK_MAX)
            )
        )
    )
    event_logic.animation_elapsed = 0
    event_logic.active_elapsed = 0
    event_logic.invoice_button_rects = {}
    event_logic.invoice_pay_enabled = false
    event_logic.receipt_panel_rect = nil
    event_logic.receipt_viewport_rect = nil
    event_logic.receipt_scroll = 0
    event_logic.receipt_max_scroll = 0

    return true
end

function event_logic.isOpen()
    return event_logic.active_event ~= nil
end

function event_logic.getActiveEvent()
    return event_logic.active_event
end

function event_logic.getActiveKind()
    return event_logic.active_kind
end

function event_logic.getHighlightedAgent()
    local agent = event_logic.active_commitment and event_logic.active_commitment.agent

    return event_logic.retribution_effect and event_logic.retribution_effect.agent
        or event_logic.active_kind == "invoice"
        and agent
        and (agent.reference or agent)
        or nil
end

function event_logic.getRetributionEffect()
    return event_logic.retribution_effect
end

function event_logic.isRetributionEffectActive()
    return event_logic.retribution_effect ~= nil
end

function event_logic.mousepressedRetributionEffect()
    local effect = event_logic.retribution_effect

    if not effect then
        return "ignored"
    end

    if effect.elapsed < RETRIBUTION_EFFECT_SECONDS then
        effect.elapsed = RETRIBUTION_EFFECT_SECONDS
        return "skipped"
    end

    event_logic.retribution_effect = nil

    return "dismissed"
end

function event_logic.hasPendingEvents(calendar_state)
    if not calendar_state or calendar_state.current_phase ~= PHASE_EVENT then
        return false
    end

    return event_logic.isOpen()
        or event_logic.isRetributionEffectActive()
        or event_logic.hasGeneralEvent(calendar_state, "current", calendar_state.current_hour)
        or getPendingInvoice(calendar_state) ~= nil
end

function event_logic.isAnimating()
    return event_logic.active_event ~= nil
        and event_logic.animation_elapsed < getAnimationDuration()
end

function event_logic.skipAnimation()
    if not event_logic.isAnimating() then
        return false
    end

    event_logic.animation_elapsed = getAnimationDuration()

    return true
end

function event_logic.dismiss(calendar_state)
    if not event_logic.active_event then
        return false
    end

    if event_logic.active_kind == "invoice" then
        local payable = event_logic.active_commitment and event_logic.active_commitment.payable

        if payable then
            payable.resolved = true
        end

        unlockCommitment(event_logic.active_commitment)
    else
        event_logic.resolveCurrentEvent(calendar_state)
    end

    event_logic.active_event = nil
    event_logic.active_kind = nil
    event_logic.active_commitment = nil
    event_logic.animation_elapsed = 0
    event_logic.active_elapsed = 0
    event_logic.invoice_button_rects = {}
    event_logic.invoice_pay_enabled = false
    event_logic.receipt_panel_rect = nil
    event_logic.receipt_viewport_rect = nil
    event_logic.receipt_scroll = 0
    event_logic.receipt_max_scroll = 0

    return true
end


function event_logic.mousepressed(x, y, button, calendar_state)
    if not event_logic.isOpen() then
        return "ignored"
    end

    if event_logic.skipAnimation() then
        return "skipped"
    end

    if event_logic.active_kind == "invoice" then
        if button == 1 then
            local pay_rect = event_logic.invoice_button_rects.pay
            local delinquency_rect = event_logic.invoice_button_rects.delinquency

            if pointInRect(x, y, pay_rect) then
                if event_logic.invoice_pay_enabled
                    and resolveInvoiceAction(calendar_state, "pay")
                then
                    return "resolved"
                end

                return "consumed"
            end

            if pointInRect(x, y, delinquency_rect)
                and resolveInvoiceAction(calendar_state, "delinquency")
            then
                return "resolved"
            end
        end

        return "consumed"
    end

    event_logic.dismiss(calendar_state)

    return "resolved"
end

function event_logic.wheelmoved(_, y)
    if event_logic.active_kind ~= "invoice" or not event_logic.receipt_panel_rect then
        return false
    end

    local mouse_x, mouse_y = love.mouse.getPosition()

    if not pointInRect(mouse_x, mouse_y, event_logic.receipt_panel_rect) then
        return false
    end

    if y > 0 then
        event_logic.receipt_scroll = math.max(
            0,
            event_logic.receipt_scroll - INVOICE_RECEIPT_SCROLL_STEP
        )
    elseif y < 0 then
        event_logic.receipt_scroll = math.min(
            event_logic.receipt_max_scroll,
            event_logic.receipt_scroll + INVOICE_RECEIPT_SCROLL_STEP
        )
    end

    return true
end

function event_logic.reset()
    event_logic.active_event = nil
    event_logic.active_kind = nil
    event_logic.active_commitment = nil
    event_logic.last_trigger_key = nil
    event_logic.animation_elapsed = 0
    event_logic.active_elapsed = 0
    event_logic.invoice_button_rects = {}
    event_logic.invoice_pay_enabled = false
    event_logic.receipt_panel_rect = nil
    event_logic.receipt_viewport_rect = nil
    event_logic.receipt_scroll = 0
    event_logic.receipt_max_scroll = 0
    event_logic.retribution_effect = nil
end

function event_logic.getModalRect(screen_w, screen_h)
    ensureFonts()

    local width = math.min(MODAL_MAX_W, math.max(1, screen_w - MODAL_SCREEN_MARGIN * 2))
    local height = MODAL_PADDING * 2
        + event_logic.title_font:getHeight()
        + MODAL_TITLE_GAP
        + MODAL_ENTRY_H * 3
        + MODAL_ENTRY_GAP * 2

    return {
        x = (screen_w - width) / 2,
        y = (screen_h - height) / 2,
        w = width,
        h = height,
    }
end

function event_logic.drawDimmer(screen_w, screen_h)
    if not event_logic.active_event then
        return
    end

    love.graphics.setColor(DIM_COLOR)
    love.graphics.rectangle("fill", 0, 0, screen_w, screen_h)
end

local function drawSignature(signature, rect)
    if not signature or type(signature.strokes) ~= "table" then
        return
    end

    local inset = 5
    local draw_x = rect.x + inset
    local draw_y = rect.y + inset
    local draw_w = math.max(1, rect.w - inset * 2)
    local draw_h = math.max(1, rect.h - inset * 2)

    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.setLineWidth(2)

    for _, stroke in ipairs(signature.strokes) do
        if #stroke == 1 then
            local point = stroke[1]

            love.graphics.circle(
                "fill",
                draw_x + point.x * draw_w,
                draw_y + point.y * draw_h,
                1
            )
        elseif #stroke > 1 then
            local vertices = {}

            for _, point in ipairs(stroke) do
                vertices[#vertices + 1] = draw_x + point.x * draw_w
                vertices[#vertices + 1] = draw_y + point.y * draw_h
            end

            love.graphics.line(vertices)
        end
    end

    love.graphics.setLineWidth(1)
end

local function getInvoicePanelRects(screen_w, screen_h)
    local total_w = math.min(INVOICE_MODAL_MAX_W, math.max(2, screen_w - MODAL_SCREEN_MARGIN * 2))
    local panel_w = (total_w - INVOICE_PANEL_GAP) / 2
    local panel_h = math.min(INVOICE_MODAL_H, math.max(1, screen_h - MODAL_SCREEN_MARGIN * 2))
    local start_x = (screen_w - total_w) / 2
    local panel_y = (screen_h - panel_h) / 2

    return {
        receipt = { x = start_x, y = panel_y, w = panel_w, h = panel_h },
        payment = {
            x = start_x + panel_w + INVOICE_PANEL_GAP,
            y = panel_y,
            w = panel_w,
            h = panel_h,
        },
    }
end

function event_logic.drawRetributionEffect(screen_w, screen_h, officer_rect, agent_rect)
    local effect = event_logic.retribution_effect

    if not effect then
        return
    end

    ensureFonts()

    local elapsed = effect.elapsed
    local effect_progress = clamp01(elapsed / RETRIBUTION_EFFECT_SECONDS)
    local close_progress = clamp01(elapsed / RETRIBUTION_PANEL_CLOSE_SECONDS)

    if close_progress < 1 then
        local alpha = 1 - close_progress
        local scale = 1 - close_progress * 0.08
        local panel_rects = getInvoicePanelRects(screen_w, screen_h)

        for _, rect in pairs(panel_rects) do
            local draw_w = rect.w * scale
            local draw_h = rect.h * scale
            local draw_x = rect.x + (rect.w - draw_w) / 2
            local draw_y = rect.y + (rect.h - draw_h) / 2

            love.graphics.setColor(0, 0, 0, alpha)
            love.graphics.rectangle("fill", draw_x, draw_y, draw_w, draw_h)
            love.graphics.setColor(1, 1, 1, alpha)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", draw_x, draw_y, draw_w, draw_h)
            love.graphics.setLineWidth(1)
        end
    end

    local flash_progress = clamp01(elapsed / RETRIBUTION_FLASH_SECONDS)
    local flash_alpha = (1 - flash_progress) * 0.42

    if flash_alpha > 0 then
        love.graphics.setColor(
            RETRIBUTION_SCREEN_COLOR[1],
            RETRIBUTION_SCREEN_COLOR[2],
            RETRIBUTION_SCREEN_COLOR[3],
            flash_alpha
        )
        love.graphics.rectangle("fill", 0, 0, screen_w, screen_h)
    end

    local outline_pulse = math.abs(math.sin(effect_progress * math.pi * 2))
    local outline_alpha = outline_pulse * (1 - clamp01((elapsed - 0.40) / 0.15))

    for _, rect in ipairs({ officer_rect, agent_rect }) do
        if rect and outline_alpha > 0 then
            local inset = 5

            love.graphics.setColor(
                RETRIBUTION_EFFECT_COLOR[1],
                RETRIBUTION_EFFECT_COLOR[2],
                RETRIBUTION_EFFECT_COLOR[3],
                outline_alpha
            )
            love.graphics.setLineWidth(4)
            love.graphics.rectangle(
                "line",
                rect.x - inset,
                rect.y - inset,
                rect.w + inset * 2,
                rect.h + inset * 2
            )
            love.graphics.setLineWidth(1)
        end
    end

    local settled = elapsed >= RETRIBUTION_EFFECT_SECONDS
    local text_alpha = clamp01((elapsed - 0.04) / 0.08)

    if text_alpha > 0 then
        local result = effect.result or {}
        local lines = {}

        if math.max(0, math.floor(tonumber(result.population_eliminated) or 0)) > 0 then
            lines[#lines + 1] = {
                text = "-" .. tostring(result.population_eliminated) .. " POP",
                color = RETRIBUTION_EFFECT_COLOR,
            }
        end

        if math.max(0, math.floor(tonumber(result.damage) or 0)) > 0 then
            lines[#lines + 1] = {
                text = "-" .. tostring(result.damage) .. " HP",
                color = RETRIBUTION_EFFECT_COLOR,
            }
        end

        if math.max(0, math.floor(tonumber(result.fatigue_tiles) or 0)) > 0 then
            lines[#lines + 1] = {
                text = "+" .. tostring(result.fatigue_tiles) .. " FATIGUE",
                color = RETRIBUTION_EFFECT_COLOR,
            }
        end

        if math.max(0, math.floor(tonumber(result.contingency_depleted) or 0)) > 0 then
            lines[#lines + 1] = {
                text = "-" .. tostring(result.contingency_depleted) .. " CONTINGENCY",
                color = RETRIBUTION_CONTINGENCY_COLOR,
            }
        end

        local shake = settled and 0 or math.sin(elapsed * 78) * 6 * (1 - effect_progress)
        local title_y = screen_h / 2 - event_logic.title_font:getHeight() - 8
        local title_h = event_logic.title_font:getHeight()
        local line_h = event_logic.text_font:getHeight()
        local content_w = event_logic.title_font:getWidth("RETRIBUTION")
        local content_h = title_h

        for _, line in ipairs(lines) do
            content_w = math.max(content_w, event_logic.text_font:getWidth(line.text))
            content_h = content_h + 5 + line_h
        end

        local backing_padding_x = 20
        local backing_padding_y = 15
        local backing_w = content_w + backing_padding_x * 2
        local backing_h = content_h + backing_padding_y * 2
        local backing_x = (screen_w - backing_w) / 2 + shake
        local backing_y = title_y - backing_padding_y

        love.graphics.setColor(0, 0, 0, 0.96 * text_alpha)
        love.graphics.rectangle("fill", backing_x, backing_y, backing_w, backing_h)

        love.graphics.setFont(event_logic.title_font)
        love.graphics.setColor(
            RETRIBUTION_EFFECT_COLOR[1],
            RETRIBUTION_EFFECT_COLOR[2],
            RETRIBUTION_EFFECT_COLOR[3],
            text_alpha
        )
        love.graphics.printf("RETRIBUTION", shake, title_y, screen_w, "center")

        love.graphics.setFont(event_logic.text_font)

        for index, line in ipairs(lines) do
            love.graphics.setColor(line.color[1], line.color[2], line.color[3], text_alpha)
            love.graphics.printf(
                line.text,
                shake,
                title_y + event_logic.title_font:getHeight() + 8
                    + (index - 1) * (event_logic.text_font:getHeight() + 5),
                screen_w,
                "center"
            )
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

local function drawInvoicePanelBacking(rect, title)
    love.graphics.setColor(MODAL_COLOR)
    love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
    love.graphics.setColor(MODAL_OUTLINE_COLOR)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h)
    love.graphics.setLineWidth(1)
    love.graphics.setFont(event_logic.title_font)
    love.graphics.setColor(MODAL_TEXT_COLOR)
    love.graphics.printf(
        title,
        rect.x + INVOICE_PANEL_PADDING,
        rect.y + INVOICE_PANEL_PADDING,
        rect.w - INVOICE_PANEL_PADDING * 2,
        "center"
    )
end

local function drawInvoiceModal(screen_w, screen_h)
    ensureFonts()

    local commitment = event_logic.active_commitment or {}
    local invoice = commitment.invoice or {}
    local work_order = commitment.work_order or {}
    local rects = getInvoicePanelRects(screen_w, screen_h)
    local receipt_drop = easeOutCubic(
        event_logic.animation_elapsed / INVOICE_PANEL_DROP_SECONDS
    )
    local payment_drop = easeOutCubic(
        (event_logic.animation_elapsed - INVOICE_PANEL_DROP_STAGGER)
            / INVOICE_PANEL_DROP_SECONDS
    )

    rects.receipt.y = rects.receipt.y - MODAL_DROP_DISTANCE * (1 - receipt_drop)
    rects.payment.y = rects.payment.y - MODAL_DROP_DISTANCE * (1 - payment_drop)

    local total_cost = math.max(0, tonumber(invoice.total_cost) or 0)
    local discount = math.max(0, tonumber(invoice.discount) or 0)
    local total_owed = math.max(0, total_cost - discount)

    drawInvoicePanelBacking(rects.receipt, "RECEIPT")
    drawInvoicePanelBacking(rects.payment, "PAYMENT CONFIRMATION")

    local receipt_x = rects.receipt.x + INVOICE_PANEL_PADDING
    local receipt_w = rects.receipt.w - INVOICE_PANEL_PADDING * 2
    local item_start_y = rects.receipt.y
        + INVOICE_PANEL_PADDING
        + event_logic.title_font:getHeight()
        + INVOICE_SECTION_GAP
    local total_y = rects.receipt.y + rects.receipt.h - INVOICE_PANEL_PADDING
        - event_logic.text_font:getHeight()
    local summary_top = discount > 0
        and total_y - event_logic.text_font:getHeight() - 8
        or total_y
    local viewport_bottom = summary_top - INVOICE_SECTION_GAP
    local viewport_h = math.max(0, viewport_bottom - item_start_y)
    local receipt_items = {}

    for _, item in ipairs(work_order.items or {}) do
        if math.max(0, tonumber(item.cost) or 0) > 0 then
            receipt_items[#receipt_items + 1] = item
        end
    end

    local item_row_h = event_logic.receipt_font:getHeight() + 5
    local item_content_h = #receipt_items * item_row_h

    event_logic.receipt_panel_rect = rects.receipt
    event_logic.receipt_viewport_rect = {
        x = receipt_x,
        y = item_start_y,
        w = receipt_w,
        h = viewport_h,
    }
    event_logic.receipt_max_scroll = math.max(0, item_content_h - viewport_h)
    event_logic.receipt_scroll = math.max(
        0,
        math.min(event_logic.receipt_scroll, event_logic.receipt_max_scroll)
    )

    love.graphics.setFont(event_logic.receipt_font)
    love.graphics.push("all")
    love.graphics.setScissor(receipt_x, item_start_y, receipt_w, viewport_h)

    local item_y = item_start_y - event_logic.receipt_scroll

    for _, item in ipairs(receipt_items) do
        local cost = math.max(0, tonumber(item.cost) or 0)
        local label = "- " .. tostring(item.name or item.equipment_id or "Equipment")
        local cost_text = formatAmount(cost)

        love.graphics.setColor(MODAL_TEXT_COLOR)
        love.graphics.print(label, receipt_x, item_y)
        drawScratchValue(
            cost_text,
            receipt_x,
            item_y,
            receipt_w,
            "right",
            event_logic.receipt_font
        )
        item_y = item_y + item_row_h
    end

    love.graphics.pop()

    love.graphics.setFont(event_logic.text_font)
    love.graphics.setColor(MODAL_TEXT_COLOR)
    love.graphics.print("TOTAL OWING", receipt_x, total_y)

    local total_text = formatAmount(total_owed)

    drawScratchValue(
        total_text,
        receipt_x,
        total_y,
        receipt_w,
        "right",
        event_logic.text_font
    )

    if discount > 0 then
        local discount_y = total_y - event_logic.text_font:getHeight() - 8
        local discount_text = "-" .. formatAmount(discount)

        love.graphics.setColor(MODAL_TEXT_COLOR)
        love.graphics.print("DISCOUNT", receipt_x, discount_y)
        drawScratchValue(
            discount_text,
            receipt_x,
            discount_y,
            receipt_w,
            "right",
            event_logic.text_font
        )
    end

    local payment_x = rects.payment.x + INVOICE_PANEL_PADDING
    local payment_w = rects.payment.w - INVOICE_PANEL_PADDING * 2
    local payment_y = rects.payment.y
        + INVOICE_PANEL_PADDING
        + event_logic.title_font:getHeight()
        + INVOICE_SECTION_GAP

    love.graphics.setColor(MODAL_TEXT_COLOR)
    love.graphics.printf("TOTAL AMOUNT OWED", payment_x, payment_y, payment_w, "center")
    drawScratchValue(
        formatAmount(total_owed),
        payment_x,
        payment_y + event_logic.text_font:getHeight() + 6,
        payment_w,
        "center",
        event_logic.title_font
    )

    love.graphics.setFont(event_logic.receipt_font)

    local signature_y = payment_y + event_logic.text_font:getHeight()
        + event_logic.title_font:getHeight() + 34
    local signature_rect = {
        x = payment_x,
        y = signature_y,
        w = payment_w,
        h = INVOICE_SIGNATURE_H,
    }

    love.graphics.setColor(MODAL_TEXT_COLOR)
    love.graphics.print("SIGNATURE OF CERTIFICATION", signature_rect.x, signature_rect.y - event_logic.receipt_font:getHeight() - 5)
    love.graphics.setColor(INVOICE_SIGNATURE_COLOR)
    love.graphics.rectangle("fill", signature_rect.x, signature_rect.y, signature_rect.w, signature_rect.h)
    drawSignature(invoice.signature, signature_rect)

    local button_y = rects.payment.y + rects.payment.h - INVOICE_PANEL_PADDING - INVOICE_BUTTON_H
    local button_w = (payment_w - INVOICE_BUTTON_GAP) / 2

    event_logic.invoice_button_rects = {
        pay = { x = payment_x, y = button_y, w = button_w, h = INVOICE_BUTTON_H },
        delinquency = {
            x = payment_x + button_w + INVOICE_BUTTON_GAP,
            y = button_y,
            w = button_w,
            h = INVOICE_BUTTON_H,
        },
    }
    event_logic.invoice_pay_enabled = econ.canAfford(total_owed)

    love.graphics.setFont(event_logic.receipt_font)

    local pay_rect = event_logic.invoice_button_rects.pay
    local pay_brightness = event_logic.invoice_pay_enabled and 1 or INVOICE_DISABLED_BRIGHTNESS

    love.graphics.setColor(
        INVOICE_PAY_COLOR[1] * pay_brightness,
        INVOICE_PAY_COLOR[2] * pay_brightness,
        INVOICE_PAY_COLOR[3] * pay_brightness,
        1
    )
    love.graphics.rectangle("fill", pay_rect.x, pay_rect.y, pay_rect.w, pay_rect.h)
    love.graphics.setColor(
        INVOICE_PAY_TEXT_COLOR[1],
        INVOICE_PAY_TEXT_COLOR[2],
        INVOICE_PAY_TEXT_COLOR[3],
        1
    )
    love.graphics.printf(
        "Pay Invoice",
        pay_rect.x,
        pay_rect.y + (pay_rect.h - event_logic.receipt_font:getHeight()) / 2,
        pay_rect.w,
        "center"
    )

    local delinquency_rect = event_logic.invoice_button_rects.delinquency

    love.graphics.setColor(INVOICE_DELINQUENCY_COLOR)
    love.graphics.rectangle(
        "fill",
        delinquency_rect.x,
        delinquency_rect.y,
        delinquency_rect.w,
        delinquency_rect.h
    )
    love.graphics.setColor(INVOICE_DELINQUENCY_TEXT_COLOR)
    love.graphics.printf(
        "Delinquency",
        delinquency_rect.x,
        delinquency_rect.y + (delinquency_rect.h - event_logic.receipt_font:getHeight()) / 2,
        delinquency_rect.w,
        "center"
    )

    local mouse_x, mouse_y = love.mouse.getPosition()

    if pointInRect(mouse_x, mouse_y, delinquency_rect) then
        local risk = math.floor(tonumber(invoice.delinquency_risk) or DELINQUENCY_RISK_MIN)
        local pulse = 0.5 + 0.5 * math.sin(
            event_logic.active_elapsed * math.pi * 2 / INVOICE_WARNING_FLASH_SECONDS
        )
        local warning_alpha = 0.28 + pulse * 0.72
        local warning = ("THERE IS %d%% CHANCE OF DELINQUENCY CAUSING RETRIBUTION"):format(risk)
        local warning_x = rects.receipt.x
        local warning_w = rects.payment.x + rects.payment.w - warning_x
        local warning_y = rects.receipt.y + rects.receipt.h + INVOICE_WARNING_GAP

        love.graphics.setColor(
            INVOICE_WARNING_COLOR[1],
            INVOICE_WARNING_COLOR[2],
            INVOICE_WARNING_COLOR[3],
            warning_alpha
        )
        love.graphics.printf(warning, warning_x, warning_y, warning_w, "center")
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function event_logic.drawModal(screen_w, screen_h)
    local active_event = event_logic.active_event

    if not active_event then
        return
    end

    if event_logic.active_kind == "invoice" then
        drawInvoiceModal(screen_w, screen_h)
        return
    end

    local rect = event_logic.getModalRect(screen_w, screen_h)
    local drop_progress = easeOutCubic(event_logic.animation_elapsed / MODAL_DROP_SECONDS)
    local drop_offset = -MODAL_DROP_DISTANCE * (1 - drop_progress)

    rect.y = rect.y + drop_offset

    local content_x = rect.x + MODAL_PADDING
    local content_w = rect.w - MODAL_PADDING * 2
    local title_y = rect.y + MODAL_PADDING
    local title_text = active_event.name or active_event.ID or "Event"
    local title_w = math.min(content_w, event_logic.title_font:getWidth(title_text))
    local title_x = content_x + (content_w - title_w) / 2

    love.graphics.setColor(MODAL_COLOR)
    love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
    love.graphics.setColor(MODAL_OUTLINE_COLOR)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h)
    love.graphics.setLineWidth(1)

    love.graphics.setFont(event_logic.title_font)
    love.graphics.setColor(MODAL_TEXT_COLOR)
    drawWithHorizontalWipe(
        title_x,
        title_y,
        title_w,
        event_logic.title_font:getHeight(),
        getWipeProgress(1),
        function()
            love.graphics.printf(
                title_text,
                content_x,
                title_y,
                content_w,
                "center"
            )
        end
    )

    love.graphics.setFont(event_logic.text_font)

    local entry_y = title_y + event_logic.title_font:getHeight() + MODAL_TITLE_GAP

    for index = 1, 3 do
        local text = tostring(active_event["text" .. index] or "")

        love.graphics.setColor(MODAL_ENTRY_COLOR)
        love.graphics.rectangle("fill", content_x, entry_y, content_w, MODAL_ENTRY_H)
        love.graphics.setColor(MODAL_TEXT_COLOR)
        drawWithHorizontalWipe(
            content_x + MODAL_ENTRY_PADDING,
            entry_y + MODAL_ENTRY_PADDING,
            content_w - MODAL_ENTRY_PADDING * 2,
            MODAL_ENTRY_H - MODAL_ENTRY_PADDING * 2,
            getWipeProgress(index + 1),
            function()
                love.graphics.printf(
                    text,
                    content_x + MODAL_ENTRY_PADDING,
                    entry_y + MODAL_ENTRY_PADDING,
                    content_w - MODAL_ENTRY_PADDING * 2,
                    "left"
                )
            end
        )

        entry_y = entry_y + MODAL_ENTRY_H + MODAL_ENTRY_GAP
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return event_logic

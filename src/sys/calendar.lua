local image_loader = require("src.assets.image_loader")
local season_data = require("data.seasons")
local event_logic = require("src.sys.event_logic")

local calendar = {}

local ICON_PATH = "assets/images/icons/calendar.webp"
local FONT_PATH = "assets/fonts/Furore.otf"
local HOURS_PER_SEASON = 12
local PHASE_START = "Start"
local PHASE_EVENT = "Event"
local PHASE_COMMAND = "Command"
local PHASE_END = "End"
local AUTO_PHASE_DELAY = 0.2
local COLUMNS = 6
local ROWS = 2
local TILE_SIZE = 46
local TILE_GAP = 5
local SECTION_ICON_GAP = 22
local ICON_SIZE = 64
local BOTTOM_MARGIN = 24
local LABEL_GAP = 8
local LABEL_FONT_SIZE = 15
local HOUR_FONT_SIZE = 12
local PHASE_LABELS = { "Start", "Event", "Command", "End" }
local PHASE_TILE_W = 112
local PHASE_TILE_H = 30
local PHASE_TILE_GAP = 8
local PHASE_TRACKER_GAP = 14
local PHASE_FONT_SIZE = 14
local HOUR_MARKER_SIZE = 12
local WORK_PREVIEW_MIN_SIZE = 12
local WORK_PREVIEW_MAX_SIZE = 22
local WORK_COMMITTED_SIZE = 18
local WORK_PREVIEW_PULSE_SECONDS = 0.30
local INVOICE_PREVIEW_MIN_SIZE = 12
local INVOICE_PREVIEW_MAX_SIZE = 22
local INVOICE_COMMITTED_SIZE = 18
local INVOICE_PREVIEW_PULSE_SECONDS = 0.30
local GENERAL_EVENT_SIZE = 18
local GENERAL_EVENT_SHARED_SIZE = 13
local GENERAL_EVENT_SHARED_MARGIN = 5
local SHARED_PREVIEW_SCALE = 0.78
local SHARED_PREVIEW_MARGIN = 5
local OUTLINE_WIDTH = 2
local NEXT_SEASON_BRIGHTNESS = 0.35
local WORK_PREVIEW_COLOR = { 249 / 255, 161 / 255, 1 / 255, 1 }
local INVOICE_PREVIEW_COLOR = { 1, 0, 73 / 255, 1 }
local GENERAL_EVENT_COLOR = { 36 / 255, 208 / 255, 1, 1 }

local function chooseSeason(excluded_season, additionally_excluded_season)
    local seasons = season_data.seasons or {}

    if #seasons == 0 then
        return { id = "UNKNOWN", name = "Unknown Season" }
    end

    if #seasons == 1 then
        return seasons[1]
    end

    local season = seasons[love.math.random(#seasons)]

    while season == excluded_season
        or (#seasons > 2 and season == additionally_excluded_season)
    do
        season = seasons[love.math.random(#seasons)]
    end

    return season
end

local function getLayout(screen_w, screen_h, label_font)
    local section_w = COLUMNS * TILE_SIZE + (COLUMNS - 1) * TILE_GAP
    local grid_h = ROWS * TILE_SIZE + (ROWS - 1) * TILE_GAP
    local total_w = section_w * 2 + ICON_SIZE + SECTION_ICON_GAP * 2
    local grid_y = screen_h - BOTTOM_MARGIN - grid_h
    local start_x = (screen_w - total_w) / 2

    return {
        start_x = start_x,
        total_w = total_w,
        current_x = start_x,
        upcoming_x = start_x + section_w + SECTION_ICON_GAP * 2 + ICON_SIZE,
        section_w = section_w,
        grid_y = grid_y,
        grid_h = grid_h,
        icon_x = start_x + section_w + SECTION_ICON_GAP,
        icon_y = grid_y + (grid_h - ICON_SIZE) / 2,
        label_y = grid_y - LABEL_GAP - label_font:getHeight(),
    }
end

function calendar.getVisualBounds(state, screen_w, screen_h)
    if not state then
        return nil
    end

    screen_w = screen_w or love.graphics.getWidth()
    screen_h = screen_h or love.graphics.getHeight()

    local layout = getLayout(screen_w, screen_h, state.label_font)
    local tracker_y = layout.label_y - PHASE_TRACKER_GAP - PHASE_TILE_H

    return {
        x = layout.start_x,
        y = tracker_y,
        w = layout.total_w,
        h = screen_h - tracker_y,
        season_label_y = layout.label_y,
    }
end

local function drawPhaseTracker(state, layout, screen_w)
    local total_w = #PHASE_LABELS * PHASE_TILE_W + (#PHASE_LABELS - 1) * PHASE_TILE_GAP
    local start_x = (screen_w - total_w) / 2
    local tracker_y = layout.label_y - PHASE_TRACKER_GAP - PHASE_TILE_H

    love.graphics.setFont(state.phase_font)

    for index, label in ipairs(PHASE_LABELS) do
        local tile_x = start_x + (index - 1) * (PHASE_TILE_W + PHASE_TILE_GAP)
        local is_current = label == state.current_phase

        love.graphics.setColor(is_current and 0 or 1, is_current and 0 or 1, is_current and 0 or 1, 1)
        love.graphics.rectangle("fill", tile_x, tracker_y, PHASE_TILE_W, PHASE_TILE_H)
        love.graphics.setColor(is_current and 1 or 0, is_current and 1 or 0, is_current and 1 or 0, 1)
        love.graphics.printf(
            label,
            tile_x,
            tracker_y + (PHASE_TILE_H - state.phase_font:getHeight()) / 2,
            PHASE_TILE_W,
            "center"
        )

        if is_current then
            love.graphics.setLineWidth(OUTLINE_WIDTH)
            love.graphics.rectangle("line", tile_x, tracker_y, PHASE_TILE_W, PHASE_TILE_H)
            love.graphics.setLineWidth(1)
        end
    end
end

local function getCommittedMarkers(state, season_side, hour)
    local work_marker = false
    local invoice_marker = false

    for _, commitment in ipairs(state.commitments or {}) do
        local completion = commitment.completion
        local payable = commitment.payable

        if completion and completion.season == season_side and completion.hour == hour then
            work_marker = true
        end

        if payable
            and payable.season == season_side
            and payable.hour == hour
            and not payable.resolved
        then
            invoice_marker = true
        end
    end

    return work_marker, invoice_marker
end

local function drawSection(
    state,
    season,
    season_side,
    start_x,
    layout,
    brightness,
    marked_hour,
    preview_hour,
    preview_elapsed,
    invoice_hour,
    invoice_elapsed
)
    love.graphics.setFont(state.label_font)
    love.graphics.setColor(brightness, brightness, brightness, 1)
    love.graphics.printf(season.name or season.id or "Unknown Season", start_x, layout.label_y, layout.section_w, "center")

    love.graphics.setLineWidth(OUTLINE_WIDTH)

    for hour = 1, HOURS_PER_SEASON do
        local column = (hour - 1) % COLUMNS
        local row = math.floor((hour - 1) / COLUMNS)
        local tile_x = start_x + column * (TILE_SIZE + TILE_GAP)
        local tile_y = layout.grid_y + row * (TILE_SIZE + TILE_GAP)
        local hour_text = tostring(hour)
        local committed_work, committed_invoice = getCommittedMarkers(state, season_side, hour)
        local show_work_marker = hour == preview_hour or committed_work
        local show_invoice_marker = hour == invoice_hour or committed_invoice
        local show_general_event = event_logic.hasGeneralEvent(state, season_side, hour)
        local markers_share_cell = show_work_marker and show_invoice_marker

        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.rectangle("fill", tile_x, tile_y, TILE_SIZE, TILE_SIZE)
        love.graphics.setColor(brightness, brightness, brightness, 1)
        love.graphics.rectangle("line", tile_x, tile_y, TILE_SIZE, TILE_SIZE)

        if show_general_event then
            local marker_size = GENERAL_EVENT_SIZE
            local marker_x = tile_x + TILE_SIZE / 2
            local marker_y = tile_y + TILE_SIZE / 2

            if show_work_marker or show_invoice_marker then
                marker_size = GENERAL_EVENT_SHARED_SIZE
                marker_x = tile_x + GENERAL_EVENT_SHARED_MARGIN + marker_size / 2
                marker_y = tile_y + TILE_SIZE - GENERAL_EVENT_SHARED_MARGIN - marker_size / 2
            end

            love.graphics.setColor(GENERAL_EVENT_COLOR)
            love.graphics.circle("fill", marker_x, marker_y, marker_size / 2)
        end

        if hour == marked_hour then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.rectangle(
                "fill",
                tile_x + (TILE_SIZE - HOUR_MARKER_SIZE) / 2,
                tile_y + (TILE_SIZE - HOUR_MARKER_SIZE) / 2,
                HOUR_MARKER_SIZE,
                HOUR_MARKER_SIZE
            )
        end

        if show_work_marker then
            local marker_size = WORK_COMMITTED_SIZE

            if hour == preview_hour then
                local pulse = 0.5 + 0.5 * math.sin(
                    (tonumber(preview_elapsed) or 0) * math.pi * 2 / WORK_PREVIEW_PULSE_SECONDS
                )

                marker_size = WORK_PREVIEW_MIN_SIZE
                    + (WORK_PREVIEW_MAX_SIZE - WORK_PREVIEW_MIN_SIZE) * pulse
            end

            local marker_x = tile_x + (TILE_SIZE - marker_size) / 2
            local marker_y = tile_y + (TILE_SIZE - marker_size) / 2

            if markers_share_cell or show_general_event then
                marker_size = marker_size * SHARED_PREVIEW_SCALE
                marker_x = tile_x + TILE_SIZE - SHARED_PREVIEW_MARGIN - marker_size
                marker_y = tile_y + TILE_SIZE - SHARED_PREVIEW_MARGIN - marker_size
            end

            love.graphics.setColor(WORK_PREVIEW_COLOR)
            love.graphics.rectangle(
                "fill",
                marker_x,
                marker_y,
                marker_size,
                marker_size
            )
        end

        if show_invoice_marker then
            local marker_size = INVOICE_COMMITTED_SIZE

            if hour == invoice_hour then
                local pulse = 0.5 + 0.5 * math.sin(
                    (tonumber(invoice_elapsed) or 0) * math.pi * 2 / INVOICE_PREVIEW_PULSE_SECONDS
                )

                marker_size = INVOICE_PREVIEW_MIN_SIZE
                    + (INVOICE_PREVIEW_MAX_SIZE - INVOICE_PREVIEW_MIN_SIZE) * pulse
            end

            local center_x = tile_x + TILE_SIZE / 2
            local center_y = tile_y + TILE_SIZE / 2

            if markers_share_cell or show_general_event then
                marker_size = marker_size * SHARED_PREVIEW_SCALE
                center_x = tile_x + SHARED_PREVIEW_MARGIN + marker_size / 2
                center_y = tile_y + SHARED_PREVIEW_MARGIN + marker_size / 2
            end

            love.graphics.setColor(INVOICE_PREVIEW_COLOR)
            love.graphics.polygon(
                "fill",
                center_x,
                center_y - marker_size / 2,
                center_x - marker_size / 2,
                center_y + marker_size / 2,
                center_x + marker_size / 2,
                center_y + marker_size / 2
            )
        end

        love.graphics.setFont(state.hour_font)
        love.graphics.setColor(brightness, brightness, brightness, 1)
        love.graphics.print(
            hour_text,
            tile_x + TILE_SIZE - state.hour_font:getWidth(hour_text) - 4,
            tile_y + 2
        )
    end

    love.graphics.setLineWidth(1)
end

function calendar.new()
    local current_season = chooseSeason()

    return {
        current_season = current_season,
        upcoming_season = chooseSeason(current_season),
        current_hour = 1,
        current_phase = PHASE_START,
        phase_elapsed = 0,
        season_index = 1,
        general_events = {
            current = event_logic.newSeasonSchedule(),
            upcoming = event_logic.newSeasonSchedule(),
        },
        commitments = {},
        next_commitment_id = 1,
        icon = image_loader.newImage(ICON_PATH),
        label_font = love.graphics.newFont(FONT_PATH, LABEL_FONT_SIZE),
        hour_font = love.graphics.newFont(FONT_PATH, HOUR_FONT_SIZE),
        phase_font = love.graphics.newFont(FONT_PATH, PHASE_FONT_SIZE),
    }
end

local function advanceHour(state)
    if state.current_hour < HOURS_PER_SEASON then
        state.current_hour = state.current_hour + 1
        return
    end

    local dismissed_season = state.current_season

    for _, commitment in ipairs(state.commitments or {}) do
        for _, marker in ipairs({ commitment.completion, commitment.payable }) do
            if marker then
                if marker.season == "upcoming" then
                    marker.season = "current"
                elseif marker.season == "current" then
                    marker.season = "past"
                end
            end
        end
    end

    state.current_season = state.upcoming_season
    state.upcoming_season = chooseSeason(state.current_season, dismissed_season)
    state.current_hour = 1
    state.season_index = math.max(1, math.floor(tonumber(state.season_index) or 1)) + 1
    event_logic.advanceSeason(state)
end

local function enterPhase(state, phase)
    state.current_phase = phase
    state.phase_elapsed = 0

    if phase == PHASE_START then
        advanceHour(state)
    end
end

function calendar.update(state, dt, options)
    options = options or {}

    if not state or state.current_phase == PHASE_COMMAND then
        return
    end

    if state.current_phase == PHASE_EVENT and options.pause_event_phase then
        return
    end

    state.phase_elapsed = state.phase_elapsed + math.max(tonumber(dt) or 0, 0)

    if state.phase_elapsed < AUTO_PHASE_DELAY then
        return
    end

    if state.current_phase == PHASE_START then
        enterPhase(state, PHASE_EVENT)
    elseif state.current_phase == PHASE_EVENT then
        enterPhase(state, PHASE_COMMAND)
    elseif state.current_phase == PHASE_END then
        enterPhase(state, PHASE_START)
    end
end

function calendar.completeEventPhase(state)
    if not state or state.current_phase ~= PHASE_EVENT then
        return false
    end

    enterPhase(state, PHASE_COMMAND)

    return true
end

function calendar.endCommandPhase(state)
    if not state or state.current_phase ~= PHASE_COMMAND then
        return false
    end

    enterPhase(state, PHASE_END)

    return true
end

function calendar.isCommandPhase(state)
    return state and state.current_phase == PHASE_COMMAND or false
end

function calendar.commitOrder(state, commitment)
    if not state or type(commitment) ~= "table" then
        return nil
    end

    state.commitments = state.commitments or {}
    state.next_commitment_id = math.max(1, math.floor(tonumber(state.next_commitment_id) or 1))
    commitment.id = state.next_commitment_id
    state.next_commitment_id = state.next_commitment_id + 1
    state.commitments[#state.commitments + 1] = commitment

    return commitment
end

function calendar.getCommittedOrders(state)
    return state and state.commitments or {}
end

function calendar.getCellRecords(state, season_side, hour)
    local records = {}

    hour = math.floor(tonumber(hour) or 0)

    for _, commitment in ipairs(state and state.commitments or {}) do
        if commitment.completion
            and commitment.completion.season == season_side
            and commitment.completion.hour == hour
        then
            records[#records + 1] = {
                kind = "work_order",
                commitment = commitment,
                data = commitment.work_order,
            }
        end

        if commitment.payable
            and commitment.payable.season == season_side
            and commitment.payable.hour == hour
            and not commitment.payable.resolved
        then
            records[#records + 1] = {
                kind = "invoice",
                commitment = commitment,
                data = commitment.invoice,
            }
        end
    end

    return records
end

function calendar.draw(state, screen_w, screen_h, options)
    if not state then
        return
    end

    screen_w = screen_w or love.graphics.getWidth()
    screen_h = screen_h or love.graphics.getHeight()
    options = options or {}

    local layout = getLayout(screen_w, screen_h, state.label_font)
    local preview = options.completion_preview
    local invoice_preview = options.invoice_preview
    local current_preview_hour = preview
        and not preview.exceeds_window
        and preview.season == "current"
        and preview.hour
        or nil
    local upcoming_preview_hour = preview
        and not preview.exceeds_window
        and preview.season == "upcoming"
        and preview.hour
        or nil
    local current_invoice_hour = invoice_preview
        and invoice_preview.season == "current"
        and invoice_preview.hour
        or nil
    local upcoming_invoice_hour = invoice_preview
        and invoice_preview.season == "upcoming"
        and invoice_preview.hour
        or nil

    if not options.hide_phase_tracker then
        drawPhaseTracker(state, layout, screen_w)
    end
    drawSection(
        state,
        state.current_season,
        "current",
        layout.current_x,
        layout,
        1,
        state.current_hour,
        current_preview_hour,
        preview and preview.elapsed,
        current_invoice_hour,
        invoice_preview and invoice_preview.elapsed
    )
    drawSection(
        state,
        state.upcoming_season,
        "upcoming",
        layout.upcoming_x,
        layout,
        NEXT_SEASON_BRIGHTNESS,
        nil,
        upcoming_preview_hour,
        preview and preview.elapsed,
        upcoming_invoice_hour,
        invoice_preview and invoice_preview.elapsed
    )

    if state.icon then
        local scale = math.min(ICON_SIZE / state.icon:getWidth(), ICON_SIZE / state.icon:getHeight())
        local draw_w = state.icon:getWidth() * scale
        local draw_h = state.icon:getHeight() * scale

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(
            state.icon,
            layout.icon_x + (ICON_SIZE - draw_w) / 2,
            layout.icon_y + (ICON_SIZE - draw_h) / 2,
            0,
            scale,
            scale
        )
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return calendar

local image_loader = require("src.assets.image_loader")
local season_data = require("data.seasons")

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
local OUTLINE_WIDTH = 2
local NEXT_SEASON_BRIGHTNESS = 0.35

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

local function drawSection(state, season, start_x, layout, brightness, marked_hour)
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

        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.rectangle("fill", tile_x, tile_y, TILE_SIZE, TILE_SIZE)
        love.graphics.setColor(brightness, brightness, brightness, 1)
        love.graphics.rectangle("line", tile_x, tile_y, TILE_SIZE, TILE_SIZE)

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

    state.current_season = state.upcoming_season
    state.upcoming_season = chooseSeason(state.current_season, dismissed_season)
    state.current_hour = 1
end

local function enterPhase(state, phase)
    state.current_phase = phase
    state.phase_elapsed = 0

    if phase == PHASE_START then
        advanceHour(state)
    end
end

function calendar.update(state, dt)
    if not state or state.current_phase == PHASE_COMMAND then
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

function calendar.draw(state, screen_w, screen_h)
    if not state then
        return
    end

    screen_w = screen_w or love.graphics.getWidth()
    screen_h = screen_h or love.graphics.getHeight()

    local layout = getLayout(screen_w, screen_h, state.label_font)

    drawPhaseTracker(state, layout, screen_w)
    drawSection(state, state.current_season, layout.current_x, layout, 1, state.current_hour)
    drawSection(state, state.upcoming_season, layout.upcoming_x, layout, NEXT_SEASON_BRIGHTNESS)

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

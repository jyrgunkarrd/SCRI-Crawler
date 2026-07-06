local phase_track = {}

local MARGIN_X = 24
local MARGIN_Y = 24
local BACKING_W = 264
local BACKING_H = 238
local BACKING_COLOR = { 0, 0, 0, 0.86 }
local TEXT_COLOR = { 1, 1, 1, 1 }
local ROUND_FLASH_COLOR = { 1, 0, 0.4353, 1 }
local PHASE_FILL_COLOR = { 1, 1, 1, 1 }
local PHASE_TEXT_COLOR = { 0, 0, 0, 1 }
local ACTIVE_PHASE_FILL_COLOR = { 0, 0, 0, 1 }
local ACTIVE_PHASE_OUTLINE_COLOR = { 1, 1, 1, 1 }
local ACTIVE_PHASE_TEXT_COLOR = { 1, 1, 1, 1 }
local PHASE_W = 224
local PHASE_H = 34
local PHASE_GAP = 10
local HEADER_H = 34
local PHASES = {
    "START",
    "MISSION",
    "SERMON",
    "END",
}

local function drawCenteredText(text, x, y, width, height, color)
    local font = love.graphics.getFont()
    local text_y = y + (height - font:getHeight()) / 2

    love.graphics.setColor(color)
    love.graphics.printf(text, x, text_y, width, "center")
end

function phase_track.draw(round, current_phase, round_flash_active)
    local backing_x = love.graphics.getWidth() - MARGIN_X - BACKING_W
    local backing_y = MARGIN_Y
    local phase_x = backing_x + (BACKING_W - PHASE_W) / 2
    local phase_y = backing_y + HEADER_H + 16

    love.graphics.setColor(BACKING_COLOR)
    love.graphics.rectangle("fill", backing_x, backing_y, BACKING_W, BACKING_H)

    drawCenteredText(
        "Round : " .. tostring(round or 0),
        backing_x,
        backing_y + 8,
        BACKING_W,
        HEADER_H,
        round_flash_active and ROUND_FLASH_COLOR or TEXT_COLOR
    )

    for index, label in ipairs(PHASES) do
        local y = phase_y + (index - 1) * (PHASE_H + PHASE_GAP)
        local active = label == current_phase

        love.graphics.setColor(active and ACTIVE_PHASE_FILL_COLOR or PHASE_FILL_COLOR)
        love.graphics.rectangle("fill", phase_x, y, PHASE_W, PHASE_H)

        if active then
            love.graphics.setColor(ACTIVE_PHASE_OUTLINE_COLOR)
            love.graphics.rectangle("line", phase_x, y, PHASE_W, PHASE_H)
        end

        drawCenteredText(label, phase_x, y, PHASE_W, PHASE_H, active and ACTIVE_PHASE_TEXT_COLOR or PHASE_TEXT_COLOR)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return phase_track

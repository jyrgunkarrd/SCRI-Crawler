local agent_logic = require("src.sys.agent_logic")
local map_tiles = require("src.rndr.map_tiles")

local agent_uix = {}

local PANEL_X = 24
local PANEL_Y = 24
local PANEL_W = 460
local PANEL_H = 190
local PANEL_PAD = 18
local PORTRAIT_BOX_SIZE = PANEL_H - PANEL_PAD * 2
local PORTRAIT_BOX_X = PANEL_X + PANEL_PAD
local PORTRAIT_BOX_Y = PANEL_Y + PANEL_PAD
local PORTRAIT_PAD = 10
local PORTRAIT_RADIUS = (PORTRAIT_BOX_SIZE - PORTRAIT_PAD * 2) / 2
local CONTENT_X = PORTRAIT_BOX_X + PORTRAIT_BOX_SIZE + PANEL_PAD
local CONTENT_Y = PANEL_Y + PANEL_PAD
local CONTENT_W = PANEL_X + PANEL_W - PANEL_PAD - CONTENT_X
local STAT_X = CONTENT_X
local STAT_Y = CONTENT_Y + 52
local STAT_ROW_H = 32
local PANEL_COLOR = { 0, 0, 0, 0.86 }
local TEXT_COLOR = { 1, 1, 1, 1 }
local OUTLINE_COLOR = { 0.02, 0.018, 0.015, 1 }
local STAT_COLORS = {
    ap = { 0.8431, 0.9098, 0.0039, 1 },
    hp = { 1, 0.2902, 0.4941, 1 },
    lp = { 0.6745, 0.9725, 0.9882, 1 },
}
local STAT_ORDER = {
    { id = "ap", label = "AP" },
    { id = "hp", label = "HP" },
    { id = "lp", label = "LP" },
}

local function buildHexPoints(center_x, center_y, radius)
    local points = {}

    for index = 0, 5 do
        local angle = math.rad(-90 + index * 60)
        points[#points + 1] = center_x + radius * math.cos(angle)
        points[#points + 1] = center_y + radius * math.sin(angle)
    end

    return points
end

local function drawPortrait(agent)
    local image = map_tiles.getAgentPortrait(agent)
    local center_x = PORTRAIT_BOX_X + PORTRAIT_BOX_SIZE / 2
    local center_y = PORTRAIT_BOX_Y + PORTRAIT_BOX_SIZE / 2
    local points = buildHexPoints(center_x, center_y, PORTRAIT_RADIUS)

    love.graphics.setColor(0.035, 0.032, 0.028, 1)
    love.graphics.rectangle("fill", PORTRAIT_BOX_X, PORTRAIT_BOX_Y, PORTRAIT_BOX_SIZE, PORTRAIT_BOX_SIZE)

    if image then
        local scale = (PORTRAIT_RADIUS * 2) / math.min(image:getWidth(), image:getHeight())

        love.graphics.stencil(function()
            love.graphics.polygon("fill", points)
        end, "replace", 1)

        love.graphics.setStencilTest("equal", 1)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(
            image,
            center_x,
            center_y,
            0,
            scale,
            scale,
            image:getWidth() / 2,
            image:getHeight() / 2
        )
        love.graphics.setStencilTest()
    end

    love.graphics.setColor(OUTLINE_COLOR)
    love.graphics.setLineWidth(3)
    love.graphics.polygon("line", points)
    love.graphics.setLineWidth(1)
end

local function drawStatValue(label, stat, color, index)
    local current = math.floor(tonumber(stat and stat.current) or 0)
    local maximum = math.floor(tonumber(stat and stat.maximum) or 0)

    local y = STAT_Y + (index - 1) * STAT_ROW_H
    local value_text = ("%d / %d"):format(current, maximum)

    love.graphics.setColor(TEXT_COLOR)
    love.graphics.print(label, STAT_X, y)

    love.graphics.setColor(color)
    love.graphics.printf(value_text, STAT_X + 58, y, CONTENT_W - 58, "right")
end

function agent_uix.draw()
    local agent = agent_logic.getSelectedAgent()

    if not agent then
        return
    end

    local stats = agent_logic.getSelectedStats()

    love.graphics.setColor(PANEL_COLOR)
    love.graphics.rectangle("fill", PANEL_X, PANEL_Y, PANEL_W, PANEL_H)

    drawPortrait(agent)

    love.graphics.setColor(TEXT_COLOR)
    love.graphics.print(agent.name or agent.id or "Agent", CONTENT_X, CONTENT_Y)

    for index, stat in ipairs(STAT_ORDER) do
        drawStatValue(stat.label, stats[stat.id], STAT_COLORS[stat.id], index)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return agent_uix

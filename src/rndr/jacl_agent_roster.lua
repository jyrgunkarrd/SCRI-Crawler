local image_loader = require("src.assets.image_loader")
local agent_definitions = require("data.agents")
local dev_roster = require("data.dev_roster")
local agent_logic = require("src.sys.agent_logic")
local strike_prep = require("src.sys.JACL_strk_prep")
local utf8 = require("utf8")

local roster = {}

local AGENT_PORTRAIT_DIR = "assets/images/agents"
local X = 22
local Y = 14
local H = 168
local PADDING_X = 18
local TITLE_W = 150
local TITLE_TOP = 30
local PROMPT_H = 30
local PROMPT_BOTTOM_PAD = 16
local SEARCH_ICON = "\239\128\130"
local SEARCH_ICON_SIZE = 18
local SEARCH_ICON_GAP = 8
local PROMPT_PAD_X = 8
local ITEM_W = 116
local GAP = 16
local PORTRAIT_RADIUS = 54
local NAME_GAP = 8
local NAME_FONT_MAX = 15
local NAME_FONT_MIN = 8
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
local PORTRAIT_OUTLINE_COLOR = { 0.015, 0.012, 0.01, 1 }
local EMPTY_COLOR = { 1, 1, 1, 0.52 }

local portraits = {}
local missing_portraits = {}

local function pointInRect(x, y, rect)
    return x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

local function buildHexPoints(center_x, center_y, radius)
    local points = {}

    for index = 0, 5 do
        local angle = math.rad(-90 + index * 60)
        points[#points + 1] = center_x + radius * math.cos(angle)
        points[#points + 1] = center_y + radius * math.sin(angle)
    end

    return points
end

local function getAgentDefinitionMap()
    local agents_by_id = {}

    for _, agent in ipairs(agent_definitions) do
        if agent.id then
            agents_by_id[agent.id] = agent
        end
    end

    return agents_by_id
end

local function loadAgents()
    local agents_by_id = getAgentDefinitionMap()
    local roster_agents = {}

    for _, agent_id in ipairs(dev_roster.playerroster or {}) do
        local agent = agents_by_id[agent_id]

        if agent then
            agent_logic.ensureRuntimeStats(agent)
            agent_logic.initializeActionHand(agent, nil, nil, { draw_hand = false })
            roster_agents[#roster_agents + 1] = agent
        else
            print("Unknown agent id in dev roster: " .. tostring(agent_id))
        end
    end

    return roster_agents
end

local function getPortrait(agent)
    if not agent or not agent.id then
        return nil
    end

    if portraits[agent.id] then
        return portraits[agent.id]
    end

    if missing_portraits[agent.id] then
        return nil
    end

    local path = ("%s/%s.webp"):format(AGENT_PORTRAIT_DIR, agent.id)
    local ok, image = pcall(image_loader.newImage, path)

    if not ok then
        print("Unable to load roster agent portrait '" .. path .. "': " .. tostring(image))
        missing_portraits[agent.id] = true
        return nil
    end

    portraits[agent.id] = image

    return image
end

local function drawHexPortrait(image, center_x, center_y, radius)
    local points = buildHexPoints(center_x, center_y, radius)
    local scale = (radius * 2) / math.min(image:getWidth(), image:getHeight())

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

    love.graphics.setColor(PORTRAIT_OUTLINE_COLOR)
    love.graphics.setLineWidth(3)
    love.graphics.polygon("line", points)
    love.graphics.setLineWidth(1)
end

local function normalizeSearchText(text)
    text = tostring(text or ""):lower()

    return text:match("^%s*(.-)%s*$")
end

local function getFilteredAgents(state)
    local query = normalizeSearchText(state.roster_search_text)
    local roster_agents = strike_prep.filterRosterAgents(state.roster_agents)

    if query == "" then
        return roster_agents
    end

    local filtered_agents = {}

    for _, agent in ipairs(roster_agents) do
        local name = tostring(agent.name or ""):lower()
        local id = tostring(agent.id or ""):lower()

        if name:find(query, 1, true) or id:find(query, 1, true) then
            filtered_agents[#filtered_agents + 1] = agent
        end
    end

    return filtered_agents
end

local function getContentWidth(agent_count)
    if agent_count <= 0 then
        return 0
    end

    return agent_count * ITEM_W + math.max(agent_count - 1, 0) * GAP
end

local function clampScroll(scroll_x, layout, agent_count)
    local max_scroll = math.max(0, getContentWidth(agent_count) - layout.content_w)

    return math.max(0, math.min(scroll_x or 0, max_scroll))
end

local function getNameFont(state, label, max_w, max_h)
    label = label or ""
    state.roster_name_fonts = state.roster_name_fonts or {}

    for font_size = NAME_FONT_MAX, NAME_FONT_MIN, -1 do
        local font = state.roster_name_fonts[font_size]

        if not font then
            font = love.graphics.newFont("assets/fonts/Furore.otf", font_size)
            state.roster_name_fonts[font_size] = font
        end

        local _, wrapped_lines = font:getWrap(label, max_w)
        local line_count = math.max(#wrapped_lines, 1)

        if font:getHeight() * line_count <= max_h then
            return font, line_count
        end
    end

    local font = state.roster_name_fonts[NAME_FONT_MIN]

    if not font then
        font = love.graphics.newFont("assets/fonts/Furore.otf", NAME_FONT_MIN)
        state.roster_name_fonts[NAME_FONT_MIN] = font
    end

    local _, wrapped_lines = font:getWrap(label, max_w)

    return font, math.max(#wrapped_lines, 1)
end

local function drawSearchPrompt(state, layout)
    local prompt_color = state.roster_search_focused and PROMPT_FOCUSED_COLOR or PROMPT_COLOR
    local text = state.roster_search_text or ""

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

    if state.roster_search_focused and math.floor(love.timer.getTime() * 2) % 2 == 0 then
        local cursor_x = text_x + state.roster_prompt_font:getWidth(visible_text)

        love.graphics.setColor(PROMPT_CURSOR_COLOR)
        love.graphics.line(cursor_x + 2, layout.prompt_y + 6, cursor_x + 2, layout.prompt_y + layout.prompt_h - 6)
    end
end

function roster.reset(state)
    state.roster_font = love.graphics.newFont("assets/fonts/Furore.otf", 13)
    state.roster_prompt_font = love.graphics.newFont("assets/fonts/Furore.otf", 13)
    state.roster_icon_font = love.graphics.newFont("assets/fonts/icons.otf", SEARCH_ICON_SIZE)
    state.roster_name_fonts = {}
    state.roster_search_text = ""
    state.roster_search_focused = false
    state.roster_agents = loadAgents()
    state.roster_scroll_x = 0
end

function roster.getLayout()
    local screen_w = love.graphics.getWidth()
    local label_x = X + PADDING_X
    local prompt_y = Y + H - PROMPT_BOTTOM_PAD - PROMPT_H
    local icon_w = SEARCH_ICON_SIZE
    local prompt_x = label_x + icon_w + SEARCH_ICON_GAP
    local prompt_w = TITLE_W - icon_w - SEARCH_ICON_GAP

    return {
        x = X,
        y = Y,
        w = math.max(0, screen_w - X * 2),
        h = H,
        content_x = X + PADDING_X + TITLE_W + PADDING_X,
        content_y = Y + 10,
        content_w = math.max(0, screen_w - X * 2 - PADDING_X * 3 - TITLE_W),
        content_h = H - 20,
        label_x = label_x,
        label_y = Y + TITLE_TOP,
        label_w = TITLE_W,
        prompt_x = prompt_x,
        prompt_y = prompt_y,
        prompt_w = prompt_w,
        prompt_h = PROMPT_H,
        icon_x = label_x,
        icon_y = prompt_y + (PROMPT_H - SEARCH_ICON_SIZE) / 2,
    }
end

function roster.getTheme()
    return {
        title_color = TITLE_COLOR,
        outline_color = OUTLINE_COLOR,
        prompt_outline_color = PROMPT_OUTLINE_COLOR,
        empty_color = EMPTY_COLOR,
        y = Y,
        h = H,
    }
end

function roster.getPortraitRadius()
    return PORTRAIT_RADIUS
end

function roster.drawAgentPortrait(agent, center_x, center_y, radius)
    local image = getPortrait(agent)

    if image then
        drawHexPortrait(image, center_x, center_y, radius)
    end
end

function roster.draw(state)
    local layout = roster.getLayout()
    local roster_agents = getFilteredAgents(state)

    state.roster_scroll_x = clampScroll(state.roster_scroll_x, layout, #roster_agents)

    love.graphics.setColor(COLOR)
    love.graphics.rectangle("fill", layout.x, layout.y, layout.w, layout.h)
    love.graphics.setColor(OUTLINE_COLOR)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", layout.x, layout.y, layout.w, layout.h)
    love.graphics.setLineWidth(1)

    love.graphics.setFont(state.roster_font)
    love.graphics.setColor(TITLE_COLOR)
    love.graphics.printf(
        "AGENT\nROSTER",
        layout.label_x,
        layout.label_y,
        layout.label_w,
        "center"
    )

    drawSearchPrompt(state, layout)

    love.graphics.setColor(DIVIDER_COLOR)
    love.graphics.line(
        layout.content_x - PADDING_X / 2,
        layout.y + 14,
        layout.content_x - PADDING_X / 2,
        layout.y + layout.h - 14
    )

    love.graphics.setScissor(layout.content_x, layout.content_y, layout.content_w, layout.content_h)

    if #roster_agents == 0 then
        love.graphics.setColor(EMPTY_COLOR)
        love.graphics.printf("No agents found.", layout.content_x, layout.y + 44, layout.content_w, "center")
    end

    for index, agent in ipairs(roster_agents) do
        local item_x = layout.content_x - state.roster_scroll_x + (index - 1) * (ITEM_W + GAP)
        local center_x = item_x + ITEM_W / 2
        local portrait_y = layout.content_y + PORTRAIT_RADIUS + 4
        local image = getPortrait(agent)

        if image then
            drawHexPortrait(image, center_x, portrait_y, PORTRAIT_RADIUS)
        end

        local name = agent.name or agent.id
        local label_y = portrait_y + PORTRAIT_RADIUS + NAME_GAP
        local label_h = layout.content_y + layout.content_h - label_y
        local name_font = getNameFont(state, name, ITEM_W, label_h)

        love.graphics.setFont(name_font)
        love.graphics.setColor(NAME_COLOR)
        love.graphics.printf(
            name,
            item_x,
            label_y,
            ITEM_W,
            "center"
        )
    end

    love.graphics.setScissor()
end

function roster.getAgentAtPoint(state, x, y)
    local layout = roster.getLayout()
    local roster_agents = getFilteredAgents(state)

    if not pointInRect(x, y, {
        x = layout.content_x,
        y = layout.content_y,
        w = layout.content_w,
        h = layout.content_h,
    }) then
        return nil
    end

    local local_x = x - layout.content_x + (state.roster_scroll_x or 0)
    local stride = ITEM_W + GAP
    local index = math.floor(local_x / stride) + 1
    local item_left = (index - 1) * stride

    if index < 1 or index > #roster_agents then
        return nil
    end

    if local_x < item_left or local_x > item_left + ITEM_W then
        return nil
    end

    return roster_agents[index]
end

function roster.pointInPrompt(state, x, y)
    local layout = roster.getLayout()

    return pointInRect(x, y, {
        x = layout.prompt_x,
        y = layout.prompt_y,
        w = layout.prompt_w,
        h = layout.prompt_h,
    })
end

function roster.setSearchFocused(state, focused)
    state.roster_search_focused = focused and true or false
end

function roster.keypressed(state, key)
    if not state.roster_search_focused then
        return false
    end

    if key == "backspace" then
        local byte_offset = utf8.offset(state.roster_search_text, -1)

        if byte_offset then
            state.roster_search_text = state.roster_search_text:sub(1, byte_offset - 1)
            state.roster_scroll_x = 0
        end

        return true
    end

    if key == "return" or key == "kpenter" then
        state.roster_search_focused = false
        return true
    end

    return false
end

function roster.textinput(state, text)
    if state.roster_search_focused then
        state.roster_search_text = (state.roster_search_text or "") .. text
        state.roster_scroll_x = 0
        return true
    end

    return false
end

function roster.wheelmoved(state, x, y)
    local layout = roster.getLayout()
    local mouse_x, mouse_y = love.mouse.getPosition()

    if not pointInRect(mouse_x, mouse_y, layout) then
        return false
    end

    local wheel_delta = y ~= 0 and y or -x

    state.roster_scroll_x = clampScroll(
        state.roster_scroll_x - wheel_delta * SCROLL_STEP,
        layout,
        #getFilteredAgents(state)
    )

    return true
end

return roster

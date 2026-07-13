local image_loader = require("src.assets.image_loader")
local jacl_definitions = require("data.jacl")
local agent_definitions = require("data.agents")
local dev_roster = require("data.dev_roster")
local agent_logic = require("src.sys.agent_logic")
local agent_uix = require("src.rndr.agent_uix")
local officers = require("src.sys.officers")

local jacl_state = {
    name = "JACL",
    definition = nil,
    image = nil,
    image_path = nil,
    left_officers = {},
    right_officers = {},
    roster_agents = {},
    roster_scroll_x = 0,
    officer_font = nil,
    jacl_font = nil,
    roster_font = nil,
    roster_name_fonts = {},
}

local BACKGROUND_COLOR = { 0.018, 0.018, 0.022, 1 }
local BACKING_COLOR = { 0, 0, 0, 1 }
local BACKING_OUTLINE_COLOR = { 1, 1, 1, 1 }
local BACKING_OUTLINE_WIDTH = 3
local BACKING_PADDING = 42
local MAX_IMAGE_SIZE = 360
local JACL_LABEL_GAP = 14
local JACL_IMAGE_BOTTOM_PADDING = 24
local JACL_LABEL_COLOR = { 1, 1, 1, 1 }
local OFFICER_LEFT_IDS = { "eng", "sci", "surg" }
local OFFICER_RIGHT_IDS = { "cap", "tac", "sher" }
local OFFICER_MAX_IMAGE_W = 155
local OFFICER_MAX_IMAGE_H = 155
local OFFICER_LABEL_GAP = 8
local OFFICER_ROW_GAP = 24
local OFFICER_SIDE_MARGIN = 54
local OFFICER_LABEL_COLOR = { 1, 1, 1, 1 }
local AGENT_PORTRAIT_DIR = "assets/images/agents"
local ROSTER_X = 22
local ROSTER_Y = 14
local ROSTER_H = 168
local ROSTER_PADDING_X = 18
local ROSTER_TITLE_W = 150
local ROSTER_ITEM_W = 116
local ROSTER_GAP = 16
local ROSTER_PORTRAIT_RADIUS = 54
local ROSTER_NAME_GAP = 8
local ROSTER_NAME_FONT_MAX = 15
local ROSTER_NAME_FONT_MIN = 8
local ROSTER_SCROLL_STEP = 46
local ROSTER_COLOR = { 0, 0, 0, 0.88 }
local ROSTER_OUTLINE_COLOR = { 1, 1, 1, 0.92 }
local ROSTER_DIVIDER_COLOR = { 1, 1, 1, 0.28 }
local ROSTER_TITLE_COLOR = { 1, 1, 1, 1 }
local ROSTER_NAME_COLOR = { 1, 1, 1, 0.9 }
local ROSTER_PORTRAIT_OUTLINE_COLOR = { 0.015, 0.012, 0.01, 1 }
local ROSTER_EMPTY_COLOR = { 1, 1, 1, 0.52 }

local roster_portraits = {}
local missing_roster_portraits = {}

local function buildHexPoints(center_x, center_y, radius)
    local points = {}

    for index = 0, 5 do
        local angle = math.rad(-90 + index * 60)
        points[#points + 1] = center_x + radius * math.cos(angle)
        points[#points + 1] = center_y + radius * math.sin(angle)
    end

    return points
end

local function pointInRect(x, y, rect)
    return x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
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

local function loadRosterAgents()
    local agents_by_id = getAgentDefinitionMap()
    local roster_agents = {}

    for _, agent_id in ipairs(dev_roster.playerroster or {}) do
        local agent = agents_by_id[agent_id]

        if agent then
            agent_logic.ensureRuntimeStats(agent)
            roster_agents[#roster_agents + 1] = agent
        else
            print("Unknown agent id in dev roster: " .. tostring(agent_id))
        end
    end

    return roster_agents
end

local function getRosterPortrait(agent)
    if not agent or not agent.id then
        return nil
    end

    if roster_portraits[agent.id] then
        return roster_portraits[agent.id]
    end

    if missing_roster_portraits[agent.id] then
        return nil
    end

    local path = ("%s/%s.webp"):format(AGENT_PORTRAIT_DIR, agent.id)
    local ok, image = pcall(image_loader.newImage, path)

    if not ok then
        print("Unable to load roster agent portrait '" .. path .. "': " .. tostring(image))
        missing_roster_portraits[agent.id] = true
        return nil
    end

    roster_portraits[agent.id] = image

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

    love.graphics.setColor(ROSTER_PORTRAIT_OUTLINE_COLOR)
    love.graphics.setLineWidth(3)
    love.graphics.polygon("line", points)
    love.graphics.setLineWidth(1)
end

local function getRosterLayout()
    local screen_w = love.graphics.getWidth()

    return {
        x = ROSTER_X,
        y = ROSTER_Y,
        w = math.max(0, screen_w - ROSTER_X * 2),
        h = ROSTER_H,
        content_x = ROSTER_X + ROSTER_PADDING_X + ROSTER_TITLE_W + ROSTER_PADDING_X,
        content_y = ROSTER_Y + 10,
        content_w = math.max(0, screen_w - ROSTER_X * 2 - ROSTER_PADDING_X * 3 - ROSTER_TITLE_W),
        content_h = ROSTER_H - 20,
    }
end

local function getRosterContentWidth(agent_count)
    if agent_count <= 0 then
        return 0
    end

    return agent_count * ROSTER_ITEM_W + math.max(agent_count - 1, 0) * ROSTER_GAP
end

local function clampRosterScroll(scroll_x, layout, agent_count)
    local max_scroll = math.max(0, getRosterContentWidth(agent_count) - layout.content_w)

    return math.max(0, math.min(scroll_x or 0, max_scroll))
end

local function getRosterAgentAtPoint(state, x, y)
    local layout = getRosterLayout()
    local roster_agents = state.roster_agents or {}

    if not pointInRect(x, y, {
        x = layout.content_x,
        y = layout.content_y,
        w = layout.content_w,
        h = layout.content_h,
    }) then
        return nil
    end

    local local_x = x - layout.content_x + (state.roster_scroll_x or 0)
    local stride = ROSTER_ITEM_W + ROSTER_GAP
    local index = math.floor(local_x / stride) + 1
    local item_left = (index - 1) * stride

    if index < 1 or index > #roster_agents then
        return nil
    end

    if local_x < item_left or local_x > item_left + ROSTER_ITEM_W then
        return nil
    end

    return roster_agents[index]
end

local function getRosterNameFont(state, label, max_w, max_h)
    label = label or ""
    state.roster_name_fonts = state.roster_name_fonts or {}

    for font_size = ROSTER_NAME_FONT_MAX, ROSTER_NAME_FONT_MIN, -1 do
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

    local font = state.roster_name_fonts[ROSTER_NAME_FONT_MIN]

    if not font then
        font = love.graphics.newFont("assets/fonts/Furore.otf", ROSTER_NAME_FONT_MIN)
        state.roster_name_fonts[ROSTER_NAME_FONT_MIN] = font
    end

    local _, wrapped_lines = font:getWrap(label, max_w)

    return font, math.max(#wrapped_lines, 1)
end

local function findImagePath(id)
    local base_path = "assets/images/jacl/" .. tostring(id)
    local extensions = { ".webp", ".png", ".jpg", ".jpeg" }

    for _, extension in ipairs(extensions) do
        local path = base_path .. extension

        if love.filesystem.getInfo(path, "file") then
            return path
        end
    end

    return nil
end

local function drawOfficer(officer, center_x, top_y, max_w, max_h, font)
    local label = officer.label

    love.graphics.setFont(font)
    love.graphics.setColor(OFFICER_LABEL_COLOR)
    love.graphics.printf(label, center_x - max_w / 2, top_y, max_w, "center")

    local _, wrapped_lines = font:getWrap(label, max_w)
    local label_h = font:getHeight() * math.max(#wrapped_lines, 1)
    local image_y = top_y + label_h + OFFICER_LABEL_GAP

    if officer.image then
        local image_w = officer.image:getWidth()
        local image_h = officer.image:getHeight()
        local scale = math.min(max_w / image_w, max_h / image_h, 1)
        local draw_w = image_w * scale
        local draw_h = image_h * scale

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(officer.image, center_x - draw_w / 2, image_y, 0, scale, scale)
    end
end

local function getOfficerLabel(officer)
    if officer.office and officer.office ~= "" then
        return officer.name .. "\n- " .. officer.office
    end

    return officer.name
end

local function getOfficerRowHeight(officer, max_w, max_h, font)
    local _, wrapped_lines = font:getWrap(officer.label, max_w)
    local label_h = font:getHeight() * math.max(#wrapped_lines, 1)

    return label_h + OFFICER_LABEL_GAP + max_h
end

local function drawOfficerColumn(officer_list, center_x, screen_h, font)
    local row_heights = {}
    local total_h = OFFICER_ROW_GAP * math.max(#officer_list - 1, 0)

    for index, officer in ipairs(officer_list) do
        officer.label = officer.label or getOfficerLabel(officer)
        row_heights[index] = getOfficerRowHeight(officer, OFFICER_MAX_IMAGE_W, OFFICER_MAX_IMAGE_H, font)
        total_h = total_h + row_heights[index]
    end

    local top_y = (screen_h - total_h) / 2
    local cursor_y = top_y

    for index, officer in ipairs(officer_list) do
        drawOfficer(
            officer,
            center_x,
            cursor_y,
            OFFICER_MAX_IMAGE_W,
            OFFICER_MAX_IMAGE_H,
            font
        )
        cursor_y = cursor_y + row_heights[index] + OFFICER_ROW_GAP
    end
end

local function drawAgentRoster(state)
    local layout = getRosterLayout()
    local roster_agents = state.roster_agents or {}

    state.roster_scroll_x = clampRosterScroll(state.roster_scroll_x, layout, #roster_agents)

    love.graphics.setColor(ROSTER_COLOR)
    love.graphics.rectangle("fill", layout.x, layout.y, layout.w, layout.h)
    love.graphics.setColor(ROSTER_OUTLINE_COLOR)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", layout.x, layout.y, layout.w, layout.h)
    love.graphics.setLineWidth(1)

    love.graphics.setFont(state.roster_font)
    love.graphics.setColor(ROSTER_TITLE_COLOR)
    love.graphics.printf(
        "AGENT\nROSTER",
        layout.x + ROSTER_PADDING_X,
        layout.y + (layout.h - state.roster_font:getHeight() * 2) / 2,
        ROSTER_TITLE_W,
        "center"
    )

    love.graphics.setColor(ROSTER_DIVIDER_COLOR)
    love.graphics.line(
        layout.content_x - ROSTER_PADDING_X / 2,
        layout.y + 14,
        layout.content_x - ROSTER_PADDING_X / 2,
        layout.y + layout.h - 14
    )

    love.graphics.setScissor(layout.content_x, layout.content_y, layout.content_w, layout.content_h)

    if #roster_agents == 0 then
        love.graphics.setColor(ROSTER_EMPTY_COLOR)
        love.graphics.printf("No agents found.", layout.content_x, layout.y + 44, layout.content_w, "center")
    end

    for index, agent in ipairs(roster_agents) do
        local item_x = layout.content_x - state.roster_scroll_x + (index - 1) * (ROSTER_ITEM_W + ROSTER_GAP)
        local center_x = item_x + ROSTER_ITEM_W / 2
        local portrait_y = layout.content_y + ROSTER_PORTRAIT_RADIUS + 4
        local image = getRosterPortrait(agent)

        if image then
            drawHexPortrait(image, center_x, portrait_y, ROSTER_PORTRAIT_RADIUS)
        end

        local name = agent.name or agent.id
        local label_y = portrait_y + ROSTER_PORTRAIT_RADIUS + ROSTER_NAME_GAP
        local label_h = layout.content_y + layout.content_h - label_y
        local name_font = getRosterNameFont(state, name, ROSTER_ITEM_W, label_h)

        love.graphics.setFont(name_font)
        love.graphics.setColor(ROSTER_NAME_COLOR)
        love.graphics.printf(
            name,
            item_x,
            label_y,
            ROSTER_ITEM_W,
            "center"
        )
    end

    love.graphics.setScissor()
end

function jacl_state:enter()
    love.graphics.setDefaultFilter("linear", "linear", 1)
    love.graphics.setFont(love.graphics.newFont("assets/fonts/Furore.otf", 20))
    love.graphics.setBackgroundColor(BACKGROUND_COLOR)

    self.officer_font = love.graphics.newFont("assets/fonts/Furore.otf", 14)
    self.jacl_font = love.graphics.newFont("assets/fonts/Furore.otf", 18)
    self.roster_font = love.graphics.newFont("assets/fonts/Furore.otf", 13)
    self.roster_name_fonts = {}
    self.left_officers = officers.loadByIds(OFFICER_LEFT_IDS)
    self.right_officers = officers.loadByIds(OFFICER_RIGHT_IDS)
    self.roster_agents = loadRosterAgents()
    self.roster_scroll_x = 0
    self.definition = jacl_definitions[1]
    self.image = nil
    self.image_path = nil

    if not self.definition or not self.definition.id then
        print("No JACL definition was found.")
        return
    end

    self.image_path = findImagePath(self.definition.id)

    if not self.image_path then
        print("No JACL image found for id: " .. tostring(self.definition.id))
        return
    end

    self.image = image_loader.newImage(self.image_path)
end

function jacl_state:draw()
    love.graphics.clear(BACKGROUND_COLOR[1], BACKGROUND_COLOR[2], BACKGROUND_COLOR[3], BACKGROUND_COLOR[4])

    local screen_w = love.graphics.getWidth()
    local screen_h = love.graphics.getHeight()
    local image_w = self.image and self.image:getWidth() or MAX_IMAGE_SIZE
    local image_h = self.image and self.image:getHeight() or MAX_IMAGE_SIZE
    local image_scale = math.min(MAX_IMAGE_SIZE / image_w, MAX_IMAGE_SIZE / image_h, 1)
    local draw_w = image_w * image_scale
    local draw_h = image_h * image_scale
    local jacl_label = self.definition and (self.definition.name or self.definition.id) or ""
    local jacl_label_h = self.jacl_font:getHeight()
    local backing_w = math.max(draw_w, self.jacl_font:getWidth(jacl_label)) + BACKING_PADDING * 2
    local label_band_h = jacl_label_h + JACL_LABEL_GAP * 2
    local backing_h = label_band_h + draw_h + JACL_IMAGE_BOTTOM_PADDING
    local backing_x = (screen_w - backing_w) / 2
    local backing_y = (screen_h - backing_h) / 2
    local label_y = backing_y + (label_band_h - jacl_label_h) / 2
    local image_y = backing_y + label_band_h
    local left_column_x = OFFICER_SIDE_MARGIN + OFFICER_MAX_IMAGE_W / 2
    local right_column_x = screen_w - OFFICER_SIDE_MARGIN - OFFICER_MAX_IMAGE_W / 2

    drawOfficerColumn(self.left_officers, left_column_x, screen_h, self.officer_font)
    drawOfficerColumn(self.right_officers, right_column_x, screen_h, self.officer_font)

    love.graphics.setColor(BACKING_COLOR)
    love.graphics.rectangle("fill", backing_x, backing_y, backing_w, backing_h)
    love.graphics.setColor(BACKING_OUTLINE_COLOR)
    love.graphics.setLineWidth(BACKING_OUTLINE_WIDTH)
    love.graphics.rectangle("line", backing_x, backing_y, backing_w, backing_h)
    love.graphics.setLineWidth(1)

    love.graphics.setFont(self.jacl_font)
    love.graphics.setColor(JACL_LABEL_COLOR)
    love.graphics.printf(jacl_label, backing_x + BACKING_PADDING, label_y, backing_w - BACKING_PADDING * 2, "center")

    if self.image then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(
            self.image,
            (screen_w - draw_w) / 2,
            image_y,
            0,
            image_scale,
            image_scale
        )
    end

    drawAgentRoster(self)
    agent_uix.draw()

    love.graphics.setColor(1, 1, 1, 1)
end

function jacl_state:keypressed(key)
    if key == "escape" then
        if not agent_uix.closeModal() then
            love.event.quit()
        end
    end
end

function jacl_state:mousepressed(x, y, button)
    if agent_uix.mousepressed(x, y, button) then
        return
    end

    if button ~= 1 then
        return
    end

    local agent = getRosterAgentAtPoint(self, x, y)

    if agent then
        agent_uix.openModal(agent, "agent")
    end
end

function jacl_state:wheelmoved(x, y)
    if agent_uix.isModalOpen() then
        agent_uix.wheelmoved(x, y)
        return
    end

    local layout = getRosterLayout()
    local mouse_x, mouse_y = love.mouse.getPosition()

    if pointInRect(mouse_x, mouse_y, layout) then
        local wheel_delta = y ~= 0 and y or -x

        self.roster_scroll_x = clampRosterScroll(
            self.roster_scroll_x - wheel_delta * ROSTER_SCROLL_STEP,
            layout,
            #(self.roster_agents or {})
        )
    end
end

return jacl_state

local image_loader = require("src.assets.image_loader")
local jacl_definitions = require("data.jacl")
local agent_uix = require("src.rndr.agent_uix")
local sfx_logic = require("src.sys.sfx_logic")
local strike_prep = require("src.sys.JACL_strk_prep")
local officers = require("src.sys.officers")
local map_preview = require("src.rndr.jacl_map_preview")
local agent_roster = require("src.rndr.jacl_agent_roster")
local strike_uix = require("src.rndr.jacl_strike_prep_uix")
local cache_rail = require("src.rndr.jacl_equipment_cache_rail")

local jacl_state = {
    name = "JACL",
    definition = nil,
    image = nil,
    image_path = nil,
    left_officers = {},
    right_officers = {},
    roster_agents = {},
    roster_scroll_x = 0,
    roster_search_text = "",
    roster_search_focused = false,
    cache_agent = nil,
    cache_mode = "rumors",
    cache_scroll_x = 0,
    cache_search_text = "",
    cache_search_focused = false,
    cache_drag = nil,
    cache_available_ids = {},
    dev_map_preview_room = nil,
    officer_font = nil,
    jacl_font = nil,
    roster_font = nil,
    roster_prompt_font = nil,
    roster_icon_font = nil,
    roster_name_fonts = {},
    launch_button_rect = nil,
    strike_button_rect = nil,
    jacl_backing_rect = nil,
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
local JACL_MODAL_OFFSET_Y = 38

local function pointInRect(x, y, rect)
    return x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
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

local function launchStrike()
    if not strike_prep.hasSlottedAgents() then
        return
    end

    local states_core = require("src.states.states_core")

    states_core.switch("mission", strike_uix.buildLaunchOptions("assets/maps/devmap.lua"))
end

function jacl_state:enter()
    love.graphics.setDefaultFilter("linear", "linear", 1)
    love.graphics.setFont(love.graphics.newFont("assets/fonts/Furore.otf", 20))
    love.graphics.setBackgroundColor(BACKGROUND_COLOR)
    agent_uix.setModalOffset(JACL_MODAL_OFFSET_Y)
    strike_prep.exit()

    self.officer_font = love.graphics.newFont("assets/fonts/Furore.otf", 14)
    self.jacl_font = love.graphics.newFont("assets/fonts/Furore.otf", 18)
    agent_roster.reset(self)
    cache_rail.reset(self)
    self.strike_button_rect = nil
    self.launch_button_rect = nil
    self.jacl_backing_rect = nil
    self.dev_map_preview_room = map_preview.load("assets/maps/devmap.lua")
    self.left_officers = officers.loadByIds(OFFICER_LEFT_IDS)
    self.right_officers = officers.loadByIds(OFFICER_RIGHT_IDS)
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

function jacl_state:leave()
    agent_uix.setModalOffset(0)
    strike_prep.exit()
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
    self.jacl_backing_rect = {
        x = backing_x,
        y = backing_y,
        w = backing_w,
        h = backing_h,
    }
    local label_y = backing_y + (label_band_h - jacl_label_h) / 2
    local image_y = backing_y + label_band_h
    local left_column_x = OFFICER_SIDE_MARGIN + OFFICER_MAX_IMAGE_W / 2
    local right_column_x = screen_w - OFFICER_SIDE_MARGIN - OFFICER_MAX_IMAGE_W / 2
    local roster_theme = agent_roster.getTheme()

    if strike_prep.isActive() then
        map_preview.draw(self, self.dev_map_preview_room, screen_h, {
            font = self.roster_font,
            title_color = roster_theme.title_color,
            outline_color = roster_theme.outline_color,
            roster_y = roster_theme.y,
            roster_h = roster_theme.h,
        })
    else
        drawOfficerColumn(self.left_officers, left_column_x, screen_h, self.officer_font)
        drawOfficerColumn(self.right_officers, right_column_x, screen_h, self.officer_font)
    end

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

    strike_uix.drawButtons(self, self.jacl_backing_rect, {
        modal_open = agent_uix.isModalOpen(),
        font = self.jacl_font,
    })

    if not agent_uix.isModalOpen() then
        cache_rail.clearTransient(self)
    end

    agent_roster.draw(self)
    strike_uix.drawPanel(self, agent_roster.getLayout(), {
        font = self.roster_font,
        outline_color = roster_theme.outline_color,
        slot_outline_color = roster_theme.prompt_outline_color,
        empty_color = roster_theme.empty_color,
        draw_agent_portrait = agent_roster.drawAgentPortrait,
    })
    agent_uix.draw()
    if not agent_uix.isDeckViewerOpen() then
        cache_rail.draw(self)
        cache_rail.drawModalPlacementPreview(self)
        agent_uix.drawOpenModalInfoPanel()
    end
    cache_rail.drawDrag(self)
    strike_uix.drawDrag({
        radius = agent_roster.getPortraitRadius(),
        draw_agent_portrait = agent_roster.drawAgentPortrait,
    })

    love.graphics.setColor(1, 1, 1, 1)
end

function jacl_state:keypressed(key)
    if key == "escape" then
        self.cache_drag = nil

        if self.cache_search_focused then
            self.cache_search_focused = false
        elseif self.roster_search_focused then
            self.roster_search_focused = false
        elseif not agent_uix.closeModal() then
            love.event.quit()
        end
    elseif cache_rail.keypressed(self, key) then
        return
    elseif agent_roster.keypressed(self, key) then
        return
    end
end

function jacl_state:mousepressed(x, y, button)
    if button == 2 and strike_prep.isActive() then
        strike_prep.exit()
        return
    end

    if cache_rail.mousepressed(self, x, y, button) then
        return
    end

    if agent_uix.mousepressed(x, y, button) then
        if not agent_uix.isModalOpen() then
            cache_rail.clearTransient(self)
        end

        return
    end

    if button ~= 1 then
        return
    end

    if self.launch_button_rect and pointInRect(x, y, self.launch_button_rect) then
        launchStrike()
        return
    end

    if self.strike_button_rect and pointInRect(x, y, self.strike_button_rect) then
        sfx_logic.playNamed("strk_pack")
        strike_prep.enter()
        self.strike_button_rect = nil
        return
    end

    if agent_roster.pointInPrompt(self, x, y) then
        agent_roster.setSearchFocused(self, true)
        self.cache_search_focused = false
        return
    end

    agent_roster.setSearchFocused(self, false)
    self.cache_search_focused = false

    if strike_prep.isActive() then
        local slot_index = strike_uix.getSlotAtPoint(self, agent_roster.getLayout(), x, y)

        if slot_index and strike_prep.startDragFromSlot(slot_index) then
            return
        end
    end

    local agent = agent_roster.getAgentAtPoint(self, x, y)

    if agent then
        if strike_prep.isActive() then
            strike_prep.startDrag(agent)
            return
        end

        cache_rail.openForAgent(self, agent)
        agent_uix.openModal(agent, "agent")
    end
end

function jacl_state:mousereleased(x, y, button)
    if button == 1 and strike_prep.getDragAgent() then
        local slot_index = strike_uix.getSlotAtPoint(self, agent_roster.getLayout(), x, y)
        local roster_layout = agent_roster.getLayout()

        if slot_index then
            strike_prep.placeDraggedAgent(slot_index)
            sfx_logic.playNamed("equip")
        elseif pointInRect(x, y, roster_layout) then
            strike_prep.returnDraggedToRoster()
            sfx_logic.playNamed("equip")
        else
            strike_prep.cancelDrag()
        end

        return
    end

    if cache_rail.mousereleased(self, x, y, button) then
        return
    end

    if agent_uix.mousereleased(x, y, button) then
        return
    end
end

function jacl_state:textinput(text)
    if cache_rail.textinput(self, text) then
        return
    end

    if agent_uix.isModalOpen() then
        return
    end

    agent_roster.textinput(self, text)
end

function jacl_state:wheelmoved(x, y)
    if agent_uix.isModalOpen() then
        if cache_rail.wheelmoved(self, x, y) then
            return
        end

        agent_uix.wheelmoved(x, y)
        return
    end

    agent_roster.wheelmoved(self, x, y)
end

return jacl_state

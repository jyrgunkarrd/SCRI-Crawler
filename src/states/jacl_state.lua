local image_loader = require("src.assets.image_loader")
local jacl_definitions = require("data.jacl")
local agent_uix = require("src.rndr.agent_uix")
local agent_logic = require("src.sys.agent_logic")
local econ = require("src.sys.econ")
local sfx_logic = require("src.sys.sfx_logic")
local strike_prep = require("src.sys.JACL_strk_prep")
local officers = require("src.sys.officers")
local map_preview = require("src.rndr.jacl_map_preview")
local agent_roster = require("src.rndr.jacl_agent_roster")
local strike_uix = require("src.rndr.jacl_strike_prep_uix")
local cache_rail = require("src.rndr.jacl_equipment_cache_rail")
local rumor_missions = require("src.sys.rumor_missions")
local rumor_chain = require("src.rndr.jacl_rumor_mission_chain")

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
    rumor_mission_scroll_y = 0,
    rumor_map_preview_cache = {},
    scratch_image = nil,
    econ_font = nil,
    strike_agent_press = nil,
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
local ECON_TILE_X = 22
local ECON_TILE_BOTTOM = 14
local ECON_TILE_MIN_W = 132
local ECON_TILE_H = 58
local ECON_TILE_PADDING = 8
local ECON_VALUE_RIGHT_PADDING = 14
local ECON_ICON_SIZE = 42
local ECON_TILE_COLOR = { 0, 0, 0, 0.88 }
local ECON_TILE_OUTLINE_COLOR = { 1, 1, 1, 0.92 }
local ECON_TEXT_COLOR = { 0, 1, 167 / 255, 1 }
local STRIKE_AGENT_DRAG_THRESHOLD = 6

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

local function drawEconTile(state, screen_h)
    local balance_text = tostring(econ.getBalance())
    local balance_w = state.econ_font:getWidth(balance_text)
    local tile_w = math.max(
        ECON_TILE_MIN_W,
        ECON_TILE_PADDING + ECON_ICON_SIZE + ECON_TILE_PADDING + balance_w + ECON_VALUE_RIGHT_PADDING
    )
    local tile_y = screen_h - ECON_TILE_BOTTOM - ECON_TILE_H
    local icon_x = ECON_TILE_X + ECON_TILE_PADDING
    local icon_y = tile_y + (ECON_TILE_H - ECON_ICON_SIZE) / 2
    local text_area_x = icon_x + ECON_ICON_SIZE + ECON_TILE_PADDING
    local text_area_w = ECON_TILE_X + tile_w - ECON_VALUE_RIGHT_PADDING - text_area_x
    local text_x = text_area_x + (text_area_w - balance_w) / 2
    local text_y = tile_y + (ECON_TILE_H - state.econ_font:getHeight()) / 2

    love.graphics.setColor(ECON_TILE_COLOR)
    love.graphics.rectangle("fill", ECON_TILE_X, tile_y, tile_w, ECON_TILE_H)
    love.graphics.setColor(ECON_TILE_OUTLINE_COLOR)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", ECON_TILE_X, tile_y, tile_w, ECON_TILE_H)
    love.graphics.setLineWidth(1)

    if state.scratch_image then
        local image_w = state.scratch_image:getWidth()
        local image_h = state.scratch_image:getHeight()
        local scale = math.min(ECON_ICON_SIZE / image_w, ECON_ICON_SIZE / image_h)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(state.scratch_image, icon_x, icon_y, 0, scale, scale)
    end

    love.graphics.setFont(state.econ_font)
    love.graphics.setColor(ECON_TEXT_COLOR)
    love.graphics.print(balance_text, text_x, text_y)
end

local function launchStrike()
    if not strike_prep.hasSlottedAgents() then
        return
    end

    local states_core = require("src.states.states_core")
    local launch_options = strike_uix.buildLaunchOptions("assets/maps/devmap.lua")

    sfx_logic.playNamed("strk_launch")
    rumor_missions.attachToLaunch(launch_options, strike_prep.getSlots())
    states_core.switch("mission", launch_options)
end

local function getStrikePreviewOptions(state, roster_theme, rumor_entries)
    return {
        font = state.roster_font,
        title_color = roster_theme.title_color,
        outline_color = roster_theme.outline_color,
        roster_y = roster_theme.y,
        roster_h = roster_theme.h,
        right_reserve = rumor_chain.getPreviewReserve(rumor_entries),
    }
end

local function getRumorMapPreview(state, entry)
    local path = entry and entry.target and entry.target.path

    if not path then
        return nil
    end

    local cached = state.rumor_map_preview_cache[path]

    if cached ~= nil then
        return cached or nil
    end

    local room = map_preview.load(path)

    state.rumor_map_preview_cache[path] = room or false

    return room
end

local function armStrikeAgentPress(state, agent, slot_index, x, y)
    state.strike_agent_press = {
        agent = agent,
        slot_index = slot_index,
        x = x,
        y = y,
    }
end

local function strikeAgentPressExceededThreshold(state, x, y)
    local press = state.strike_agent_press

    if not press then
        return false
    end

    local dx = x - press.x
    local dy = y - press.y

    return dx * dx + dy * dy >= STRIKE_AGENT_DRAG_THRESHOLD * STRIKE_AGENT_DRAG_THRESHOLD
end

local function beginStrikeAgentDrag(state)
    local press = state.strike_agent_press

    if not press then
        return false
    end

    state.strike_agent_press = nil

    if press.slot_index then
        if strike_prep.getSlots()[press.slot_index] ~= press.agent then
            return false
        end

        return strike_prep.startDragFromSlot(press.slot_index)
    end

    return strike_prep.startDrag(press.agent)
end

local function openAgentModal(state, agent)
    cache_rail.openForAgent(state, agent)
    agent_uix.openModal(agent, "agent")
end

function jacl_state:enter()
    love.graphics.setDefaultFilter("linear", "linear", 1)
    love.graphics.setFont(love.graphics.newFont("assets/fonts/Furore.otf", 20))
    love.graphics.setBackgroundColor(BACKGROUND_COLOR)
    agent_uix.setModalOffset(JACL_MODAL_OFFSET_Y)
    agent_uix.setEquipmentCardDrawEnabled(false)
    strike_prep.exit()

    self.officer_font = love.graphics.newFont("assets/fonts/Furore.otf", 14)
    self.jacl_font = love.graphics.newFont("assets/fonts/Furore.otf", 18)
    self.econ_font = love.graphics.newFont("assets/fonts/Furore.otf", 22)
    self.scratch_image = self.scratch_image or image_loader.newImage("assets/images/icons/scratch.webp")
    agent_roster.reset(self)
    cache_rail.reset(self)
    self.strike_button_rect = nil
    self.launch_button_rect = nil
    self.jacl_backing_rect = nil
    self.rumor_mission_scroll_y = 0
    self.rumor_map_preview_cache = {}
    self.strike_agent_press = nil
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

function jacl_state:leave(next_state)
    self.strike_agent_press = nil
    agent_uix.setModalOffset(0)
    agent_uix.setEquipmentCardDrawEnabled(true)

    if next_state == "mission" then
        for _, agent in ipairs(self.roster_agents or {}) do
            agent_logic.prepareDecksForStateTransition(agent)
        end
    end

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
        local rumor_entries = rumor_missions.generate(strike_prep.getSlots())
        local preview_options = getStrikePreviewOptions(self, roster_theme, rumor_entries)
        local hovered_rumor = rumor_chain.getHovered(self, rumor_entries, screen_h, preview_options)
        local preview_room = getRumorMapPreview(self, hovered_rumor) or self.dev_map_preview_room

        map_preview.draw(self, preview_room, screen_h, preview_options)
        rumor_chain.draw(self, rumor_entries, screen_h, preview_options, {
            font = self.roster_font,
            outline_color = roster_theme.outline_color,
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

    drawEconTile(self, screen_h)
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
        self.strike_agent_press = nil
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
        self.strike_agent_press = nil
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
        local slotted_agent = slot_index and strike_prep.getSlots()[slot_index] or nil

        if slotted_agent then
            armStrikeAgentPress(self, slotted_agent, slot_index, x, y)
            return
        end
    end

    local agent = agent_roster.getAgentAtPoint(self, x, y)

    if agent then
        if strike_prep.isActive() then
            armStrikeAgentPress(self, agent, nil, x, y)
            return
        end

        openAgentModal(self, agent)
    end
end

function jacl_state:mousereleased(x, y, button)
    if button == 1 and self.strike_agent_press then
        local pressed_agent = self.strike_agent_press.agent

        if strikeAgentPressExceededThreshold(self, x, y) then
            beginStrikeAgentDrag(self)
        else
            self.strike_agent_press = nil
            openAgentModal(self, pressed_agent)
            return
        end
    end

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

function jacl_state:mousemoved(x, y)
    if self.strike_agent_press and strikeAgentPressExceededThreshold(self, x, y) then
        beginStrikeAgentDrag(self)
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

    if strike_prep.isActive() then
        local rumor_entries = rumor_missions.generate(strike_prep.getSlots())
        local roster_theme = agent_roster.getTheme()
        local preview_options = getStrikePreviewOptions(self, roster_theme, rumor_entries)

        if rumor_chain.wheelmoved(self, rumor_entries, love.graphics.getHeight(), preview_options, x, y) then
            return
        end
    end

    agent_roster.wheelmoved(self, x, y)
end

return jacl_state

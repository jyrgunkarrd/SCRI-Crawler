local image_loader = require("src.assets.image_loader")
local jacl_definitions = require("data.jacl")
local agent_uix = require("src.rndr.agent_uix")
local agent_logic = require("src.sys.agent_logic")
local econ = require("src.sys.econ")
local equip_logic = require("src.sys.equip_logic")
local luggage = require("src.sys.luggage")
local sfx_logic = require("src.sys.sfx_logic")
local strike_prep = require("src.sys.JACL_strk_prep")
local officers = require("src.sys.officers")
local map_preview = require("src.rndr.jacl_map_preview")
local agent_roster = require("src.rndr.jacl_agent_roster")
local strike_uix = require("src.rndr.jacl_strike_prep_uix")
local cache_rail = require("src.rndr.jacl_equipment_cache_rail")
local rumor_missions = require("src.sys.rumor_missions")
local rumor_chain = require("src.rndr.jacl_rumor_mission_chain")
local reward_uix = require("src.rndr.reward_uix")
local calendar = require("src.sys.calendar")

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
    pending_reward_summary = nil,
    reward_modal = nil,
    cashout_flash = nil,
    econ_pulse = nil,
    calendar = nil,
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
local REWARDS_BACKDROP_COLOR = { 0, 0, 0, 0.82 }
local REWARDS_PANEL_COLOR = { 0, 0, 0, 0.96 }
local REWARDS_BORDER_COLOR = { 1, 1, 1, 1 }
local REWARDS_TEXT_COLOR = { 1, 1, 1, 1 }
local REWARDS_TITLE_H = 30
local REWARDS_SECTION_GAP = 18
local REWARDS_PANEL_MAX_W = 960
local REWARDS_PANEL_PAD = 18
local REWARDS_PANEL_HEADER_H = 28
local REWARDS_ITEM_W = 122
local REWARDS_ITEM_GRID_SIZE = 94
local REWARDS_ITEM_LABEL_GAP = 6
local REWARDS_ITEM_LABEL_H = 36
local REWARDS_ITEM_GAP = 16
local REWARDS_AGENT_HEADER_H = 24
local REWARDS_AGENT_ITEMS_GAP = 8
local REWARDS_AGENT_SECTION_GAP = 18
local REWARD_CLAIM_FLASH_SECONDS = 0.08
local REWARD_CLAIM_FADE_SECONDS = 0.16
local CASHOUT_FLASH_SECONDS = 0.48
local ECON_PULSE_SECONDS = 0.28
local REWARD_CLAIM_COLOR = { 0, 1, 167 / 255, 1 }

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

local function drawEconTile(state, screen_h, options)
    options = options or {}

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
    local scale = tonumber(options.scale) or 1

    if scale ~= 1 then
        local center_x = ECON_TILE_X + tile_w / 2
        local center_y = tile_y + ECON_TILE_H / 2

        love.graphics.push()
        love.graphics.translate(center_x, center_y)
        love.graphics.scale(scale, scale)
        love.graphics.translate(-center_x, -center_y)
    end

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

    if scale ~= 1 then
        love.graphics.pop()
    end

    return {
        x = ECON_TILE_X,
        y = tile_y,
        w = tile_w,
        h = ECON_TILE_H,
    }
end

local function drawCashoutFlash(state, econ_rect)
    local flash = state.cashout_flash

    if not flash or not econ_rect then
        return
    end

    local progress = math.min(1, flash.elapsed / CASHOUT_FLASH_SECONDS)
    local blink = 0.42 + 0.58 * math.abs(math.sin(flash.elapsed * 34))
    local alpha = (1 - progress) * blink
    local font = state.econ_font or love.graphics.getFont()
    local text = "+" .. tostring(math.max(0, math.floor(tonumber(flash.value) or 0)))
    local text_x = econ_rect.x + (econ_rect.w - font:getWidth(text)) / 2
    local text_y = econ_rect.y - font:getHeight() - 10

    love.graphics.setFont(font)
    love.graphics.setColor(ECON_TEXT_COLOR[1], ECON_TEXT_COLOR[2], ECON_TEXT_COLOR[3], alpha)
    love.graphics.print(text, text_x, text_y)
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

local function createRewardsModal(summary)
    return {
        scratch = math.max(0, math.floor(tonumber(summary and summary.scratch) or 0)),
        scratch_available = true,
        luggage = luggage.collectFromAgents(summary and summary.agents or {}),
        scratch_rect = nil,
        luggage_rects = {},
    }
end

local function groupRewardLuggage(entries)
    local groups = {}
    local group_by_agent = {}

    for index, entry in ipairs(entries or {}) do
        local key = entry.agent or entry.slot_index or index
        local group = group_by_agent[key]

        if not group then
            group = {
                agent = entry.agent,
                entries = {},
            }
            group_by_agent[key] = group
            groups[#groups + 1] = group
        end

        group.entries[#group.entries + 1] = {
            entry = entry,
            modal_index = index,
        }
    end

    return groups
end

local function getRewardsModalLayout(state)
    local modal = state.reward_modal
    local screen_w = love.graphics.getWidth()
    local screen_h = love.graphics.getHeight()
    local max_panel_w = math.max(
        REWARDS_ITEM_W + REWARDS_PANEL_PAD * 2,
        math.min(REWARDS_PANEL_MAX_W, screen_w - 80)
    )
    local max_columns = math.max(
        1,
        math.floor((max_panel_w - REWARDS_PANEL_PAD * 2 + REWARDS_ITEM_GAP) / (REWARDS_ITEM_W + REWARDS_ITEM_GAP))
    )
    local groups = groupRewardLuggage(modal and modal.luggage or {})
    local largest_group = 0

    for _, group in ipairs(groups) do
        largest_group = math.max(largest_group, #group.entries)
    end

    local columns = math.max(1, math.min(max_columns, math.max(largest_group, 1)))
    local row_h = REWARDS_ITEM_GRID_SIZE + REWARDS_ITEM_LABEL_GAP + REWARDS_ITEM_LABEL_H
    local content_h = 0

    if #groups == 0 then
        content_h = row_h
    else
        for index, group in ipairs(groups) do
            group.header_offset_y = content_h
            content_h = content_h + REWARDS_AGENT_HEADER_H + REWARDS_AGENT_ITEMS_GAP
            group.items_offset_y = content_h
            group.rows = math.ceil(#group.entries / columns)
            content_h = content_h
                + group.rows * row_h
                + math.max(0, group.rows - 1) * REWARDS_ITEM_GAP

            if index < #groups then
                content_h = content_h + REWARDS_AGENT_SECTION_GAP
            end
        end
    end

    local panel_w = REWARDS_PANEL_PAD * 2
        + columns * REWARDS_ITEM_W
        + math.max(0, columns - 1) * REWARDS_ITEM_GAP
    local panel_h = REWARDS_PANEL_PAD
        + REWARDS_PANEL_HEADER_H
        + 10
        + content_h
        + REWARDS_PANEL_PAD
    local total_h = REWARDS_TITLE_H
        + REWARDS_SECTION_GAP
        + reward_uix.getTileHeight()
        + REWARDS_SECTION_GAP
        + panel_h
    local top_y = math.max(24, (screen_h - total_h) / 2)
    local scratch_y = top_y + REWARDS_TITLE_H + REWARDS_SECTION_GAP
    local panel_y = scratch_y + reward_uix.getTileHeight() + REWARDS_SECTION_GAP

    return {
        screen_w = screen_w,
        screen_h = screen_h,
        center_x = screen_w / 2,
        title_y = top_y,
        scratch_y = scratch_y,
        panel_x = (screen_w - panel_w) / 2,
        panel_y = panel_y,
        panel_w = panel_w,
        panel_h = panel_h,
        columns = columns,
        row_h = row_h,
        content_y = panel_y + REWARDS_PANEL_PAD + REWARDS_PANEL_HEADER_H + 10,
        groups = groups,
    }
end

local function getRewardClaimVisual(animation)
    if animation.elapsed <= REWARD_CLAIM_FLASH_SECONDS then
        local progress = animation.elapsed / REWARD_CLAIM_FLASH_SECONDS

        return 1 + 0.08 * progress, 1, 0.42 * (1 - progress)
    end

    local progress = math.min(
        1,
        (animation.elapsed - REWARD_CLAIM_FLASH_SECONDS) / REWARD_CLAIM_FADE_SECONDS
    )

    return 1.08 * (1 - progress), 1 - progress, 0
end

local function drawRewardClaimAnimation(state, font, item_font)
    local modal = state.reward_modal
    local animation = modal and modal.claim_animation or nil

    if not animation or not animation.rect then
        return
    end

    local rect = animation.rect
    local scale, alpha, flash_alpha = getRewardClaimVisual(animation)
    local center_x = rect.x + rect.w / 2
    local center_y = rect.y + rect.h / 2

    love.graphics.push()
    love.graphics.translate(center_x, center_y)
    love.graphics.scale(math.max(scale, 0.01), math.max(scale, 0.01))
    love.graphics.translate(-center_x, -center_y)

    if animation.kind == "scratch" then
        reward_uix.drawScratchTile(animation.value, center_x, rect.y, {
            font = font,
            alpha = alpha,
        })
    else
        luggage.draw(animation.entry.item, rect.x, rect.y, rect.w, rect.h, {
            font = item_font,
            alpha = alpha,
        })
    end

    if flash_alpha > 0 then
        love.graphics.setColor(
            REWARD_CLAIM_COLOR[1],
            REWARD_CLAIM_COLOR[2],
            REWARD_CLAIM_COLOR[3],
            flash_alpha
        )
        love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
        love.graphics.setColor(REWARD_CLAIM_COLOR)
        love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h)
        love.graphics.setLineWidth(1)
    end

    love.graphics.pop()
end

local function drawRewardsModal(state)
    local modal = state.reward_modal

    if not modal then
        return
    end

    local layout = getRewardsModalLayout(state)
    local font = state.econ_font or love.graphics.getFont()
    local item_font = state.roster_font or font
    local title = "REWARDS"

    love.graphics.setColor(REWARDS_BACKDROP_COLOR)
    love.graphics.rectangle("fill", 0, 0, layout.screen_w, layout.screen_h)
    love.graphics.setFont(font)
    love.graphics.setColor(REWARDS_TEXT_COLOR)
    love.graphics.print(title, layout.center_x - font:getWidth(title) / 2, layout.title_y)

    if modal.scratch_available then
        modal.scratch_rect = reward_uix.drawScratchTile(
            modal.scratch,
            layout.center_x,
            layout.scratch_y,
            { font = font }
        )
    else
        modal.scratch_rect = nil
    end

    love.graphics.setColor(REWARDS_PANEL_COLOR)
    love.graphics.rectangle("fill", layout.panel_x, layout.panel_y, layout.panel_w, layout.panel_h)
    love.graphics.setColor(REWARDS_BORDER_COLOR)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", layout.panel_x, layout.panel_y, layout.panel_w, layout.panel_h)
    love.graphics.setLineWidth(1)
    love.graphics.setFont(item_font)
    love.graphics.setColor(REWARDS_TEXT_COLOR)
    love.graphics.print("Luggage", layout.panel_x + REWARDS_PANEL_PAD, layout.panel_y + REWARDS_PANEL_PAD)

    modal.luggage_rects = {}

    for _, group in ipairs(layout.groups) do
        local agent_name = group.agent and (group.agent.name or group.agent.id) or "Agent"
        local header_y = layout.content_y + group.header_offset_y

        love.graphics.setFont(item_font)
        love.graphics.setColor(REWARDS_TEXT_COLOR)
        love.graphics.print(agent_name, layout.panel_x + REWARDS_PANEL_PAD, header_y)

        local divider_x = layout.panel_x + REWARDS_PANEL_PAD + item_font:getWidth(agent_name) + 12
        local divider_right = layout.panel_x + layout.panel_w - REWARDS_PANEL_PAD

        if divider_x < divider_right then
            love.graphics.setColor(1, 1, 1, 0.32)
            love.graphics.line(divider_x, header_y + item_font:getHeight() / 2, divider_right, header_y + item_font:getHeight() / 2)
        end

        for group_index, grouped_entry in ipairs(group.entries) do
            local entry = grouped_entry.entry
            local column = (group_index - 1) % layout.columns
            local row = math.floor((group_index - 1) / layout.columns)
            local item_x = layout.panel_x + REWARDS_PANEL_PAD + column * (REWARDS_ITEM_W + REWARDS_ITEM_GAP)
            local item_y = layout.content_y + group.items_offset_y + row * (layout.row_h + REWARDS_ITEM_GAP)
            local grid_x = item_x + (REWARDS_ITEM_W - REWARDS_ITEM_GRID_SIZE) / 2
            local item_name = entry.item and (entry.item.name or entry.item.id) or "Luggage"

            modal.luggage_rects[grouped_entry.modal_index] = {
                x = grid_x,
                y = item_y,
                w = REWARDS_ITEM_GRID_SIZE,
                h = REWARDS_ITEM_GRID_SIZE,
            }

            local claiming = modal.claim_animation and modal.claim_animation.entry == entry

            if not claiming then
                luggage.draw(entry.item, grid_x, item_y, REWARDS_ITEM_GRID_SIZE, REWARDS_ITEM_GRID_SIZE, {
                    font = item_font,
                })
                love.graphics.setFont(item_font)
                love.graphics.setColor(REWARDS_TEXT_COLOR)
                love.graphics.printf(
                    item_name,
                    item_x,
                    item_y + REWARDS_ITEM_GRID_SIZE + REWARDS_ITEM_LABEL_GAP,
                    REWARDS_ITEM_W,
                    "center"
                )
            end
        end
    end

    if #modal.luggage == 0 then
        love.graphics.setColor(1, 1, 1, 0.58)
        love.graphics.printf(
            "No luggage",
            layout.panel_x + REWARDS_PANEL_PAD,
            layout.content_y + (layout.row_h - item_font:getHeight()) / 2,
            layout.panel_w - REWARDS_PANEL_PAD * 2,
            "center"
        )
    end

    drawRewardClaimAnimation(state, font, item_font)
    love.graphics.setColor(1, 1, 1, 1)
end

local function dismissRewardsModalIfEmpty(state)
    local modal = state.reward_modal

    if modal and not modal.scratch_available and #modal.luggage == 0 then
        state.reward_modal = nil
    end
end

local function copyRect(rect)
    return {
        x = rect.x,
        y = rect.y,
        w = rect.w,
        h = rect.h,
    }
end

local function finishRewardClaim(state)
    local modal = state.reward_modal
    local animation = modal and modal.claim_animation or nil

    if not animation then
        return
    end

    if animation.kind == "luggage" then
        equip_logic.removeFromAgent(animation.entry.agent, animation.entry.item)

        for index, entry in ipairs(modal.luggage) do
            if entry == animation.entry then
                table.remove(modal.luggage, index)
                break
            end
        end

        modal.luggage_rects = {}
    end

    econ.add(animation.value)
    sfx_logic.playNamed("cash")
    state.cashout_flash = {
        value = animation.value,
        elapsed = 0,
    }
    state.econ_pulse = {
        elapsed = 0,
    }
    modal.claim_animation = nil
    dismissRewardsModalIfEmpty(state)
end

local function redeemRewardsAtPoint(state, x, y)
    local modal = state.reward_modal

    if not modal then
        return false
    end

    if modal.claim_animation then
        return true
    end

    if modal.scratch_available and modal.scratch_rect and pointInRect(x, y, modal.scratch_rect) then
        modal.scratch_available = false
        modal.claim_animation = {
            kind = "scratch",
            value = modal.scratch,
            rect = copyRect(modal.scratch_rect),
            elapsed = 0,
        }
        modal.scratch_rect = nil
        return true
    end

    for index, rect in ipairs(modal.luggage_rects or {}) do
        if pointInRect(x, y, rect) then
            local entry = modal.luggage[index]

            if entry then
                modal.claim_animation = {
                    kind = "luggage",
                    entry = entry,
                    value = luggage.getFilledValue(entry.item),
                    rect = copyRect(rect),
                    elapsed = 0,
                }
            end

            return true
        end
    end

    return false
end

function jacl_state:enter(previous_state, transition_options)
    self.pending_reward_summary = previous_state == "mission"
        and transition_options
        and transition_options.rewards
        or nil
    self.reward_modal = nil
    self.cashout_flash = nil
    self.econ_pulse = nil
    agent_uix.setExternalEquipmentPreview(nil)
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
    self.calendar = self.calendar or calendar.new()
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

function jacl_state:transitionComplete(previous_state)
    if previous_state == "mission" and self.pending_reward_summary then
        self.reward_modal = createRewardsModal(self.pending_reward_summary)
    end

    self.pending_reward_summary = nil
end

function jacl_state:update(dt)
    calendar.update(self.calendar, dt)

    local claim = self.reward_modal and self.reward_modal.claim_animation or nil

    if claim then
        claim.elapsed = claim.elapsed + dt

        if claim.elapsed >= REWARD_CLAIM_FLASH_SECONDS + REWARD_CLAIM_FADE_SECONDS then
            finishRewardClaim(self)
        end
    end

    if self.cashout_flash then
        self.cashout_flash.elapsed = self.cashout_flash.elapsed + dt

        if self.cashout_flash.elapsed >= CASHOUT_FLASH_SECONDS then
            self.cashout_flash = nil
        end
    end

    if self.econ_pulse then
        self.econ_pulse.elapsed = self.econ_pulse.elapsed + dt

        if self.econ_pulse.elapsed >= ECON_PULSE_SECONDS then
            self.econ_pulse = nil
        end
    end
end

function jacl_state:leave(next_state)
    self.strike_agent_press = nil
    self.pending_reward_summary = nil
    self.reward_modal = nil
    self.cashout_flash = nil
    self.econ_pulse = nil
    agent_uix.setExternalEquipmentPreview(nil)
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

    calendar.draw(self.calendar, screen_w, screen_h)
    drawEconTile(self, screen_h)
    agent_roster.draw(self)
    strike_uix.drawPanel(self, agent_roster.getLayout(), {
        font = self.roster_font,
        outline_color = roster_theme.outline_color,
        slot_outline_color = roster_theme.prompt_outline_color,
        empty_color = roster_theme.empty_color,
        draw_agent_portrait = agent_roster.drawAgentPortrait,
    })
    agent_uix.setExternalEquipmentPreview(cache_rail.getHoveredPreviewItem(self))
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
    drawRewardsModal(self)

    if self.reward_modal or self.cashout_flash or self.econ_pulse then
        local pulse_scale = 1

        if self.econ_pulse then
            local progress = math.min(1, self.econ_pulse.elapsed / ECON_PULSE_SECONDS)

            pulse_scale = 1 + 0.08 * math.sin(math.pi * progress)
        end

        local econ_rect = drawEconTile(self, screen_h, { scale = pulse_scale })

        drawCashoutFlash(self, econ_rect)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

local function endCommandPhase(state)
    if not calendar.endCommandPhase(state.calendar) then
        return false
    end

    sfx_logic.playNamed("command")
    state.strike_agent_press = nil
    state.roster_search_focused = false
    cache_rail.clearTransient(state)
    strike_prep.exit()

    while agent_uix.closeModal() do
        -- Close nested viewers before closing their parent agent modal.
    end

    return true
end

function jacl_state:keypressed(key)
    if self.reward_modal then
        return
    end

    if key == "space" and endCommandPhase(self) then
        return
    end

    if not calendar.isCommandPhase(self.calendar) then
        return
    end

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
    if not calendar.isCommandPhase(self.calendar) then
        return
    end

    if self.reward_modal then
        if button == 1 then
            redeemRewardsAtPoint(self, x, y)
        end

        return
    end

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
    if not calendar.isCommandPhase(self.calendar) then
        return
    end

    if self.reward_modal then
        return
    end

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
    if not calendar.isCommandPhase(self.calendar) then
        return
    end

    if self.strike_agent_press and strikeAgentPressExceededThreshold(self, x, y) then
        beginStrikeAgentDrag(self)
    end
end

function jacl_state:textinput(text)
    if not calendar.isCommandPhase(self.calendar) then
        return
    end

    if self.reward_modal then
        return
    end

    if cache_rail.textinput(self, text) then
        return
    end

    if agent_uix.isModalOpen() then
        return
    end

    agent_roster.textinput(self, text)
end

function jacl_state:wheelmoved(x, y)
    if not calendar.isCommandPhase(self.calendar) then
        return
    end

    if self.reward_modal then
        return
    end

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

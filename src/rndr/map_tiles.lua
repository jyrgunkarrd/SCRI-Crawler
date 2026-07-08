local map_tiles = {}
local image_loader = require("src.assets.image_loader")
local burn_palette = require("data.burn_palette")
local sfx_logic = require("src.sys.sfx_logic")
local block_logic = require("src.sys.block_logic")

local HEX_SIZE = 54
local SQRT_3 = math.sqrt(3)
local TILE_COLOR = { 0.33, 0.49, 0.42, 1 }
local CORRIDOR_COLOR = { 0.27, 0.39, 0.35, 1 }
local AGENT_PORTRAIT_DIR = "assets/images/agents"
local ENEMY_PORTRAIT_DIR = "assets/images/enemy"
local HAZARD_PORTRAIT_DIR = "assets/images/hazard"
local PORTRAIT_RADIUS = HEX_SIZE * 0.78
local PORTRAIT_OUTLINE_COLOR = { 0.015, 0.012, 0.01, 1 }
local ENEMY_PORTRAIT_OUTLINE_COLOR = { 0.6118, 0, 0.0431, 1 }
local HAZARD_PORTRAIT_OUTLINE_COLOR = { 0.9765, 0.6314, 0, 1 }
local ENEMY_PORTRAIT_OUTLINE_INSET = 5
local EXHAUSTED_PORTRAIT_COLOR = { 0.34, 0.34, 0.34, 0.72 }
local SELECTED_PULSE_SPEED = 3.6
local SELECTED_PULSE_AMOUNT = 0.075
local SHOUT_BOX_COLOR = { 1, 1, 1, 0.96 }
local SHOUT_TEXT_COLOR = { 0, 0, 0, 1 }
local SHOUT_BOX_H = 34
local SHOUT_BOX_PAD_X = 10
local SHOUT_BOX_PAD_Y = 4
local MOVE_EASE_OVERSHOOT = 1.04
local ELIMINATION_ANIMATION_SECONDS = 0.55
local ELIMINATION_MIN_SCALE = 0.72
local BLOCK_GLYPH = "\239\143\173"
local BLOCK_COLOR = { 0.7412, 0.6824, 0.7176, 1 }
local BLOCK_OVERLAY_FONT_SIZE = 18
local BLOCK_OVERLAY_RING_SECONDS = 0.28
local BLOCK_OVERLAY_RING_START_RADIUS = PORTRAIT_RADIUS * 0.56
local BLOCK_OVERLAY_RING_END_RADIUS = PORTRAIT_RADIUS * 1.18
local BLOCK_OVERLAY_RING_WIDTH = 5
local CORPSE_BADGE_GLYPH = "\239\149\140"
local TOKEN_BADGE_RADIUS = 15
local TOKEN_BADGE_FONT_SIZE = 18
local TOKEN_BADGE_Y_OFFSET = PORTRAIT_RADIUS * 0.68
local agent_portraits = {}
local missing_agent_portraits = {}
local enemy_portraits = {}
local missing_enemy_portraits = {}
local hazard_portraits = {}
local missing_hazard_portraits = {}
local agent_eliminations = {}
local agent_elimination_sound_played = false
local block_overlay_font = nil
local block_overlay_states = setmetatable({}, { __mode = "k" })
local corpse_greyscale_shader = nil
local corpse_badge_font = nil

local function hexToColor(hex, alpha)
    if type(hex) ~= "string" or #hex < 6 then
        return { 1, 1, 1, alpha or 1 }
    end

    return {
        tonumber(hex:sub(1, 2), 16) / 255,
        tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255,
        alpha or 1,
    }
end

local function axialToPixel(q, r)
    return HEX_SIZE * SQRT_3 * (q + r / 2), HEX_SIZE * 1.5 * r
end

local function buildHexPoints(center_x, center_y, radius)
    local points = {}
    radius = radius or HEX_SIZE

    for index = 0, 5 do
        local angle = math.rad(-90 + index * 60)
        points[#points + 1] = center_x + radius * math.cos(angle)
        points[#points + 1] = center_y + radius * math.sin(angle)
    end

    return points
end

local function getBounds(room)
    local min_x = math.huge
    local min_y = math.huge
    local max_x = -math.huge
    local max_y = -math.huge

    for _, tile in ipairs(room.tiles) do
        local x, y = axialToPixel(tile.q, tile.r)

        min_x = math.min(min_x, x - HEX_SIZE)
        min_y = math.min(min_y, y - HEX_SIZE)
        max_x = math.max(max_x, x + HEX_SIZE)
        max_y = math.max(max_y, y + HEX_SIZE)
    end

    return min_x, min_y, max_x, max_y
end

local function getCenteredOffset(room)
    local min_x, min_y, max_x, max_y = getBounds(room)
    local room_width = max_x - min_x
    local room_height = max_y - min_y
    local screen_width = love.graphics.getWidth()
    local screen_height = love.graphics.getHeight()

    return (screen_width - room_width) / 2 - min_x, (screen_height - room_height) / 2 - min_y
end

local function getAgentPortrait(agent)
    if not agent or not agent.id then
        return nil
    end

    if agent_portraits[agent.id] then
        return agent_portraits[agent.id]
    end

    if missing_agent_portraits[agent.id] then
        return nil
    end

    local path = ("%s/%s.webp"):format(AGENT_PORTRAIT_DIR, agent.id)
    local ok, image = pcall(image_loader.newImage, path)

    if not ok then
        print("Unable to load agent portrait '" .. path .. "': " .. tostring(image))
        missing_agent_portraits[agent.id] = true
        return nil
    end

    agent_portraits[agent.id] = image

    return image
end

function map_tiles.getAgentPortrait(agent)
    return getAgentPortrait(agent)
end

local function getEnemyPortrait(enemy)
    if not enemy or not enemy.id then
        return nil
    end

    if enemy_portraits[enemy.id] then
        return enemy_portraits[enemy.id]
    end

    if missing_enemy_portraits[enemy.id] then
        return nil
    end

    local path = ("%s/%s.webp"):format(ENEMY_PORTRAIT_DIR, enemy.id)
    local ok, image = pcall(image_loader.newImage, path)

    if not ok then
        print("Unable to load enemy portrait '" .. path .. "': " .. tostring(image))
        missing_enemy_portraits[enemy.id] = true
        return nil
    end

    enemy_portraits[enemy.id] = image

    return image
end

function map_tiles.getEnemyPortrait(enemy)
    return getEnemyPortrait(enemy)
end

local function getHazardPortrait(hazard)
    if not hazard or not hazard.id then
        return nil
    end

    if hazard_portraits[hazard.id] then
        return hazard_portraits[hazard.id]
    end

    if missing_hazard_portraits[hazard.id] then
        return nil
    end

    local path = ("%s/%s.webp"):format(HAZARD_PORTRAIT_DIR, hazard.id)
    local ok, image = pcall(image_loader.newImage, path)

    if not ok then
        print("Unable to load hazard portrait '" .. path .. "': " .. tostring(image))
        missing_hazard_portraits[hazard.id] = true
        return nil
    end

    hazard_portraits[hazard.id] = image

    return image
end

function map_tiles.getHazardPortrait(hazard)
    return getHazardPortrait(hazard)
end

local function getAgentCurrentAp(agent)
    if not agent or not agent.runtime_stats or not agent.runtime_stats.ap then
        return nil
    end

    return agent.runtime_stats.ap.current
end

local function getCorpseGreyscaleShader()
    if corpse_greyscale_shader then
        return corpse_greyscale_shader
    end

    corpse_greyscale_shader = love.graphics.newShader([[
        vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
        {
            vec4 pixel = Texel(texture, texture_coords) * color;
            float grey = dot(pixel.rgb, vec3(0.299, 0.587, 0.114));
            return vec4(vec3(grey), pixel.a);
        }
    ]])

    return corpse_greyscale_shader
end

local function drawHexPortrait(image, center_x, center_y, radius, color, outline_color, inset_outline_radius, outer_outline_color, image_shader)
    local points = buildHexPoints(center_x, center_y, radius)
    local scale = (radius * 2) / math.min(image:getWidth(), image:getHeight())

    love.graphics.stencil(function()
        love.graphics.polygon("fill", points)
    end, "replace", 1)

    love.graphics.setStencilTest("equal", 1)
    love.graphics.setColor(color)
    if image_shader then
        love.graphics.setShader(image_shader)
    end
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
    if image_shader then
        love.graphics.setShader()
    end
    love.graphics.setStencilTest()

    love.graphics.setLineWidth(3)

    if outer_outline_color then
        love.graphics.setColor(outer_outline_color)
        love.graphics.polygon("line", points)
    end

    love.graphics.setColor(outline_color)
    love.graphics.polygon("line", inset_outline_radius and buildHexPoints(center_x, center_y, inset_outline_radius) or points)
    love.graphics.setLineWidth(1)
end

local function drawBlockOverlay(unit, center_x, center_y)
    if block_logic.getBlock(unit) <= 0 then
        block_overlay_states[unit] = nil
        return
    end

    if not block_overlay_font then
        block_overlay_font = love.graphics.newFont("assets/fonts/icons.otf", BLOCK_OVERLAY_FONT_SIZE)
    end

    local state = block_overlay_states[unit]
    local pulse_id = unit.block_pulse_id or 0

    if not state then
        state = { elapsed = 0, pulse_id = pulse_id }
        block_overlay_states[unit] = state
    elseif state.pulse_id ~= pulse_id then
        state.elapsed = 0
        state.pulse_id = pulse_id
    end

    if state.elapsed < BLOCK_OVERLAY_RING_SECONDS then
        local t = math.max(0, math.min(state.elapsed / BLOCK_OVERLAY_RING_SECONDS, 1))
        local eased = 1 - (1 - t) * (1 - t) * (1 - t)
        local ring_radius = BLOCK_OVERLAY_RING_START_RADIUS
            + (BLOCK_OVERLAY_RING_END_RADIUS - BLOCK_OVERLAY_RING_START_RADIUS) * eased
        local ring_alpha = 1 - t

        love.graphics.setColor(BLOCK_COLOR[1], BLOCK_COLOR[2], BLOCK_COLOR[3], ring_alpha)
        love.graphics.setLineWidth(BLOCK_OVERLAY_RING_WIDTH)
        love.graphics.circle("line", center_x, center_y, ring_radius, 96)
        love.graphics.setLineWidth(1)
    end

    local badge_y = center_y + TOKEN_BADGE_Y_OFFSET
    local previous_font = love.graphics.getFont()

    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.circle("fill", center_x, badge_y, TOKEN_BADGE_RADIUS, 48)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(block_overlay_font)
    love.graphics.print(
        BLOCK_GLYPH,
        center_x - block_overlay_font:getWidth(BLOCK_GLYPH) / 2,
        badge_y - block_overlay_font:getHeight() / 2
    )
    love.graphics.setFont(previous_font)
end

local function drawAgentPortraitTile(tile, center_x, center_y, selected)
    if not tile.agent then
        return
    end

    local image = getAgentPortrait(tile.agent)

    if not image then
        return
    end

    local pulse_scale = 1

    if selected then
        pulse_scale = 1 + math.sin(love.timer.getTime() * SELECTED_PULSE_SPEED) * SELECTED_PULSE_AMOUNT
    end

    local radius = PORTRAIT_RADIUS * pulse_scale
    local color = { 1, 1, 1, 1 }

    if getAgentCurrentAp(tile.agent) == 0 then
        color = EXHAUSTED_PORTRAIT_COLOR
    end

    drawHexPortrait(image, center_x, center_y, radius, color, PORTRAIT_OUTLINE_COLOR)
    drawBlockOverlay(tile.agent, center_x, center_y)
end

local function drawEnemyPortraitTile(tile, center_x, center_y, selected)
    if not tile.enemy then
        return
    end

    local image = getEnemyPortrait(tile.enemy)

    if not image then
        return
    end

    local pulse_scale = 1

    if selected then
        pulse_scale = 1 + math.sin(love.timer.getTime() * SELECTED_PULSE_SPEED) * SELECTED_PULSE_AMOUNT
    end

    local radius = PORTRAIT_RADIUS * pulse_scale

    drawHexPortrait(
        image,
        center_x,
        center_y,
        radius,
        { 1, 1, 1, 1 },
        ENEMY_PORTRAIT_OUTLINE_COLOR,
        radius - ENEMY_PORTRAIT_OUTLINE_INSET,
        PORTRAIT_OUTLINE_COLOR
    )
    drawBlockOverlay(tile.enemy, center_x, center_y)
end

local function drawHazardPortraitTile(tile, center_x, center_y, selected)
    if not tile.hazard then
        return
    end

    local image = getHazardPortrait(tile.hazard)

    if not image then
        return
    end

    local pulse_scale = 1

    if selected then
        pulse_scale = 1 + math.sin(love.timer.getTime() * SELECTED_PULSE_SPEED) * SELECTED_PULSE_AMOUNT
    end

    local radius = PORTRAIT_RADIUS * pulse_scale

    drawHexPortrait(
        image,
        center_x,
        center_y,
        radius,
        { 1, 1, 1, 1 },
        HAZARD_PORTRAIT_OUTLINE_COLOR,
        radius - ENEMY_PORTRAIT_OUTLINE_INSET,
        PORTRAIT_OUTLINE_COLOR
    )
    drawBlockOverlay(tile.hazard, center_x, center_y)
end

local function drawCorpsePortraitTile(tile, center_x, center_y)
    if not tile.corpse or tile.agent or tile.enemy or tile.hazard then
        return
    end

    local image = getEnemyPortrait(tile.corpse)

    if not image then
        return
    end

    drawHexPortrait(
        image,
        center_x,
        center_y,
        PORTRAIT_RADIUS,
        { 1, 1, 1, 1 },
        PORTRAIT_OUTLINE_COLOR,
        nil,
        nil,
        getCorpseGreyscaleShader()
    )

    if not corpse_badge_font then
        corpse_badge_font = love.graphics.newFont("assets/fonts/icons.otf", TOKEN_BADGE_FONT_SIZE)
    end

    local badge_y = center_y + TOKEN_BADGE_Y_OFFSET
    local previous_font = love.graphics.getFont()

    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.circle("fill", center_x, badge_y, TOKEN_BADGE_RADIUS, 48)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(corpse_badge_font)
    love.graphics.print(
        CORPSE_BADGE_GLYPH,
        center_x - corpse_badge_font:getWidth(CORPSE_BADGE_GLYPH) / 2,
        badge_y - corpse_badge_font:getHeight() / 2 - 1
    )
    love.graphics.setFont(previous_font)
end

local function drawMovingPortrait(unit, kind, center_x, center_y)
    local image = kind == "hazard" and getHazardPortrait(unit)
        or kind == "enemy" and getEnemyPortrait(unit)
        or getAgentPortrait(unit)

    if not image then
        return
    end

    if kind == "enemy" or kind == "hazard" then
        drawHexPortrait(
            image,
            center_x,
            center_y,
            PORTRAIT_RADIUS,
            { 1, 1, 1, 1 },
            kind == "hazard" and HAZARD_PORTRAIT_OUTLINE_COLOR or ENEMY_PORTRAIT_OUTLINE_COLOR,
            PORTRAIT_RADIUS - ENEMY_PORTRAIT_OUTLINE_INSET,
            PORTRAIT_OUTLINE_COLOR
        )
        drawBlockOverlay(unit, center_x, center_y)
    else
        drawHexPortrait(image, center_x, center_y, PORTRAIT_RADIUS, { 1, 1, 1, 1 }, PORTRAIT_OUTLINE_COLOR)
        drawBlockOverlay(unit, center_x, center_y)
    end
end

local function drawAgentEliminations(offset_x, offset_y)
    for index = #agent_eliminations, 1, -1 do
        local animation = agent_eliminations[index]
        local image = getAgentPortrait(animation.agent)

        if not image then
            table.remove(agent_eliminations, index)
        else
            local progress = math.min(animation.elapsed / ELIMINATION_ANIMATION_SECONDS, 1)
            local x, y = axialToPixel(animation.q, animation.r)
            local center_x = x + offset_x
            local center_y = y + offset_y
            local alpha = progress < 0.22 and 1 or 1 - ((progress - 0.22) / 0.78)
            local scale = 1 - (1 - ELIMINATION_MIN_SCALE) * progress
            local color_index = 2 + math.min(3, math.floor(progress * 8) % 4)
            local color = hexToColor(burn_palette["burn" .. tostring(color_index)], math.max(0, alpha))

            if progress > 0.42 then
                local fade = (progress - 0.42) / 0.58

                color[1] = color[1] * (1 - fade)
                color[2] = color[2] * (1 - fade)
                color[3] = color[3] * (1 - fade)
            end

            drawHexPortrait(
                image,
                center_x,
                center_y,
                PORTRAIT_RADIUS * scale,
                color,
                { 0, 0, 0, math.max(0, alpha) }
            )
        end
    end
end

local function easeOutBack(t)
    local overshoot = MOVE_EASE_OVERSHOOT
    local shifted = t - 1

    return 1 + shifted * shifted * ((overshoot + 1) * shifted + overshoot)
end

function map_tiles.axialToPixel(q, r)
    return axialToPixel(q, r)
end

function map_tiles.buildHexPoints(center_x, center_y)
    return buildHexPoints(center_x, center_y)
end

function map_tiles.getCenteredOffset(room)
    return getCenteredOffset(room)
end

function map_tiles.getBounds(room)
    return getBounds(room)
end

local function getDrawOffset(room, camera_x, camera_y)
    local offset_x, offset_y = getCenteredOffset(room)

    return offset_x + (camera_x or 0), offset_y + (camera_y or 0)
end

function map_tiles.drawBase(room, camera_x, camera_y)
    if not room or not room.tiles then
        return
    end

    local offset_x, offset_y = getDrawOffset(room, camera_x, camera_y)

    for _, tile in ipairs(room.tiles) do
        local x, y = axialToPixel(tile.q, tile.r)

        if tile.color then
            love.graphics.setColor(tile.color)
        elseif tile.corridor then
            love.graphics.setColor(CORRIDOR_COLOR)
        else
            love.graphics.setColor(TILE_COLOR)
        end

        local center_x = x + offset_x
        local center_y = y + offset_y

        love.graphics.polygon("fill", buildHexPoints(center_x, center_y))
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function map_tiles.drawPortraits(room, camera_x, camera_y, selected_tile, moving_unit, moving_kind)
    if not room or not room.tiles then
        return
    end

    local offset_x, offset_y = getDrawOffset(room, camera_x, camera_y)

    for _, tile in ipairs(room.tiles) do
        local x, y = axialToPixel(tile.q, tile.r)
        local center_x = x + offset_x
        local center_y = y + offset_y

        drawCorpsePortraitTile(tile, center_x, center_y)
        drawHazardPortraitTile(tile, center_x, center_y, tile == selected_tile)

        if tile.enemy ~= moving_unit or moving_kind ~= "enemy" then
            drawEnemyPortraitTile(tile, center_x, center_y, tile == selected_tile)
        end

        if tile.agent ~= moving_unit or moving_kind == "enemy" then
            drawAgentPortraitTile(tile, center_x, center_y, tile == selected_tile)
        end
    end

    drawAgentEliminations(offset_x, offset_y)

    love.graphics.setColor(1, 1, 1, 1)
end

function map_tiles.update(dt)
    agent_elimination_sound_played = false

    for _, state in pairs(block_overlay_states) do
        state.elapsed = state.elapsed + dt
    end

    for index = #agent_eliminations, 1, -1 do
        local animation = agent_eliminations[index]

        animation.elapsed = animation.elapsed + dt

        if animation.elapsed >= ELIMINATION_ANIMATION_SECONDS then
            table.remove(agent_eliminations, index)
        end
    end
end

function map_tiles.startAgentElimination(agent, tile, options)
    if not agent or not tile then
        return false
    end

    agent_eliminations[#agent_eliminations + 1] = {
        agent = agent,
        q = tile.q,
        r = tile.r,
        elapsed = 0,
    }

    options = options or {}

    if options.play_sound ~= false and not agent_elimination_sound_played then
        sfx_logic.playNamed("agent_ko")
        agent_elimination_sound_played = true
    end

    return true
end

function map_tiles.clearAnimations()
    agent_eliminations = {}
    agent_elimination_sound_played = false
    block_overlay_states = setmetatable({}, { __mode = "k" })
end

function map_tiles.drawMovingAgent(room, camera_x, camera_y, animation)
    if not room or not animation or not animation.agent or not animation.from or not animation.to then
        return
    end

    local offset_x, offset_y = getDrawOffset(room, camera_x, camera_y)
    local from_x, from_y = axialToPixel(animation.from.q, animation.from.r)
    local to_x, to_y = axialToPixel(animation.to.q, animation.to.r)
    local progress = math.min(animation.elapsed / animation.duration, 1)
    local eased = easeOutBack(progress)
    local x = from_x + (to_x - from_x) * eased + offset_x
    local y = from_y + (to_y - from_y) * eased + offset_y

    drawMovingPortrait(animation.agent, animation.kind or "agent", x, y)
    love.graphics.setColor(1, 1, 1, 1)
end

function map_tiles.drawSelectionShout(room, camera_x, camera_y, selected_tile, shout)
    if not room or not selected_tile or not shout or not shout.text then
        return
    end

    local offset_x, offset_y = getDrawOffset(room, camera_x, camera_y)
    local x, y = axialToPixel(selected_tile.q, selected_tile.r)
    local center_x = x + offset_x
    local center_y = y + offset_y
    local font = love.graphics.getFont()
    local text_w = font:getWidth(shout.text)
    local box_w = text_w + SHOUT_BOX_PAD_X * 2
    local box_x = center_x - box_w / 2
    local box_y = center_y + PORTRAIT_RADIUS * 0.16

    love.graphics.setColor(SHOUT_BOX_COLOR)
    love.graphics.rectangle("fill", box_x, box_y, box_w, SHOUT_BOX_H)

    love.graphics.setColor(SHOUT_TEXT_COLOR)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", box_x, box_y, box_w, SHOUT_BOX_H)
    love.graphics.setLineWidth(1)
    love.graphics.print(shout.text, box_x + SHOUT_BOX_PAD_X, box_y + SHOUT_BOX_PAD_Y)

    love.graphics.setColor(1, 1, 1, 1)
end

function map_tiles.draw(room, camera_x, camera_y)
    map_tiles.drawBase(room, camera_x, camera_y)
    map_tiles.drawPortraits(room, camera_x, camera_y)
end

return map_tiles

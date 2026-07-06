local card_vis = require("src.rndr.card_vis")
local image_loader = require("src.assets.image_loader")
local sfx_logic = require("src.sys.sfx_logic")

local action_vis = {}

local AGENT_IMAGE_DIR = "assets/images/agents"
local ENEMY_IMAGE_DIR = "assets/images/enemy"
local BACKDROP_COLOR = { 0, 0, 0, 0.72 }
local SHADOW_COLOR = { 0, 0, 0, 0.62 }
local DAMAGE_TEXT_COLOR = { 1, 0.2902, 0.4902, 1 }
local IMAGE_H = 520
local CARD_W = 150
local DAMAGE_BOX_PAD_X = 12
local DAMAGE_BOX_PAD_Y = 7
local SLIDE_DURATION = 0.34
local PROJECTILE_OVERLAP = 0.08
local FOLLOW_THROUGH_DURATION = 0.24
local FOLLOW_THROUGH_X = 28
local PROJECTILE_DURATION = 0.34
local MISS_SOUND_T = 0.78
local IMPACT_DURATION = 0.28
local FALL_DURATION = 0.62
local HOLD_DURATION = 0.22

local active = nil
local full_images = {}
local missing_full_images = {}

local function clamp01(value)
    return math.max(0, math.min(value, 1))
end

local function easeOutCubic(t)
    t = clamp01(t)

    return 1 - (1 - t) * (1 - t) * (1 - t)
end

local function easeInCubic(t)
    t = clamp01(t)

    return t * t * t
end

local function getImageDir(kind)
    return kind == "enemy" and ENEMY_IMAGE_DIR or AGENT_IMAGE_DIR
end

local function getFullImage(unit, kind)
    if not unit or not unit.id then
        return nil
    end

    local cache_key = (kind or "agent") .. ":" .. unit.id

    if full_images[cache_key] then
        return full_images[cache_key]
    end

    if missing_full_images[cache_key] then
        return nil
    end

    local image_dir = getImageDir(kind)
    local paths = {
        ("%s/%s-full.webp"):format(image_dir, unit.id),
        ("%s/%sfull.webp"):format(image_dir, unit.id),
    }

    for _, path in ipairs(paths) do
        if love.filesystem.getInfo(path, "file") then
            local ok, image = pcall(image_loader.newImage, path)

            if ok then
                full_images[cache_key] = image
                return image
            end

            print("Unable to load action cut-in image '" .. path .. "': " .. tostring(image))
        end
    end

    missing_full_images[cache_key] = true

    return nil
end

local function getImageDraw(unit, kind, center_x, center_y, height)
    local image = getFullImage(unit, kind)

    if not image then
        return {
            image = nil,
            x = center_x - height / 2,
            y = center_y - height / 2,
            w = height,
            h = height,
            scale = 1,
        }
    end

    local scale = height / image:getHeight()
    local width = image:getWidth() * scale

    return {
        image = image,
        x = center_x - width / 2,
        y = center_y - height / 2,
        w = width,
        h = height,
        scale = scale,
    }
end

local function drawUnitImage(unit, kind, center_x, center_y, height, rotation, alpha)
    local draw = getImageDraw(unit, kind, center_x, center_y, height)

    love.graphics.setColor(SHADOW_COLOR[1], SHADOW_COLOR[2], SHADOW_COLOR[3], SHADOW_COLOR[4] * (alpha or 1))
    love.graphics.rectangle("fill", draw.x + 10, draw.y + 14, draw.w, draw.h)

    if not draw.image then
        love.graphics.setColor(0.04, 0.038, 0.034, alpha or 1)
        love.graphics.rectangle("fill", draw.x, draw.y, draw.w, draw.h)
        love.graphics.setColor(1, 1, 1, alpha or 1)
        love.graphics.printf(unit and (unit.name or unit.id) or "", draw.x, center_y - 10, draw.w, "center")
        return
    end

    love.graphics.setColor(1, 1, 1, alpha or 1)
    love.graphics.draw(
        draw.image,
        center_x,
        center_y,
        rotation or 0,
        draw.scale,
        draw.scale,
        draw.image:getWidth() / 2,
        draw.image:getHeight() / 2
    )
end

local function getLayout()
    local screen_w = love.graphics.getWidth()
    local screen_h = love.graphics.getHeight()
    local center_x = screen_w / 2
    local center_y = screen_h / 2

    return {
        center_y = center_y,
        agent_start_x = -260,
        agent_x = center_x - 270,
        target_x = center_x + 270,
        card_hit_x = center_x + 145,
        card_hit_y = center_y - 10,
        card_fail_x = screen_w + 160,
        card_fail_y = center_y - 36,
    }
end

local function getAgentX(animation, layout)
    local slide_t = easeOutCubic(animation.elapsed / SLIDE_DURATION)
    local agent_x = layout.agent_start_x + (layout.agent_x - layout.agent_start_x) * slide_t
    local follow_t = clamp01((animation.elapsed - animation.projectile_start) / FOLLOW_THROUGH_DURATION)

    return agent_x + FOLLOW_THROUGH_X * easeOutCubic(follow_t)
end

local function getProjectileOrigin(animation, layout)
    local launch_slide_t = easeOutCubic(animation.projectile_start / SLIDE_DURATION)
    local launch_agent_x = layout.agent_start_x + (layout.agent_x - layout.agent_start_x) * launch_slide_t

    return launch_agent_x + 128, layout.center_y - 20
end

local function getProjectilePosition(animation, layout, t, failed)
    local eased = easeOutCubic(t)
    local target_x = failed and layout.card_fail_x or layout.card_hit_x
    local target_y = failed and layout.card_fail_y or layout.card_hit_y
    local start_x, start_y = getProjectileOrigin(animation, layout)

    return start_x + (target_x - start_x) * eased,
        start_y + (target_y - start_y) * eased
end

local function getTargetJitter(animation)
    if not animation.damaged or animation.failed then
        return 0, 0
    end

    local impact_t = animation.elapsed - animation.impact_start

    if impact_t < 0 or impact_t > IMPACT_DURATION then
        return 0, 0
    end

    local strength = (1 - impact_t / IMPACT_DURATION) * 16
    local shake = math.sin(impact_t * 86)

    return shake * strength, math.cos(impact_t * 73) * strength * 0.45
end

local function getTargetFall(animation)
    if not animation.eliminated then
        return 0, 0, 0
    end

    local fall_t = clamp01((animation.elapsed - animation.impact_start) / FALL_DURATION)
    local eased = easeInCubic(fall_t)

    return math.rad(45) * eased, 0, love.graphics.getHeight() * 0.9 * eased
end

local function drawDamageBox(damage, x, y)
    local text = tostring(math.floor(tonumber(damage) or 0))
    local font = love.graphics.getFont()
    local text_w = font:getWidth(text)
    local text_h = font:getHeight()
    local box_w = text_w + DAMAGE_BOX_PAD_X * 2
    local box_h = text_h + DAMAGE_BOX_PAD_Y * 2
    local box_x = x + CARD_W / 2 + 18
    local box_y = y - box_h / 2

    love.graphics.setColor(0, 0, 0, 0.94)
    love.graphics.rectangle("fill", box_x, box_y, box_w, box_h)
    love.graphics.setColor(DAMAGE_TEXT_COLOR)
    love.graphics.print(text, box_x + DAMAGE_BOX_PAD_X, box_y + DAMAGE_BOX_PAD_Y - 1)
end

function action_vis.start(event)
    if not event or not event.agent or not event.target or not event.card then
        return
    end

    active = {
        event = event,
        elapsed = 0,
        projectile_start = SLIDE_DURATION - PROJECTILE_OVERLAP,
        impact_start = SLIDE_DURATION - PROJECTILE_OVERLAP + PROJECTILE_DURATION,
        total_duration = SLIDE_DURATION - PROJECTILE_OVERLAP + PROJECTILE_DURATION + math.max(IMPACT_DURATION + HOLD_DURATION, FALL_DURATION),
        damaged = event.damaged,
        eliminated = event.eliminated,
        failed = event.failed,
        impact_sfx_played = false,
        miss_sfx_played = false,
    }
end

function action_vis.update(dt)
    if not active then
        return
    end

    active.elapsed = active.elapsed + dt

    if active.failed and not active.miss_sfx_played then
        local miss_time = active.projectile_start + PROJECTILE_DURATION * MISS_SOUND_T

        if active.elapsed >= miss_time then
            sfx_logic.playNamed("miss")
            active.miss_sfx_played = true
        end
    end

    if not active.failed and not active.impact_sfx_played and active.elapsed >= active.impact_start then
        if active.eliminated then
            sfx_logic.playNamed("destroy")
        elseif active.damaged then
            sfx_logic.playNamed("dmg")
        end

        active.impact_sfx_played = true
    end

    if active.elapsed >= active.total_duration then
        active = nil
    end
end

function action_vis.isActive()
    return active ~= nil
end

function action_vis.draw()
    if not active then
        return
    end

    local event = active.event
    local layout = getLayout()
    local agent_x = getAgentX(active, layout)
    local target_jitter_x, target_jitter_y = getTargetJitter(active)
    local target_rotation, _, target_fall_y = getTargetFall(active)

    love.graphics.setColor(BACKDROP_COLOR)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())

    drawUnitImage(
        event.target,
        event.target_kind,
        layout.target_x + target_jitter_x,
        layout.center_y + target_jitter_y + target_fall_y,
        IMAGE_H,
        target_rotation,
        1
    )
    drawUnitImage(event.agent, event.agent_kind or "agent", agent_x, layout.center_y + 8, IMAGE_H, 0, 1)

    if active.elapsed >= active.projectile_start then
        local projectile_t = clamp01((active.elapsed - active.projectile_start) / PROJECTILE_DURATION)
        local card_x, card_y = getProjectilePosition(active, layout, projectile_t, active.failed)
        local rotation = (projectile_t * math.pi * 2.4)

        if not active.failed and (active.damaged or active.eliminated) and active.elapsed > active.impact_start then
            local bounce_t = clamp01((active.elapsed - active.impact_start) / IMPACT_DURATION)
            card_x = layout.card_hit_x - 70 * easeOutCubic(bounce_t)
            card_y = layout.card_hit_y - 30 * math.sin(bounce_t * math.pi)
            rotation = rotation - bounce_t * 1.2
        end

        card_vis.drawCardImageOnly(event.card, card_x, card_y, CARD_W)
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", card_x - CARD_W / 2, card_y - CARD_W / 2, CARD_W, CARD_W)
        love.graphics.setLineWidth(1)

        if not active.failed and active.elapsed >= active.impact_start then
            drawDamageBox(event.damage, card_x, card_y)
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return action_vis

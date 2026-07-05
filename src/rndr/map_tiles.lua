local map_tiles = {}
local image_loader = require("src.assets.image_loader")

local HEX_SIZE = 54
local SQRT_3 = math.sqrt(3)
local TILE_COLOR = { 0.33, 0.49, 0.42, 1 }
local CORRIDOR_COLOR = { 0.27, 0.39, 0.35, 1 }
local AGENT_PORTRAIT_DIR = "assets/images/agents"
local PORTRAIT_RADIUS = HEX_SIZE * 0.78
local PORTRAIT_OUTLINE_COLOR = { 0.015, 0.012, 0.01, 1 }
local SELECTED_PULSE_SPEED = 3.6
local SELECTED_PULSE_AMOUNT = 0.075
local SHOUT_BOX_COLOR = { 1, 1, 1, 0.96 }
local SHOUT_TEXT_COLOR = { 0, 0, 0, 1 }
local SHOUT_BOX_H = 34
local SHOUT_BOX_PAD_X = 10
local SHOUT_BOX_PAD_Y = 4
local agent_portraits = {}
local missing_agent_portraits = {}

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

local function drawPortraitTile(tile, center_x, center_y, selected)
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

function map_tiles.drawPortraits(room, camera_x, camera_y, selected_tile)
    if not room or not room.tiles then
        return
    end

    local offset_x, offset_y = getDrawOffset(room, camera_x, camera_y)

    for _, tile in ipairs(room.tiles) do
        local x, y = axialToPixel(tile.q, tile.r)

        drawPortraitTile(tile, x + offset_x, y + offset_y, tile == selected_tile)
    end

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

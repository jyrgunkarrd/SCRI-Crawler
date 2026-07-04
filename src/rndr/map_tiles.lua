local map_tiles = {}
local image_loader = require("src.assets.image_loader")

local HEX_SIZE = 54
local SQRT_3 = math.sqrt(3)
local TILE_COLOR = { 0.33, 0.49, 0.42, 1 }
local CORRIDOR_COLOR = { 0.27, 0.39, 0.35, 1 }
local TEST_PORTRAIT_PATH = "assets/images/TMR_hex.webp"
local PORTRAIT_RADIUS = HEX_SIZE * 0.78
local PORTRAIT_OUTLINE_COLOR = { 0.015, 0.012, 0.01, 1 }
local test_portrait

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

local function getTestPortrait()
    if not test_portrait then
        test_portrait = image_loader.newImage(TEST_PORTRAIT_PATH)
    end

    return test_portrait
end

local function shouldDrawTestPortrait(tile)
    return tile.start
end

local function drawPortraitTile(tile, center_x, center_y)
    if not shouldDrawTestPortrait(tile) then
        return
    end

    local image = getTestPortrait()
    local points = buildHexPoints(center_x, center_y, PORTRAIT_RADIUS)
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

function map_tiles.draw(room, camera_x, camera_y)
    if not room or not room.tiles then
        return
    end

    local offset_x, offset_y = getCenteredOffset(room)
    offset_x = offset_x + (camera_x or 0)
    offset_y = offset_y + (camera_y or 0)

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
        drawPortraitTile(tile, center_x, center_y)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return map_tiles

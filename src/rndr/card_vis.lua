local image_loader = require("src.assets.image_loader")
local fate_logic = require("src.sys.fate_logic")

local card_vis = {}

local CARD_WIDTH = 300
local CARD_RADIUS = 12
local CARD_PADDING = 14
local CARD_OUTLINE_WIDTH = 2
local HEADER_HEIGHT = 46
local TEXT_BOX_HEIGHT = 190
local FALLBACK_IMAGE_HEIGHT = 190
local TEXT_BOX_PADDING = 14
local BODY_FONT_SIZE = 13
local FLAVOR_FONT_SIZE = 12
local TEXT_BLOCK_GAP = 10
local TAG_ROW_HEIGHT = 22
local TAG_GAP = 6
local TAG_PAD_X = 7
local TAG_TEXT_Y_OFFSET = 3
local COST_PIP_WIDTH = 6
local COST_PIP_GAP = 4
local COST_PIP_TEXT_GAP = 6
local COST_BOX_GAP = 10
local ZERO_COST_PIP_WIDTH = 22
local ZERO_COST_PIP_HEIGHT = 5
local ZERO_COST_PIP_TOP_PADDING = 10
local HEADER_TEXT_Y_OFFSET = 1
local RARITY_LABEL_MIN_WIDTH = 28
local RARITY_LABEL_PAD_X = 10
local RARITY_LABEL_PAD_Y = 5
local CARD_BACKING_PADDING = 8
local CARD_IMAGE_EXTENSIONS = { "webp", "png", "jpg", "jpeg" }
local RARITY_PATH = "data.rarity"
local DEFAULT_RARITY_CARD_COLOR = { 1, 1, 1, 1 }
local DEFAULT_RARITY_LABEL_TEXT_COLOR = { 1, 1, 1, 1 }
local SCALED_VALUE_TEXT_COLOR = { 1, 0.8275, 0.349, 1 }

local card_images = {}
local missing_images = {}
local body_font
local flavor_font
local rarity_styles

local function getBodyFont()
    if not body_font then
        body_font = love.graphics.newFont("assets/fonts/Furore.otf", BODY_FONT_SIZE)
    end

    return body_font
end

local function getFlavorFont()
    if not flavor_font then
        flavor_font = love.graphics.newFont("assets/fonts/DejaVuSans-Oblique.ttf", FLAVOR_FONT_SIZE)
    end

    return flavor_font
end

local function htmlColorToLoveColor(color, fallback)
    fallback = fallback or DEFAULT_RARITY_CARD_COLOR

    if type(color) ~= "string" then
        return fallback
    end

    color = color:gsub("#", "")

    if #color ~= 6 then
        return fallback
    end

    local r = tonumber(color:sub(1, 2), 16)
    local g = tonumber(color:sub(3, 4), 16)
    local b = tonumber(color:sub(5, 6), 16)

    if not r or not g or not b then
        return fallback
    end

    return { r / 255, g / 255, b / 255, 1 }
end

local function getRarityField(rarity_entry, field)
    if type(rarity_entry) ~= "table" then
        return nil
    end

    if rarity_entry[field] then
        return rarity_entry[field]
    end

    for _, entry in ipairs(rarity_entry) do
        if type(entry) == "table" and entry[field] then
            return entry[field]
        end
    end

    return nil
end

local function normalizeRarityStyle(rarity_entry)
    if type(rarity_entry) == "string" then
        return {
            card = htmlColorToLoveColor(rarity_entry, DEFAULT_RARITY_CARD_COLOR),
            label_text = DEFAULT_RARITY_LABEL_TEXT_COLOR,
        }
    end

    local card_color = getRarityField(rarity_entry, "card") or getRarityField(rarity_entry, "box")
    local label_text_color = getRarityField(rarity_entry, "label_text")

    return {
        card = htmlColorToLoveColor(card_color, DEFAULT_RARITY_CARD_COLOR),
        label_text = htmlColorToLoveColor(label_text_color, DEFAULT_RARITY_LABEL_TEXT_COLOR),
    }
end

local function getRarityStyles()
    if rarity_styles then
        return rarity_styles
    end

    rarity_styles = {}

    local ok, rarity_data = pcall(require, RARITY_PATH)

    if not ok then
        print("Unable to load rarity colors: " .. tostring(rarity_data))
        return rarity_styles
    end

    for rarity, rarity_entry in pairs(rarity_data) do
        rarity_styles[tostring(rarity):lower()] = normalizeRarityStyle(rarity_entry)
    end

    return rarity_styles
end

local function getRarityStyle(rarity)
    return getRarityStyles()[(rarity or ""):lower()] or {
        card = DEFAULT_RARITY_CARD_COLOR,
        label_text = DEFAULT_RARITY_LABEL_TEXT_COLOR,
    }
end

local function getRarityLabel(rarity)
    local normalized = (rarity or ""):lower()

    if normalized == "fast" then
        return "quick"
    end

    return normalized
end

local function getRarityLabelHeight()
    return getBodyFont():getHeight() + RARITY_LABEL_PAD_Y * 2
end

local function findCardImagePath(card_id, image_dir)
    if not card_id then
        return nil
    end

    image_dir = image_dir or "assets/images/cards"

    for _, extension in ipairs(CARD_IMAGE_EXTENSIONS) do
        local path = ("%s/%s.%s"):format(image_dir, card_id, extension)

        if love.filesystem.getInfo(path, "file") then
            return path
        end
    end

    return nil
end

local function getCardImageId(card)
    return card and (card.art_id or card.art or card.id) or nil
end

local function getCardImage(card)
    local image_id = getCardImageId(card)
    local image_dir = card and card.image_dir or "assets/images/cards"
    local cache_key = image_dir .. ":" .. tostring(image_id)

    if not card or not card.id then
        return nil
    end

    if card_images[cache_key] then
        return card_images[cache_key]
    end

    if missing_images[cache_key] then
        if image_id ~= card.id then
            return getCardImage({
                id = card.id,
                image_dir = image_dir,
            })
        end

        return nil
    end

    local path = findCardImagePath(image_id, image_dir)

    if not path then
        missing_images[cache_key] = true

        if image_id ~= card.id then
            return getCardImage({
                id = card.id,
                image_dir = image_dir,
            })
        end

        return nil
    end

    local ok, image = pcall(image_loader.newImage, path)

    if not ok then
        print("Unable to load card image '" .. path .. "': " .. tostring(image))
        missing_images[cache_key] = true

        if image_id ~= card.id then
            return getCardImage({
                id = card.id,
                image_dir = image_dir,
            })
        end

        return nil
    end

    card_images[cache_key] = image

    return image
end

local function getCardImageHeight(card)
    local image = getCardImage(card)

    if not image then
        return FALLBACK_IMAGE_HEIGHT
    end

    return CARD_WIDTH * image:getHeight() / image:getWidth()
end

local function drawCardImage(card, x, y, width)
    local image = getCardImage(card)

    if not image then
        return
    end

    local scale = width / image:getWidth()

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, x, y, 0, scale, scale)
end

local function drawWrappedText(text, x, y, width, height, align, font, vertical_align)
    local previous_font = love.graphics.getFont()
    font = font or previous_font
    love.graphics.setFont(font)

    local _, wrapped_lines = font:getWrap(text or "", width)
    local text_height = #wrapped_lines * font:getHeight()
    local text_y = y

    if vertical_align ~= "top" then
        text_y = y + (height - text_height) / 2
    end

    love.graphics.printf(text or "", x, text_y, width, align)
    love.graphics.setFont(previous_font)

    return text_y, text_height
end

local function appendRichToken(lines, token, color, font, width)
    if token == "" then
        return
    end

    local line = lines[#lines]
    local token_width = font:getWidth(token)

    if line.width > 0 and line.width + token_width > width then
        lines[#lines + 1] = {
            fragments = {},
            width = 0,
        }
        line = lines[#lines]
    end

    line.fragments[#line.fragments + 1] = {
        text = token,
        color = color,
    }
    line.width = line.width + token_width
end

local function appendRichTextPart(lines, text, color, font, width)
    local start = 1

    while start <= #text do
        local newline_start, newline_end = text:find("\n", start, true)
        local part = newline_start and text:sub(start, newline_start - 1) or text:sub(start)
        local cursor = 1

        while cursor <= #part do
            local space_start, space_end = part:find("%s+", cursor)

            if space_start == cursor then
                appendRichToken(lines, part:sub(space_start, space_end), color, font, width)
                cursor = space_end + 1
            else
                local next_end = space_start and space_start - 1 or #part
                appendRichToken(lines, part:sub(cursor, next_end), color, font, width)
                cursor = next_end + 1
            end
        end

        if not newline_start then
            break
        end

        lines[#lines + 1] = {
            fragments = {},
            width = 0,
        }
        start = newline_end + 1
    end
end

local function layoutRichText(segments, font, width)
    local lines = {
        {
            fragments = {},
            width = 0,
        },
    }

    for _, segment in ipairs(segments or {}) do
        appendRichTextPart(lines, segment.text or "", segment.color, font, width)
    end

    return lines, #lines * font:getHeight()
end

local function drawRichText(segments, x, y, width, height, font, vertical_align)
    local previous_font = love.graphics.getFont()
    font = font or previous_font
    love.graphics.setFont(font)

    local lines, text_height = layoutRichText(segments, font, width)
    local cursor_y = vertical_align == "top" and y or y + (height - text_height) / 2

    for _, line in ipairs(lines) do
        local cursor_x = x

        for _, fragment in ipairs(line.fragments) do
            love.graphics.setColor(fragment.color or { 1, 1, 1, 1 })
            love.graphics.print(fragment.text, cursor_x, cursor_y)
            cursor_x = cursor_x + font:getWidth(fragment.text)
        end

        cursor_y = cursor_y + font:getHeight()
    end

    love.graphics.setFont(previous_font)

    return y, text_height
end

local function drawTags(tags, x, y, width)
    if not tags or #tags == 0 then
        return 0
    end

    local previous_font = love.graphics.getFont()
    local font = getBodyFont()
    local fitted_tags = {}
    local total_width = 0

    love.graphics.setFont(font)

    for _, tag in ipairs(tags) do
        local label = tostring(tag)
        local tag_width = font:getWidth(label) + TAG_PAD_X * 2
        local next_width = tag_width

        if total_width > 0 then
            next_width = next_width + TAG_GAP
        end

        if total_width + next_width <= width then
            fitted_tags[#fitted_tags + 1] = {
                label = label,
                width = tag_width,
            }
            total_width = total_width + next_width
        end
    end

    local cursor_x = x + (width - total_width) / 2

    for index, tag in ipairs(fitted_tags) do
        if index > 1 then
            cursor_x = cursor_x + TAG_GAP
        end

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("fill", cursor_x, y, tag.width, TAG_ROW_HEIGHT)

        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.print(tag.label, cursor_x + TAG_PAD_X, y + TAG_TEXT_Y_OFFSET)

        cursor_x = cursor_x + tag.width
    end

    love.graphics.setFont(previous_font)

    return TAG_ROW_HEIGHT + TEXT_BLOCK_GAP
end

local function drawTextBoxContent(tags, text, flavor, x, y, width, height)
    local tag_offset = drawTags(tags, x, y, width)
    local text_y = y + tag_offset
    local text_height_available = height - tag_offset
    local text_height = 0

    if text_height_available <= 0 then
        return
    end

    love.graphics.setColor(1, 1, 1, 1)

    if type(text) == "table" then
        _, text_height = drawRichText(text, x, text_y, width, text_height_available, getBodyFont(), "top")
    else
        _, text_height = drawWrappedText(text, x, text_y, width, text_height_available, "left", getBodyFont(), "top")
    end

    if not flavor or flavor == "" then
        return
    end

    local flavor_y = text_y + text_height + TEXT_BLOCK_GAP
    local remaining_height = text_height_available - text_height - TEXT_BLOCK_GAP

    if remaining_height > 0 then
        love.graphics.setColor(1, 1, 1, 1)
        drawWrappedText(flavor, x, flavor_y, width, remaining_height, "left", getFlavorFont(), "top")
    end
end

local function getContextUnit(context)
    if type(context) ~= "table" then
        return context
    end

    return context.unit or context.agent or context.owner
end

local function getNestedValue(root, path)
    local value = root

    for segment in tostring(path or ""):gmatch("[^%.]+") do
        if type(value) ~= "table" then
            return nil
        end

        value = value[segment]
    end

    return value
end

local function shouldScaleCardPath(card, path)
    local group, key = tostring(path or ""):match("^([^%.]+)%.(.+)$")

    if not group or not key then
        return false
    end

    local scale_group = card and card.level_scale and card.level_scale[group]

    return scale_group and scale_group[key] == true
end

local function resolveCardToken(card, context, token)
    local value = getNestedValue(card, token)

    if value == nil then
        return "{" .. tostring(token) .. "}"
    end

    if type(value) == "number" and shouldScaleCardPath(card, token) then
        value = value * fate_logic.getFateScale(getContextUnit(context))
    end

    if type(value) == "number" then
        return tostring(math.floor(value))
    end

    return tostring(value)
end

local function resolveCardText(card, context, text)
    return (text or ""):gsub("{([^}]+)}", function(token)
        return resolveCardToken(card, context, token)
    end)
end

local function resolveCardTextSegments(card, context, text)
    local segments = {}
    local cursor = 1
    text = text or ""

    while cursor <= #text do
        local token_start, token_end, token = text:find("{([^}]+)}", cursor)

        if not token_start then
            segments[#segments + 1] = {
                text = text:sub(cursor),
            }
            break
        end

        if token_start > cursor then
            segments[#segments + 1] = {
                text = text:sub(cursor, token_start - 1),
            }
        end

        segments[#segments + 1] = {
            text = resolveCardToken(card, context, token),
            color = SCALED_VALUE_TEXT_COLOR,
        }
        cursor = token_end + 1
    end

    if #segments == 0 then
        segments[1] = {
            text = text,
        }
    end

    return segments
end

local function getWrappedTextBounds(text, x, y, width, height, font, vertical_align)
    font = font or love.graphics.getFont()

    local _, wrapped_lines = font:getWrap(text or "", width)
    local text_height = #wrapped_lines * font:getHeight()
    local text_y = y

    if vertical_align ~= "top" then
        text_y = y + (height - text_height) / 2
    end

    return x, text_y, width, text_height
end

local function drawCostPips(cost, x, y, bottom_y, color)
    local pip_count = math.max(0, math.floor(cost or 0))
    local pip_height = bottom_y - y

    if pip_height <= 0 then
        return nil
    end

    love.graphics.setColor(color)

    if pip_count == 0 then
        local pip_y = y + ZERO_COST_PIP_TOP_PADDING
        love.graphics.rectangle("fill", x, pip_y, ZERO_COST_PIP_WIDTH, ZERO_COST_PIP_HEIGHT)
        return x + ZERO_COST_PIP_WIDTH, y + pip_height
    end

    for index = 1, pip_count do
        local pip_x = x + (index - 1) * (COST_PIP_WIDTH + COST_PIP_GAP)
        love.graphics.rectangle("fill", pip_x, y, COST_PIP_WIDTH, pip_height)
    end

    return x + pip_count * COST_PIP_WIDTH + (pip_count - 1) * COST_PIP_GAP, y + pip_height
end

local function drawClippedHeaderBox(card_x, card_y, card_height, box_x, box_bottom_y, color)
    local box_width = card_x + CARD_WIDTH - box_x
    local box_height = box_bottom_y - card_y

    if box_width <= 0 or box_height <= 0 then
        return
    end

    love.graphics.stencil(function()
        love.graphics.rectangle("fill", card_x, card_y, CARD_WIDTH, card_height, CARD_RADIUS, CARD_RADIUS)
    end, "replace", 1)
    love.graphics.setStencilTest("greater", 0)

    love.graphics.setColor(color)
    love.graphics.rectangle("fill", box_x, card_y, box_width, box_height)
    love.graphics.rectangle("line", box_x, card_y, box_width, box_height)
    love.graphics.setStencilTest()
end

local function drawRarityLabel(rarity, x, y, box_color, label_text_color)
    local label = getRarityLabel(rarity)
    local previous_font = love.graphics.getFont()
    local font = getBodyFont()
    local label_width = math.max(RARITY_LABEL_MIN_WIDTH, font:getWidth(label) + RARITY_LABEL_PAD_X * 2)
    local label_height = getRarityLabelHeight()

    love.graphics.setFont(font)
    love.graphics.setColor(box_color)
    love.graphics.rectangle("fill", x, y, label_width, label_height)

    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.setLineWidth(2)
    love.graphics.line(x, y + label_height, x + label_width, y + label_height)
    love.graphics.line(x + label_width, y, x + label_width, y + label_height)

    love.graphics.setColor(label_text_color)
    love.graphics.printf(label, x, y + (label_height - font:getHeight()) / 2, label_width, "center")
    love.graphics.setFont(previous_font)
end

function card_vis.loadCardAssets(card)
    getCardImage(card)
end

function card_vis.getCardWidth()
    return CARD_WIDTH
end

function card_vis.getCardHeight(card)
    return CARD_PADDING + HEADER_HEIGHT + getCardImageHeight(card) + CARD_PADDING + TEXT_BOX_HEIGHT + CARD_PADDING
end

function card_vis.getVisibleHandCardHeight()
    return CARD_PADDING + HEADER_HEIGHT + getRarityLabelHeight()
end

function card_vis.getExtendedHandCardHeight(card)
    return CARD_PADDING + HEADER_HEIGHT + getCardImageHeight(card)
end

function card_vis.drawCardPortrait(card, x, y, width, height)
    local image = getCardImage(card)

    if not image then
        return
    end

    love.graphics.stencil(function()
        love.graphics.rectangle("fill", x, y, width, height)
    end, "replace", 1)
    love.graphics.setStencilTest("greater", 0)

    local scale = math.max(width / image:getWidth(), height / image:getHeight())
    local image_width = image:getWidth() * scale
    local image_height = image:getHeight() * scale

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, x + (width - image_width) / 2, y + (height - image_height) / 2, 0, scale, scale)
    love.graphics.setStencilTest()
end

function card_vis.drawCardImageOnly(card, center_x, center_y, width)
    local image = getCardImage(card)

    if not image then
        return
    end

    local scale = width / image:getWidth()

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
end

function card_vis.drawCard(card, x, y, context)
    if not card then
        return
    end

    local image_height = getCardImageHeight(card)
    local card_height = card_vis.getCardHeight(card)
    local content_x = x + CARD_PADDING
    local content_y = y + CARD_PADDING
    local content_width = CARD_WIDTH - CARD_PADDING * 2
    local header_y = content_y
    local image_y = header_y + HEADER_HEIGHT
    local text_box_y = image_y + image_height + CARD_PADDING
    local rarity_style = getRarityStyle(card.rarity)
    local rarity_card_color = rarity_style.card
    local rarity_label_text_color = rarity_style.label_text

    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle(
        "fill",
        x - CARD_BACKING_PADDING,
        y - CARD_BACKING_PADDING,
        CARD_WIDTH + CARD_BACKING_PADDING * 2,
        card_height + CARD_BACKING_PADDING * 2,
        CARD_RADIUS + CARD_BACKING_PADDING,
        CARD_RADIUS + CARD_BACKING_PADDING
    )
    love.graphics.rectangle("fill", x, y, CARD_WIDTH, card_height, CARD_RADIUS, CARD_RADIUS)
    love.graphics.rectangle("fill", content_x, header_y, content_width, HEADER_HEIGHT)

    local _, header_text_y = getWrappedTextBounds(card.name, content_x, header_y, content_width, HEADER_HEIGHT)
    local pips_right_x, pips_bottom_y = drawCostPips(card.cost, content_x, y, header_text_y - COST_PIP_TEXT_GAP, rarity_card_color)

    if pips_right_x and pips_bottom_y then
        drawClippedHeaderBox(x, y, card_height, pips_right_x + COST_BOX_GAP, pips_bottom_y, rarity_card_color)
    end

    love.graphics.setColor(1, 1, 1, 1)
    drawWrappedText(card.name, content_x, header_y + HEADER_TEXT_Y_OFFSET, content_width, HEADER_HEIGHT, "left")

    drawCardImage(card, x, image_y, CARD_WIDTH)
    drawRarityLabel(card.rarity, x, image_y, rarity_card_color, rarity_label_text_color)

    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", content_x, text_box_y, content_width, TEXT_BOX_HEIGHT)

    love.graphics.setColor(rarity_card_color)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", content_x, text_box_y, content_width, TEXT_BOX_HEIGHT)
    love.graphics.setColor(1, 1, 1, 1)
    drawTextBoxContent(
        card.tags or {},
        resolveCardTextSegments(card, context, card.textbox),
        card.flavor,
        content_x + TEXT_BOX_PADDING,
        text_box_y + TEXT_BOX_PADDING,
        content_width - TEXT_BOX_PADDING * 2,
        TEXT_BOX_HEIGHT - TEXT_BOX_PADDING * 2
    )

    love.graphics.setColor(rarity_card_color)
    love.graphics.setLineWidth(CARD_OUTLINE_WIDTH)
    love.graphics.rectangle("line", x, y, CARD_WIDTH, card_height, CARD_RADIUS, CARD_RADIUS)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

function card_vis.drawScaledCard(card, x, y, scale, context)
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.scale(scale, scale)
    card_vis.drawCard(card, 0, 0, context)
    love.graphics.pop()
end

return card_vis

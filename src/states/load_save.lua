local utf8 = require("utf8")
local image_loader = require("src.assets.image_loader")
local save_slots = require("src.sys.save_slots")
local sfx_logic = require("src.sys.sfx_logic")

local load_save = {
    name = "load_save",
    title_font = nil,
    slot_font = nil,
    modal_font = nil,
    load_icon = nil,
    delete_icon = nil,
    slot_rects = {},
    load_rects = {},
    delete_rects = {},
    signature_modal = nil,
    delete_modal = nil,
    signature_reveals = {},
}

local FONT_PATH = "assets/fonts/Furore.otf"
local LOAD_ICON_PATH = "assets/images/icons/load.webp"
local DELETE_ICON_PATH = "assets/images/icons/delete.webp"
local TITLE_FONT_SIZE = 24
local SLOT_FONT_SIZE = 15
local MODAL_FONT_SIZE = 16
local SLOT_MAX_W = 460
local SLOT_MAX_H = 62
local SLOT_MIN_H = 36
local SLOT_GAP = 7
local SLOT_PAD = 6
local IDENTIFIER_GAP = 3
local LOAD_BUTTON_GAP = 10
local LOAD_ICON_PAD = 8
local DELETE_ICON_PAD = 8
local SIDE_MARGIN = 32
local VERTICAL_MARGIN = 26
local TITLE_GAP = 20
local MODAL_MAX_W = 620
local MODAL_H = 360
local MODAL_PAD = 24
local MODAL_CANVAS_H = 170
local MODAL_BUTTON_W = 210
local MODAL_BUTTON_H = 42
local MODAL_BUTTON_BOTTOM_PAD = 22
local DELETE_MODAL_H = 250
local DELETE_INPUT_H = 46
local SIGNATURE_PREVIEW_LINE_WIDTH = 2
local SIGNATURE_CANVAS_LINE_WIDTH = 3
local MIN_DRAW_DISTANCE = 2.5
local SIGNATURE_REVEAL_SECONDS = 0.65
local BACKGROUND_COLOR = { 0.018, 0.018, 0.022, 1 }
local SLOT_FILL_COLOR = { 0, 0, 0, 1 }
local SLOT_OUTLINE_COLOR = { 1, 1, 1, 1 }
local SLOT_TEXT_COLOR = { 1, 1, 1, 1 }
local SIGNATURE_FILL_COLOR = { 184 / 255, 184 / 255, 184 / 255, 1 }
local SIGNATURE_TEXT_COLOR = { 0, 0, 0, 1 }
local HOVER_FILL_COLOR = { 1, 1, 1, 1 }
local HOVER_TEXT_COLOR = { 0, 0, 0, 1 }
local MODAL_DIM_COLOR = { 0, 0, 0, 0.78 }
local MODAL_FILL_COLOR = { 0, 0, 0, 0.98 }
local ERROR_TEXT_COLOR = { 1, 0.3, 0.3, 1 }
local OUTLINE_WIDTH = 2

local function pointInRect(x, y, rect)
    return rect
        and x >= rect.x
        and x <= rect.x + rect.w
        and y >= rect.y
        and y <= rect.y + rect.h
end

local function getLayout(state, screen_w, screen_h)
    local slot_count = save_slots.getCount()
    local title_h = state.title_font:getHeight()
    local gaps_h = (slot_count - 1) * SLOT_GAP
    local available_slot_h = screen_h
        - VERTICAL_MARGIN * 2
        - title_h
        - TITLE_GAP
        - gaps_h
    local slot_h = math.min(SLOT_MAX_H, math.max(SLOT_MIN_H, available_slot_h / slot_count))
    local column_h = title_h + TITLE_GAP + slot_count * slot_h + gaps_h
    local load_space = slot_h + LOAD_BUTTON_GAP
    local slot_w = math.min(
        SLOT_MAX_W,
        math.max(1, screen_w - SIDE_MARGIN * 2 - load_space * 2)
    )

    return {
        title_y = (screen_h - column_h) / 2,
        slot_x = (screen_w - slot_w) / 2,
        slot_y = (screen_h - column_h) / 2 + title_h + TITLE_GAP,
        slot_w = slot_w,
        slot_h = slot_h,
    }
end

local function rebuildSlotRects(state, screen_w, screen_h)
    local layout = getLayout(state, screen_w, screen_h)

    state.slot_rects = {}
    state.load_rects = {}
    state.delete_rects = {}

    for index = 1, save_slots.getCount() do
        local rect = {
            x = layout.slot_x,
            y = layout.slot_y + (index - 1) * (layout.slot_h + SLOT_GAP),
            w = layout.slot_w,
            h = layout.slot_h,
        }

        state.slot_rects[index] = rect

        if not save_slots.isEmpty(index) then
            state.load_rects[index] = {
                x = rect.x - LOAD_BUTTON_GAP - rect.h,
                y = rect.y,
                w = rect.h,
                h = rect.h,
            }
            state.delete_rects[index] = {
                x = rect.x + rect.w + LOAD_BUTTON_GAP,
                y = rect.y,
                w = rect.h,
                h = rect.h,
            }
        end
    end

    return layout
end

local function getModalLayout(state, screen_w, screen_h)
    local modal_w = math.min(MODAL_MAX_W, math.max(1, screen_w - SIDE_MARGIN * 2))
    local modal_h = math.min(MODAL_H, math.max(1, screen_h - VERTICAL_MARGIN * 2))
    local x = (screen_w - modal_w) / 2
    local y = (screen_h - modal_h) / 2

    return {
        panel = { x = x, y = y, w = modal_w, h = modal_h },
        canvas = {
            x = x + MODAL_PAD,
            y = y + 78,
            w = modal_w - MODAL_PAD * 2,
            h = MODAL_CANVAS_H,
        },
        confirm = {
            x = x + (modal_w - MODAL_BUTTON_W) / 2,
            y = y + modal_h - MODAL_BUTTON_BOTTOM_PAD - MODAL_BUTTON_H,
            w = MODAL_BUTTON_W,
            h = MODAL_BUTTON_H,
        },
    }
end

local function getDeleteModalLayout(screen_w, screen_h)
    local modal_w = math.min(MODAL_MAX_W, math.max(1, screen_w - SIDE_MARGIN * 2))
    local modal_h = math.min(DELETE_MODAL_H, math.max(1, screen_h - VERTICAL_MARGIN * 2))
    local x = (screen_w - modal_w) / 2
    local y = (screen_h - modal_h) / 2

    return {
        panel = { x = x, y = y, w = modal_w, h = modal_h },
        input = {
            x = x + MODAL_PAD,
            y = y + 118,
            w = modal_w - MODAL_PAD * 2,
            h = DELETE_INPUT_H,
        },
    }
end

local function closeSignatureModal(state)
    state.signature_modal = nil
end

local function openSignatureModal(state, slot_index)
    state.signature_modal = {
        slot_index = slot_index,
        strokes = {},
        active_stroke = nil,
        error = nil,
    }
end

local function closeDeleteModal(state)
    state.delete_modal = nil
    love.keyboard.setTextInput(false)
end

local function openDeleteModal(state, slot_index)
    state.delete_modal = {
        slot_index = slot_index,
        input = "",
        error = nil,
    }
    love.keyboard.setTextInput(true)
end

local function confirmDelete(state)
    local modal = state.delete_modal

    if not modal then
        return false
    end

    if modal.input:lower() ~= "delete" then
        modal.error = "Type Delete exactly, then press Enter."
        return false
    end

    local success, delete_error = save_slots.delete(modal.slot_index)

    if not success then
        modal.error = delete_error or "Unable to delete this save slot."
        return false
    end

    state.signature_reveals[modal.slot_index] = nil
    closeDeleteModal(state)
    return true
end

local function confirmSignature(state)
    local modal = state.signature_modal

    if not modal then
        return false
    end

    local success, save_error = save_slots.setSignature(modal.slot_index, {
        kind = "drawn",
        strokes = modal.strokes,
    })

    if not success then
        modal.error = save_error or "Unable to save this signature."
        return false
    end

    state.signature_reveals[modal.slot_index] = { elapsed = 0 }
    sfx_logic.playNamed("write")
    closeSignatureModal(state)
    return true
end

local function drawSignature(signature, rect, line_width)
    if not signature or type(signature.strokes) ~= "table" then
        return
    end

    love.graphics.setColor(SIGNATURE_TEXT_COLOR)
    love.graphics.setLineWidth(line_width)

    for _, stroke in ipairs(signature.strokes) do
        if #stroke == 1 then
            local point = stroke[1]

            love.graphics.circle(
                "fill",
                rect.x + point.x * rect.w,
                rect.y + point.y * rect.h,
                line_width / 2
            )
        elseif #stroke > 1 then
            local vertices = {}

            for _, point in ipairs(stroke) do
                vertices[#vertices + 1] = rect.x + point.x * rect.w
                vertices[#vertices + 1] = rect.y + point.y * rect.h
            end

            love.graphics.line(vertices)
        end
    end

    love.graphics.setLineWidth(1)
end

local function drawRevealedSignature(signature, rect, reveal)
    if not reveal then
        drawSignature(signature, rect, SIGNATURE_PREVIEW_LINE_WIDTH)
        return
    end

    local progress = math.min(1, reveal.elapsed / SIGNATURE_REVEAL_SECONDS)
    local eased_progress = 1 - (1 - progress) * (1 - progress)
    local scissor_x, scissor_y, scissor_w, scissor_h = love.graphics.getScissor()

    love.graphics.setScissor(rect.x, rect.y, rect.w * eased_progress, rect.h)
    drawSignature(signature, rect, SIGNATURE_PREVIEW_LINE_WIDTH)

    if scissor_x then
        love.graphics.setScissor(scissor_x, scissor_y, scissor_w, scissor_h)
    else
        love.graphics.setScissor()
    end
end

local function startSignatureStroke(modal, canvas, x, y)
    local stroke = {
        {
            x = math.max(0, math.min(1, (x - canvas.x) / canvas.w)),
            y = math.max(0, math.min(1, (y - canvas.y) / canvas.h)),
        },
    }

    modal.strokes[#modal.strokes + 1] = stroke
    modal.active_stroke = stroke
    modal.error = nil
end

local function continueSignatureStroke(modal, canvas, x, y)
    local stroke = modal.active_stroke

    if not stroke or not pointInRect(x, y, canvas) then
        modal.active_stroke = nil
        return
    end

    local last_point = stroke[#stroke]
    local normalized_x = math.max(0, math.min(1, (x - canvas.x) / canvas.w))
    local normalized_y = math.max(0, math.min(1, (y - canvas.y) / canvas.h))
    local distance_x = (normalized_x - last_point.x) * canvas.w
    local distance_y = (normalized_y - last_point.y) * canvas.h

    if distance_x * distance_x + distance_y * distance_y >= MIN_DRAW_DISTANCE * MIN_DRAW_DISTANCE then
        stroke[#stroke + 1] = { x = normalized_x, y = normalized_y }
    end
end

local function drawButtonIcon(image, rect, hovered, padding)
    local available_size = math.max(1, math.min(rect.w, rect.h) - padding * 2)
    local scale = math.min(available_size / image:getWidth(), available_size / image:getHeight())

    love.graphics.setColor(hovered and HOVER_TEXT_COLOR or SLOT_TEXT_COLOR)
    love.graphics.draw(
        image,
        rect.x + rect.w / 2,
        rect.y + rect.h / 2,
        0,
        scale,
        scale,
        image:getWidth() / 2,
        image:getHeight() / 2
    )
end

local function drawSignatureModal(state, screen_w, screen_h, mouse_x, mouse_y)
    local modal = state.signature_modal

    if not modal then
        return
    end

    local layout = getModalLayout(state, screen_w, screen_h)
    local confirm_hovered = pointInRect(mouse_x, mouse_y, layout.confirm)

    love.graphics.setColor(MODAL_DIM_COLOR)
    love.graphics.rectangle("fill", 0, 0, screen_w, screen_h)
    love.graphics.setColor(MODAL_FILL_COLOR)
    love.graphics.rectangle("fill", layout.panel.x, layout.panel.y, layout.panel.w, layout.panel.h)
    love.graphics.setColor(SLOT_OUTLINE_COLOR)
    love.graphics.setLineWidth(OUTLINE_WIDTH)
    love.graphics.rectangle("line", layout.panel.x, layout.panel.y, layout.panel.w, layout.panel.h)
    love.graphics.setLineWidth(1)

    love.graphics.setFont(state.modal_font)
    love.graphics.setColor(SLOT_TEXT_COLOR)
    love.graphics.printf(
        ("DRAW YOUR SIGNATURE — SLOT %02d"):format(modal.slot_index),
        layout.panel.x,
        layout.panel.y + MODAL_PAD,
        layout.panel.w,
        "center"
    )

    love.graphics.setColor(SIGNATURE_FILL_COLOR)
    love.graphics.rectangle("fill", layout.canvas.x, layout.canvas.y, layout.canvas.w, layout.canvas.h)
    drawSignature(
        { kind = "drawn", strokes = modal.strokes },
        layout.canvas,
        SIGNATURE_CANVAS_LINE_WIDTH
    )

    love.graphics.setColor(confirm_hovered and HOVER_FILL_COLOR or SLOT_FILL_COLOR)
    love.graphics.rectangle("fill", layout.confirm.x, layout.confirm.y, layout.confirm.w, layout.confirm.h)
    love.graphics.setColor(SLOT_OUTLINE_COLOR)
    love.graphics.rectangle("line", layout.confirm.x, layout.confirm.y, layout.confirm.w, layout.confirm.h)
    love.graphics.setColor(confirm_hovered and HOVER_TEXT_COLOR or SLOT_TEXT_COLOR)
    love.graphics.printf(
        "CONFIRM",
        layout.confirm.x,
        layout.confirm.y + (layout.confirm.h - state.modal_font:getHeight()) / 2,
        layout.confirm.w,
        "center"
    )

    if modal.error then
        love.graphics.setColor(ERROR_TEXT_COLOR)
        love.graphics.printf(
            modal.error,
            layout.panel.x + MODAL_PAD,
            layout.canvas.y + layout.canvas.h + 7,
            layout.panel.w - MODAL_PAD * 2,
            "center"
        )
    end
end

local function drawDeleteModal(state, screen_w, screen_h)
    local modal = state.delete_modal

    if not modal then
        return
    end

    local layout = getDeleteModalLayout(screen_w, screen_h)

    love.graphics.setColor(MODAL_DIM_COLOR)
    love.graphics.rectangle("fill", 0, 0, screen_w, screen_h)
    love.graphics.setColor(MODAL_FILL_COLOR)
    love.graphics.rectangle("fill", layout.panel.x, layout.panel.y, layout.panel.w, layout.panel.h)
    love.graphics.setColor(SLOT_OUTLINE_COLOR)
    love.graphics.setLineWidth(OUTLINE_WIDTH)
    love.graphics.rectangle("line", layout.panel.x, layout.panel.y, layout.panel.w, layout.panel.h)
    love.graphics.setLineWidth(1)

    love.graphics.setFont(state.modal_font)
    love.graphics.setColor(SLOT_TEXT_COLOR)
    love.graphics.printf(
        ("DELETE SAVE SLOT %02d?"):format(modal.slot_index),
        layout.panel.x,
        layout.panel.y + MODAL_PAD,
        layout.panel.w,
        "center"
    )
    love.graphics.printf(
        "Type Delete and press Enter to confirm.",
        layout.panel.x + MODAL_PAD,
        layout.panel.y + 66,
        layout.panel.w - MODAL_PAD * 2,
        "center"
    )

    love.graphics.setColor(SIGNATURE_FILL_COLOR)
    love.graphics.rectangle("fill", layout.input.x, layout.input.y, layout.input.w, layout.input.h)
    love.graphics.setColor(SIGNATURE_TEXT_COLOR)
    love.graphics.printf(
        modal.input,
        layout.input.x + 10,
        layout.input.y + (layout.input.h - state.modal_font:getHeight()) / 2,
        layout.input.w - 20,
        "left"
    )

    if modal.error then
        love.graphics.setColor(ERROR_TEXT_COLOR)
        love.graphics.printf(
            modal.error,
            layout.panel.x + MODAL_PAD,
            layout.input.y + layout.input.h + 14,
            layout.panel.w - MODAL_PAD * 2,
            "center"
        )
    end
end

function load_save:enter()
    self.title_font = self.title_font or love.graphics.newFont(FONT_PATH, TITLE_FONT_SIZE)
    self.slot_font = self.slot_font or love.graphics.newFont(FONT_PATH, SLOT_FONT_SIZE)
    self.modal_font = self.modal_font or love.graphics.newFont(FONT_PATH, MODAL_FONT_SIZE)
    self.load_icon = self.load_icon or image_loader.newImage(LOAD_ICON_PATH)
    self.delete_icon = self.delete_icon or image_loader.newImage(DELETE_ICON_PATH)
    self.slot_rects = {}
    self.load_rects = {}
    self.delete_rects = {}
    self.signature_modal = nil
    self.delete_modal = nil
    self.signature_reveals = {}
    save_slots.load()

    love.keyboard.setTextInput(false)
    love.graphics.setDefaultFilter("linear", "linear", 1)
    love.graphics.setBackgroundColor(BACKGROUND_COLOR)
end


function load_save:leave()
    self.signature_modal = nil
    self.delete_modal = nil
    love.keyboard.setTextInput(false)
end

function load_save:update(dt)
    for index, reveal in pairs(self.signature_reveals) do
        reveal.elapsed = reveal.elapsed + math.max(0, tonumber(dt) or 0)

        if reveal.elapsed >= SIGNATURE_REVEAL_SECONDS then
            self.signature_reveals[index] = nil
        end
    end
end

function load_save:draw()
    local screen_w = love.graphics.getWidth()
    local screen_h = love.graphics.getHeight()
    local mouse_x, mouse_y = love.mouse.getPosition()
    local layout = rebuildSlotRects(self, screen_w, screen_h)

    love.graphics.clear(BACKGROUND_COLOR)
    love.graphics.setFont(self.title_font)
    love.graphics.setColor(SLOT_TEXT_COLOR)
    love.graphics.printf("SELECT SAVE FILE", 0, layout.title_y, screen_w, "center")

    love.graphics.setFont(self.slot_font)
    local modal_open = self.signature_modal or self.delete_modal

    for index, rect in ipairs(self.slot_rects) do
        local signature = save_slots.getSignature(index)
        local hovered = not modal_open and not signature and pointInRect(mouse_x, mouse_y, rect)
        local signature_h = math.max(1, rect.h - SLOT_PAD * 2 - self.slot_font:getHeight() - IDENTIFIER_GAP)
        local signature_rect = {
            x = rect.x + SLOT_PAD,
            y = rect.y + SLOT_PAD + self.slot_font:getHeight() + IDENTIFIER_GAP,
            w = rect.w - SLOT_PAD * 2,
            h = signature_h,
        }

        love.graphics.setColor(hovered and HOVER_FILL_COLOR or SLOT_FILL_COLOR)
        love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
        love.graphics.setColor(SLOT_OUTLINE_COLOR)
        love.graphics.setLineWidth(OUTLINE_WIDTH)
        love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(hovered and HOVER_TEXT_COLOR or SLOT_TEXT_COLOR)
        love.graphics.printf(("SAVE SLOT %02d"):format(index), rect.x, rect.y + SLOT_PAD, rect.w, "center")

        love.graphics.setColor(SIGNATURE_FILL_COLOR)
        love.graphics.rectangle("fill", signature_rect.x, signature_rect.y, signature_rect.w, signature_rect.h)

        if signature then
            drawRevealedSignature(signature, signature_rect, self.signature_reveals[index])
        end

        local load_rect = self.load_rects[index]

        if load_rect then
            local load_hovered = not modal_open and pointInRect(mouse_x, mouse_y, load_rect)

            love.graphics.setColor(load_hovered and HOVER_FILL_COLOR or SLOT_FILL_COLOR)
            love.graphics.rectangle("fill", load_rect.x, load_rect.y, load_rect.w, load_rect.h)
            love.graphics.setColor(SLOT_OUTLINE_COLOR)
            love.graphics.rectangle("line", load_rect.x, load_rect.y, load_rect.w, load_rect.h)
            drawButtonIcon(self.load_icon, load_rect, load_hovered, LOAD_ICON_PAD)
        end

        local delete_rect = self.delete_rects[index]

        if delete_rect then
            local delete_hovered = not modal_open and pointInRect(mouse_x, mouse_y, delete_rect)

            love.graphics.setColor(delete_hovered and HOVER_FILL_COLOR or SLOT_FILL_COLOR)
            love.graphics.rectangle("fill", delete_rect.x, delete_rect.y, delete_rect.w, delete_rect.h)
            love.graphics.setColor(SLOT_OUTLINE_COLOR)
            love.graphics.rectangle("line", delete_rect.x, delete_rect.y, delete_rect.w, delete_rect.h)
            drawButtonIcon(self.delete_icon, delete_rect, delete_hovered, DELETE_ICON_PAD)
        end
    end

    drawSignatureModal(self, screen_w, screen_h, mouse_x, mouse_y)
    drawDeleteModal(self, screen_w, screen_h)
    love.graphics.setColor(1, 1, 1, 1)
end

function load_save:mousepressed(x, y, button)
    if self.delete_modal then
        if button == 2 then
            closeDeleteModal(self)
        end

        return
    end

    if self.signature_modal then
        if button == 2 then
            closeSignatureModal(self)
        elseif button == 1 then
            local layout = getModalLayout(self, love.graphics.getWidth(), love.graphics.getHeight())

            if pointInRect(x, y, layout.confirm) then
                confirmSignature(self)
            elseif pointInRect(x, y, layout.canvas) then
                startSignatureStroke(self.signature_modal, layout.canvas, x, y)
            end
        end

        return
    end

    if button ~= 1 then
        return
    end

    rebuildSlotRects(self, love.graphics.getWidth(), love.graphics.getHeight())

    for index, delete_rect in pairs(self.delete_rects) do
        if pointInRect(x, y, delete_rect) then
            openDeleteModal(self, index)
            return
        end
    end

    for index, load_rect in pairs(self.load_rects) do
        if pointInRect(x, y, load_rect) and save_slots.setActive(index) then
            local states_core = require("src.states.states_core")

            sfx_logic.playNamed("load")
            states_core.switch("JACL", {
                save_slot = index,
                signature = save_slots.getSignature(index),
            })
            return
        end
    end

    for index, rect in ipairs(self.slot_rects) do
        if pointInRect(x, y, rect) and save_slots.isEmpty(index) then
            openSignatureModal(self, index)
            return
        end
    end
end

function load_save:keypressed(key)
    local delete_modal = self.delete_modal

    if delete_modal then
        if key == "backspace" then
            local byte_offset = utf8.offset(delete_modal.input, -1)

            if byte_offset then
                delete_modal.input = delete_modal.input:sub(1, byte_offset - 1)
            end

            delete_modal.error = nil
        elseif key == "return" or key == "kpenter" then
            confirmDelete(self)
        elseif key == "escape" then
            closeDeleteModal(self)
        end

        return
    end

    local modal = self.signature_modal

    if not modal then
        if key == "escape" then
            love.event.quit()
        end

        return
    end

    if key == "backspace" then
        table.remove(modal.strokes)
        modal.active_stroke = nil
        modal.error = nil
    elseif key == "return" or key == "kpenter" then
        confirmSignature(self)
    elseif key == "escape" then
        closeSignatureModal(self)
    end
end

function load_save:textinput(text)
    local modal = self.delete_modal

    if not modal then
        return
    end

    local candidate = modal.input .. text
    local character_count = utf8.len(candidate)
    local layout = getDeleteModalLayout(love.graphics.getWidth(), love.graphics.getHeight())

    if character_count
        and character_count <= 16
        and self.modal_font:getWidth(candidate) <= layout.input.w - 20
    then
        modal.input = candidate
        modal.error = nil
    end
end

function load_save:mousereleased(_, _, button)
    local modal = self.signature_modal

    if modal and button == 1 then
        modal.active_stroke = nil
    end
end

function load_save:mousemoved(x, y)
    local modal = self.signature_modal

    if not modal or not modal.active_stroke then
        return
    end

    local layout = getModalLayout(self, love.graphics.getWidth(), love.graphics.getHeight())

    continueSignatureStroke(modal, layout.canvas, x, y)
end

return load_save

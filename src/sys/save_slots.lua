local save_slots = {}

local SAVE_PATH = "save_slots.dat"
local SLOT_COUNT = 12
local COORDINATE_SCALE = 10000
local MAX_STROKES = 256
local MAX_POINTS = 8192
local signatures = {}
local active_slot = nil
local loaded = false

local function normalizeIndex(index)
    index = math.floor(tonumber(index) or 0)

    if index < 1 or index > SLOT_COUNT then
        return nil
    end

    return index
end

local function clampUnit(value)
    return math.max(0, math.min(1, tonumber(value) or 0))
end

local function normalizeSignature(signature)
    if type(signature) ~= "table" or type(signature.strokes) ~= "table" then
        return nil
    end

    local normalized = {
        kind = "drawn",
        strokes = {},
    }
    local point_count = 0

    for stroke_index, stroke in ipairs(signature.strokes) do
        if stroke_index > MAX_STROKES or point_count >= MAX_POINTS then
            break
        end

        if type(stroke) == "table" then
            local normalized_stroke = {}

            for _, point in ipairs(stroke) do
                if point_count >= MAX_POINTS then
                    break
                end

                if type(point) == "table" then
                    normalized_stroke[#normalized_stroke + 1] = {
                        x = clampUnit(point.x or point[1]),
                        y = clampUnit(point.y or point[2]),
                    }
                    point_count = point_count + 1
                end
            end

            if #normalized_stroke > 0 then
                normalized.strokes[#normalized.strokes + 1] = normalized_stroke
            end
        end
    end

    if point_count == 0 then
        return nil
    end

    return normalized
end

local function serializeSignature(signature)
    local serialized_strokes = {}

    for _, stroke in ipairs(signature.strokes) do
        local serialized_points = {}

        for _, point in ipairs(stroke) do
            serialized_points[#serialized_points + 1] = ("%d:%d"):format(
                math.floor(point.x * COORDINATE_SCALE + 0.5),
                math.floor(point.y * COORDINATE_SCALE + 0.5)
            )
        end

        serialized_strokes[#serialized_strokes + 1] = table.concat(serialized_points, ",")
    end

    return table.concat(serialized_strokes, "|")
end

local function deserializeSignature(value)
    local signature = { kind = "drawn", strokes = {} }

    for serialized_stroke in value:gmatch("[^|]+") do
        local stroke = {}

        for raw_x, raw_y in serialized_stroke:gmatch("(%d+):(%d+)") do
            stroke[#stroke + 1] = {
                x = tonumber(raw_x) / COORDINATE_SCALE,
                y = tonumber(raw_y) / COORDINATE_SCALE,
            }
        end

        if #stroke > 0 then
            signature.strokes[#signature.strokes + 1] = stroke
        end
    end

    return normalizeSignature(signature)
end

local function ensureLoaded()
    if loaded then
        return
    end

    loaded = true
    signatures = {}

    if not love.filesystem.getInfo(SAVE_PATH, "file") then
        return
    end

    local contents, read_error = love.filesystem.read(SAVE_PATH)

    if not contents then
        print("Unable to read save-slot signatures: " .. tostring(read_error))
        return
    end

    for line in contents:gmatch("[^\r\n]+") do
        local raw_index, serialized_signature = line:match("^(%d+)\tD\t(.+)$")
        local index = normalizeIndex(raw_index)
        local signature = serialized_signature and deserializeSignature(serialized_signature) or nil

        if index and signature then
            signatures[index] = signature
        end
    end
end

local function writeSignatures()
    local lines = {}

    for index = 1, SLOT_COUNT do
        if signatures[index] then
            lines[#lines + 1] = tostring(index) .. "\tD\t" .. serializeSignature(signatures[index])
        end
    end

    return love.filesystem.write(SAVE_PATH, table.concat(lines, "\n"))
end

function save_slots.load()
    ensureLoaded()
end

function save_slots.getCount()
    return SLOT_COUNT
end

function save_slots.getSignature(index)
    ensureLoaded()

    return signatures[normalizeIndex(index)]
end

function save_slots.isEmpty(index)
    return save_slots.getSignature(index) == nil
end

function save_slots.setSignature(index, signature)
    ensureLoaded()

    index = normalizeIndex(index)
    signature = normalizeSignature(signature)

    if not index or not signature then
        return false, "Draw a signature before confirming."
    end

    local previous_signature = signatures[index]
    signatures[index] = signature

    local success, write_error = writeSignatures()

    if not success then
        signatures[index] = previous_signature
        return false, write_error
    end

    return true
end

function save_slots.delete(index)
    ensureLoaded()

    index = normalizeIndex(index)

    if not index or not signatures[index] then
        return false, "This save slot is already empty."
    end

    local previous_signature = signatures[index]
    signatures[index] = nil

    local success, write_error = writeSignatures()

    if not success then
        signatures[index] = previous_signature
        return false, write_error
    end

    if active_slot == index then
        active_slot = nil
    end

    return true
end

function save_slots.setActive(index)
    index = normalizeIndex(index)

    if not index or save_slots.isEmpty(index) then
        return false
    end

    active_slot = index
    return true
end

function save_slots.getActiveSlot()
    return active_slot
end

function save_slots.getActiveSignature()
    return active_slot and save_slots.getSignature(active_slot) or nil
end

return save_slots

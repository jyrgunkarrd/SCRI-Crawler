local editor = {}

local OUTPUT_DIR = "data/map_files"
local PALETTE_DIR = "assets/map_palettes"
local FONT_PATH = "assets/fonts/Furore.otf"
local SWATCH_COUNT = 10
local HEX_SIZE = 42
local SQRT_3 = math.sqrt(3)
local TILE_COLOR = { 0.28, 0.42, 0.36, 1 }
local CORRIDOR_COLOR = { 0.21, 0.32, 0.29, 1 }
local HOVER_COLOR = { 0.85, 0.78, 0.45, 0.55 }
local START_COLOR = { 0.09, 0.075, 0.045, 1 }
local START_FILL_COLOR = { 0.95, 0.82, 0.36, 0.9 }
local DOOR_FILL_COLOR = { 1, 1, 1, 1 }
local DOOR_OUTLINE_COLOR = { 0.03, 0.025, 0.02, 1 }
local DOOR_SELECT_COLOR = { 0.95, 0.82, 0.36, 0.35 }
local SPAWN_MARKER_FILL_COLOR = { 1, 1, 1, 0.92 }
local SPAWN_MARKER_TEXT_COLOR = { 0, 0, 0, 1 }
local DOOR_RADIUS_RATIO = 0.28
local GRID_COLOR = { 1, 1, 1, 0.08 }
local TEXT_COLOR = { 0.88, 0.88, 0.82, 1 }
local BACKGROUND_COLOR = { 0.055, 0.058, 0.068, 1 }

local state = {
    tiles = {},
    doors = {},
    palette_id = 1,
    palette = {},
    swatch_index = 1,
    camera_x = 0,
    camera_y = 0,
    dragging = false,
    erase_dragging = false,
    pan_dragging = false,
    message = "R room  C corridor  D doors  S start  E spawn  Enter export",
    paint_mode = "room",
    door_selection = nil,
    export_index = 1,
    map_files = {},
    active_file_index = nil,
    active_file_name = nil,
    dirty = false,
    confirm_action = nil,
    confirm_target = nil,
    pending_load = nil,
    show_tile_labels = false,
    space_down = false,
    spawn_edit = nil,
    door_edit = nil,
}

local function getSourceRoot()
    local source = love.filesystem.getSource()

    if source and source:match("%.love$") then
        return love.filesystem.getSourceBaseDirectory()
    end

    return source or "."
end

local function joinPath(...)
    local parts = { ... }
    local path = table.concat(parts, "/"):gsub("//+", "/")

    return path
end

local function stripTrailingSlash(path)
    return (path:gsub("/+$", ""))
end

local function shellQuote(path)
    return "'" .. path:gsub("'", "'\\''") .. "'"
end

local function copyColor(color)
    return { color[1], color[2], color[3], color[4] or 1 }
end

local function getFallbackPalette()
    return {
        { 0.28, 0.42, 0.36, 1 },
        { 0.21, 0.32, 0.29, 1 },
        { 0.42, 0.36, 0.24, 1 },
        { 0.48, 0.28, 0.22, 1 },
        { 0.34, 0.28, 0.46, 1 },
        { 0.24, 0.36, 0.50, 1 },
        { 0.50, 0.42, 0.24, 1 },
        { 0.36, 0.36, 0.38, 1 },
        { 0.16, 0.18, 0.20, 1 },
        { 0.70, 0.62, 0.42, 1 },
    }
end

local function getActiveSwatch()
    return state.palette[state.swatch_index] or state.palette[1] or TILE_COLOR
end

local function getPalettePath(id)
    local numeric_path = ("%s/%d.png"):format(PALETTE_DIR, id)
    local named_path = ("%s/palette_%d.png"):format(PALETTE_DIR, id)

    if love.filesystem.getInfo(numeric_path) then
        return numeric_path
    end

    return named_path
end

local function loadPalette(id)
    local path = getPalettePath(id)

    if not love.filesystem.getInfo(path) then
        state.message = ("Palette %d not found."):format(id)
        return false
    end

    local ok, image_data = pcall(love.image.newImageData, path)

    if not ok then
        state.message = "Palette load failed: " .. tostring(image_data)
        return false
    end

    local width = image_data:getWidth()
    local height = image_data:getHeight()
    local y = math.max(0, math.min(height - 1, math.floor(height / 2)))
    local palette = {}

    for index = 1, SWATCH_COUNT do
        local x = math.max(0, math.min(width - 1, math.floor((index - 0.5) * width / SWATCH_COUNT)))
        local r, g, b, a = image_data:getPixel(x, y)

        palette[index] = { r, g, b, a }
    end

    state.palette_id = id
    state.palette = palette
    state.swatch_index = math.max(1, math.min(#state.palette, state.swatch_index))
    state.message = ("Loaded palette %d."):format(id)

    return true
end

local function selectSwatch(delta)
    state.swatch_index = ((state.swatch_index - 1 + delta) % SWATCH_COUNT) + 1
    state.message = ("Selected swatch %d."):format(state.swatch_index)
end

local function markDirty()
    state.dirty = true
    state.confirm_action = nil
    state.confirm_target = nil
    state.pending_load = nil
end

local function markClean()
    state.dirty = false
    state.confirm_action = nil
    state.confirm_target = nil
end

local function requestConfirmation(action, target, message)
    if state.confirm_action == action and state.confirm_target == target then
        state.confirm_action = nil
        state.confirm_target = nil
        return true
    end

    state.confirm_action = action
    state.confirm_target = target
    state.message = message

    return false
end

local function cancelConfirmation()
    state.confirm_action = nil
    state.confirm_target = nil
    state.pending_load = nil
end

local function tileKey(q, r)
    return q .. "," .. r
end

local function doorEndpointKey(endpoint)
    return tileKey(endpoint.q, endpoint.r)
end

local function doorKey(a, b)
    local a_key = doorEndpointKey(a)
    local b_key = doorEndpointKey(b)

    if a_key < b_key then
        return a_key .. "|" .. b_key
    end

    return b_key .. "|" .. a_key
end

local function areAdjacent(a, b)
    local dq = b.q - a.q
    local dr = b.r - a.r

    return (dq == 1 and dr == 0)
        or (dq == 1 and dr == -1)
        or (dq == 0 and dr == -1)
        or (dq == -1 and dr == 0)
        or (dq == -1 and dr == 1)
        or (dq == 0 and dr == 1)
end

local function getBaseName(path)
    local file_name = path:match("([^/]+)$") or path

    return (file_name:gsub("%.[^%.]+$", ""))
end

local function axialToPixel(q, r)
    return HEX_SIZE * SQRT_3 * (q + r / 2), HEX_SIZE * 1.5 * r
end

local function pixelToAxial(x, y)
    local q = (SQRT_3 / 3 * x - 1 / 3 * y) / HEX_SIZE
    local r = (2 / 3 * y) / HEX_SIZE

    return q, r
end

local function cubeRound(q, r)
    local x = q
    local z = r
    local y = -x - z
    local rounded_x = math.floor(x + 0.5)
    local rounded_y = math.floor(y + 0.5)
    local rounded_z = math.floor(z + 0.5)
    local x_diff = math.abs(rounded_x - x)
    local y_diff = math.abs(rounded_y - y)
    local z_diff = math.abs(rounded_z - z)

    if x_diff > y_diff and x_diff > z_diff then
        rounded_x = -rounded_y - rounded_z
    elseif y_diff > z_diff then
        rounded_y = -rounded_x - rounded_z
    else
        rounded_z = -rounded_x - rounded_y
    end

    return rounded_x, rounded_z
end

local function screenToTile(x, y)
    local world_x = x - love.graphics.getWidth() / 2 - state.camera_x
    local world_y = y - love.graphics.getHeight() / 2 - state.camera_y

    return cubeRound(pixelToAxial(world_x, world_y))
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

local function getScreenCenter(q, r)
    local x, y = axialToPixel(q, r)

    return x + love.graphics.getWidth() / 2 + state.camera_x,
        y + love.graphics.getHeight() / 2 + state.camera_y
end

local function getDoorMidpoint(door)
    local ax, ay = getScreenCenter(door.a.q, door.a.r)
    local bx, by = getScreenCenter(door.b.q, door.b.r)

    return (ax + bx) / 2, (ay + by) / 2
end

local function getDoorAtPoint(x, y)
    local best_key = nil
    local best_distance = math.huge
    local hit_radius = HEX_SIZE * DOOR_RADIUS_RATIO + 8

    for key, door in pairs(state.doors) do
        local midpoint_x, midpoint_y = getDoorMidpoint(door)
        local dx = x - midpoint_x
        local dy = y - midpoint_y
        local distance = math.sqrt(dx * dx + dy * dy)

        if distance <= hit_radius and distance < best_distance then
            best_key = key
            best_distance = distance
        end
    end

    return best_key and state.doors[best_key] or nil, best_key
end

local function setTile(q, r, value)
    local key = tileKey(q, r)

    if value then
        local existing = state.tiles[key]
        state.tiles[key] = {
            q = q,
            r = r,
            start = existing and existing.start or nil,
            spawn_event = existing and existing.spawn_event or nil,
            corridor = state.paint_mode == "corridor" or nil,
            palette = state.palette_id,
            swatch = state.swatch_index,
            color = copyColor(getActiveSwatch()),
        }
        markDirty()
    else
        for door_id, door in pairs(state.doors) do
            if doorEndpointKey(door.a) == key or doorEndpointKey(door.b) == key then
                state.doors[door_id] = nil

                if state.door_edit and state.door_edit.key == door_id then
                    state.door_edit = nil
                end
            end
        end

        state.tiles[key] = nil
        markDirty()
    end
end

local function toggleStartAt(q, r)
    local key = tileKey(q, r)
    local tile = state.tiles[key] or { q = q, r = r }

    tile.start = not tile.start or nil
    state.tiles[key] = tile

    if tile.start then
        state.message = ("Marked start at q=%d r=%d"):format(q, r)
    else
        state.message = ("Cleared start at q=%d r=%d"):format(q, r)
    end

    markDirty()
end

local function startSpawnEventEditAt(q, r)
    local tile = state.tiles[tileKey(q, r)]

    if not tile then
        state.message = "Spawn events need an existing hex."
        return
    end

    cancelConfirmation()
    state.door_selection = nil
    state.spawn_edit = {
        q = q,
        r = r,
        text = tile.spawn_event or "",
        suppress_text = "e",
    }
    state.message = ("Spawn event q=%d r=%d: %s"):format(q, r, state.spawn_edit.text)
end

local function commitSpawnEventEdit()
    if not state.spawn_edit then
        return
    end

    local edit = state.spawn_edit
    local key = tileKey(edit.q, edit.r)
    local tile = state.tiles[key]

    if tile then
        tile.spawn_event = edit.text ~= "" and edit.text or nil
        state.message = tile.spawn_event
            and ("Set spawn event %q at q=%d r=%d"):format(tile.spawn_event, edit.q, edit.r)
            or ("Cleared spawn event at q=%d r=%d"):format(edit.q, edit.r)
        markDirty()
    else
        state.message = "Spawn event target no longer exists."
    end

    state.spawn_edit = nil
end

local function cancelSpawnEventEdit()
    if state.spawn_edit then
        state.spawn_edit = nil
        state.message = "Spawn event edit cancelled."
    end
end

local function startDoorEventEdit(door_key, suppress_text)
    local door = state.doors[door_key]

    if not door then
        state.message = "Door target no longer exists."
        return
    end

    cancelConfirmation()
    state.door_selection = nil
    state.spawn_edit = nil
    state.door_edit = {
        key = door_key,
        text = door.door_event or "",
        suppress_text = suppress_text,
        label = ("%d,%d <-> %d,%d"):format(door.a.q, door.a.r, door.b.q, door.b.r),
    }
    state.message = ("Door event %s: %s"):format(state.door_edit.label, state.door_edit.text)
end

local function commitDoorEventEdit()
    if not state.door_edit then
        return
    end

    local edit = state.door_edit
    local door = state.doors[edit.key]

    if door then
        door.door_event = edit.text ~= "" and edit.text or nil
        state.message = door.door_event
            and ("Set door event %q"):format(door.door_event)
            or "Cleared door event."
        markDirty()
    else
        state.message = "Door target no longer exists."
    end

    state.door_edit = nil
end

local function cancelDoorEventEdit()
    if state.door_edit then
        state.door_edit = nil
        state.message = "Door event edit cancelled."
    end
end

local function applyBrush(x, y, value)
    local q, r = screenToTile(x, y)

    setTile(q, r, value)
end

local function toggleDoorAt(q, r)
    local tile = state.tiles[tileKey(q, r)]

    if not tile then
        state.message = "Doors need existing hexes."
        state.door_selection = nil
        return
    end

    if not state.door_selection then
        state.door_selection = { q = q, r = r }
        state.message = ("Door start q=%d r=%d"):format(q, r)
        return
    end

    local first = state.door_selection
    local second = { q = q, r = r }
    state.door_selection = nil

    if first.q == second.q and first.r == second.r then
        state.message = "Door cancelled."
        return
    end

    if not areAdjacent(first, second) then
        state.message = "Door endpoints must be adjacent."
        return
    end

    local key = doorKey(first, second)

    if state.doors[key] then
        state.doors[key] = nil
        state.message = "Door removed."
    else
        state.doors[key] = { a = first, b = second }
        state.message = "Door placed."
        startDoorEventEdit(key)
    end

    markDirty()
end

local function sortedTiles()
    local tiles = {}

    for _, tile in pairs(state.tiles) do
        tiles[#tiles + 1] = tile
    end

    table.sort(tiles, function(a, b)
        if a.r == b.r then
            return a.q < b.q
        end

        return a.r < b.r
    end)

    return tiles
end

local function getNativeOutputDir()
    return joinPath(stripTrailingSlash(getSourceRoot()), OUTPUT_DIR)
end

local function scanMapFiles()
    love.filesystem.createDirectory(OUTPUT_DIR)

    state.map_files = {}

    for _, file_name in ipairs(love.filesystem.getDirectoryItems(OUTPUT_DIR)) do
        local path = joinPath(OUTPUT_DIR, file_name)
        local info = love.filesystem.getInfo(path)

        if info and info.type == "file" and file_name:match("%.lua$") then
            state.map_files[#state.map_files + 1] = file_name
        end
    end

    table.sort(state.map_files)
end

local function mapFileExists(file_name)
    for _, map_file in ipairs(state.map_files) do
        if map_file == file_name then
            return true
        end
    end

    return false
end

local function getNextAvailableFileName()
    scanMapFiles()

    while mapFileExists(("map_%03d.lua"):format(state.export_index)) do
        state.export_index = state.export_index + 1
    end

    return ("map_%03d.lua"):format(state.export_index)
end

local function getExportPath()
    local file_name = state.active_file_name or ("map_%03d.lua"):format(state.export_index)

    return joinPath(getNativeOutputDir(), file_name), file_name
end

local function getExportPathForFile(file_name)
    return joinPath(getNativeOutputDir(), file_name), file_name
end

local function writeFile(path, data)
    os.execute("mkdir -p " .. shellQuote(getNativeOutputDir()))

    local file, err = io.open(path, "wb")

    if not file then
        return nil, err
    end

    file:write(data)
    file:close()

    return true
end

local function updateActiveFileAfterSave(file_name)
    state.active_file_name = file_name
    scanMapFiles()

    for index, map_file in ipairs(state.map_files) do
        if map_file == file_name then
            state.active_file_index = index
            break
        end
    end

    if file_name == ("map_%03d.lua"):format(state.export_index) then
        state.export_index = state.export_index + 1
    end

    markClean()
end

local function serializeMap(file_name)
    local lines = {
        "return {",
        ("    id = %q,"):format(getBaseName(file_name)),
        "    tiles = {",
    }

    for _, tile in ipairs(sortedTiles()) do
        local fields = {
            ("q = %d"):format(tile.q),
            ("r = %d"):format(tile.r),
        }

        if tile.start then
            fields[#fields + 1] = "start = true"
        end

        if tile.corridor then
            fields[#fields + 1] = "corridor = true"
        end

        if tile.spawn_event then
            fields[#fields + 1] = ("spawn_event = %q"):format(tile.spawn_event)
        end

        if tile.palette then
            fields[#fields + 1] = ("palette = %d"):format(tile.palette)
        end

        if tile.swatch then
            fields[#fields + 1] = ("swatch = %d"):format(tile.swatch)
        end

        if tile.color then
            fields[#fields + 1] = ("color = { %.4f, %.4f, %.4f, %.4f }")
                :format(tile.color[1], tile.color[2], tile.color[3], tile.color[4] or 1)
        end

        lines[#lines + 1] = "        { " .. table.concat(fields, ", ") .. " },"
    end

    lines[#lines + 1] = "    },"
    lines[#lines + 1] = "    doors = {"

    local door_keys = {}

    for key in pairs(state.doors) do
        door_keys[#door_keys + 1] = key
    end

    table.sort(door_keys)

    for _, key in ipairs(door_keys) do
        local door = state.doors[key]
        local fields = {
            ("a = { q = %d, r = %d }"):format(door.a.q, door.a.r),
            ("b = { q = %d, r = %d }"):format(door.b.q, door.b.r),
        }

        if door.door_event then
            fields[#fields + 1] = ("door_event = %q"):format(door.door_event)
        end

        lines[#lines + 1] = "        { " .. table.concat(fields, ", ") .. " },"
    end

    lines[#lines + 1] = "    },"
    lines[#lines + 1] = "}"
    lines[#lines + 1] = ""

    return table.concat(lines, "\n")
end

local function saveCurrentMap()
    local path, file_name = getExportPath()
    local ok, err = writeFile(path, serializeMap(file_name))

    if not ok then
        state.message = "Save failed: " .. tostring(err)
        print(state.message)
        return false
    end

    state.message = "Saved " .. joinPath(OUTPUT_DIR, file_name)
    updateActiveFileAfterSave(file_name)
    print(state.message)

    return true
end

local function exportMap()
    local path, file_name = getExportPath()

    if state.dirty and state.active_file_name then
        local message = ("Unsaved changes. Press Enter again to overwrite %s."):format(file_name)

        if not requestConfirmation("export", file_name, message) then
            return
        end
    end

    local ok, err = writeFile(path, serializeMap(file_name))

    if not ok then
        state.message = "Export failed: " .. tostring(err)
        print(state.message)
        return
    end

    state.message = "Exported " .. joinPath(OUTPUT_DIR, file_name)
    updateActiveFileAfterSave(file_name)
    print(state.message)
end

local function saveAsMap()
    local file_name = getNextAvailableFileName()
    local path = getExportPathForFile(file_name)
    local ok, err = writeFile(path, serializeMap(file_name))

    if not ok then
        state.message = "Save As failed: " .. tostring(err)
        print(state.message)
        return
    end

    state.message = "Saved as " .. joinPath(OUTPUT_DIR, file_name)
    updateActiveFileAfterSave(file_name)
    print(state.message)
end

local function performLoadMapFile(next_index, next_file_name)
    scanMapFiles()

    for index, map_file in ipairs(state.map_files) do
        if map_file == next_file_name then
            next_index = index
            break
        end
    end

    state.active_file_index = next_index
    state.active_file_name = next_file_name

    local module_path = ("data.map_files.%s"):format(getBaseName(state.active_file_name))
    package.loaded[module_path] = nil

    local ok, map_file = pcall(require, module_path)

    if not ok then
        state.message = "Load failed: " .. tostring(map_file)
        print(state.message)
        return
    end

    state.tiles = {}
    state.doors = {}

    for _, tile in ipairs(map_file.tiles or {}) do
        state.tiles[tileKey(tile.q, tile.r)] = {
            q = tile.q,
            r = tile.r,
            start = tile.start or nil,
            corridor = tile.corridor or nil,
            spawn_event = tile.spawn_event,
            palette = tile.palette,
            swatch = tile.swatch,
            color = tile.color and copyColor(tile.color) or nil,
        }
    end

    for _, door in ipairs(map_file.doors or {}) do
        if door.a and door.b then
            state.doors[doorKey(door.a, door.b)] = {
                a = { q = door.a.q, r = door.a.r },
                b = { q = door.b.q, r = door.b.r },
                door_event = door.door_event,
            }
        end
    end

    state.spawn_edit = nil
    state.door_edit = nil
    state.door_selection = nil
    state.pending_load = nil
    state.message = ("Loaded %s"):format(state.active_file_name)
    markClean()
    print(state.message)
end

local function loadMapFile(index)
    scanMapFiles()

    if #state.map_files == 0 then
        state.message = "No map files in " .. OUTPUT_DIR
        return
    end

    local next_index = ((index - 1) % #state.map_files) + 1
    local next_file_name = state.map_files[next_index]

    if state.dirty then
        state.pending_load = {
            index = next_index,
            file_name = next_file_name,
        }
        state.message = ("Unsaved changes. Enter saves then loads %s. Press load again to discard. Esc cancels.")
            :format(next_file_name)
        return
    end

    performLoadMapFile(next_index, next_file_name)
end

local function drawGrid()
    local width = love.graphics.getWidth()
    local height = love.graphics.getHeight()
    local min_q, min_r = screenToTile(-HEX_SIZE * 2, -HEX_SIZE * 2)
    local max_q, max_r = screenToTile(width + HEX_SIZE * 2, height + HEX_SIZE * 2)

    love.graphics.setColor(GRID_COLOR)
    love.graphics.setLineWidth(1)

    for r = math.min(min_r, max_r) - 4, math.max(min_r, max_r) + 4 do
        for q = math.min(min_q, max_q) - 4, math.max(min_q, max_q) + 4 do
            local x, y = getScreenCenter(q, r)

            love.graphics.polygon("line", buildHexPoints(x, y))
        end
    end
end

local function drawTiles()
    for _, tile in ipairs(sortedTiles()) do
        local x, y = getScreenCenter(tile.q, tile.r)
        local color = tile.color or (tile.corridor and CORRIDOR_COLOR or TILE_COLOR)

        love.graphics.setColor(color)
        love.graphics.polygon("fill", buildHexPoints(x, y))

        if tile.start then
            love.graphics.setColor(START_FILL_COLOR)
            love.graphics.polygon("fill", buildHexPoints(x, y, HEX_SIZE * 0.42))
            love.graphics.setColor(START_COLOR)
            love.graphics.setLineWidth(3)
            love.graphics.polygon("line", buildHexPoints(x, y, HEX_SIZE * 0.42))
            love.graphics.setLineWidth(1)
        end

        if tile.spawn_event then
            local font = love.graphics.getFont()
            local label = "E"
            local width = 22
            local height = 22

            love.graphics.setColor(SPAWN_MARKER_FILL_COLOR)
            love.graphics.rectangle("fill", x - width / 2, y - height / 2, width, height)
            love.graphics.setColor(SPAWN_MARKER_TEXT_COLOR)
            love.graphics.print(label, x - font:getWidth(label) / 2, y - font:getHeight() / 2)
        end
    end
end

local function drawTileLabels()
    if not state.show_tile_labels then
        return
    end

    local font = love.graphics.getFont()

    love.graphics.setColor(1, 1, 1, 0.92)

    for _, tile in ipairs(sortedTiles()) do
        local x, y = getScreenCenter(tile.q, tile.r)
        local label = tile.corridor and "C" or "R"
        local width = 22
        local height = 22

        love.graphics.setColor(0, 0, 0, 0.78)
        love.graphics.rectangle("fill", x - width / 2, y - height / 2, width, height)
        love.graphics.setColor(1, 1, 1, 0.92)
        love.graphics.print(label, x - font:getWidth(label) / 2, y - font:getHeight() / 2)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

local function drawDoors()
    for _, door in pairs(state.doors) do
        local ax, ay = getScreenCenter(door.a.q, door.a.r)
        local bx, by = getScreenCenter(door.b.q, door.b.r)
        local midpoint_x = (ax + bx) / 2
        local midpoint_y = (ay + by) / 2
        local radius = HEX_SIZE * DOOR_RADIUS_RATIO

        love.graphics.setColor(DOOR_FILL_COLOR)
        love.graphics.circle("fill", midpoint_x, midpoint_y, radius)
        love.graphics.setColor(DOOR_OUTLINE_COLOR)
        love.graphics.setLineWidth(3)
        love.graphics.circle("line", midpoint_x, midpoint_y, radius)
    end

    love.graphics.setLineWidth(1)

    if state.door_selection then
        local x, y = getScreenCenter(state.door_selection.q, state.door_selection.r)

        love.graphics.setColor(DOOR_SELECT_COLOR)
        love.graphics.polygon("fill", buildHexPoints(x, y))
    end
end

local function drawHover()
    local mouse_x, mouse_y = love.mouse.getPosition()
    local q, r = screenToTile(mouse_x, mouse_y)
    local x, y = getScreenCenter(q, r)

    love.graphics.setColor(HOVER_COLOR)
    love.graphics.polygon("fill", buildHexPoints(x, y))
end

local function drawStatus()
    local active_file = state.active_file_name or ("map_%03d.lua"):format(state.export_index)
    local dirty_text = state.dirty and "*" or "saved"
    local message = state.message

    if state.spawn_edit then
        message = ("Spawn event q=%d r=%d: %s_   Enter save  Esc cancel")
            :format(state.spawn_edit.q, state.spawn_edit.r, state.spawn_edit.text)
    elseif state.door_edit then
        message = ("Door event %s: %s_   Enter save  Esc cancel")
            :format(state.door_edit.label, state.door_edit.text)
    end

    local text = ("%s   Mode: %s   Palette: %d   Swatch: %d   File: %s   Tiles: %d")
        :format(message, state.paint_mode, state.palette_id, state.swatch_index, active_file .. " " .. dirty_text, #sortedTiles())

    love.graphics.setColor(0, 0, 0, 0.48)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), 76)
    love.graphics.setColor(TEXT_COLOR)
    love.graphics.print(text, 16, 12)
    love.graphics.setColor(1, 1, 1, 1)
end

local function drawPalette()
    local swatch_size = 24
    local gap = 6
    local x = 16
    local y = 44

    for index = 1, SWATCH_COUNT do
        local color = state.palette[index] or TILE_COLOR

        love.graphics.setColor(color)
        love.graphics.rectangle("fill", x, y, swatch_size, swatch_size)

        if index == state.swatch_index then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.setLineWidth(3)
        else
            love.graphics.setColor(0, 0, 0, 0.75)
            love.graphics.setLineWidth(1)
        end

        love.graphics.rectangle("line", x, y, swatch_size, swatch_size)
        x = x + swatch_size + gap
    end

    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

function editor.load()
    love.window.setTitle("SCRI Diablo Map Editor")
    love.graphics.setBackgroundColor(BACKGROUND_COLOR)
    love.graphics.setDefaultFilter("linear", "linear", 1)
    love.graphics.setFont(love.graphics.newFont(FONT_PATH, 18))
    state.palette = getFallbackPalette()
    loadPalette(1)
    scanMapFiles()
end

function editor.update() end

function editor.draw()
    love.graphics.clear(BACKGROUND_COLOR[1], BACKGROUND_COLOR[2], BACKGROUND_COLOR[3], BACKGROUND_COLOR[4])
    drawGrid()
    drawTiles()
    drawTileLabels()
    drawDoors()
    drawHover()
    drawStatus()
    drawPalette()
end

function editor.keypressed(key)
    if state.spawn_edit then
        if key == "escape" then
            cancelSpawnEventEdit()
        elseif key == "return" or key == "kpenter" then
            commitSpawnEventEdit()
        elseif key == "backspace" then
            state.spawn_edit.text = state.spawn_edit.text:sub(1, -2)
        end

        return
    end

    if state.door_edit then
        if key == "escape" then
            cancelDoorEventEdit()
        elseif key == "return" or key == "kpenter" then
            commitDoorEventEdit()
        elseif key == "backspace" then
            state.door_edit.text = state.door_edit.text:sub(1, -2)
        end

        return
    end

    if state.pending_load then
        local pending_load = state.pending_load

        if key == "escape" then
            state.pending_load = nil
            state.message = "Load cancelled."
        elseif key == "return" or key == "kpenter" then
            if saveCurrentMap() then
                performLoadMapFile(pending_load.index, pending_load.file_name)
            end
        elseif key == "l" or key == "[" or key == "]" then
            performLoadMapFile(pending_load.index, pending_load.file_name)
        else
            state.message = ("Unsaved changes. Enter saves then loads %s. Press load again to discard. Esc cancels.")
                :format(pending_load.file_name)
        end

        return
    end

    if key == "escape" then
        if state.door_selection then
            state.door_selection = nil
            state.message = "Door selection cancelled."
        else
            love.event.quit()
        end
    elseif key == "r" then
        cancelConfirmation()
        state.paint_mode = "room"
        state.door_selection = nil
        state.message = "Painting room hexes."
    elseif key == "c" then
        cancelConfirmation()
        state.paint_mode = "corridor"
        state.door_selection = nil
        state.message = "Painting corridor hexes."
    elseif key == "," then
        cancelConfirmation()
        selectSwatch(-1)
    elseif key == "." then
        cancelConfirmation()
        selectSwatch(1)
    elseif key:match("^%d$") then
        cancelConfirmation()
        local palette_id = key == "0" and 10 or tonumber(key)

        loadPalette(palette_id)
    elseif key == "d" then
        cancelConfirmation()
        state.paint_mode = "door"
        state.door_selection = nil
        state.message = "Door mode: click two adjacent hexes."
    elseif key == "e" then
        if state.confirm_action == "export" then
            state.message = "Export pending. Press Enter to overwrite, or choose another action to cancel."
            return
        end

        local mouse_x, mouse_y = love.mouse.getPosition()
        local q, r = screenToTile(mouse_x, mouse_y)

        startSpawnEventEditAt(q, r)
    elseif key == "return" or key == "kpenter" then
        exportMap()
    elseif key == "a" then
        cancelConfirmation()
        saveAsMap()
    elseif key == "l" then
        loadMapFile(state.active_file_index or 1)
    elseif key == "]" then
        loadMapFile((state.active_file_index or 0) + 1)
    elseif key == "[" then
        loadMapFile((state.active_file_index or 2) - 1)
    elseif key == "delete" or key == "backspace" then
        if state.dirty and not requestConfirmation("clear", "current", "Unsaved changes. Press clear again to discard and clear.") then
            return
        end

        state.tiles = {}
        state.doors = {}
        state.spawn_edit = nil
        state.door_edit = nil
        state.door_selection = nil
        state.active_file_name = nil
        state.active_file_index = nil
        state.message = "Cleared map."
        markDirty()
    elseif key == "home" then
        cancelConfirmation()
        state.camera_x = 0
        state.camera_y = 0
        state.message = "Reset camera."
    elseif key == "tab" then
        cancelConfirmation()
        state.show_tile_labels = not state.show_tile_labels
        state.message = state.show_tile_labels and "Tile labels on." or "Tile labels off."
    elseif key == "s" then
        local mouse_x, mouse_y = love.mouse.getPosition()
        local q, r = screenToTile(mouse_x, mouse_y)

        toggleStartAt(q, r)
    elseif key == "space" then
        state.space_down = true
    end
end

function editor.textinput(text)
    local edit = state.spawn_edit or state.door_edit

    if not edit then
        return
    end

    if edit.suppress_text and text:lower() == edit.suppress_text then
        edit.suppress_text = nil
        return
    end

    edit.suppress_text = nil

    edit.text = edit.text .. text
end

function editor.keyreleased(key)
    if key == "space" then
        state.space_down = false
    end
end

function editor.mousepressed(x, y, button)
    if state.spawn_edit or state.door_edit or state.pending_load then
        return
    end

    if state.paint_mode == "door" and button == 1 and not state.space_down then
        cancelConfirmation()
        local q, r = screenToTile(x, y)

        toggleDoorAt(q, r)
    elseif state.paint_mode == "door" and button == 2 then
        cancelConfirmation()
        local _, door_key = getDoorAtPoint(x, y)

        if door_key then
            startDoorEventEdit(door_key)
        else
            state.door_selection = nil
            state.message = "Door selection cancelled."
        end
    elseif button == 1 and not state.space_down then
        cancelConfirmation()
        state.dragging = true
        applyBrush(x, y, true)
    elseif button == 2 then
        cancelConfirmation()
        state.erase_dragging = true
        applyBrush(x, y, false)
    elseif button == 3 or state.space_down then
        cancelConfirmation()
        state.pan_dragging = true
    end
end

function editor.mousereleased(_, _, button)
    if button == 1 then
        state.dragging = false
        state.pan_dragging = false
    elseif button == 2 then
        state.erase_dragging = false
    elseif button == 3 then
        state.pan_dragging = false
    end
end

function editor.mousemoved(x, y, dx, dy)
    if state.spawn_edit or state.door_edit or state.pending_load then
        return
    end

    if state.pan_dragging then
        state.camera_x = state.camera_x + dx
        state.camera_y = state.camera_y + dy
    elseif state.dragging then
        applyBrush(x, y, true)
    elseif state.erase_dragging then
        applyBrush(x, y, false)
    end
end

function editor.wheelmoved(_, y)
    if y > 0 then
        HEX_SIZE = math.min(96, HEX_SIZE + 4)
    elseif y < 0 then
        HEX_SIZE = math.max(18, HEX_SIZE - 4)
    end
end

return editor

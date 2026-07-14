local equip_logic = require("src.sys.equip_logic")

local rumor_missions = {}

local function resolveMapPath(mission)
    if type(mission) ~= "string" or mission == "" then
        return nil
    end

    local path = mission

    if not path:match("%.lua$") then
        path = path .. ".lua"
    end

    if not path:match("/") then
        path = "assets/maps/" .. path
    end

    return path
end

local function getMissionTargets(item, definition)
    local source = item and item.mission or definition and definition.mission
    local missions = type(source) == "table" and source or { source }
    local targets = {}

    for _, mission in ipairs(missions) do
        local path = resolveMapPath(mission)

        if path then
            targets[#targets + 1] = {
                id = tostring(mission):gsub("%.lua$", ""):match("([^/]+)$"),
                path = path,
            }
        end
    end

    return targets
end


local function inventorySort(a, b)
    local a_row = tonumber(a and a.inv_row) or math.huge
    local b_row = tonumber(b and b.inv_row) or math.huge

    if a_row ~= b_row then
        return a_row < b_row
    end

    local a_col = tonumber(a and a.inv_col) or math.huge
    local b_col = tonumber(b and b.inv_col) or math.huge

    if a_col ~= b_col then
        return a_col < b_col
    end

    return tostring(a and a.id or "") < tostring(b and b.id or "")
end

function rumor_missions.generate(slots)
    local chain = {}

    for slot_index = 1, 4 do
        local agent = slots and slots[slot_index] or nil

        if agent then
            local inventory = {}

            for _, item in ipairs(equip_logic.getInventory(agent)) do
                if tostring(item and item.category or ""):lower() == "rumor" then
                    inventory[#inventory + 1] = item
                end
            end

            table.sort(inventory, inventorySort)

            for _, item in ipairs(inventory) do
                local definition = equip_logic.getDefinition(item.id)
                local targets = getMissionTargets(item, definition)

                if #targets > 0 then
                    chain[#chain + 1] = {
                        slot_index = slot_index,
                        agent = agent,
                        item = item,
                        id = item.id,
                        name = item.name or definition and definition.name or item.id,
                        image_path = item.image_path or ("assets/images/equip/%s.webp"):format(item.id),
                        targets = targets,
                        target = targets[1],
                    }
                end
            end
        end
    end

    return chain
end

function rumor_missions.attachToLaunch(launch_options, slots)
    launch_options = launch_options or {}

    local map_sequence = {}

    if launch_options.map_path then
        map_sequence[#map_sequence + 1] = launch_options.map_path
    end

    for _, rumor in ipairs(rumor_missions.generate(slots)) do
        if rumor.target and rumor.target.path then
            map_sequence[#map_sequence + 1] = rumor.target.path
        end
    end

    launch_options.mission_chain = map_sequence
    launch_options.mission_chain_index = 1

    return launch_options
end

function rumor_missions.advanceLaunch(launch_options)
    local sequence = launch_options and launch_options.mission_chain or nil
    local current_index = tonumber(launch_options and launch_options.mission_chain_index) or 1
    local next_path = sequence and sequence[current_index + 1] or nil

    if not next_path then
        return nil
    end

    local next_options = {}

    for key, value in pairs(launch_options) do
        next_options[key] = value
    end

    next_options.map_path = next_path
    next_options.mission_chain_index = current_index + 1

    return next_options
end

return rumor_missions

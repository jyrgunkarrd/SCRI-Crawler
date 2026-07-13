local equip_index = {
    categorized = {},
    byId = {},
    ids = {},
    all = {},
}

local ROOT_PATH = "data/equip"
local unpack = table.unpack or unpack

local function pathToModule(path)
    return path:gsub("%.lua$", ""):gsub("/", ".")
end

local function addDefinitions(category_path, module_name)
    local definitions = require(module_name)
    local category = equip_index.categorized

    for _, segment in ipairs(category_path) do
        category[segment] = category[segment] or {}
        category = category[segment]
    end

    for _, definition in ipairs(definitions or {}) do
        if definition.id then
            category[definition.id] = definition
            equip_index.byId[definition.id] = definition
            equip_index.ids[#equip_index.ids + 1] = definition.id
            equip_index.all[#equip_index.all + 1] = definition
        end
    end
end

local function scanDirectory(path, category_path)
    local items = love.filesystem.getDirectoryItems(path)
    table.sort(items)

    for _, item in ipairs(items) do
        local item_path = ("%s/%s"):format(path, item)
        local info = love.filesystem.getInfo(item_path)

        if info and info.type == "directory" then
            local next_category_path = { unpack(category_path) }

            next_category_path[#next_category_path + 1] = item
            scanDirectory(item_path, next_category_path)
        elseif info and info.type == "file" and item:match("%.lua$") and item ~= "index.lua" then
            addDefinitions(category_path, pathToModule(item_path))
        end
    end
end

scanDirectory(ROOT_PATH, {})

return equip_index

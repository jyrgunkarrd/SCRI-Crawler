local card_index = {
    categorized = {},
    byId = {},
    all = {},
}

local ROOT_PATH = "data/cards"
local unpack = table.unpack or unpack

local function pathToModule(path)
    return path:gsub("%.lua$", ""):gsub("/", ".")
end

local function addCards(category_path, module_name)
    local cards = require(module_name)
    local category = card_index.categorized

    for _, segment in ipairs(category_path) do
        category[segment] = category[segment] or {}
        category = category[segment]
    end

    for _, card in ipairs(cards) do
        category[card.id] = card
        card_index.byId[card.id] = card
        card_index.all[#card_index.all + 1] = card
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
            addCards(category_path, pathToModule(item_path))
        end
    end
end

scanDirectory(ROOT_PATH, {})

return card_index

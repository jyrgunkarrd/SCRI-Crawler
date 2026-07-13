local image_loader = require("src.assets.image_loader")
local officer_definitions = require("data.officers")

local officers = {}

local IMAGE_DIR = "assets/images/officers/"
local IMAGE_EXTENSIONS = { ".webp", ".png", ".jpg", ".jpeg" }

local function findImagePath(id)
    local base_path = IMAGE_DIR .. tostring(id)

    for _, extension in ipairs(IMAGE_EXTENSIONS) do
        local path = base_path .. extension

        if love.filesystem.getInfo(path, "file") then
            return path
        end
    end

    return nil
end

local function buildDefinitionMap()
    local definitions_by_id = {}

    for _, definition in ipairs(officer_definitions) do
        if definition.id then
            definitions_by_id[definition.id] = definition
        end
    end

    return definitions_by_id
end

function officers.loadByIds(ids)
    local definitions_by_id = buildDefinitionMap()
    local loaded = {}

    for _, id in ipairs(ids) do
        local definition = definitions_by_id[id]

        if not definition then
            print("No officer definition found for id: " .. tostring(id))
        else
            local image_path = findImagePath(id)
            local image = nil

            if image_path then
                image = image_loader.newImage(image_path)
            else
                print("No officer image found for id: " .. tostring(id))
            end

            loaded[#loaded + 1] = {
                id = id,
                name = definition.name or id,
                office = definition.office or "",
                image = image,
                image_path = image_path,
            }
        end
    end

    return loaded
end

return officers

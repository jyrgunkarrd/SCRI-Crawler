-- data/map_pieces.lua
-- map piece definitions

local map_pieces = {

-- chambers

    {

        id = "START",
        min_hex = 19,
        max_hex = 19,
        exits = {
            "N",
            "NE",
            "E",
            "SE",
            "S",
            "SW",
            "W",
            "NW",
        },

    },

-- corridors

    {
        id = "CORRIDOR",
        corridor = true,
        min_hex = 2,
        max_hex = 7,
        flex = 3,
    }

}

return map_pieces
-- data/equip/tomes.lua
-- tome definitions

local tomes = {

    {

        id = "PHNX",
        name = "Lexurgy of the Pheonix",
        category = "equipment",
        slot = {

            "Lex",

        },
        inv_size = {H = 2, W = 2},
        stat_req = {

            {lex = 5},

        },
        lock_in = true, 
        lex_deck = {

            "INCN",
            "INCN",
            "INCN",
            "INCN",
            "INCN",

        },

    },

}

return tomes

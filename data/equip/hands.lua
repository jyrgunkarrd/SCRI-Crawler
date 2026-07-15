-- data/equip/hands.lua
-- hand slot equipment definitions

local hands = {

    {

        id = "MAM_BRK",
        name = "Palace Breaker",
        category = "equipment",
        slot = {

            "Hand",

        },
        inv_size = {H = 2, W = 2},
        stat_req = {

            {strength = 5},

        },
        lock_in = true, 
        owner = "MAM",

    },

    {

        id = "MAM_KOB",
        name = "Brass Koban",
        category = "equipment",
        slot = {

            "Hand",

        },
        inv_size = {H = 2, W = 2},
        stat_req = {

            {lex = 3},

        },
        lock_in = true, 
        owner = "MAM",

    },

}

return hands
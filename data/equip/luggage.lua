-- data/equip/luggage.lua
-- luggage definitions

local luggage = {

    {

        id = "bag",
        name = "Canvas Bag",
        inv_size = {H = 1, W = 1},
        category = "luggage",
        mult = 1,
        -- Order Data
        order = true,
        work = 2,
        cost = 2,
        avail_min = 5,
        avail_max = 10,
        options = {

            { name = "Crunch Time", cost_mult = 2, work_mult = 0.5 },

        },

    },

    {

        id = "brief",
        name = "Steel Briefcase",
        inv_size = {H = 2, W = 2},
        category = "luggage",
        mult = 2,  
        -- Order Data
        order = true,
        work = 5,
        cost = 1,
        avail_min = 5,
        avail_max = 10,
        options = {

            { name = "Crunch Time", cost_mult = 2, work_mult = 0.5 },

        },

    },

    {

        id = "truck",
        name = "Bank Truck",
        inv_size = {H = 4, W = 4},
        category = "luggage",
        mult = 4,  

    },



}

return luggage
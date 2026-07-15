-- data/equip/rumors.lua
-- rumor definitions

local rumors = {

    {

        id = "MAM_8",
        name = "The Eight Songs",
        inv_size = {H = 2, W = 2},
        category = "rumor",
        mission = "map_002",

    },

    {

        id = "MAM_SENG",
        name = "Fuji Masakage's Diary",
        inv_size = {H = 2, W = 2},
        category = "rumor", 
        mission = "map_001",
        equip_A = "MAM_BRK",
        equip_B = "MAM_KOB",

    },


}

return rumors
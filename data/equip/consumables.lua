-- data/equip/consumables.lua
-- consumable equipment definitions

local consumables = {

    {

        id = "RSTIT",
        name = "Red Stitch",
        inv_size = {H = 1, W = 1},
        category = "consumable",
        effect = {

            hp_heal = 1,
            blk = 2,

        },
        previewtext = "Gain 2 block and heal 1 HP.",

    },

    {

        id = "BPUL",
        name = "Blue Pulse",
        inv_size = {H = 1, W = 1},
        category = "consumable",
        effect = {

            lp_heal = 3,

        },
        previewtext = "Restore 3 LP.",

    },


}

return consumables
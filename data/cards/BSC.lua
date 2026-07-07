-- data/cards/BSC.lua
-- Basic card definition

local basic_cards = {

    {
        id = "ATK",
        name = "Attack",
        cost = 1,
        rarity = "common",
        textbox = "Deal 3 damage to an enemy.\n\nRange 1.",
        play_func = {

            targ = "enemy",
            dmg = 3,
            rng = 1,

        },
    },

    {
        id = "DFN",
        name = "Defend",
        cost = 1,
        rarity = "common",
        textbox = "This Agent gains 3 block.",
        play_func = {

            targ = "self",
            blk = 3,

        },
    },

    {
        id = "BYP",
        name = "Bypass",
        cost = 0,
        rarity = "common",
        textbox = "Deal 3 Bypass damage to a door, hazard or terminal.",
        play_func = {

            targ = "door",
            bp = 3,
            rng = 1,

        },
    },

}

return basic_cards

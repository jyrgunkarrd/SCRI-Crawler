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
            dmg = "3",
            rng = "1",

        },
    },

}

return basic_cards

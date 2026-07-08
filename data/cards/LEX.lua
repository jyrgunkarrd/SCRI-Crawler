-- data/cards/LEX.lua
-- Lexurgy card definition

local lex_cards = {

    {
        id = "INCN",
        name = "Incinerate",
        cost = 1,
        rarity = "lex",
        textbox = "Deal 6 damage to an enemy.\n\nRange 4.",
        play_func = {

            targ = "enemy",
            dmg = 6,
            rng = 4,

        },
    },
}

return lex_cards
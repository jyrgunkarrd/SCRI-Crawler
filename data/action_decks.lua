-- data/action_decks.lua
-- action deck definitions

local action_deck_logic = require("src.sys.action_deck_logic")

local action_decks = {

    {

        id = "BSCDECK",
        slots = action_deck_logic.buildSplitSlots({ "ATK", "DFN" }),

    },

}

return action_decks

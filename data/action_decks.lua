-- data/action_decks.lua
-- action deck definitions

local action_deck_logic = require("src.sys.action_deck_logic")

local function buildCardList(counts)
    local cards = {}

    for _, entry in ipairs(counts) do
        for _ = 1, entry.count do
            cards[#cards + 1] = entry.card
        end
    end

    return cards
end

local action_decks = {

    {

        id = "BSCDECK",
        slots = action_deck_logic.buildSplitSlots({ "ATK", "DFN" }),

    },

    {

        id = "BSCSLYDECK",
        slots = action_deck_logic.buildSplitSlots(buildCardList({
            --Burn 1 Slots (18 Cards)
            { card = "BYP", count = 10 },
            { card = "ATK", count = 6 },
            { card = "DFN", count = 2 },

            --Burn 2 Slots (12 Cards)
            { card = "BYP", count = 6 },
            { card = "ATK", count = 4 },
            { card = "DFN", count = 2 },

            --Burn 3 Slots (12 Cards)
            { card = "BYP", count = 6 },
            { card = "ATK", count = 4 },
            { card = "DFN", count = 2 },

            --Burn 4 Slots (12 Cards)
            { card = "BYP", count = 4 },
            { card = "ATK", count = 6 },
            { card = "DFN", count = 2 },

            --Burn 5 Slots (6 Cards)
            { card = "ATK", count = 4 },
            { card = "DFN", count = 2 },
        })),

    },

}

return action_decks

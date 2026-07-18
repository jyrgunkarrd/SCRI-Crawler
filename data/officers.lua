-- data/officers.lua
-- officer definitions

local officers = {

    {

        id = "cap",
        name = "Cpt. Carol Layte",
        office = "The Helm",
        shout = "Engage",

    },

    {

        id = "tac",
        name = "Cdr. Julia West",
        office = "The Smoke Pit",
        shout = "Lock and load",

    },

    {

        id = "sher",
        name = "Detective Creeks",
        office = "The Fence",
        shout = "Trust nothing",

    },


    {

        id = "surg",
        name = "Dr. Park Ha-eun",
        office = "The Wet Block",
        shout = "Clean and prep.",

    },

    {

        id = "eng",
        name = "Dr. J. Martin",
        office = "The Plug",
        shout = "We're cooking.",

    },

    {

        id = "sci",
        name = "Dr. Aya al-Najjar",
        office = "The Blackboard",
        shout = "Project initiated.",
        orders = {

            "luggage",

        },

    },

}

return officers
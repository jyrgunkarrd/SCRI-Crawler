-- data/agents.lua
-- agent definitions

local agents = {

    {

        id = "MAM",
        name = "Mammoth",
        slots = {

            "Head",
            "Body",
            "Hand",
            "Hand",
            "Legs",
            "Jewelry",
            "Belt",
            "Lex",
            "Lex",
            "Lex",

        },
        stats = {
            {hp = 50},
            {ap = 5},
            {lp = 2},
            {strength = 2},
            {agility = 0},
            {lex = 1}, 
        },
        fate = "BSCSTACK",
        actions = {

            "BSCDECK",

        },
        actions_art = {
            
            { cardid = "ATK", art = "MAM_ATK" },
        
        },
        shout_select = "As a river bends.",

    },

    {

        id = "APEX",
        name = "Apex",
        slots = {

            "Head",
            "Body",
            "Hand",
            "Hand",
            "Legs",
            "Jewelry",
            "Jewelry",
            "Belt",
            "Belt",

        },
        stats = {
            {hp = 40},
            {ap = 5},
            {lp = 2},
            {strength = 1},
            {agility = 2},
            {lex = 1}, 
        },
        fate = "BSCSTACK",
        actions = {

            "BSCDECK",

        },
        shout_select = "I see them.",

    },

    {

        id = "SAW",
        name = "Snow & Miss White",
        slots = {

            "Head",
            "Body",
            "Hand",
            "Hand",
            "Legs",
            "Jewelry",
            "Belt",
            "Lex",
            "Ally",
            "Ally",

        },
        stats = {
            {hp = 30},
            {ap = 5},
            {lp = 2},
            {strength = 0},
            {agility = 4},
            {lex = 1}, 
        },
        fate = "BSCSTACK",
        actions = {

            "BSCDECK",

        },
        shout_select = "We're ready.",

    },

    {

        id = "WICK",
        name = "Wick",
        slots = {

            "Head",
            "Body",
            "Hand",
            "Hand",
            "Jewelry",
            "Machine",
            "Lex",
            "Lex",
            "Lex",
            "Ally",

        },
        stats = {
            {hp = 10},
            {ap = 5},
            {lp = 14},
            {strength = 0},
            {agility = 0},
            {lex = 7}, 
        },
        fate = "BSCSTACK",
        actions = {

            "BSCDECK",

        },
        shout_select = "Say the word.",

    },

    {

        id = "BMNCH",
        name = "Big Munch",
        slots = {

            "Head",
            "Body",
            "Body",
            "Hand",
            "Hand",
            "Legs",
            "Legs",
            "Jewelry",
            "Lex",
            "Lex",

        },
        stats = {
            {hp = 60},
            {ap = 5},
            {lp = 2},
            {strength = 1},
            {agility = 0},
            {lex = 1}, 
        },
        fate = "BSCSTACK",
        actions = {

            "BSCDECK",

        },
        shout_select = "MUNCH HUNGRY!",

    },

    {

        id = "B6",
        name = "Betty Six",
        slots = {

            "Head",
            "Body",
            "Hand",
            "Hand",
            "Legs",
            "Jewelry",
            "Belt",
            "Belt",
            "Machine",
            "Ally",

        },
        stats = {
            {hp = 30},
            {ap = 5},
            {lp = 0},
            {strength = 2},
            {agility = 3},
            {lex = 0}, 
        },
        fate = "BSCSTACK",
        actions = {

            "BSCDECK",

        },
        actions_art = {
            
            { cardid = "ATK", art = "B6_ATK" },
        
        },
        shout_select = "They're dead already.",

    },

    {

        id = "TMW",
        name = "Tomorrow",
        slots = {

            "Head",
            "Body",
            "Hand",
            "Hand",
            "Legs",
            "Jewelry",
            "Belt",
            "Machine",
            "Lex",
            "Lex",
        },
        stats = {
            {hp = 20},
            {ap = 5},
            {lp = 2},
            {strength = 1},
            {agility = 4},
            {lex = 1}, 
        },
        fate = "BSCSTACK",
        actions = {

            "BSCDECK",

        },
        actions_art = {
            
            { cardid = "ATK", art = "TMW_ATK" },
        
        },
        shout_select = "Good news?",

    },

}

return agents

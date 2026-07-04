-- data/agents.lua
-- agent definitions

local agents = {

    {

        id = "MAM",
        fullimg = "MAMfull",
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
            {strength = 2},
            {agility = 0},
            {lex = 1}, 
        },
        fate = "BSCSTACK",
        shout_select = "As a river bends.",

    },

    {

        id = "APEX",
        fullimg = "APEXfull",
        name = "Apex",
        method = "crusade", 
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
        nweap = "MMA",
        nprot = "FLESH",
        fate = "BSCSTACK",
        pulseshout = "I see them.",

    },

    {

        id = "SAW",
        fullimg = "SAWfull",
        name = "Snow & Miss White",
        method = "beast", 

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
        nweap = "FIST",
        nprot = "FLESH",
        fate = "BSCSTACK",
        pulseshout = "We're ready.",

    },

    {

        id = "WICK",
        fullimg = "WICKfull",
        name = "Wick",
        method = "inferno", 
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
        nweap = "FIST",
        nprot = "AUG",
        fate = "BSCSTACK",
        pulseshout = "Say the word.",

    },

    {

        id = "BMNCH",
        fullimg = "BMNCHfull",
        name = "Big Munch",
        method = "rampage", 
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
        nweap = "SPRNAT",
        nprot = "SHELL",
        fate = "BSCSTACK",
        pulseshout = "MUNCH HUNGRY!",

    },

    {

        id = "B6",
        fullimg = "B6full",
        name = "Betty Six",
        method = "trigger", 
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
        nweap = "FIST",
        nprot = "AUG",
        fate = "BSCSTACK",
        pulseshout = "They're dead already.",

    },

    {

        id = "TMW",
        fullimg = "TMWfull",
        name = "Tomorrow",
        method = "gate", 
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
        nweap = "FIST",
        nprot = "AUG",
        fate = "BSCSTACK",
        pulseshout = "Good news?",

    },

}

return agents
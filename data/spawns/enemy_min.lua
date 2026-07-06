-- data/spawns/enemy_min.lua
-- minor enemy definitions

local enemy_min = {

    {

        id = "FORG",
        name = "Forgiven",
        stats = {
            {hp = 2},
            {atk = 1},
            {spd = 2},
            {rng = 1},
        },
        en_act = {

            { act1 = "FORGatk", weight = 1, dmg = 0 }

        },
        fate = "BSCSTACK",
        enemy = true,

    },

}

return enemy_min
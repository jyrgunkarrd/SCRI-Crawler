-- data/spawns/hazards.lua
-- hazard definitions

local hazards = {

    {

        id = "SENTRY",
        name = "Sentry Turret",
        stats = {
            {hp = 8},
            {atk = 3},
            {bp = 2},
        },
        en_act = {

            { act1 = "SENTRYatk", weight = 1, dmg = 0 }

        },
        level_scale = {
            stats = {
                atk = true,
            },
        },
        fate = "BSCSTACK",
        lv = 0,
        hpgrowth = 2,
        bpgrowth = 1,
        hazard = true,
        xpreward = 1,

    },

}

return hazards

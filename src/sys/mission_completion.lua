local mission_completion = {}

local function isDefeated(enemy)
    local hp = enemy and enemy.runtime_stats and enemy.runtime_stats.hp

    return hp and hp.current <= 0 or false
end

function mission_completion.initialize(room)
    local tracker = {
        required_bosses = 0,
        bosses = {},
    }

    for _, tile in ipairs(room and room.tiles or {}) do
        if tile.spawn_event and tile.boss_spawner then
            tracker.required_bosses = tracker.required_bosses + 1
        end
    end

    return tracker
end

function mission_completion.update(tracker, room)
    if not tracker then
        return false
    end

    for _, tile in ipairs(room and room.tiles or {}) do
        if tile.enemy and tile.enemy.boss then
            tracker.bosses[tile.enemy] = true
        end
    end

    if tracker.required_bosses <= 0 then
        return false
    end

    local defeated_bosses = 0

    for boss in pairs(tracker.bosses) do
        if isDefeated(boss) then
            defeated_bosses = defeated_bosses + 1
        end
    end

    return defeated_bosses >= tracker.required_bosses
end

return mission_completion

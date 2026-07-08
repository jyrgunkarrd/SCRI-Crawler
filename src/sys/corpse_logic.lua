local corpse_logic = {}

function corpse_logic.create(enemy)
    return {
        id = enemy and enemy.id or nil,
        corpse_marker = true,
        source_enemy_id = enemy and enemy.id or nil,
        source_enemy_name = enemy and enemy.name or nil,
    }
end

function corpse_logic.replaceEnemy(tile, enemy)
    if not tile or tile.enemy ~= enemy then
        return false
    end

    tile.enemy = nil
    tile.corpse = corpse_logic.create(enemy)

    return true
end

return corpse_logic

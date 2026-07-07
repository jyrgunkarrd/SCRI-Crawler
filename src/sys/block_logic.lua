local block_logic = {}
local sfx_logic = require("src.sys.sfx_logic")

function block_logic.getBlock(unit)
    return math.max(0, math.floor(tonumber(unit and unit.block) or 0))
end

function block_logic.addBlock(unit, amount)
    if not unit then
        return 0
    end

    local value = math.max(0, math.floor(tonumber(amount) or 0))

    if value <= 0 then
        return block_logic.getBlock(unit)
    end

    unit.block = block_logic.getBlock(unit) + value
    unit.block_pulse_id = (unit.block_pulse_id or 0) + 1
    sfx_logic.playNamed("defend")

    return unit.block
end

function block_logic.clearBlock(unit)
    if unit then
        unit.block = 0
        unit.block_pulse_id = 0
    end
end

function block_logic.absorbDamage(unit, damage)
    local incoming = math.max(0, math.floor(tonumber(damage) or 0))
    local block = block_logic.getBlock(unit)

    if incoming <= 0 or block <= 0 then
        return incoming, 0
    end

    local absorbed = math.min(block, incoming)

    unit.block = block - absorbed

    return incoming - absorbed, absorbed
end

return block_logic

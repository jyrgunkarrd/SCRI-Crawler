local phase_rules = {}

local AUTO_PHASE_DELAY = 0.35
local ROUND_FLASH_SECONDS = 0.35

phase_rules.PHASE_START = "START"
phase_rules.PHASE_MISSION = "MISSION"
phase_rules.PHASE_SERMON = "SERMON"
phase_rules.PHASE_END = "END"

local current_phase = phase_rules.PHASE_START
local elapsed = 0
local round = 0
local round_flash_elapsed = 0

local function setPhase(phase)
    current_phase = phase
    elapsed = 0
end

function phase_rules.load()
    setPhase(phase_rules.PHASE_START)
    round = 0
    round_flash_elapsed = 0
end

function phase_rules.update(dt)
    local previous_phase = current_phase

    if round_flash_elapsed > 0 then
        round_flash_elapsed = math.max(0, round_flash_elapsed - dt)
    end

    if current_phase == phase_rules.PHASE_START or current_phase == phase_rules.PHASE_SERMON then
        elapsed = elapsed + dt

        if elapsed >= AUTO_PHASE_DELAY then
            setPhase(current_phase == phase_rules.PHASE_START and phase_rules.PHASE_MISSION or phase_rules.PHASE_END)
        end
    elseif current_phase == phase_rules.PHASE_END then
        elapsed = elapsed + dt

        if elapsed >= AUTO_PHASE_DELAY then
            round = round + 1
            round_flash_elapsed = ROUND_FLASH_SECONDS
            setPhase(phase_rules.PHASE_START)
        end
    end

    return current_phase ~= previous_phase
end

function phase_rules.advanceMission()
    if current_phase ~= phase_rules.PHASE_MISSION then
        return false
    end

    setPhase(phase_rules.PHASE_SERMON)
    return true
end

function phase_rules.isMissionPhase()
    return current_phase == phase_rules.PHASE_MISSION
end

function phase_rules.isStartPhase()
    return current_phase == phase_rules.PHASE_START
end

function phase_rules.isRoundFlashActive()
    return round_flash_elapsed > 0
end

function phase_rules.getCurrentPhase()
    return current_phase
end

function phase_rules.getRound()
    return round
end

return phase_rules

local sfx_logic = {}

local SFX_DIR = "assets/audio/sfx"
local VOICE_DIR = "assets/audio/sfx/voices"
local OFFICER_VOICE_DIR = "assets/audio/sfx/voices/officers"
local sources = {}
local missing = {}

local function getSource(path)
    if sources[path] then
        return sources[path]
    end

    if missing[path] then
        return nil
    end

    if not love.filesystem.getInfo(path, "file") then
        missing[path] = true
        return nil
    end

    local ok, source = pcall(love.audio.newSource, path, "static")

    if not ok then
        print("Unable to load sfx '" .. path .. "': " .. tostring(source))
        missing[path] = true
        return nil
    end

    sources[path] = source

    return source
end

function sfx_logic.play(path)
    local source = getSource(path)

    if not source then
        return false
    end

    local instance = source:clone()
    instance:play()

    return true
end

function sfx_logic.playNamed(name)
    return sfx_logic.play(("%s/%s.wav"):format(SFX_DIR, name))
end

function sfx_logic.playAgentVoice(agent)
    if not agent or not agent.id then
        return false
    end

    return sfx_logic.play(("%s/%s.wav"):format(VOICE_DIR, agent.id))
end

function sfx_logic.playOfficerVoice(officer)
    if not officer or not officer.id then
        return false
    end

    return sfx_logic.play(("%s/%s.wav"):format(OFFICER_VOICE_DIR, officer.id))
end

function sfx_logic.playAgentSelect(agent)
    sfx_logic.playNamed("token_select")
    sfx_logic.playAgentVoice(agent)
end

function sfx_logic.playMove()
    if not sfx_logic.playNamed("move") then
        sfx_logic.playNamed("movement")
    end
end

return sfx_logic

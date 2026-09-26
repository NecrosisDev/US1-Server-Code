local base = "zc_hmcd_mutators/"
local shared = {base .. "sh_config.lua", base .. "cl_state.lua", base .. "cl_sighting.lua", base .. "cl_equal_opportunities.lua", base .. "cl_postmortem.lua", base .. "cl_gang_mentality.lua"}
if SERVER then
    for _, path in ipairs(shared) do AddCSLuaFile(path) end
    include(base .. "sv_core.lua")
    include(base .. "sh_config.lua")
    include(base .. "sv_points.lua")
    include(base .. "sv_roles.lua")
    include(base .. "sv_postmortem_karma.lua")
    local modules = file.Find(base .. "mutators/sv_*.lua", "LUA")
    table.sort(modules)
    for _, name in ipairs(modules) do include(base .. "mutators/" .. name) end
    include(base .. "sv_admin.lua")
    ZC_HMCD_MUTATORS:Start()
else
    include(base .. "sh_config.lua")
    include(base .. "cl_state.lua")
    include(base .. "cl_sighting.lua")
    include(base .. "cl_equal_opportunities.lua")
    include(base .. "cl_postmortem.lua")
    include(base .. "cl_gang_mentality.lua")
end


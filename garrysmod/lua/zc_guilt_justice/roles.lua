-- Remove reputation-weighted secret-role selection without rerolling current players.
local M=assert(ZCityMetaSafety)
M.roleFunctions=M.roleFunctions or setmetatable({},{__mode="k"})
local sources={
    ["addons/zcity/gamemodes/zcity/gamemode/modes/homicide/sv_homicide.lua"]=true,
    ["addons/zcity/gamemodes/zcity/gamemode/modes/homicide_fear/core/sv_fear.lua"]=true
}
function M.RoleFunction(original)
    if not isfunction(original) or M.roleFunctions[original] then return M.roleFunctions[original] or original end
    local info=debug.getinfo(original,"S")
    if info and info.short_src=="addons/zc_traitor_population/lua/autorun/server/sv_zc_traitor_population.lua" then
        local base,dispatch
        for i=1,10 do
            local name,value=debug.getupvalue(original,i)
            if name=="original" then base=value elseif name=="dispatch" then dispatch=value end
        end
        if isfunction(base) and isfunction(dispatch) then
            local safe=M.RoleFunction(base)
            if safe~=base then
                local wrapped=function(self,...)return dispatch(safe,self,...)end
                M.roleFunctions[original]=wrapped;M.roleFunctions[wrapped]=wrapped
                M.roleAudit=M.roleAudit or {};M.roleAudit[wrapped]=M.roleAudit[safe]
                return wrapped
            end
        end
        return original
    end
    if not info or not sources[info.short_src] then return original end
    local text=file.Read(info.short_src,"GAME");if not text then return original end
    local lines=string.Explode("\n",text)
    local block=table.concat(lines,"\n",info.linedefined,info.lastlinedefined)
    local colon=block:match("^function MODE:Intermission%(%s*%)")
    local dot=block:match("^function MODE%.SpawnPlayers%([^\n]*%)")
    if not colon and not dot then return original end
    local gates
    block,gates=block:gsub("%(ply%.Karma or 100%)","100")
    if colon then block=block:gsub("^function MODE:Intermission%(%s*%)","return function(self)",1)
    else block=block:gsub("^function MODE%.SpawnPlayers%(","return function(",1) end
    local names,values={},{}
    for i=1,30 do
        local name,value=debug.getupvalue(original,i);if not name then break end
        assert(name=="MODE" or name=="gaymaps" or name=="homicide_traitoramount","Unexpected role-selector capture")
        names[#names+1]=name;values[#values+1]=value
    end
    local compiled=CompileString("return function("..table.concat(names,",")..")\n"..block.."\nend","zc_role_privacy",false)
    assert(isfunction(compiled),tostring(compiled));setfenv(compiled,getfenv(original))
    local replacement=compiled()(unpack(values))
    assert(isfunction(replacement));M.roleFunctions[original]=replacement;M.roleFunctions[replacement]=replacement
    M.roleAudit=M.roleAudit or {}
    M.roleAudit[replacement]={source=info.short_src,gates=gates}
    return replacement
end
function M.InstallRoles()
    if not zb or not zb.modes then return end
    for _,mode in pairs(zb.modes) do
        for _,key in ipairs({"Intermission","SpawnPlayers"}) do
            local fn=mode[key]
            local pop=ZC_TRAITOR_POPULATION
            local owned=pop and pop.mode==mode and pop.wrapper==fn
            if isfunction(fn) and not owned then mode[key]=M.RoleFunction(fn) end
        end
    end
end
hook.Add("InitPostEntity","ZCityMetaSafety_Roles",function()M.InstallRoles()end)
hook.Add("ZB_PreRoundStart","ZCityMetaSafety_Roles",function()M.InstallRoles()end,-2)
timer.Create("ZCityMetaSafety_Roles",1,0,function()M.InstallRoles()end)
M.InstallRoles()

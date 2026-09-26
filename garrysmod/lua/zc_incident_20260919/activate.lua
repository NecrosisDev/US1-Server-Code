assert(SERVER)
local path="homigrad/libraries/core/sh_networking.lua"
local source=assert(file.Read(path,"LUA"))
assert(util.SHA256(source)=="89c049bb20c6da8b23cc13687a038681cfafe752fec6ac92ef49186714c6c75d","installed source hash mismatch")
local em,pm=FindMetaTable("Entity"),FindMetaTable("Player")
local methods={send=em.SendNetVar,sync=pm.SyncVars,clear=em.ClearNetVars}
for name,fn in pairs(methods)do
    local info=debug.getinfo(fn,"S")
    assert(info and info.source:find("homigrad/libraries/core/sh_networking.lua",1,true),"unexpected current owner: "..name)
end
local autoActivated=ZCWoundQueue~=nil
assert(not ZCWoundQueue or ZCWoundQueue.Version=="20260919.1","another queue version is active")
local function slice(first,last,textSource)
    textSource=textSource or source
    local a=assert(textSource:find(first,1,true))
    local b=assert(textSource:find(last,a+1,true))
    return textSource:sub(a,b-1)
end
local text="local entityMeta=FindMetaTable('Entity') local playerMeta=FindMetaTable('Player')\n"
text=text..slice("    -- ZC_WOUND_QUEUE_BEGIN","    -- ZC_WOUND_QUEUE_END")
text=text..slice("    function playerMeta:SyncVars()","    function playerMeta:GetLocalVar")
text=text..slice("    function entityMeta:ClearNetVars(receiver)","\thook.Add(\"EntityRemoved\"")
local install=CompileString(text,"zc_wound_queue_activation_20260919",false)
assert(isfunction(install),tostring(install))
local setter=em.SetNetVar
if not autoActivated then install() end
-- Source auto-refresh can reload the library before this activation script.
-- Restore the existing addon through its own idempotent loader in that case.
if not debug.getinfo(em.SetNetVar,"S").source:find("sv_zc_netopt.lua",1,true) then
    include("autorun/server/sv_zc_netopt.lua")
end
assert(debug.getinfo(em.SetNetVar,"S").source:find("sv_zc_netopt.lua",1,true),"scalar optimizer missing")
local original=assert(file.Read("zc_incident_20260919/networking_original.lua","LUA"))
assert(util.SHA256(original)=="76aaa93a673e6e5ad437e28e9e9f616def54195172049613c344de67905524be","rollback hash mismatch")
local rollbackText="local entityMeta=FindMetaTable('Entity') local playerMeta=FindMetaTable('Player')\n"
rollbackText=rollbackText..slice("    function entityMeta:SendNetVar(key, receiver)","\thook.Add(\"EntityRemoved\"",original)
rollbackText=rollbackText..slice("    function playerMeta:SyncVars()","    function playerMeta:GetLocalVar",original)
local restore=CompileString(rollbackText,"zc_wound_queue_rollback_20260919",false)
assert(isfunction(restore),tostring(restore))
local active={send=em.SendNetVar,sync=pm.SyncVars,clear=em.ClearNetVars}
ZCWoundQueue.Rollback=function()
    assert(em.SendNetVar==active.send and pm.SyncVars==active.sync and em.ClearNetVars==active.clear,"concurrent changes: refusing rollback")
    ZCWoundQueue.Flush()
    hook.Remove("Tick","ZC_WoundNetFlush")
    restore()
    ZCWoundQueue=nil
end
file.CreateDir("zc_incident_20260919")
file.Write("zc_incident_20260919/activation.json",util.TableToJSON({time=os.time(),version=ZCWoundQueue.Version,sha256=util.SHA256(source),map=game.GetMap(),players=#player.GetHumans(),scalarOptimizerPreserved=true,autoActivated=autoActivated},true))
print("ZC_INCIDENT_ACTIVATED",ZCWoundQueue.Version,game.GetMap())


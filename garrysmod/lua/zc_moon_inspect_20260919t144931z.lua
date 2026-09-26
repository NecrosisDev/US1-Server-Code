-- Read-only snapshot; no player actions or gravity writes.
local cv=GetConVar('sv_gravity')
local s=ZC_HMCD_MOON_GRAVITY_STATE
local m=ZC_HMCD_MUTATORS
local r={time=os.time(),map=game.GetMap(),gravity=cv and cv:GetFloat(),default=cv and cv:GetDefault(),physics=physenv.GetGravity(),players=#player.GetHumans(),current=m and m.current and m.current.definition.ID or false,lease={}}
if s and s.lease then
 for _,k in ipairs({'token','phase','owns','cancelled','beforeRestore','restorePhysics'}) do r.lease[k]=s.lease[k] end
 for i=1,64 do
  local name,v=debug.getupvalue(s.lease.dispatch,i)
  if not name then break end
  if name=='previous' or name=='previousPhysics' then r.lease[name]=v end
 end
end
r.shutdownHook=(hook.GetTable().ShutDown or {}).zc_hmcd_mutators~=nil
r.physicsHook=type((hook.GetTable().ShutDown or {}).ZCMoonGravity_ShutDown)
r.journalExists=file.Exists('zc_hmcd_mutators/moon_gravity_lease.json','DATA')
file.CreateDir('zc_moon_repair')
file.Write('zc_moon_repair/inspect_20260919t144931z.json',util.TableToJSON(r,true))
print('ZC_MOON_INSPECT',r.gravity,r.current)

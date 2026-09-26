-- Manual, single-callback incident repair. Not an autorun file.
assert(SERVER and engine.ActiveGamemode()=="zcity", "Wrong server")
assert(not ZCAmmoDeltaRepair, "Existing transaction requires reconciliation")
local path="homigrad/sv_inventory.lua"
local hashes={before="4ca0291b63156c12c8637aba4b27a20931014699d71b160bbbc1f8ec327ea34d",after="f093d904cc82e63174bceb15fd99d0033e4e40cd9b7411cb57e190adb9169c70"}
local function callback(which)
 local s=assert(file.Read("zc_ammo_delta_stage/"..which..".txt","DATA"))
 assert(util.SHA256(s)==hashes[which], "Staged source drift")
 local a=assert(s:find('hook.Add("PlayerAmmoChanged"',1,true))
 local b=assert(s:find('local vecZero',a,true));local captured
 local env=setmetatable({hook={Add=function(e,n,f)
  assert(e=="PlayerAmmoChanged" and n=="homigrad-inventory" and not captured);captured=f
 end}},{__index=_G})
 local chunk=CompileString(s:sub(a,b-1),"@zc_ammo_delta/"..which..".lua",false)
 assert(isfunction(chunk),tostring(chunk));setfenv(chunk,env);chunk()
 assert(isfunction(captured) and debug.getupvalue(captured,1)==nil)
 setfenv(captured,_G);return captured
end
local old=assert((hook.GetTable().PlayerAmmoChanged or {})["homigrad-inventory"])
local baseline,replacement=callback("before"),callback("after")
assert(debug.getinfo(old,"S").short_src:find("sv_inventory.lua",1,true),"Unexpected callback source")
assert(string.dump(old,true)==string.dump(baseline,true),"Running callback differs from baseline")
local R={old=old,replacement=replacement,version="ammo-positive-delta-1"}
local dispatch={hook.Call,hook.Add,include,net.Start,FindMetaTable("Entity").SetNetVar}
local function sameDispatch()
 return hook.Call==dispatch[1] and hook.Add==dispatch[2] and include==dispatch[3] and net.Start==dispatch[4] and FindMetaTable("Entity").SetNetVar==dispatch[5]
end
local startup={}
for _,e in ipairs({"Initialize","PostGamemodeLoaded","InitPostEntity"})do
 startup[e]={};for n,f in pairs(hook.GetTable()[e] or {})do startup[e][n]=f end
end
local function sameStartup()
 for e,t in pairs(startup)do
  local now=hook.GetTable()[e] or {}
  for n,f in pairs(t)do if now[n]~=f then return false end end
  for n,f in pairs(now)do if t[n]~=f then return false end end
 end
 return true
end
function R.Verify()
 local f=(hook.GetTable().PlayerAmmoChanged or {})["homigrad-inventory"]
 local r={version=R.version,at=os.time(),map=game.GetMap(),installedHash=util.SHA256(file.Read(path,"LUA") or ""),
  callbackMatches=isfunction(f) and string.dump(f,true)==string.dump(replacement,true),
  startupUnchanged=sameStartup(),dispatchUnchanged=sameDispatch(),activation=R.activation or "prepared"}
 file.CreateDir("zc_ammo_delta");file.Write("zc_ammo_delta/verification.json",util.TableToJSON(r,true))
 print("AMMO_DELTA_VERIFY",r.callbackMatches,r.startupUnchanged,r.dispatchUnchanged)
 return r
end
function R.Apply()
 assert(not R.live,"Already adopted; verify instead")
 assert(util.SHA256(assert(file.Read(path,"LUA")))==hashes.after,"Installed file mismatch")
 assert(sameStartup() and sameDispatch(),"Startup or dispatcher changed; reconcile")
 local f=assert(hook.GetTable().PlayerAmmoChanged["homigrad-inventory"])
 if f==old then
  hook.Add("PlayerAmmoChanged","homigrad-inventory",replacement);R.live=replacement;R.activation="single callback replaced"
 elseif getfenv(f)==_G and string.dump(f,true)==string.dump(replacement,true) then
  R.live=f;R.activation="existing matching auto-refresh adopted"
 else error("Concurrent callback override; no replacement") end
 local r=R.Verify();assert(r.callbackMatches and r.startupUnchanged and r.dispatchUnchanged)
end
function R.Rollback()
 assert(R.live and hook.GetTable().PlayerAmmoChanged["homigrad-inventory"]==R.live,"Concurrent override; no rollback")
 hook.Add("PlayerAmmoChanged","homigrad-inventory",old)
 R.live=nil;R.activation="rolled back";R.Verify()
end
ZCAmmoDeltaRepair=R
print("AMMO_DELTA_PREPARED",R.version)

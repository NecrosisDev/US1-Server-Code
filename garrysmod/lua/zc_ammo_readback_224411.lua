-- Readback only, works after a normal map change without old transaction globals.
assert(SERVER and engine.ActiveGamemode()=="zcity")
local source=assert(file.Read("zc_ammo_delta_stage/after.txt","DATA"))
local hash="f093d904cc82e63174bceb15fd99d0033e4e40cd9b7411cb57e190adb9169c70"
assert(util.SHA256(source)==hash)
local a=assert(source:find('hook.Add("PlayerAmmoChanged"',1,true))
local b=assert(source:find('local vecZero',a,true));local expected
local env=setmetatable({hook={Add=function(e,n,f)
 assert(e=="PlayerAmmoChanged" and n=="homigrad-inventory");expected=f
end}},{__index=_G})
local compile=CompileString(source:sub(a,b-1),"@ammo_verify_only",false)
assert(isfunction(compile));setfenv(compile,env);compile()
local actual=assert((hook.GetTable().PlayerAmmoChanged or {})["homigrad-inventory"])
local report={at=os.time(),map=game.GetMap(),players=#player.GetHumans(),
 sourceMatches=util.SHA256(file.Read("homigrad/sv_inventory.lua","LUA") or "")==hash,
 callbackMatches=string.dump(actual,true)==string.dump(expected,true),
 source=debug.getinfo(actual,"S").short_src,noActivationPerformed=true}
file.CreateDir("zc_ammo_delta");file.Write("zc_ammo_delta/postmap_verification.json",util.TableToJSON(report,true))
print("AMMO_LOADED_READBACK",report.sourceMatches,report.callbackMatches,report.map,report.players)

-- One-time deployment verification; never changes player health or roles.
local F=assert(ZCityFFBrain)
F.InstallPillBridge(); F.InstallDamagePriority()
assert(F.Version=="20260915.2" and F.Settings.victimScale==0.5)
assert(math.abs(F.KarmaRate(25)-0.004)<0.000001)
assert(math.abs(F.KarmaRate(40)-0.0011)<0.000001)
assert(timer.Exists("ZCityFFBrain_Karma"))
local hooks=hook.GetTable().EntityTakeDamage
assert(hook.GetULibTable().EntityTakeDamage[-1].ZCityFFBrain_Capture.fn==hooks.ZCityFFBrain_Capture)
assert(F.pillBridge.wrapper==ZCityPillCompat.Damage)
local native=hooks["homigrad-damage"]
local outer=ZCityPillCompat.wraps[hooks] and ZCityPillCompat.wraps[hooks]["homigrad-damage"]
assert(native==F.nativeBridge.wrapper or (outer and native==outer.wrapper and outer.original==F.nativeBridge.wrapper))
local function upvalue(fn,wanted)
    if not isfunction(fn) then return end
    for i=1,40 do
        local name,value=debug.getupvalue(fn,i)
        if not name then return end
        if name==wanted then return value end
    end
end
local request=assert(net.Receivers["zc_welcome_request_v2"])
local state=assert(upvalue(upvalue(request,"SyncTo"),"state"),"Guide memory state unavailable")
assert(state.version==2 and state.revision==17 and #state.pages==7)
local page
for _,p in ipairs(state.pages) do if p.id==7 then page=p end end
assert(page and page.title=="FRIENDLY FIRE & KARMA" and string.find(page.body,"DOUBLES",1,true))
local clients=0
for _,p in ipairs(player.GetHumans()) do request(0,p); clients=clients+1 end
local result={version=F.Version,guideRevision=state.revision,guidePages=#state.pages,
    guideSyncedTo=clients,victimScale=F.Settings.victimScale,
    karmaAt40=F.KarmaRate(40),karmaAt25=F.KarmaRate(25),
    captureHighPriority=true,nativeBridge=true,pillBridge=true,
    droneVersion=ZCityDronesCompat.Version,pillVersion=ZCityPillCompat.Version,
    ffEnabled=GetConVar("zc_ff_brain_enabled"):GetBool(),
    ffScale=GetConVar("zc_ff_brain_scale"):GetFloat(),
    ffGrace=GetConVar("zc_ff_brain_grace"):GetFloat(),
    karmaEnabled=GetConVar("zc_karma_brain_enabled"):GetBool(),
    karmaScale=GetConVar("zc_karma_brain_scale"):GetFloat()}
file.Write("zc_ff_karma_deployment.json",util.TableToJSON(result,true))
print("ZCF_KARMA_VERIFIED",util.TableToJSON(result))

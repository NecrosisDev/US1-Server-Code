-- Upgrade only the scanner response. Do not spawn test NPCs into the live round.
assert(SERVER and engine.ActiveGamemode()=="zcity")
local functions={}
for _,s in ipairs({{name="escalation",path="zc_scanner_response/escalation.lua",hash="1a13e5dfb2842712e1b1940de7dd79d0f6889c65793c0bbd0136d1f71bbdf610"},{name="response",path="autorun/server/zc_scanner_response.lua",hash="88b8f2d03a616b4f5f791b1f31ba0e0a3a587125092238b014c144bbb21383ff"}})do
    local text=assert(file.Read(s.path,"LUA"));assert(util.SHA256(text)==s.hash,s.path)
    local fn=CompileString(text,s.path,false);assert(isfunction(fn),tostring(fn));functions[s.name]=fn
end
local previous=assert(ZCityScannerResponse)
local jobs,responders=previous.pending,previous.responders
local form=assert(pk_pills.getPillTable("cityscanner"))
local photo=form.attack2 and form.attack2.func
functions.response()
local S=assert(ZCityScannerResponse)
assert(S.Version=="20260915.2" and S.pending==jobs and S.responders==responders)
assert(#S.Rosters[1]==2 and #S.Rosters[2]==3)
assert(S.Rosters[2][1].weapon=="weapon_ar2" and S.Rosters[2][2].weapon=="weapon_smg1" and S.Rosters[2][3].weapon=="weapon_shotgun")
assert(S.InstallPill() and (form.attack2 and form.attack2.func)==photo)
assert(S.wrapped[form] and form.die==S.wrapped[form].wrapper)
assert(hook.GetTable().OnNPCKilled.ZCityScannerResponse_Death==S.OnKilled)
assert(isfunction(hook.GetTable().EntityRemoved.ZCityScannerResponse_PatrolRemoved))
assert(timer.Exists("ZCityScannerResponse_Service"))
local graph=S.Graph();local groups=0
for _ in pairs(S.patrols)do groups=groups+1 end
local result={time=os.time(),version=S.Version,map=game.GetMap(),
    nodes=graph and graph.count or 0,walkableNodes=graph and #graph.ground or 0,
    graphReason=S.graphReason or "ready",enabled=GetConVar("zc_scanner_response"):GetBool(),
    pending=#S.pending,active=S.Count(),trackedPatrols=groups,adopted=S.legacyAdopted,
    players=#player.GetHumans(),ff=ZCityFFBrain.Version,combat=ZCityGuiltJustice.PolicyVersion,
    bounty=ZCityKarmaBounties.Version,pill=ZCityPillCompat.Version,drone=ZCityDronesCompat.Version,
    npcDeathHook=true,pillDeathHook=true,removalGuard=true,photoUnchanged=true}
file.Write("zc_scanner_escalation_deployed.json",util.TableToJSON(result,true))
print("ZCITY_SCANNER_ESCALATION_ACTIVATED",S.Version,result.map,result.nodes)

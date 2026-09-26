-- Verify and activate only the new scanner-response addon. No live test NPCs spawned.
assert(SERVER and engine.ActiveGamemode()=="zcity")
local sources={{name="graph",path="zc_scanner_response/graph.lua",hash="c870348c70b9d9ef5d307d0d95cd862d52e9e37c15bbf2a7fa34792013190005"},{name="response",path="autorun/server/zc_scanner_response.lua",hash="c2fedd99ba40293c81892f2bca2542793ba2d2cfcb0d77ffb4a636b6f0bfb538"}}
local functions={}
for _,s in ipairs(sources)do
    local text=assert(file.Read(s.path,"LUA"));assert(util.SHA256(text)==s.hash,s.path)
    local fn=CompileString(text,s.path,false);assert(isfunction(fn),tostring(fn));functions[s.name]=fn
end
local form=assert(pk_pills.getPillTable("cityscanner"))
local photo=form.attack2 and form.attack2.func
functions.response()
local S=assert(ZCityScannerResponse);assert(S.Version=="20260915.1" and S.InstallPill())
assert((form.attack2 and form.attack2.func)==photo,"Photo callback changed")
assert(S.wrapped[form] and form.die==S.wrapped[form].wrapper)
assert(hook.GetTable().OnNPCKilled.ZCityScannerResponse_Death==S.OnKilled)
assert(timer.Exists("ZCityScannerResponse_Service"))
local graph=S.Graph()
local result={time=os.time(),version=S.Version,map=game.GetMap(),
    nodes=graph and graph.count or 0,walkableNodes=graph and #graph.ground or 0,
    graphReason=S.graphReason or "ready",enabled=GetConVar("zc_scanner_response"):GetBool(),
    pillDeathHook=true,npcDeathHook=true,photoUnchanged=true,pending=#S.pending,active=S.Count(),
    players=#player.GetHumans(),ff=ZCityFFBrain.Version,combat=ZCityGuiltJustice.PolicyVersion,
    bounty=ZCityKarmaBounties.Version,pill=ZCityPillCompat.Version,drone=ZCityDronesCompat.Version}
file.Write("zc_scanner_response_deployed.json",util.TableToJSON(result,true))
print("ZCITY_SCANNER_RESPONSE_ACTIVATED",S.Version,result.map,result.nodes)

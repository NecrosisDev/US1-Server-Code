if not SERVER then return end
local payload=assert(util.JSONToTable(file.Read("zci_panel_stage/restraints.txt","DATA")))
local results={time=os.time(),files={},sessions=0,humans=#player.GetHumans()}
for _,r in ipairs(payload) do
 local fn=CompileString(r.source,"RestraintPreflight/"..r.path,false)
 results.files[#results.files+1]={path=r.path,hash=r.hash,ok=isfunction(fn) and util.SHA256(r.source)==r.hash,error=isstring(fn) and fn or nil}
end
for _,s in pairs(ZCityHostage.Gameplay.Sessions) do if not s.done then results.sessions=results.sessions+1 end end
file.Write("zci_panel_stage/restraints-preflight.json",util.TableToJSON(results))

local E=assert(scripted_ents.GetStored('ent_hg_grenade')).t
ZCPerf2Install={oldExplode=E.Explode,poop=ZCityPoopThrow,urine=ZCityUrine,
 oldPoopStats=table.Copy(ZCityPoopThrow.stats),oldUrineStats=table.Copy(ZCityUrine.stats),time=os.time()}
local s=ZCPerf2Install;s.oldPoopFunctions={};s.oldUrineFunctions={}
for k,v in pairs(s.poop)do if type(v)=='function'then s.oldPoopFunctions[k]=v end end
for k,v in pairs(s.urine)do if type(v)=='function'then s.oldUrineFunctions[k]=v end end
local r={time=s.time,map=game.GetMap(),players=#player.GetHumans(),tick=engine.TickInterval(),classes={},oldJobs=0}
for c in pairs(scripted_ents.GetList())do
 local t=scripted_ents.GetStored(c).t
 if t.Explode==s.oldExplode then r.classes[#r.classes+1]=c end
end
for _,e in ipairs(ents.GetAll())do
 if IsValid(e) and e.Explode==s.oldExplode and timer.Exists('GrenadeCheck_'..e:EntIndex()..'_'..e:GetCreationID()) then r.oldJobs=r.oldJobs+1 end
end
file.CreateDir('zc_perf_batch2')
file.Write('zc_perf_batch2/capture_20260919t122952z.json',util.TableToJSON(r,true))
print('ZC_PERF2_CAPTURE',#r.classes,r.players)

-- Read-only deployment and networking inspection; no gameplay actions.
local r={time=os.time(),map=game.GetMap(),players=#player.GetHumans(),tick=engine.TickInterval(),batch2={},network={}}
local function src(f)if type(f)~='function' then return false end;local d=debug.getinfo(f,'S');return {path=d.source,first=d.linedefined,last=d.lastlinedefined}end
local E=scripted_ents.GetStored('ent_hg_grenade');E=E and E.t
local old=ZCPerf2Install
r.batch2.grenadeVersion=E and E.ZCFragmentBudgetVersion
r.batch2.grenadeFunction=E and src(E.Explode)
r.batch2.changedSinceInstall=old and E and E.Explode~=old.oldExplode
r.batch2.poopVersion=ZCityPoopThrow and ZCityPoopThrow.Version
r.batch2.urineVersion=ZCityUrine and ZCityUrine.Version
r.batch2.poopTimer=timer.Exists('ZCityPoopThrow_Tick');r.batch2.urineTimer=timer.Exists('ZCityUrine_Tick')
r.batch2.classes={};r.batch2.staleClasses={};r.batch2.staleEntities=0;r.batch2.activeFragmentJobs=0
for c in pairs(scripted_ents.GetList()) do local t=scripted_ents.GetStored(c).t
 if E and t.Explode==E.Explode then r.batch2.classes[#r.batch2.classes+1]=c end
 if old and t.Explode==old.oldExplode then r.batch2.staleClasses[#r.batch2.staleClasses+1]=c end
end
for _,e in ipairs(ents.GetAll()) do if IsValid(e) then
 if old and e.Explode==old.oldExplode then r.batch2.staleEntities=r.batch2.staleEntities+1 end
 if timer.Exists('GrenadeCheck_'..e:EntIndex()..'_'..e:GetCreationID()) then r.batch2.activeFragmentJobs=r.batch2.activeFragmentJobs+1 end
end end
local EM,PM=FindMetaTable('Entity'),FindMetaTable('Player')
r.network.sync=src(PM.SyncVars);r.network.sender=src(EM.SendNetVar);r.network.setter=src(EM.SetNetVar)
r.network.budgetLinked=ZCTickBudget and ZCTickBudget.entitySender and EM.SendNetVar==ZCTickBudget.entitySender.wrapper or false
r.network.budgetDrift=ZCTickBudget and ZCTickBudget.networkDrift or false
r.network.fullSyncVersion=zb and zb.net and zb.net.fullSync and zb.net.fullSync.Version or false
r.network.pendingBase=timer.Exists('ZB_FullSyncBudget')
r.batch2.poopErrors=ZCityPoopThrow and ZCityPoopThrow.stats.errors;r.batch2.urineErrors=ZCityUrine and ZCityUrine.stats.errors
file.CreateDir('zc_net_validation');file.Write('zc_net_validation/inspect_20260919t132421z.json',util.TableToJSON(r,true))
print('ZC_NET_VALIDATION_INSPECT',r.map,r.players)

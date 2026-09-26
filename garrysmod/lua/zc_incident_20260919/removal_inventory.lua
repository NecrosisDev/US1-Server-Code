assert(SERVER)
local r={at=os.time(),players=#player.GetHumans(),alive=0,mode=zb.CROUND,state=zb.ROUND_STATE,hooks={},gc={}}
for _,p in ipairs(player.GetHumans())do if p:Alive()then r.alive=r.alive+1 end end
for _,event in ipairs({'EntityRemoved','PreCleanupMap','PostCleanupMap'})do
 r.hooks[event]={}
 for name,fn in pairs(hook.GetTable()[event]or {})do local d=debug.getinfo(fn,'S');r.hooks[event][tostring(name)]={source=d.source,line=d.linedefined}end
end
r.gc.spikeActive=ZCSpike and ZCSpike.active;r.gc.spikeStep=ZCSpike and ZCSpike.gcStep
for _,name in ipairs({'zc_gc_smooth','zc_gc_step','zc_gcsmooth','zc_gcsmooth_step','net_compresspackets'})do local cv=GetConVar(name);r.gc[name]=cv and cv:GetString()or'MISSING'end
file.Write('zc_incident_20260919/removal_hooks.json',util.TableToJSON(r,false))

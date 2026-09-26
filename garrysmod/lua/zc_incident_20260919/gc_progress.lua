assert(SERVER)
local h=ZCGCCost20260919
if h then
 for i=1,30 do local name,v=debug.getupvalue(h.finish,i)if not name then break end
  if name=='r' then
   local out={calls=v.calls,totalMs=v.totalMs,maxMs=v.maxMs,spikes=v.spikes,states=v.states,active=true}
   file.Write('zc_incident_20260919/gc_progress.json',util.TableToJSON(out,false));return
  end
 end
end
file.Write('zc_incident_20260919/gc_progress.json',util.TableToJSON({active=false},false))

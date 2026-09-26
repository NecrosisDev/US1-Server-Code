-- Bounded observation of existing counters/state. Does not wrap net functions or send client messages.
assert(SERVER and engine.ActiveGamemode()=="zcity")
local name="ZC48NetObserve_20260916_1254"
assert(not timer.Exists(name))
local r={started=os.time(),map=game.GetMap(),samples={},hashes={}}
for _,path in ipairs({"homigrad/sv_inventory.lua","homigrad/organism/tier_1/sv_organism.lua","homigrad/sh_ammostuff.lua"})do
 local body=file.Read(path,"LUA");r.hashes[path]=body and util.SHA256(body) or "missing"
end
local function sample()
 local s={time=SysTime(),mode=zb.CROUND,round=zb.ROUND_STATE,players={},calls=table.Copy(ZCNETOPT and ZCNETOPT.sent or {})}
 for _,p in ipairs(player.GetHumans())do
  local row={id=p:EntIndex(),creation=p:GetCreationID(),alive=p:Alive(),loss=p:PacketLoss(),ping=p:Ping(),values={}}
  local vars=zb.net.list[p] or {}
  for _,k in ipairs({"Inventory","wounds","arterialwounds"})do
   local v=vars[k];local text=istable(v) and util.TableToJSON(v) or nil
   row.values[k]={empty=istable(v) and next(v)==nil,jsonBytes=text and #text or 0,signature=text and util.CRC(text) or type(v)}
  end
  s.players[#s.players+1]=row
 end
 r.samples[#r.samples+1]=s
end
local function save(reason)
 timer.Remove(name);r.reason=reason;r.finished=os.time()
 file.CreateDir("zc_capacity_audit");file.Write("zc_capacity_audit/network_20260916_1254.json",util.TableToJSON(r))
end
sample()
timer.Create(name,1,15,function()
 local ok,err=xpcall(sample,debug.traceback)
 if not ok then r.error=err;save("error")elseif #r.samples>=16 then save("complete")end
end)

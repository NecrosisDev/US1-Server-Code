-- Pinned, content-only asset transfer; one acknowledged 8 KiB chunk at a time.
if not SERVER then return end
local C=assert(ZCityPoop)
local A=C.Content or {version="20260918.3",queue={},sessions=setmetatable({},{__mode="k"}),
 ready=setmetatable({},{__mode="k"}),stats={requested=0,completed=0,failed=0,chunks=0,stains=0},serial=0}
C.Content=A
A.reported=A.reported or setmetatable({},{__mode="k"})
local PACK=assert(file.Read("zc_poop/assets_v3.dat","DATA"),"Poop assets missing")
assert(#PACK==1172789,"Poop package length differs")
local CHUNK=8192;local TOTAL=math.ceil(#PACK/CHUNK)
for _,n in ipairs({"ZCPoopContentV3","ZCPoopChunkV3","ZCPoopStainV3"})do util.AddNetworkString(n)end
function A.Save()
 local pending=0
 for p,s in pairs(A.sessions)do if IsValid(p)and not s.done then pending=pending+1 end end
 file.CreateDir("zc_poop")
 file.Write("zc_poop/visual_status.json",util.TableToJSON({version=A.version,time=os.time(),stats=A.stats,
 pending=pending,clients=A.clients or {},chunk_bytes=CHUNK,packed_bytes=#PACK},true))
end
function A.SendStain(p,ent)
 local d=ent.ZCPoopDecal
 if not d or not IsValid(p)or not A.ready[p]then return end
 net.Start("ZCPoopStainV3");net.WriteUInt(d.id,32);net.WriteVector(d.pos);net.WriteNormal(d.normal);net.Send(p)
end
function C.MakeStain(ent)
 if not IsValid(ent)or ent.ZCPoopDecal then return false end
 local pos=ent:GetPos()
 local tr=util.TraceLine({start=pos+Vector(0,0,16),endpos=pos-Vector(0,0,96),mask=MASK_SOLID_BRUSHONLY})
 if not tr.HitWorld or tr.StartSolid or tr.HitSky or tr.HitNormal.z<0.4 then return false end
 A.serial=A.serial+1;ent.ZCPoopDecal={id=A.serial,pos=tr.HitPos,normal=tr.HitNormal}
 A.stats.stains=A.stats.stains+1
 for p in pairs(A.ready)do A.SendStain(p,ent)end
 return true
end
net.Receive("ZCPoopContentV3",function(bits,p)
 if not IsValid(p)or p:IsBot()or bits<2 or bits>128 then return end
 local op=net.ReadUInt(2);local s=A.sessions[p]
 if op==0 then
  if s or A.ready[p]then return end
  s={index=1,attempts=0,queued=RealTime()};A.sessions[p]=s;A.queue[#A.queue+1]=p
  A.stats.requested=A.stats.requested+1
 elseif op==1 and s and bits>=18 then
  local index=net.ReadUInt(16)
  if index==s.index and s.waiting then s.index=s.index+1;s.waiting=false;s.attempts=0 end
 elseif op==2 and bits>=21 then
  local ok=net.ReadBool();local triangles=net.ReadUInt(16);local stain=net.ReadBool();local texture=net.ReadBool()
  if A.ready[p]or A.reported[p]then return end
  A.reported[p]=true
  A.clients=A.clients or {};A.clients[p:SteamID64()]={ready=ok,triangles=triangles,stain=stain,texture=texture}
  if ok and triangles>0 and stain and texture then
   A.ready[p]=true;A.stats.completed=A.stats.completed+1
   if s then s.done=true end
   for ent in pairs(C.owned)do if IsValid(ent)then A.SendStain(p,ent)end end
  else A.stats.failed=A.stats.failed+1;if s then s.done=true end end
  A.Save()
 end
end)
timer.Create("ZCityPoop_ContentSend",0.04,0,function()
 local p=table.remove(A.queue,1);if not p then return end
 local s=A.sessions[p]
 if not IsValid(p)or not s or s.done or s.index>TOTAL then return end
 A.queue[#A.queue+1]=p
 if s.waiting then
  if RealTime()-s.sent<8 then return end
  if s.attempts>=3 then s.done=true;A.stats.failed=A.stats.failed+1;A.Save();return end
 end
 local data=PACK:sub((s.index-1)*CHUNK+1,s.index*CHUNK)
 net.Start("ZCPoopChunkV3");net.WriteUInt(s.index,16);net.WriteUInt(TOTAL,16)
 net.WriteUInt(#data,14);net.WriteData(data,#data);net.Send(p)
 s.sent=RealTime();s.waiting=true;s.attempts=s.attempts+1;A.stats.chunks=A.stats.chunks+1
end)
timer.Create("ZCityPoop_ContentStatus",10,0,A.Save)
A.Save()

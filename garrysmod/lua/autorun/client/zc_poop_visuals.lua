-- Fixed content-only GMA; never mounts an unverified or client-selected archive.
if not CLIENT then return end
if ZCPoopVisuals and ZCPoopVisuals.version=="20260918.3"then return end
local P={version="20260918.3",parts={},count=0,received=0,seen={},pending={},ready=false}
ZCPoopVisuals=P
local MODEL="models/poo/poo.mdl"
local HASH="fcc5bb4b0d4e794dfb672c1c8710a7f75bf75fcdc87f13a973399b06865e03a0"
local BYTES=8535114;local PACKED=1172789
local CACHE="zc_poop/"..HASH..".dat"
local CHUNKS=math.ceil(PACKED/8192)
local function report(ok,triangles,stain,texture)
 net.Start("ZCPoopContentV3");net.WriteUInt(2,2);net.WriteBool(ok)
 net.WriteUInt(math.min(65535,triangles or 0),16);net.WriteBool(stain);net.WriteBool(texture);net.SendToServer()
end
local function paint(id,pos,normal)
 if P.seen[id]then return end
 if not P.ready then if #P.pending<256 then P.pending[#P.pending+1]={id,pos,normal}end;return end
 util.DecalEx(P.stain,game.GetWorld(),pos,normal,Color(255,255,255),0.32,0.32)
 P.seen[id]=true;P.decals=(P.decals or 0)+1
end
net.Receive("ZCPoopStainV3",function()paint(net.ReadUInt(32),net.ReadVector(),net.ReadNormal())end)
local function loadAssets()
 local ok=game.MountGMA("data/"..CACHE)
 if not ok then report(false,0,false,false);return end
 P.material=CreateMaterial("zc_poop_visual_"..HASH:sub(1,12),"VertexLitGeneric",{
  ["$basetexture"]="models/poo/poo",["$bumpmap"]="models/poo/poo_n",["$phong"]="1",
  ["$phongboost"]="4",["$phongexponent"]="30"})
 P.stain=Material("zc_poop/stain")
 local meshes=util.GetModelMeshes(MODEL,0,0);local triangles=0
 for _,mesh in ipairs(meshes or {})do triangles=triangles+#(mesh.triangles or {})/3 end
 local texture=P.material:GetTexture("$basetexture")
 local goodTexture=texture~=nil and not texture:IsError()
 local goodStain=not P.stain:IsError()
 P.ready=triangles>0 and goodTexture and goodStain
 if P.ready then
  for _,e in ipairs(ents.FindByModel(MODEL))do
   if e:GetNW2Bool("zc_poop",false)then e:SetModel(MODEL);e:SetNoDraw(false);e:SetSubMaterial(0,"!"..P.material:GetName())end
  end
  for _,d in ipairs(P.pending)do paint(d[1],d[2],d[3])end
  P.pending={}
 end
 report(P.ready,triangles,goodStain,goodTexture)
end
net.Receive("ZCPoopChunkV3",function(bits)
 local index,total,size=net.ReadUInt(16),net.ReadUInt(16),net.ReadUInt(14)
 if P.ready or total~=CHUNKS or index<1 or index>total or size<1 or size>8192
  or bits<46+size*8 or P.received+size>PACKED+8192 then return end
 local data=net.ReadData(size);if not data or #data~=size then return end
 if not P.parts[index]then P.parts[index]=data;P.count=P.count+1;P.received=P.received+size end
 net.Start("ZCPoopContentV3");net.WriteUInt(1,2);net.WriteUInt(index,16);net.SendToServer()
 if P.count~=total then return end
 local packed=table.concat(P.parts);P.parts={}
 if #packed~=PACKED then report(false,0,false,false);return end
 local raw=util.Decompress(packed,BYTES)
 if not raw or #raw~=BYTES or util.SHA256(raw)~=HASH or raw:sub(1,4)~="GMAD"then report(false,0,false,false);return end
 file.CreateDir("zc_poop");file.Write(CACHE,raw)
 local saved=file.Read(CACHE,"DATA")
 if not saved or util.SHA256(saved)~=HASH then report(false,0,false,false);return end
 loadAssets()
end)
timer.Simple(1,function()
 local data=file.Read(CACHE,"DATA")
 if data and #data==BYTES and util.SHA256(data)==HASH then loadAssets();return end
 net.Start("ZCPoopContentV3");net.WriteUInt(0,2);net.SendToServer()
end)
timer.Create("ZCityPoop_RefreshMeshes",1,0,function()
 if not P.ready then return end
 for _,e in ipairs(ents.FindByModel(MODEL))do
  if e:GetNW2Bool("zc_poop",false)and e.ZCPoopVisualVersion~=P.version then
   e:SetNoDraw(false);e:SetSubMaterial(0,"!"..P.material:GetName());e.ZCPoopVisualVersion=P.version
  end
 end
end)
hook.Add("PostCleanupMap","ZCityPoop_DecalState",function()P.seen={};P.pending={}end)

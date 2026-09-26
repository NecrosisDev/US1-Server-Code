local r={time=os.time(),assets={},poops={},systems={},players=#player.GetHumans(),map=game.GetMap()}
for i=1,4 do local n='homigrad/blooddrip'..i..'.wav';r.assets[n]=file.Exists('sound/'..n,'GAME') end
r.decal=util.DecalMaterial('YellowBlood');r.decalExists=type(r.decal)=='string' and file.Exists('materials/'..r.decal..'.vmt','GAME')
r.stainDefinition=file.Read('scripts/decals_subrect.txt','GAME')
for ent in pairs(ZCityPoop and ZCityPoop.owned or {}) do if IsValid(ent) then
 local ph=ent:GetPhysicsObject();local lo,hi=ent:GetModelBounds()
 r.poops[#r.poops+1]={mass=IsValid(ph) and ph:GetMass(),scale=ent:GetModelScale(),mins=tostring(lo),maxs=tostring(hi)}
end end
for _,n in ipairs({'ZCityPoop','ZCityPoopThrow','ZCityPoopInvoluntary','ZCityUrine'}) do local s=_G[n];if s then r.systems[n]={version=s.Version,stats=s.stats and table.Copy(s.stats)} end end
r.normals={}
for _,normal in ipairs({Vector(0,0,1),Vector(0,0,-1),Vector(1,0,0),Vector(0,1,0),Vector(1,2,3):GetNormalized()}) do
 local f=math.abs(normal.x)<.9 and Vector(1,0,0) or Vector(0,1,0);f=(f-normal*f:Dot(normal)):GetNormalized()
 local a=f:AngleEx(normal);r.normals[#r.normals+1]={normal=tostring(normal),up=tostring(a:Up()),dot=a:Up():Dot(normal)}
end
r.stainDefinition=nil
file.CreateDir('zc_repair_batches');file.Write('zc_repair_batches/inspect_20260919t025322z.json',util.TableToJSON(r,true))
print('ZCREPAIR_INSPECT_READY')

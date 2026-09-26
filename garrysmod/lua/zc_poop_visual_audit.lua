assert(SERVER and engine.ActiveGamemode()=="zcity")
local C=assert(ZCityPoop);local A=assert(C.Content)
local report={version=C.Version,time=os.time(),clients={},decals_before=A.stats.stains,temporary_prop=false}
for _,p in ipairs(player.GetAll())do
 if p:Alive()and p:Team()<1000 then
  local body=C.Body(p)
  if IsValid(body)then
   local pos,ang=C.DropPosition(p,body)
   if pos then
    local e=ents.Create("prop_physics")
    e:SetModel(C.Model);e:SetPos(pos);e:SetAngles(ang);e:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
    C.owned[e]=true;e.ZCityCosmeticPoop=true;e.PhysgunDisabled=true;e.DoNotDuplicate=true
    e:Spawn();e:SetNW2Bool("zc_poop",true);e:SetNoDraw(false)
    local phys=e:GetPhysicsObject()
    if IsValid(phys)then phys:AddGameFlag(FVPHYSICS_NO_IMPACT_DMG);phys:EnableMotion(false)end
    report.temporary_prop=true;report.decal_projected=C.MakeStain(e)
    timer.Simple(100,function()if IsValid(e)then e:Remove()end end)
    break
   end
  end
 end
end
local function save()file.Write("zc_poop/visual_audit.json",util.TableToJSON(report,true))end
local pending={};local expires=RealTime()+90
util.AddNetworkString("ZCPoopVisualAuditV3")
net.Receive("ZCPoopVisualAuditV3",function(bits,p)
 if not pending[p]or RealTime()>expires or bits<18 or bits>32 then return end
 pending[p]=nil
 report.clients[p:SteamID64()]={ready=net.ReadBool(),decals=net.ReadUInt(16),material=net.ReadBool()};save()
end)
timer.Simple(55,function()
 local code=[[local p=ZCPoopVisuals net.Start("ZCPoopVisualAuditV3") net.WriteBool(p and p.ready==true) net.WriteUInt(p and p.decals or 0,16) net.WriteBool(p and p.material and not p.material:IsError()or false) net.SendToServer()]]
 for _,p in ipairs(player.GetAll())do if not p:IsBot()then pending[p]=true;p:SendLua(code)end end
end)
save()

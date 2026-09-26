-- One-shot read-only census. No entity, physics, player, or network writes.
assert(SERVER and engine.ActiveGamemode()=="zcity")
local begin=SysTime()
local out={map=game.GetMap(),at=os.time(),players=#player.GetHumans(),checked=0,stored=0,
 hidden=0,parented=0,physicsObjects=0,motionEnabled=0,awake=0,beyond16384=0,examples={},complete=true}
local list=ents.FindByClass("weapon_*");out.candidates=#list
for _,e in ipairs(list)do
 if SysTime()-begin>0.002 then out.complete=false;break end
 out.checked=out.checked+1
 local parent=e:GetParent()
 if IsValid(parent) and e:GetNoDraw() then
  out.parented=out.parented+1
  local inv=parent.inventory
  local stored=istable(inv) and istable(inv.Weapons) and inv.Weapons[e:GetClass()]==e
  if stored and not IsValid(e:GetOwner()) then
   out.stored=out.stored+1
   local pos,ppos=e:GetPos(),parent:GetPos();local ph=e:GetPhysicsObject()
   local far=math.abs(pos.x)>16384 or math.abs(pos.y)>16384 or math.abs(pos.z)>16384
   if far then out.beyond16384=out.beyond16384+1 end
   local motion,awake=false,false
   if IsValid(ph)then out.physicsObjects=out.physicsObjects+1;motion=ph:IsMotionEnabled();awake=not ph:IsAsleep()end
   if motion then out.motionEnabled=out.motionEnabled+1 end
   if awake then out.awake=out.awake+1 end
   if #out.examples<12 then out.examples[#out.examples+1]={id=e:EntIndex(),class=e:GetClass(),parent=parent:GetClass(),pos=pos,parentPos=ppos,offsetZ=pos.z-ppos.z,moveType=e:GetMoveType(),physics=IsValid(ph),motion=motion,awake=awake}end
  end
 end
end
out.scanMs=(SysTime()-begin)*1000
file.CreateDir("zc_ammo_delta");file.Write("zc_ammo_delta/storage_observation.json",util.TableToJSON(out,true))
print("AMMO_STORAGE_OBS",out.stored,out.checked,out.complete,out.scanMs)

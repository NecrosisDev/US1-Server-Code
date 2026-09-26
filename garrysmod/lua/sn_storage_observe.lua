-- One-shot diagnostic; only reads game state and writes its own DATA report.
assert(SERVER and engine.ActiveGamemode()=="zcity")
local start=SysTime()
local r={at=os.time(),map=game.GetMap(),mode=zb.CROUND,players=#player.GetHumans(),
 bodies=0,entries=0,entities=0,hidden=0,parented=0,physics=0,awake=0,far=0,examples={},complete=true}
local bodies=ents.FindByClass("prop_ragdoll")
for _,b in ipairs(bodies)do
 if SysTime()-start>0.002 then r.complete=false;break end
 local inv=b.inventory or b:GetNetVar("Inventory")
 if istable(inv) and istable(inv.Weapons)then
  r.bodies=r.bodies+1
  for class,e in pairs(inv.Weapons)do
   r.entries=r.entries+1
   if isentity(e) and IsValid(e)then
    r.entities=r.entities+1
    local pos,pp=e:GetPos(),b:GetPos();local ph=e:GetPhysicsObject()
    if e:GetNoDraw()then r.hidden=r.hidden+1 end
    if e:GetParent()==b then r.parented=r.parented+1 end
    if IsValid(ph)then r.physics=r.physics+1;if not ph:IsAsleep()then r.awake=r.awake+1 end end
    if math.abs(pos.z-pp.z)>9000 then r.far=r.far+1 end
    if #r.examples<8 then r.examples[#r.examples+1]={class=class,offset=pos-pp,hidden=e:GetNoDraw(),
     owned=IsValid(e:GetOwner()),parent=e:GetParent()==b,physics=IsValid(ph),move=e:GetMoveType()}end
   end
  end
 end
end
r.ms=(SysTime()-start)*1000
file.CreateDir("zc_storage_native");file.Write("zc_storage_native/observation.json",util.TableToJSON(r,true))
print("SN_OBSERVE",r.entities,r.far,r.complete)

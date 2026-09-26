-- Explicit deployment smoke check. No player is made to run the command.
assert(SERVER and engine.ActiveGamemode()=="zcity")
local body=assert(file.Read("autorun/server/zc_poop.lua","LUA"))
assert(util.SHA256(body)=="1f940d8d41a76703577604cccd6933991fdd5addaf5fb7fe9b48b696b5c529a2","poop source differs from tested release")
assert(isfunction(CompileString(body,"poop_preflight",false)))
include("autorun/server/zc_poop.lua")
local C=assert(ZCityPoop)
assert(C.Version=="20260918.2" and C.Cooldown==30 and C.Limit==2)
assert(concommand.GetTable().poop==C.Callback)
assert(C.Spawn(NULL)==false)
assert(util.IsValidModel(C.Model) and util.IsValidProp(C.Model))
assert(file.Exists("sound/"..C.Sound,"GAME"))
local report={version=C.Version,command="poop",cooldown=C.Cooldown,limit=C.Limit,
 model=C.Model,sound=C.Sound,source_hash=util.SHA256(body),time=os.time(),passed=true,
 clients_sent=0,clients_received=0,clients_assets_ready=0,physics_smoke=false,positions_checked=0}
for _,p in ipairs(player.GetAll()) do
 if p:Alive() and p:Team()<1000 then
  local character=C.Body(p)
  if IsValid(character) then
   local pos,ang=C.DropPosition(p,character)
   report.positions_checked=report.positions_checked+1
   if pos and not report.physics_smoke then
    local e=ents.Create("prop_physics")
    assert(IsValid(e));C.owned[e]=true
    local ok,err=pcall(function()
     e:SetNoDraw(true);e:SetModel(C.Model);e:SetPos(pos);e:SetAngles(ang)
     e:SetCollisionGroup(COLLISION_GROUP_DEBRIS);e:Spawn()
     local phys=e:GetPhysicsObject();assert(IsValid(phys))
     phys:AddGameFlag(FVPHYSICS_NO_IMPACT_DMG);phys:SetMass(1);phys:EnableMotion(false)
     report.physics_smoke=true
    end)
    if IsValid(e) then e:Remove() end
    assert(ok,tostring(err))
   end
  end
 end
end
local function save()file.Write("zc_poop_deployed.json",util.TableToJSON(report,true))end
local pending={};local expires=RealTime()+30
util.AddNetworkString("ZCPoopAssetCheck")
net.Receive("ZCPoopAssetCheck",function(len,p)
 if len<3 or len>16 or RealTime()>expires or not pending[p] then return end
 pending[p]=nil
 local model,snd,texture=net.ReadBool(),net.ReadBool(),net.ReadBool()
 report.clients_received=report.clients_received+1
 if model and snd and texture then report.clients_assets_ready=report.clients_assets_ready+1 end
 save()
end)
local client=[[net.Start("ZCPoopAssetCheck") net.WriteBool(file.Exists("models/poo/poo.mdl","GAME")) net.WriteBool(file.Exists("sound/snd_jack_hmcd_fart.wav","GAME")) net.WriteBool(file.Exists("materials/models/poo/poo.vtf","GAME")) net.SendToServer()]]
for _,p in ipairs(player.GetAll()) do
 if not p:IsBot() then pending[p]=true;report.clients_sent=report.clients_sent+1;p:SendLua(client) end
end
save()
print("ZC_POOP_ACTIVE",C.Version,report.physics_smoke)

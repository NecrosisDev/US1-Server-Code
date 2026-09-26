-- Cosmetic poop command for server 450e82aa. No karma, injury or role logic.
if not SERVER then return end
local C=ZCityPoop or {accounts={},owned=setmetatable({},{__mode="k"})}
local existing=concommand.GetTable().poop
assert(not existing or existing==C.Callback,"poop command already belongs to another addon")
assert(not ConVarExists("poop"),"poop is already a console variable")
ZCityPoop=C
C.Version="20260918.h1"
C.Model="models/poo/poo.mdl"
C.Scale=0.75
C.Sound="snd_jack_hmcd_fart.wav"
C.Cooldown=30
C.Limit=2
AddCSLuaFile("autorun/client/zc_poop_visuals.lua")
include("zc_poop/content.lua")
local function playerOK(p)
    return IsValid(p) and p:IsPlayer() and p:Alive() and p:Team()<1000
        and p:GetObserverMode()==OBS_MODE_NONE
end
local function accountID(p)
    return p:IsBot() and ("bot:"..p:UserID()) or p:SteamID64()
end
local function tell(p,s,text,now)
    if now<(s.notice or 0) then return end
    s.notice=now+2
    p:PrintMessage(HUD_PRINTCONSOLE,"poop: "..text.."\n")
end
function C.Body(p)
    local P=ZCityPillCompat
    if P and P.spawning and P.spawning[p] then return nil end
    local morph=P and P.Morph and P.Morph(p)
    if IsValid(morph) then
        local puppet=morph.GetPuppet and morph:GetPuppet()
        return IsValid(puppet) and puppet or morph
    end
    return IsValid(p.FakeRagdoll) and p.FakeRagdoll or p
end
function C.DropPosition(p,body)
    -- Bounds measured from Smallotown poo.mdl and verified with Entity:GetModelBounds.
    local scale=C.Scale or 1
    local lo,hi=Vector(-5.128058,-5.029512,-0.209915)*scale,Vector(5.264503,5.144993,7.800672)*scale
    local radius=math.max(math.abs(lo.x),math.abs(lo.y),math.abs(hi.x),math.abs(hi.y))+1
    local yaw=Angle(0,body:GetAngles().y,0)
    local center=body:WorldSpaceCenter()
    local wanted=center-yaw:Forward()*18
    local ignore={p,body}
    for ent in pairs(C.owned) do if IsValid(ent) then ignore[#ignore+1]=ent end end
    local path=util.TraceLine({start=center,endpos=wanted,mask=MASK_SOLID,filter=ignore})
    if path.StartSolid then return nil end
    if path.Hit then wanted=center end
    local floor=util.TraceLine({start=wanted,endpos=wanted-Vector(0,0,160),mask=MASK_SOLID,filter=ignore})
    if not floor.Hit or floor.StartSolid or floor.HitSky or floor.HitNormal.z<0.4 then return nil end
    local pos=floor.HitPos+Vector(0,0,3-lo.z)
    local hull={mins=Vector(-radius,-radius,lo.z),maxs=Vector(radius,radius,hi.z),mask=MASK_SOLID,filter=ignore}
    hull.start=pos;hull.endpos=pos+Vector(0,0,8)
    local clearance=util.TraceHull(hull)
    if clearance.StartSolid or clearance.AllSolid then return nil end
    pos=clearance.HitPos
    if not util.IsInWorld(pos) then return nil end
    return pos,yaw
end
function C.RemoveState(s)
    local old=s.poops or {}
    s.poops={} -- EntityRemoved may edit the ownership ledger synchronously.
    for _,ent in ipairs(old) do if IsValid(ent) then ent:Remove() end end
end
function C.Settle(ent)
    if not IsValid(ent) then return end
    local T=ZCityPoopThrow
    if ent.ZCPoopWasManipulated or IsValid(ent.ZCPoopHolder)
        or (T and T.ActiveHolder and IsValid(T.ActiveHolder(ent))) then return end
    local phys=ent:GetPhysicsObject()
    if IsValid(phys) then phys:EnableMotion(false) end
    if type(C.MakeStain)=="function" then C.MakeStain(ent) end
end
function C.Cleanup()
    for _,s in pairs(C.accounts) do C.RemoveState(s) end
end
function C.Spawn(p)
    if not playerOK(p) or p:InVehicle() then return false,"not_playing" end
    local id=accountID(p)
    if not isstring(id) or id=="" or id=="0" then return false,"identity" end
    local now=RealTime()
    local s=C.accounts[id] or {poops={},next=0}
    C.accounts[id]=s;s.player=p
    if now<s.next then
        tell(p,s,"wait "..math.ceil(s.next-now).." seconds.",now)
        return false,"cooldown"
    end
    if now<(s.retry or 0) then return false,"retry" end
    s.retry=now+1
    local body=C.Body(p)
    if not IsValid(body) then return false,"no_body" end
    if not file.Exists(C.Model,"GAME") or not file.Exists("sound/"..C.Sound,"GAME")
        or not util.IsValidProp(C.Model) then
        tell(p,s,"the required model or sound is unavailable.",now)
        return false,"assets"
    end
    local pos,ang=C.DropPosition(p,body)
    if not pos then
        tell(p,s,"stand near clear ground first.",now)
        return false,"blocked"
    end
    local ent=ents.Create("prop_physics")
    if not IsValid(ent) then return false,"entity_limit" end
    C.owned[ent]=true
    ent.DoNotDuplicate=true;ent.PhysgunDisabled=true;ent.ZCityCosmeticPoop=true
    ent.ZCityPoopOwner=id
    local ok,err=pcall(function()
        ent:SetModel(C.Model);ent:SetModelScale(C.Scale or 1,0);ent:SetPos(pos);ent:SetAngles(ang)
        ent:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
        ent:Spawn();ent:Activate()
        ent:SetNoDraw(false);ent:SetNW2Bool("zc_poop",true)
        assert(IsValid(ent),"poop prop was removed during spawn")
        ent:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
        local phys=ent:GetPhysicsObject()
        assert(IsValid(phys),"poop model has no physics object")
        phys:AddGameFlag(FVPHYSICS_NO_IMPACT_DMG)
        phys:SetMass(1);phys:Wake()
    end)
    if not ok then
        if IsValid(ent) then ent:Remove() end
        if not C.spawnErrorLogged then
            C.spawnErrorLogged=true;ErrorNoHalt("[Poop] Spawn failed: "..tostring(err).."\n")
        end
        return false,"spawn_failed"
    end
    local live={}
    for _,old in ipairs(s.poops) do if IsValid(old) then live[#live+1]=old end end
    while #live>=C.Limit do table.remove(live,1):Remove() end
    live[#live+1]=ent;s.poops=live;s.next=now+C.Cooldown
    -- Spatial sound only; no chat announcement, role checks or injury writes.
    pcall(body.EmitSound,body,C.Sound,65,100,0.7,CHAN_AUTO)
    timer.Simple(2,function() C.Settle(ent) end)
    return true,ent
end
C.Callback=function(p) C.Spawn(p) end
concommand.Add("poop",C.Callback,nil,"Fart and drop a poop. 30-second cooldown; two active poops per player.")
local function deny(_,ent) if C.owned[ent] then return false end end
hook.Add("PhysgunPickup","ZCityPoop_NoPickup",deny)
hook.Add("GravGunPickupAllowed","ZCityPoop_NoPickup",deny)
hook.Add("GravGunPunt","ZCityPoop_NoPunt",deny)
hook.Add("AllowPlayerPickup","ZCityPoop_NoPickup",deny)
hook.Add("CanTool","ZCityPoop_NoDupe",function(_,tr,tool)
    if tr and C.owned[tr.Entity] and tool~="remover" then return false end
end)
hook.Add("CanProperty","ZCityPoop_NoProperties",function(_,_,ent)
    if C.owned[ent] then return false end
end)
hook.Add("EntityTakeDamage","ZCityPoop_NoDamage",function(ent,info)
    if C.owned[info:GetInflictor()] or C.owned[info:GetAttacker()] then return true end
end)
hook.Add("PlayerDisconnected","ZCityPoop_Disconnect",function(p)
    local id=accountID(p);local s=C.accounts[id]
    if not s then return end
    C.RemoveState(s);s.player=nil
    timer.Simple(math.max(1,s.next-RealTime()+1),function()
        if C.accounts[id]==s and not IsValid(s.player) then C.accounts[id]=nil end
    end)
end)
hook.Add("EntityRemoved","ZCityPoop_ForgetRemoved",function(ent)
    if not C.owned[ent] then return end
    C.owned[ent]=nil
    for _,s in pairs(C.accounts) do
        for i=#(s.poops or {}),1,-1 do
            if s.poops[i]==ent then table.remove(s.poops,i) end
        end
    end
end)
hook.Add("ZB_EndRound","ZCityPoop_RoundCleanup",C.Cleanup)
hook.Add("PostCleanupMap","ZCityPoop_MapCleanup",C.Cleanup)
-- Request the existing map content even when the current map is not Smallotown.
resource.AddWorkshop("2264867796")
-- Also register the exact model/material/sound files for standard downloads.
for _,path in ipairs({C.Model,"materials/models/poo/poo.vmt","materials/models/poo/poo.vtf",
    "materials/models/poo/poo_n.vtf","sound/"..C.Sound}) do
    if file.Exists(path,"GAME") then resource.AddFile(path) end
end
util.PrecacheModel(C.Model)
util.PrecacheSound(C.Sound)

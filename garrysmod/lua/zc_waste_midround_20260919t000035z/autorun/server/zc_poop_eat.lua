-- Server 450e82aa: voluntary USE consumption; native vomiting, not custom damage.
if not SERVER then return end
local E=ZCityPoopEat or {}
ZCityPoopEat=E
E.Version="20260919.spawn1"
E.Delay=3
E.Duration=60
E.VomitInterval=1.5
E.UseDistance=96
E.Sound="snd_jack_hmcd_eat1.wav"
E.Message="Why did I do that?"
E.states=E.states or setmetatable({},{__mode="k"})
E.claimed=E.claimed or setmetatable({},{__mode="k"})
E.stats=E.stats or {eaten=0,vomits=0,errors=0}
E.logged=E.logged or {}
local function finite(n)return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function accountID(p)return p:IsBot() and ("bot:"..p:UserID()) or p:SteamID64()end
function E.OwnerOf(ent,C)
    for owner,account in pairs(C.accounts or {})do
        for _,poop in ipairs(account.poops or {})do
            if poop==ent then return owner end
        end
    end
end
local function playing(p)
    return IsValid(p) and p:IsPlayer() and p:Alive() and p:Team()~=TEAM_SPECTATOR
        and p:GetObserverMode()==OBS_MODE_NONE
end
E.CanPlay=playing
local function carrier(p)
    local P=ZCityPillCompat
    return P and ((P.spawning and P.spawning[p]) or (P.IsCarrier and P.IsCarrier(p)))
end
function E.Reset(p)E.states[p]=nil end
function E.ResetAll()E.states=setmetatable({},{__mode="k"})end
function E.Error(tag,err)
    E.stats.errors=E.stats.errors+1
    if E.logged[tag]then return end
    E.logged[tag]=true
    file.CreateDir("zc_poop")
    file.Append("zc_poop/eating_errors.txt",os.date("!%Y-%m-%dT%H:%M:%SZ").." "..tag.." "..tostring(err):sub(1,1000).."\n")
end
function E.Character(p)
    if not hg or not hg.organism or type(hg.organism.Vomit)~="function"
        or type(hg.GetCurrentCharacter)~="function"then return end
    local org=p.organism
    if type(org)~="table" or org.alive==false or not finite(org.blood) or not finite(org.pulse)then return end
    local body=hg.GetCurrentCharacter(p)
    if not IsValid(body)then return end
    local bone=body:LookupBone("ValveBiped.Bip01_Head1")
    if bone==nil or bone<0 or not body:GetBoneMatrix(bone)then return end
    return body
end
function E.InReach(p,ent)
    local origin=p:EyePos()
    local target=ent:NearestPoint(origin)
    if origin:DistToSqr(target)>E.UseDistance*E.UseDistance then return false end
    -- Only the world should block eating. The poop is tiny and ordinary props/weapons
    -- must not make the interaction require a pixel-perfect collision trace.
    local tr=util.TraceLine({start=origin,endpos=ent:WorldSpaceCenter(),mask=MASK_SOLID_BRUSHONLY})
    return not tr.StartSolid and not tr.AllSolid and not tr.Hit
end
function E.HeldPoop(p,expected)
    local C=ZCityPoop
    if not C or type(C.owned)~="table" or not IsValid(p)then return end
    local w=p:GetActiveWeapon()
    if not IsValid(w) or w:GetClass()~="weapon_hands_sh"then return end
    if type(w.GetFists)=="function" and w:GetFists()then return end
    if type(w.GetCarrying)~="function" or not p:KeyDown(IN_ATTACK2)then return end
    local ent=w:GetCarrying()
    if not IsValid(ent) or not C.owned[ent]then return end
    if IsValid(expected) and ent~=expected then return end
    return ent,w
end
-- Remove the old proximity-based target finder from persistent hot-reload state.
E.FindTarget=nil
function E.Eat(p,ent)
    local C=ZCityPoop
    if not C or not C.owned or not IsValid(ent) or not C.owned[ent] or E.claimed[ent]then return false end
    if not playing(p) or carrier(p) or p:InVehicle()then return false end
    -- Eating is intentionally a two-step action: RMB-grab this exact poop with
    -- lowered hands, then press USE while RMB is still held.
    if E.HeldPoop(p,ent)~=ent then
        E.stats.heldrequired=(E.stats.heldrequired or 0)+1
        return false
    end
    local org=p.organism
    if type(org)~="table" or org.otrub or type(p.Notify)~="function"then return false end
    local now=CurTime();local old=E.states[p]
    if old and old.org==org and now<old.ends then return false end
    if not E.InReach(p,ent)then return false end
    local body=E.Character(p)
    if not body or not file.Exists("sound/"..E.Sound,"GAME")then return false end
    local owner=E.OwnerOf(ent,C)
    local eater=accountID(p)
    local foreign=type(owner)=="string" and owner~=eater
    -- Only someone else's poop starts the delayed damaging vomit loop.
    local state=foreign and {org=org,starts=now+E.Delay,ends=now+E.Delay+E.Duration,
        next=now+E.Delay,last=now,epoch=E.epoch or 0} or nil
    E.claimed[ent]=true
    if state then E.states[p]=state end
    local ok,err=pcall(ent.Remove,ent)
    if not ok then
        E.states[p]=old;E.claimed[ent]=nil;E.Error("consume",err);return false
    end
    C.owned[ent]=nil
    for _,account in pairs(C.accounts or {})do
        for i=#(account.poops or {}),1,-1 do
            if account.poops[i]==ent then table.remove(account.poops,i)end
        end
    end
    E.stats.eaten=E.stats.eaten+1
    -- Eating sound and regret always occur; native vomiting only follows foreign poop.
    ok,err=pcall(body.EmitSound,body,E.Sound,60,100,1,CHAN_AUTO)
    if not ok then E.Error("sound",err)end
    ok,err=pcall(p.Notify,p,E.Message,3,"zc_poop_regret",0)
    if not ok then E.Error("notify",err)end
    return true
end
function E.Step(p,state,now)
    if E.states[p]~=state then return end
    if not playing(p) or carrier(p) or p.organism~=state.org or state.org.alive==false
        or state.epoch~=(E.epoch or 0) or now<state.last or now>=state.ends then
        E.Reset(p);return
    end
    state.last=now
    if now<state.next then return end
    -- Keep native 1.5-second retching continuous, but never replay missed ticks as a damage burst.
    if not E.Character(p)then state.next=now+0.5;return end
    local untilTime=p:GetNetVar("vomiting",0)
    if finite(untilTime) and untilTime>now then
        state.next=math.max(now+0.05,untilTime);return
    end
    state.next=now+E.VomitInterval
    local ok,err=pcall(hg.organism.Vomit,p)
    if ok then E.stats.vomits=E.stats.vomits+1
    else E.Reset(p);E.Error("vomit",err)end
end
function E.Tick()
    local now=CurTime()
    for p,state in pairs(E.states)do
        local ok,err=pcall(E.Step,p,state,now)
        if not ok then E.Reset(p);E.Error("tick",err)end
    end
end
E.Use=function(p,ent)
    local C=ZCityPoop
    if not C or not C.owned or not IsValid(ent) or not C.owned[ent]then return end
    -- Do not consume or block USE unless this player is actively RMB-holding
    -- this exact poop with lowered hands.
    if E.HeldPoop(p,ent)~=ent then return end
    local ok,err=pcall(E.Eat,p,ent)
    if not ok then E.Error("use",err)end
    return false
end
hook.Add("PlayerUse","ZCityPoop_Eat",E.Use,1)
hook.Add("KeyPress","ZCityPoop_EatKey",function(p,key)
    if key~=IN_USE or not playing(p)then return end
    E.stats.usepress=(E.stats.usepress or 0)+1
    local ent=E.HeldPoop(p)
    if not IsValid(ent)then return end
    E.stats.helduses=(E.stats.helduses or 0)+1
    local ok,err=pcall(E.Eat,p,ent)
    if not ok then E.Error("keypress",err)end
end)
E.Timer=function()E.Tick()end
timer.Create("ZCityPoop_Eating",0.1,0,E.Timer)
for _,event in ipairs({"PlayerSpawn","PlayerDeath","PlayerSilentDeath","PlayerDisconnected"})do
    local isSpawn=event=="PlayerSpawn"
    hook.Add(event,"ZCityPoop_EatingReset",function(p)
        if isSpawn and OverrideSpawn then return end
        E.Reset(p)
    end)
end
E.RoundReset=function()E.epoch=(E.epoch or 0)+1;E.ResetAll()end
hook.Add("ZB_EndRound","ZCityPoop_EatingReset",E.RoundReset)
hook.Add("PostCleanupMap","ZCityPoop_EatingReset",E.RoundReset)
if file.Exists("sound/"..E.Sound,"GAME")then util.PrecacheSound(E.Sound);resource.AddFile("sound/"..E.Sound)end

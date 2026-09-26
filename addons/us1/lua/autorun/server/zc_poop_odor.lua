-- Server 450e82aa: nearby poop smell, native ZCity notice and vomiting.
-- No custom networking, role checks, penalty changes or collision changes.
if not SERVER then return end
local S=ZCityPoopOdor or {}
ZCityPoopOdor=S
S.Version="20260920.tuning1"
S.Radius=160
S.RollInterval=10
S.RollChance=0.03
S.Interval=0.5
local previousNoticeCooldown=S.NoticeCooldown or 30
S.NoticeCooldown=120
S.NoticeDuration=30
S.Message="It smells like shit over here."
S.states=S.states or setmetatable({},{__mode="k"})
-- Notification history survives exposure/organism/no-poop resets.
S.nextNotices=S.nextNotices or setmetatable({},{__mode="k"})
-- Preserve an existing loaded notice deadline if this version is later hotloaded.
for p,state in pairs(S.states)do
    if (state.nextNotice or 0)>0 then
        S.nextNotices[p]=math.max(S.nextNotices[p] or 0,state.nextNotice-previousNoticeCooldown+S.NoticeCooldown)
    end
end
S.stats=S.stats or {notices=0,vomits=0,errors=0}
S.logged=S.logged or {}
local function finite(n)return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function accountID(p)return p:IsBot() and ("bot:"..p:UserID()) or p:SteamID64()end
local function playing(p)
    return IsValid(p) and p:IsPlayer() and p:Alive() and p:Team()<1000
        and p:GetObserverMode()==OBS_MODE_NONE
end
function S.Reset(p)S.states[p]=nil end
function S.ResetAll()S.states=setmetatable({},{__mode="k"})end
function S.Error(tag,err)
    S.stats.errors=S.stats.errors+1
    if S.logged[tag]then return end
    S.logged[tag]=true
    file.CreateDir("zc_poop")
    file.Append("zc_poop/odor_errors.txt",os.date("!%Y-%m-%dT%H:%M:%SZ").." "..tag.." "..tostring(err):sub(1,1000).."\n")
end
function S.Collect(C)
    local out,seen={},{}
    -- Ownership comes from the existing account ledger, never a client claim.
    for owner,state in pairs(C.accounts or {})do
        for _,ent in ipairs(state.poops or {})do
            if IsValid(ent) and C.owned[ent] and not seen[ent]then
                seen[ent]=true
                out[#out+1]={entity=ent,owner=owner,position=ent:WorldSpaceCenter()}
            end
        end
    end
    return out
end
function S.Near(p,body,id,entries)
    local origin=body:WorldSpaceCenter()
    local any,foreign=false,false
    for _,entry in ipairs(entries)do
        if IsValid(entry.entity) and origin:DistToSqr(entry.position)<=S.Radius*S.Radius then
            local tr=util.TraceLine({start=entry.position,endpos=origin,
                mask=MASK_SOLID_BRUSHONLY,filter={p,body,entry.entity}})
            if not tr.Hit and not tr.StartSolid and not tr.AllSolid then
                any=true
                if entry.owner~=id then foreign=true;break end
            end
        end
    end
    return any,foreign
end
function S.CanVomit(p,C)
    local org=p.organism
    if not hg or not hg.organism or type(hg.organism.Vomit)~="function"
        or type(hg.IsValidPlayer)~="function" or not hg.IsValidPlayer(p)
        or type(org)~="table" or org.alive==false or org.otrub
        or not finite(org.blood) or not finite(org.pulse)then return false end
    -- Do not feed a hidden Pill Pack carrier into human physiology.
    local P=ZCityPillCompat
    if P and ((P.spawning and P.spawning[p]) or (P.IsCarrier and P.IsCarrier(p)))then return false end
    if type(hg.GetCurrentCharacter)~="function"then return false end
    local character=hg.GetCurrentCharacter(p)
    if not IsValid(character)then return false end
    local bone=character:LookupBone("ValveBiped.Bip01_Head1")
    if bone==nil or bone<0 or not character:GetBoneMatrix(bone)then return false end
    local untilTime=p:GetNetVar("vomiting",0)
    if finite(untilTime) and untilTime>CurTime()then return false end
    return true
end
function S.Step(p,C,entries,now)
    if not playing(p)then S.Reset(p);return end
    local body=C.Body(p)
    local org=p.organism
    if not IsValid(body) or (org and (org.alive==false or org.otrub))then S.Reset(p);return end
    local id=accountID(p)
    if type(id)~="string" or id=="" or id=="0"then S.Reset(p);return end
    local s=S.states[p]
    if not s or s.org~=org then
        s={org=org,near=false,fired=false,nextNotice=0};S.states[p]=s
    end
    local near,foreign=S.Near(p,body,id,entries)
    if near and not s.near and now>=(S.nextNotices[p] or 0) and type(p.Notify)=="function"then
        S.nextNotices[p]=now+S.NoticeCooldown
        local ok,result=pcall(p.Notify,p,S.Message,S.NoticeDuration,"zc_poop_smell",0)
        if not ok then S.Error("notify",result)
        elseif result~=false then S.stats.notices=S.stats.notices+1 end
    end
    s.near=near
    local P=ZCityPillCompat
    local carrier=P and ((P.spawning and P.spawning[p]) or (P.IsCarrier and P.IsCarrier(p)))
    if not foreign or carrier then
        s.nextRoll=nil;s.fired=false;return
    end
    if s.fired then return end
    if not s.nextRoll or now>s.nextRoll+S.RollInterval*2 then
        s.nextRoll=now+S.RollInterval
    end
    if now<s.nextRoll then return end
    s.nextRoll=now+S.RollInterval
    if math.Rand(0,1)>=S.RollChance or not S.CanVomit(p,C)then return end
    s.fired=true
    local ok,err=pcall(hg.organism.Vomit,p)
    if ok then S.stats.vomits=S.stats.vomits+1 else S.Error("vomit",err)end
end
function S.Tick()
    local C=ZCityPoop
    if not C or type(C.Body)~="function" or type(C.owned)~="table"then S.ResetAll();return end
    local entries=S.Collect(C)
    if #entries==0 then S.ResetAll();return end
    local now=RealTime()
    for _,p in ipairs(player.GetAll())do
        local ok,err=pcall(S.Step,p,C,entries,now)
        if not ok then S.Reset(p);S.Error("step",err)end
    end
end
S.Callback=function()
    local ok,err=pcall(S.Tick)
    if not ok then S.ResetAll();S.Error("tick",err)end
end
timer.Create("ZCityPoop_Odor",S.Interval,0,S.Callback)
hook.Add("PlayerSpawn","ZCityPoop_OdorReset",S.Reset)
hook.Add("PlayerDeath","ZCityPoop_OdorReset",S.Reset)
hook.Add("PlayerSilentDeath","ZCityPoop_OdorReset",S.Reset)
hook.Add("PlayerDisconnected","ZCityPoop_OdorReset",S.Reset)
hook.Add("ZB_EndRound","ZCityPoop_OdorReset",S.ResetAll)
hook.Add("PostCleanupMap","ZCityPoop_OdorReset",S.ResetAll)

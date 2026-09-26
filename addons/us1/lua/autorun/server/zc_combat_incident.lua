-- Temporary bounded, server-private evidence. Never changes gameplay state.
if not SERVER then return end
ZCCombatIncident=ZCCombatIncident or {records={}}
local D=ZCCombatIncident
D.version="20260923.1"
local enabled=CreateConVar("zc_combat_incident_capture","1",FCVAR_ARCHIVE,"Capture bounded private combat regression evidence",0,1)
local previous=setmetatable({}, {__mode="k"})
local commands=setmetatable({}, {__mode="k"})
local commandAt=setmetatable({}, {__mode="k"})
local life=setmetatable({}, {__mode="k"})
local function number(n)
    if type(n)=="number" and n==n and math.abs(n)<math.huge then return n end
end
local function snapshot(p)
    local o=p.organism or {}
    local g=ZCityHostage and ZCityHostage.Gameplay
    local s=g and g.ByPlayer and g.ByPlayer[p]
    local f=ZCityFFBrain and ZCityFFBrain.states and ZCityFFBrain.states[p]
    local m=ZCityMetaSafety and ZCityMetaSafety.accounts and ZCityMetaSafety.accounts[p:SteamID64()]
    local w=p:GetActiveWeapon()
    return {id=p:SteamID64(),life=life[p] or 0,alive=p:Alive(),team=p:Team(),
        brain=number(o.brain),skull=number(o.skull),oxygen=o.o2 and number(o.o2[1]),
        unconscious=o.otrub==true,shakingUntil=number(o.start_shaking),karma=number(p.Karma),
        cuffNet=p:GetNetVar("handcuffed",false)==true,cuffBody=o.handcuffed==true,cuffEntity=p.handcuffed==true,
        role=p:GetNWString("zch_role",""),session=p:GetNWInt("zch_session",0),
        registeredSession=s and s.id or 0,sessionDone=s and s.done or false,
        stealthLocked=ZCityStealth and ZCityStealth.Locked(p)==true or false,
        sprinting=p:IsSprinting(),grounded=p:OnGround(),ragdolled=IsValid(p.FakeRagdoll),
        kickUntil=p:GetNWFloat("InLegKick",0),taunt=p:GetNWBool("TauntStopMoving",false),
        weapon=IsValid(w) and w:GetClass() or "",ffAdded=f and number(f.added),
        pendingBrain=m and number(m.ready),round=zb and zb.ROUND_START,roundState=zb and zb.ROUND_STATE}
end
function D.Record(kind,p,detail)
    if not enabled:GetBool() or not IsValid(p) or not p:IsPlayer() or p:IsBot() then return end
    local row=snapshot(p)
    row.kind=kind row.at=CurTime() row.utc=os.time() row.detail=detail
    local records=D.records
    if #records>=256 then table.remove(records,1) end
    records[#records+1]=row D.dirty=true
    return row
end
local function safe(fn,...)
    local ok,err=pcall(fn,...)
    if not ok and (D.errorAt or 0)<CurTime() then
        D.errorAt=CurTime()+30
        ErrorNoHalt("[Combat incident] Capture failed: "..tostring(err).."\n")
    end
end
local function sample(p)
    if not IsValid(p) or p:IsBot() then return end
    local o=p.organism
    if not o or not number(o.brain) then return end
    local old=previous[p]
    if not old or old.org~=o or math.abs(o.brain-old.brain)>=0.002
        or o.otrub~=old.unconscious or o.start_shaking~=old.shaking then
        D.Record("medical_state",p,{previousBrain=old and old.brain,newBody=not old or old.org~=o})
        previous[p]={org=o,brain=o.brain,unconscious=o.otrub,shaking=o.start_shaking}
    end
end
timer.Create("ZCCombatIncident.Sample",0.5,0,function()
    if not enabled:GetBool() then return end
    for _,p in ipairs(player.GetHumans()) do safe(sample,p) end
end)
-- Two observers compare commands around ordinary hooks; neither mutates cmd.
hook.Add("StartCommand","ZCCombatIncident.Before",function(p,cmd)
    if enabled:GetBool() and IsValid(p) and not p:IsBot() then commands[p]=cmd:GetButtons() end
end,-2)
hook.Add("StartCommand","ZCCombatIncident.After",function(p,cmd)
    local before=commands[p] commands[p]=nil
    if not enabled:GetBool() or not before or not IsValid(p) then return end
    local after=cmd:GetButtons()
    local attack=bit.band(before,IN_ATTACK+IN_ATTACK2)~=0
    local changed=before~=after
    if (attack or changed) and (commandAt[p] or 0)<=CurTime() then
        commandAt[p]=CurTime()+2
        safe(D.Record,"command_state",p,{before=before,after=after,forward=cmd:GetForwardMove(),side=cmd:GetSideMove()})
    end
end,2)
hook.Add("PlayerSpawn","ZCCombatIncident.Spawn",function(p)
    life[p]=(life[p] or 0)+1 previous[p]=nil commands[p]=nil commandAt[p]=nil
    timer.Simple(0,function() if IsValid(p) then safe(D.Record,"spawn",p) end end)
end)
hook.Add("PlayerDisconnected","ZCCombatIncident.Leave",function(p)
    safe(D.Record,"disconnect",p)
    previous[p]=nil commands[p]=nil commandAt[p]=nil life[p]=nil
end)
local function save()
    if not D.dirty then return end
    local data=util.TableToJSON({version=D.version,map=game.GetMap(),records=D.records})
    if not data then return end
    file.CreateDir("zc_combat_incident")
    file.Write("zc_combat_incident/latest.json",data)
    D.dirty=nil
end
timer.Create("ZCCombatIncident.Save",30,0,function() safe(save) end)
hook.Add("ShutDown","ZCCombatIncident.Save",function() safe(save) end)
concommand.Add("zc_combat_incident_dump",function(p)
    if IsValid(p) then return end -- server console only; private state is not networked.
    for _,human in ipairs(player.GetHumans()) do safe(D.Record,"manual_snapshot",human) end
    safe(save)
end, nil, "Server console: snapshot every human's combat state and save the incident file.")

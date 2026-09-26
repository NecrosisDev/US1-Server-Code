local G=ZCityHostage.Gameplay
local I=ZCityInteractions

function G.ControlWeapon(p,kind)
    if not IsValid(p) then return end
    local choices={}
    for _,w in ipairs(p:GetWeapons()) do
        local profile=I.WeaponProfile(w)
        if profile and profile.kind==kind and w:GetOwner()==p then choices[#choices+1]=w end
    end
    table.sort(choices,function(a,b)
        if a:GetClass()==b:GetClass() then return a:EntIndex()<b:EntIndex() end
        return a:GetClass()<b:GetClass()
    end)
    return choices[1]
end
function G.ControlKnife(p) return G.ControlWeapon(p,"knife") end
function G.ControlWire(p) return G.ControlWeapon(p,"wire") end
function G.WireHandoffStatus(p,w)
    local s=G.ByPlayer[p]
    if not s or s.a~=p or s.phase~="hold" then return false,"Establish a hostage hold first" end
    return I.CanWireHandoff(p,s.v,s,w)
end

function G.KnifeHandoffStatus(p,w,preview)
    local s=G.ByPlayer[p]
    if not s or s.a~=p or s.phase~="hold" then return false,"Establish a hostage hold first" end
    local stealth=ZCityStealth
    if not stealth or not stealth.CanHostageHandoff then return false,"Stealth integration is unavailable" end
    return stealth.CanHostageHandoff(p,s.v,s,w,preview)
end

function G.HandoffSwitchAllowed(p,w)
    local s=G.ByPlayer[p]
    return s and not s.done and s.a==p and s.phase=="handoff" and s.handoff
        and s.handoff.selecting and s.handoff.weapon==w and IsValid(w) and w:GetOwner()==p
end

local function startHandoff(p,equipment,kind)
    local w=equipment or G.ControlWeapon(p,kind)
    local status=kind=="wire" and G.WireHandoffStatus or G.KnifeHandoffStatus
    local ok,why=status(p,w)
    if not ok then return false,why end
    local s=G.ByPlayer[p]
    local previousStart=s.start
    local h={kind=kind,weapon=w,previous=s.weapons[p],readyAt=CurTime()+.4,deadline=CurTime()+2,selecting=true}
    s.handoff=h s.phase="handoff" s.start=CurTime() s.deadline=nil
    G.PublishHandoff(s)
    local called,err=pcall(p.SelectWeapon,p,w:GetClass())
    h.selecting=nil
    if s.done then return false,"Handoff interrupted" end
    if not called or p:GetActiveWeapon()~=w then
        if p:GetActiveWeapon()==h.previous then
            s.handoff=nil s.phase="hold" s.start=previousStart
            G.PublishHandoff(s)
        else G.End(s,"Weapon switch interrupted the hold") end
        if not called then ErrorNoHalt("[Interactions] Weapon selection failed: "..tostring(err).."\n") end
        return false,"Weapon switch was refused"
    end
    s.weapons[p]=w
    return true
end
function G.StartKnifeHandoff(p,equipment) return startHandoff(p,equipment,"knife") end
function G.StartWireHandoff(p,equipment) return startHandoff(p,equipment,"wire") end

function G.StepControlHandoff(s)
    local h=s.handoff local stealth=ZCityStealth
    local intent=h and h.kind=="wire" and "fiberwire" or "interrogate"
    if not h or not IsValid(h.weapon) or h.weapon:GetOwner()~=s.a or s.a:GetActiveWeapon()~=h.weapon
        or not I.HandsAvailable(s.a) or not stealth or not I.PolicyAllowed(s.a,intent,s.v) then
        G.End(s,"Weapon handoff interrupted") return
    end
    if CurTime()>=h.deadline then G.End(s,"Weapon was not ready; hold released") return end
    if CurTime()<h.readyAt or not stealth.Armed(s.a,stealth.Actions[intent]) then return end
    local ok,why
    if h.kind=="wire" then ok,why=I.StartWire(s.a,s.v,s)
    else ok,why=stealth.Begin(s.a,s.v,"interrogate",s) end
    if not ok and not s.done then G.End(s,why or "Weapon handoff interrupted") end
end

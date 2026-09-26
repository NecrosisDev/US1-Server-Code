-- Context-menu adapter to the installed ZCity Gore V2 torso transition.
-- No independent crawler physiology, ragdoll renderer, or maintenance loop.
if not SERVER then return end
local M=ZCMakeCrawler or {}
ZCMakeCrawler=M
M.Version="20260920.recovery3-admin1"
-- Admin rollout after the first consenting client validated both recovery actions.
M.TrialSteamID64="admin"
function M.IsTrialAdmin(ply)
    return IsValid(ply) and ply:IsPlayer() and ply:IsAdmin() and (M.TrialSteamID64=="admin" or ply:SteamID64()==M.TrialSteamID64)
end
M.ready=M.ready or setmetatable({},{__mode="k"})
M.stats=M.stats or {applied=0,clients=0,errors=0}
M.logged=M.logged or {}
AddCSLuaFile("autorun/client/cl_make_crawler.lua")
util.AddNetworkString("ZCMakeCrawler_Apply")
util.AddNetworkString("ZCMakeCrawler_Ready")
util.AddNetworkString("ZCMakeCrawler_ReturnLegs")
util.AddNetworkString("ZCMakeCrawler_TrialReady")

-- Retire only this button's obsolete parallel implementation on hot reload.
-- Removed timers can have one last queued callback; it must be inert.
local function retiredStabilize() return false end
M.Stabilize=retiredStabilize;M.RetiredStabilize=retiredStabilize;M.SyncOrganism=nil
-- Retire old anonymous delayed callbacks without touching an entity.
function M.ApplyGoreToRagdoll() return true,"retired" end
hook.Remove("Fake","ZCMakeCrawler_FlagRagdoll")
hook.Remove("PostPlayerDeath","ZCMakeCrawler_DeathRagdoll")
hook.Remove("PlayerSpawn","ZCMakeCrawler_Reset")
hook.Remove("PlayerInitialSpawn","ZCMakeCrawler_Client")
for _,p in player.Iterator() do
    timer.Remove("ZCMakeCrawler_Stabilize_"..p:EntIndex())
end
-- Existing delayed delivery closures may still call this; client code is unchanged.
function M.SendClient() return false end

function M.ResolvePlayer(ent)
    if not IsValid(ent) then return end
    if ent:IsPlayer() then return ent end
    if not ent:IsRagdoll() then return end
    -- A resurrected body can still carry its former owner's .ply pointer.
    -- Only a currently controlled body identifies a live recovery target.
    local owner=ent:GetNWEntity("ply")
    if IsValid(owner) and owner:IsPlayer() and owner.FakeRagdoll==ent then return owner end
    for _,p in player.Iterator() do
        if p.FakeRagdoll==ent then return p end
    end

end

function M.Error(tag,err)
    M.stats.errors=(M.stats.errors or 0)+1
    if M.logged[tag] then return end
    M.logged[tag]=true
    file.CreateDir("zc_make_crawler")
    file.Append("zc_make_crawler/errors.txt",os.date("!%Y-%m-%dT%H:%M:%SZ").." "..tag.." "..tostring(err):sub(1,1000).."\n")
end

-- A button transition has no lasting damage exemption. Restore only the medical
-- changes made synchronously by native torso amputation; subsequent hits are normal.
local traumaFields={"blood","bleed","internalBleed","pain","avgpain","painadd","shock","adrenaline","adrenalineAdd"}
function M.CaptureTrauma(ply)
    local org=ply.organism
    local before={values={},wounds=table.Copy(org.wounds or {}),arterialwounds=table.Copy(org.arterialwounds or {})}
    for _,key in ipairs(traumaFields) do before.values[key]=org[key] end
    return before
end
function M.RestoreTrauma(ply,before)
    local org=ply.organism
    for _,key in ipairs(traumaFields) do org[key]=before.values[key] end
    org.wounds=before.wounds;org.arterialwounds=before.arterialwounds
    ply:SetNetVar("wounds",org.wounds);ply:SetNetVar("arterialwounds",org.arterialwounds)
    timer.Remove("ZCity Gore V2_PainPhrases_"..ply:EntIndex())
    ply.fullsend=true
    if hg.send_organism then hg.send_organism(org) end
end

M.pendingReset=setmetatable({},{__mode="k"}) -- Invalidate the old delayed full-body reset.
M.restoring=M.restoring or setmetatable({},{__mode="k"})
M.life=M.life or setmetatable({},{__mode="k"})
local function living(ply)
    return IsValid(ply) and ply:IsPlayer() and ply:Alive() and type(ply.organism)=="table"
end
function M.IsCrawler(ply)
    if not living(ply) then return false end
    local rag=ply.FakeRagdoll
    return ply:GetNWBool("ZCityTorsoSevered",false) or ply.organism.torsoamputated==true
        or (IsValid(rag) and not rag:IsMarkedForDeletion() and rag:GetNWBool("ZCityTorsoSevered",false))
end
local function removing(ent)
    return not IsValid(ent) or ent:IsMarkedForDeletion()
end
local function sync(ply)
    ply.fullsend=true
    if hg.send_organism then hg.send_organism(ply.organism) end
end
local function stopPain(ply)
    timer.Remove("ZCity Gore V2_PainPhrases_"..ply:EntIndex())
end
local function invalidateLife(ply)
    M.life[ply]=(M.life[ply] or 0)+1
end
hook.Add("PlayerDeath","ZCMakeCrawler_Life",invalidateLife)
hook.Add("PlayerSilentDeath","ZCMakeCrawler_Life",invalidateLife)
hook.Add("PlayerSpawn","ZCMakeCrawler_Life",function(ply)
    if not M.restoring[ply] then invalidateLife(ply) end
end)

-- Only the existing Reset organism property is medical recovery. Keep ordinary
-- spawn/death clears free to reset anatomy for a new life.
hook.Add("Org Clear","ZCMakeCrawler_ResetOrganism",function(org)
    if type(org)~="table" then return end
    local ply=org.owner
    if M.medicalReset and M.IsCrawler(ply) and not M.restoring[ply] then
        M.medicalReset[org]=M.medicalReset[org] or {ply=ply,rag=ply.FakeRagdoll,life=M.life[ply] or 0}
    else
        org.torsoamputated=false -- Not a base-organism field.
    end
end)

function M.MedicalReset(receive,...)
    local previous=M.medicalReset
    local context={}
    M.medicalReset=context
    local result={pcall(receive,...)}
    M.medicalReset=previous
    -- Run after ALL native clear hooks, independent of hook iteration order.
    for org,state in pairs(context) do
        local ply=state.ply
        if living(ply) and ply.organism==org and ply.FakeRagdoll==state.rag
            and (M.life[ply] or 0)==state.life and not removing(state.rag) then
            org.torsoamputated=true;org.llegamputated=true;org.rlegamputated=true
            org.needfake=true
            ply:SetNWBool("ZCityTorsoSevered",true)
            stopPain(ply)
            sync(ply)
        end
    end
    if not result[1] then error(result[2],0) end
    return unpack(result,2)
end

function M.BindResetProperty()
    local property=properties and properties.List and properties.List.reset_org
    if not property or type(property.Receive)~="function" then return false end
    if type(property.Filter)~="function" then return false end
    if property.Filter~=M.resetFilter then
        local originalFilter=property.Filter
        M.resetFilter=function(self,target,actor)
            if M.IsCrawler(M.ResolvePlayer(target)) and not M.IsTrialAdmin(actor) then return false end
            return originalFilter(self,target,actor)
        end
        property.Filter=M.resetFilter
    end
    if property.Receive==M.resetReceive then return true end
    local original=property.Receive
    M.resetReceive=function(...) return M.MedicalReset(original,...) end
    property.Receive=M.resetReceive -- Retain native permission/filter/net handling.
    return true
end
local function bindReset()
    if M.BindResetProperty() then timer.Remove("ZCMakeCrawler_BindReset") end
end
hook.Add("InitPostEntity","ZCMakeCrawler_BindReset",function() bindReset() end)
hook.Add("OnReloaded","ZCMakeCrawler_BindReset",function() bindReset() end)
timer.Create("ZCMakeCrawler_BindReset",1,30,bindReset)
bindReset()

local function finite(v)
    return isvector(v) and v.x==v.x and v.y==v.y and v.z==v.z
        and math.abs(v.x)<1000000 and math.abs(v.y)<1000000 and math.abs(v.z)<1000000
end
function M.RestoreBody(ply)
    if not M.IsCrawler(ply) then return false,"not_a_living_crawler" end
    if M.restoring[ply] or OverrideSpawn then return false,"recovery_busy" end
    local rag,lower=ply.FakeRagdoll,ply.__zcGoreLowerTorso
    local org,life=ply.organism,M.life[ply] or 0
    if ply:InVehicle() then return false,"leave_vehicle_first" end
    if not hg or not hg.organism or type(hg.organism.Clear)~="function" then return false,"medical_api_missing" end
    if IsValid(rag) then
        if removing(rag) then return false,"body_removal_pending" end
        if type(hg.FakeUp)~="function" then return false,"recovery_api_missing" end
        local bone=rag:LookupBone("ValveBiped.Bip01_Pelvis")
        local matrix=bone and bone>=0 and rag:GetBoneMatrix(bone)
        if not matrix or not finite(matrix:GetTranslation()) then return false,"invalid_body_pose" end
        local overrideBefore=OverrideSpawn
        M.restoring[ply]=true
        local ok,result=pcall(hg.FakeUp,ply,true,true)
        M.restoring[ply]=nil
        OverrideSpawn=overrideBefore
        if not ok then
            M.Error("return_recovery",result);return false,"recovery_error"
        end
        if not living(ply) or ply.organism~=org or (M.life[ply] or 0)~=life then return false,"target_changed_during_recovery" end
        -- Entity:Remove keeps a valid entity until the NEXT tick. Native FakeUp
        -- must have released both live-body slots and retired the old ragdoll.
        if result~=true or not removing(rag) or IsValid(ply.FakeRagdoll)
            or (hg.ragdollFake and IsValid(hg.ragdollFake[ply])) then return false,"recovery_incomplete" end
    elseif hg.ragdollFake and IsValid(hg.ragdollFake[ply]) then
        return false,"body_state_mismatch"
    end
    ply:SetNWBool("ZCityTorsoSevered",false)
    ply:SetNWBool("zc_make_crawler",false)
    ply.__zcGoreTorsoPending=nil;ply.__zcGoreBlastQueued=nil
    ply.__zcGoreLowerTorso=nil;ply.__zcGoreLastInitialPhrase=nil;ply.__zcGoreLastPainPhrase=nil
    org.torsoamputated=false;org.llegamputated=false;org.rlegamputated=false;org.needfake=false
    stopPain(ply)
    if IsValid(lower) and lower:GetNWBool("ZCityTorsoLowerPart",false) then lower:Remove() end
    -- Native body removal owns caps/intestines; do not independently rebuild bones.
    hg.organism.Clear(org)
    org.needfake=false
    sync(ply)
    M.stats.resets=(M.stats.resets or 0)+1
    return true
end

net.Receive("ZCMakeCrawler_ReturnLegs",function(bits,actor)
    if not M.IsTrialAdmin(actor) or bits<1 or bits>64 then return end
    if (actor.ZCMakeCrawlerReturnNext or 0)>CurTime() then return end
    actor.ZCMakeCrawlerReturnNext=CurTime()+0.5
    local target=net.ReadEntity()
    local property=properties and properties.List and properties.List.reset_org
    local victim=M.ResolvePlayer(target)
    if not M.IsCrawler(victim) or (target~=victim and target~=victim.FakeRagdoll) then return end
    -- Check permission against the resolved living player, not a stale corpse owner.
    if not property or type(property.Filter)~="function" or not property:Filter(victim,actor) then return end
    local ok,why=M.RestoreBody(victim)
    if ok then
        actor:ChatPrint("[MakeCrawler] Legs returned and organism fully healed.")
        print("[MakeCrawler] "..actor:Nick().." returned legs to "..victim:Nick())
    else
        actor:ChatPrint("[MakeCrawler] Could not return legs: "..tostring(why)..".")
    end
end)

function M.Apply(victim,byName)
    if not IsValid(victim) or not victim:IsPlayer() or not victim:Alive() or type(victim.organism)~="table" then
        return false,"invalid_target"
    end
    if M.pendingReset[victim] then return false,"organism_reset_pending" end
    if victim:GetNWBool("ZCityTorsoSevered",false) or victim.organism.torsoamputated then return true,"already" end
    if victim.__zcGoreTorsoPending then return false,"native_transition_pending" end
    local native=hg and hg.ZCityGore_AmputateTorso
    if type(native)~="function" then return false,"native_torso_api_missing" end
    -- Same transition as native blast dismemberment, without spawning an explosion.
    -- It owns fake creation, split bodies/caps, physics maps, trauma and replication.
    local before=M.CaptureTrauma(victim)
    local ok,applied=pcall(native,victim,vector_origin,true)
    if not ok then M.Error("native_torso",applied);return false,"native_torso_error" end
    if applied~=true then return false,"native_torso_rejected" end
    if not victim:GetNWBool("ZCityTorsoSevered",false) or victim.organism.torsoamputated~=true then
        M.Error("native_state","native routine returned without torso state");return false,"native_state_incomplete"
    end
    M.RestoreTrauma(victim,before)
    M.stats.applied=(M.stats.applied or 0)+1
    print("[MakeCrawler] "..tostring(byName or "?").." used native torso amputation on "..victim:Nick())
    return true
end

net.Receive("ZCMakeCrawler_Apply",function(bits,ply)
    if not IsValid(ply) or not ply:IsPlayer() or not (ply:IsAdmin() or ply:IsSuperAdmin()) then return end
    if bits<1 or bits>64 or (ply.ZCMakeCrawlerNext or 0)>CurTime() then return end
    ply.ZCMakeCrawlerNext=CurTime()+0.5
    local target=net.ReadEntity()
    local victim=M.ResolvePlayer(target)
    if not IsValid(victim) or victim==ply then return end
    if target~=victim and target~=victim.FakeRagdoll then
        local current=hg and hg.GetCurrentCharacter and hg.GetCurrentCharacter(victim)
        if current~=target then ply:ChatPrint("[MakeCrawler] Target is not the current living body.");return end
    end
    local ok,why=M.Apply(victim,ply:Nick().." (context menu)")
    if ok then
        ply:ChatPrint(why=="already" and "[MakeCrawler] Target already has native torso amputation." or "[MakeCrawler] Native torso amputation applied.")
    else
        ply:ChatPrint("[MakeCrawler] Could not transform target: "..tostring(why))
    end
end)
net.Receive("ZCMakeCrawler_Ready",function(bits,p)
    if not IsValid(p) or bits>8 or M.ready[p] then return end
    M.ready[p]=true;M.stats.clients=(M.stats.clients or 0)+1
end)
print("[MakeCrawler] Loaded "..M.Version.." (native torso adapter)")

net.Receive("ZCMakeCrawler_TrialReady",function(bits,ply)
    if not M.IsTrialAdmin(ply) or bits>256 then return end
    local version=net.ReadString()
    if version~=M.Version then return end
    M.trialReady=M.trialReady or setmetatable({},{__mode="k"})
    local previous=M.trialReady[ply]
    if previous and previous.userID==ply:UserID() and previous.version==version then return end
    M.trialReady[ply]={userID=ply:UserID(),version=version}
    M.trialReadyUserID=ply:UserID();M.trialReadyVersion=version
    print("[MakeCrawler] Trial client registered "..version.." "..ply:SteamID64().." userid="..ply:UserID())
end)

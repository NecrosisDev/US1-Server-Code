-- Context-menu adapter to the installed ZCity Gore V2 torso transition.
-- No independent crawler physiology, ragdoll renderer, or maintenance loop.
if not SERVER then return end
local M=ZCMakeCrawler or {}
ZCMakeCrawler=M
M.Version="20260919.native2"
M.ready=M.ready or setmetatable({},{__mode="k"})
M.stats=M.stats or {applied=0,clients=0,errors=0}
M.logged=M.logged or {}
AddCSLuaFile("autorun/client/cl_make_crawler.lua")
util.AddNetworkString("ZCMakeCrawler_Apply")
util.AddNetworkString("ZCMakeCrawler_Ready")

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
    local owner=ent.ply
    if not IsValid(owner) and hg and type(hg.RagdollOwner)=="function" then owner=hg.RagdollOwner(ent) end
    if not IsValid(owner) then owner=ent:GetNWEntity("ply") end
    if IsValid(owner) and owner:IsPlayer() then return owner end
    for _,p in player.Iterator() do
        if p:GetRagdollEntity()==ent or p.FakeRagdoll==ent then return p end
    end
end

function M.Error(tag,err)
    M.stats.errors=(M.stats.errors or 0)+1
    if M.logged[tag] then return end
    M.logged[tag]=true
    file.CreateDir("zc_make_crawler")
    file.Append("zc_make_crawler/errors.txt",os.date("!%Y-%m-%dT%H:%M:%SZ").." "..tag.." "..tostring(err):sub(1,1000).."\n")
end

function M.Apply(victim,byName)
    if not IsValid(victim) or not victim:IsPlayer() or not victim:Alive() or type(victim.organism)~="table" then
        return false,"invalid_target"
    end
    if victim:GetNWBool("ZCityTorsoSevered",false) or victim.organism.torsoamputated then return true,"already" end
    if victim.__zcGoreTorsoPending then return false,"native_transition_pending" end
    local native=hg and hg.ZCityGore_AmputateTorso
    if type(native)~="function" then return false,"native_torso_api_missing" end
    -- Same transition as native blast dismemberment, without spawning an explosion.
    -- It owns fake creation, split bodies/caps, physics maps, trauma and replication.
    local ok,applied=pcall(native,victim,vector_origin,true)
    if not ok then M.Error("native_torso",applied);return false,"native_torso_error" end
    if applied~=true then return false,"native_torso_rejected" end
    if not victim:GetNWBool("ZCityTorsoSevered",false) or victim.organism.torsoamputated~=true then
        M.Error("native_state","native routine returned without torso state");return false,"native_state_incomplete"
    end
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

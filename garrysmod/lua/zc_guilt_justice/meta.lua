-- Server-only privacy boundary: never publish a current hidden-round consequence.
if not SERVER then return end
ZCityMetaSafety=ZCityMetaSafety or {}
local M=ZCityMetaSafety
M.Version="20260916.2"
M.boot=M.boot or (tostring(os.time())..":"..util.CRC(tostring(SysTime())))
local path="zc_guilt_justice/meta_state.txt"
local function finite(n)return isnumber(n) and n==n and math.abs(n)<math.huge end
local function isPlayer(p)return IsValid(p) and p:IsPlayer() end
local lossEnabled=CreateConVar("zc_karma_loss_enabled","0",FCVAR_ARCHIVE,
    "Allow karma deductions (0 blocks immediate and deferred losses; gains remain enabled)",0,1)
M.LossControlVersion="20260923.loss1"
function M.LossEnabled()return lossEnabled:GetBool() end
function M.LossDelta(delta)
    if delta<0 and not M.LossEnabled() then return 0 end
    return delta
end
function M.ID(p)return isPlayer(p) and (p:IsBot() and "bot:"..p:UserID() or p:SteamID64()) end
function M.Round()return M.boot..":"..ZCityKarmaBounties.RoundKey() end
function M.Hidden()
    local mode=isfunction(CurrentRound) and CurrentRound()
    return mode and ZCityKarmaBounties.Kind(mode)=="homicide" or false
end
function M.Locked()
    return not M.releasing and zb and zb.ROUND_STATE~=nil and zb.ROUND_STATE~=3 and M.Hidden()
end
if not M.accounts then
    local raw=file.Read(path,"DATA")
    local data=raw and util.JSONToTable(raw,false,true)
    M.accounts=istable(data) and data.version==1 and istable(data.accounts) and data.accounts or {}
    M.loadError=raw~=nil and not (istable(data) and data.version==1 and istable(data.accounts))
end
function M.Save()
    if M.loadError then return false end
    local raw=util.TableToJSON({version=1,accounts=M.accounts},true)
    if not raw or #raw>2097152 then return false end
    file.CreateDir("zc_guilt_justice")
    local old=file.Read(path,"DATA")
    if old then file.Write("zc_guilt_justice/meta_state_backup.txt",old) end
    file.Write(path,raw)
    local ok=file.Read(path,"DATA")==raw
    if ok then M.dirty=false end
    return ok
end
for id,r in pairs(M.accounts) do
    if not isstring(id) or not istable(r) or not isstring(r.round)
        or not finite(r.public) or not finite(r.balance) or not finite(r.brain or 0)
        or not finite(r.ready or 0) or r.balance < -60 or r.balance > 120
        or (r.status~="pending" and r.status~="reserved" and r.status~="done" and r.status~="review") then
        M.loadError=true;break
    end
end
function M.Commit(p,r)
    if not isPlayer(p) or not r or r.status=="done" or r.status=="review" then return end
    if ZCityGuiltJustice.loading[p] then return end
    if r.status=="reserved" then
        r.status="review";M.dirty=true;M.Save()
        ZCityGuiltJustice.Log("refund_requires_review",{account=M.ID(p),transaction="deferred-round"})
        return -- An interrupted persistence commit is never replayed blindly.
    end
    local before=finite(p.Karma) and p.Karma or r.public
    local after=math.Clamp(before+M.LossDelta(r.balance-r.public),-60,zb.MaxKarma or 120)
    r.status="reserved";r.before=before;r.after=after
    if not M.Save() then r.status="pending";return end
    local prior=M.releasing;M.releasing=true
    local ok,err=pcall(function()
        p.Karma=after;p:SetNetVar("Karma",after)
        if p.guilt_SetValue then p:guilt_SetValue(after) end
    end)
    M.releasing=prior
    if not ok then error(err,0) end
    r.ready=math.min(0.10,(r.ready or 0)+(r.brain or 0));r.readyAfter=r.round
    r.brain=0;r.status="done";r.public=after;r.balance=after;M.dirty=true
    ZCityGuiltJustice.Log("bounty_settlement",{account=M.ID(p),round=r.round,adjustment=after-before})
    M.Save()
    if (after<=0 or r.banMinutes) and not p:IsAdmin() and not p:IsSuperAdmin() then
        local minutes=r.banMinutes or 60;r.banMinutes=nil
        local reset=after+M.LossDelta(10-after)
        p.Karma=reset;p:SetNetVar("Karma",reset);p:guilt_SetValue(reset)
        r.public=reset;r.balance=reset;M.Save()
        if ULib and ULib.addBan then ULib.addBan(p:SteamID(),minutes,"Karma limit reached.",p:Nick(),"System") end
    end
end
-- Lazy persistence for balance drift only. Write-ahead saves (M.Commit, M.CommitBatch,
-- M.ApplyCarry), PlayerDisconnected and ShutDown still save immediately, so a crash can
-- lose at most LAZY_SAVE seconds of unsettled balance changes (owner accepted 10 s).
-- PROVISIONAL(2026-09-21, whole-file save is 12-22 ms so it cannot run every second;
-- replace with an append journal, ratify-by: 2026-10-19)
local LAZY_SAVE=10
function M.LazySave()
    if not M.dirty or (M.nextLazySave or 0)>SysTime() then return end
    M.nextLazySave=SysTime()+LAZY_SAVE
    return M.Save()
end
-- Drop records that carry nothing: from an earlier boot, settled or never changed, no queued
-- dose, no carry, no pending ban. M.Account rebuilds the same record on the next visit.
-- Online players are skipped so M.Change/M.Balance never see a record vanish under them.
function M.Prune()
    if M.loadError then return 0 end
    local online,prefix,n={},M.boot..":",0
    for _,p in ipairs(player.GetAll()) do online[M.ID(p) or ""]=true end
    for id,r in pairs(M.accounts) do
        if not online[id] and (r.status=="done" or r.status=="pending")
            and string.sub(r.round,1,#prefix)~=prefix and r.balance==r.public
            and (r.ready or 0)<=0 and (r.brain or 0)<=0 and not r.banMinutes then
            M.accounts[id]=nil;n=n+1
        end
    end
    if n>0 then M.dirty=true end
    return n
end
-- Round-end settlement for many accounts in two whole-file saves instead of two per
-- account. The write-ahead order is M.Commit's: every account is on disk as "reserved"
-- before any karma is touched and "done" only after, so an interruption still leaves
-- "reserved" records that go to review and are never replayed. Runs inside one frame on
-- purpose: a "reserved" record seen by M.Loaded/M.Account on a later tick would be sent
-- to review.
-- PROVISIONAL(2026-09-21, M.Save rewrites the whole accounts file - 2 writes + 2 reads -
-- so even this is over the 2 ms budget; replace with an append journal, ratify-by: 2026-10-19)
function M.CommitBatch(list)
    local batch={}
    for _,e in ipairs(list) do
        local p,r=e[1],e[2]
        if isPlayer(p) and r and r.status=="pending" and not ZCityGuiltJustice.loading[p] then
            local before=finite(p.Karma) and p.Karma or r.public
            r.before=before;r.after=math.Clamp(before+M.LossDelta(r.balance-r.public),-60,zb.MaxKarma or 120)
            r.status="reserved";batch[#batch+1]=e
        end
    end
    if #batch==0 then return end
    if not M.Save() then
        for _,e in ipairs(batch) do e[2].status="pending" end
        return
    end
    local prior,settled,failed=M.releasing,{},nil
    M.releasing=true
    for _,e in ipairs(batch) do
        local p,after=e[1],e[2].after
        local ok,err=pcall(function()
            p.Karma=after;p:SetNetVar("Karma",after)
            if p.guilt_SetValue then p:guilt_SetValue(after) end
        end)
        -- A failed apply stays "reserved" (review on next touch), exactly as in M.Commit,
        -- but no longer stops the other accounts from settling.
        if ok then settled[#settled+1]=e else failed=failed or err end
    end
    M.releasing=prior
    for _,e in ipairs(settled) do
        local r=e[2];local after=r.after
        r.ready=math.min(0.10,(r.ready or 0)+(r.brain or 0));r.readyAfter=r.round
        r.brain=0;r.status="done";r.public=after;r.balance=after
    end
    M.dirty=true
    for _,e in ipairs(settled) do
        local r=e[2]
        ZCityGuiltJustice.Log("bounty_settlement",{account=M.ID(e[1]),round=r.round,adjustment=r.after-r.before})
    end
    M.Save()
    local bans={}
    for _,e in ipairs(settled) do
        local p,r=e[1],e[2]
        if (r.after<=0 or r.banMinutes) and not p:IsAdmin() and not p:IsSuperAdmin() then
            local minutes=r.banMinutes or 60;r.banMinutes=nil
            local reset=r.after+M.LossDelta(10-r.after)
            p.Karma=reset;p:SetNetVar("Karma",reset);p:guilt_SetValue(reset)
            r.public=reset;r.balance=reset
            bans[#bans+1]={p:SteamID(),minutes,p:Nick()}
        end
    end
    if #bans>0 then
        M.Save()
        if ULib and ULib.addBan then
            for _,b in ipairs(bans) do ULib.addBan(b[1],b[2],"Karma limit reached.",b[3],"System") end
        end
    end
    if failed then error(failed,0) end
end
function M.Account(p)
    local id=M.ID(p);if not id then return end
    local r=M.accounts[id];local round=M.Round()
    if r and r.round~=round and r.status=="pending" then
        M.Commit(p,r)
        if r.status=="pending" then return r end
    end
    if r and (r.status=="reserved" or r.status=="review") then return r end
    if not r or r.round~=round or (r.status=="done" and M.Locked()) then
        local value=finite(p.Karma) and p.Karma or 100
        local ready,origin=r and r.ready or 0,r and r.readyAfter
        r={round=round,public=value,balance=value,brain=0,ready=ready,readyAfter=origin,brainDoseVersion=2,status="pending",initialized=finite(p.Karma)}
        M.accounts[id]=r;M.dirty=true
    end
    return r
end
function M.Public(p)
    if not isPlayer(p) then return end
    if M.Locked() then
        local r=M.Account(p)
        -- A prior-round/boot transaction may await loading, persistence or review.
        -- Keep that transaction intact, but never use its old public snapshot to
        -- apply current-life penalties against a newly loaded player score.
        if r and r.round==M.Round() then return r.public end
    end
    return p.Karma
end
function M.Balance(p)
    local r=M.accounts[M.ID(p) or ""]
    if M.Locked() then r=M.Account(p) end
    if r and r.status~="done" then return r.balance end
end
function M.Change(p,delta)
    if finite(delta) and delta<0 and not M.LossEnabled() then return true,0 end
    local r=M.accounts[M.ID(p) or ""]
    if M.Locked() then r=M.Account(p) end
    if not r or (r.status=="done" and not M.Locked()) then return false end
    if M.loadError or r.status=="reserved" or r.status=="review" then return true,0 end
    if not finite(delta) then return true,0 end
    local before=r.balance;r.balance=math.Clamp(before+delta,-60,zb.MaxKarma or 120)
    M.dirty=true
    return true,r.balance-before
end
function M.QueueBrain(p,amount)
    local r=M.Account(p)
    if not r or not finite(amount) or amount<=0 or M.loadError then return 0 end
    local add=math.min(amount,math.max(0,0.10-(r.brain or 0)))
    r.brain=(r.brain or 0)+add;M.dirty=true;return add
end
function M.BanLater(p,minutes)
    local r=M.Account(p)
    if r then r.banMinutes=math.max(r.banMinutes or 0,minutes);M.dirty=true end
end
function M.Loaded(p)
    if not isPlayer(p) then return end
    ZCityGuiltJustice.loading[p]=nil
    local r=M.accounts[M.ID(p)]
    if r and r.initialized==false and finite(p.Karma) then
        r.balance=math.Clamp(p.Karma+r.balance-r.public,-60,zb.MaxKarma);r.public=p.Karma;r.initialized=true
    end
    if r and r.round==M.Round() and r.status=="pending" and M.Locked() then p.Karma=r.public
    elseif r and r.status~="done" then M.Commit(p,r) end
    if M.Locked() then M.Account(p) end
end
function M.Finish()
    -- The gamemode has already ended the round and sent its reveal before this hook.
    if M.Locked() then return end
    for _,life in pairs(ZCityGuiltJustice.cases) do
        if life.dead and not life.ready and not life.failed then ZCityGuiltJustice.Flush(life) end
        if life.metaHeld then life.metaHeld=nil;life.expires=CurTime()+45 end
    end
    local pending={}
    for _,p in ipairs(player.GetAll()) do
        local r=M.accounts[M.ID(p)]
        if r and r.status=="pending" then pending[#pending+1]={p,r} end
    end
    M.CommitBatch(pending)
    M.LazySave()
end
function M.ApplyCarry(p)
    local r=M.accounts[M.ID(p) or ""]
    if not r or (r.ready or 0)<=0 or r.readyAfter==M.Round() then return end
    if not zb or zb.ROUND_STATE~=1 or not p:Alive() or p:Team()>=1000 then return end
    if (p.ZCMetaSpawnReady or 0)>CurTime() then return end
    if ZCityPillCompat and IsValid(ZCityPillCompat.Morph(p)) then return end
    local F=ZCityFFBrain;local org=p.organism
    if not F or not istable(org) or org.alive==false or not finite(org.brain) then return end
    if F.AdminImmune and F.AdminImmune(p) then r.ready=0;M.dirty=true;return end
    local amount=math.max(0,math.min(r.ready,0.125-org.brain));local saved=r.ready
    r.ready=0;M.dirty=true
    if not M.Save() then r.ready=saved;return end
    if amount>0 then org.brain=org.brain+amount;F.QueueSync(p,org) end
end
function M.Tick()
    if M.loadError then return end
    local held=M.Locked()==true
    SetGlobalBool("zc_meta_review_hold",held)
    for _,p in ipairs(player.GetAll()) do
        if held then M.Account(p) end
        M.ApplyCarry(p)
    end
    if not held then M.Finish() end
    M.LazySave()
end
hook.Add("ZB_StartRound","ZCityMetaSafety_Snapshot",function()M.Prune();M.Tick()end,-2)
hook.Add("ZB_EndRound","ZCityMetaSafety_Release",function()
    timer.Simple(0,function()M.Finish();M.Tick()end)
end,2)
hook.Add("PlayerSpawn","ZCityMetaSafety_Spawn",function(p)
    p.ZCMetaSpawnReady=CurTime()+1
end)
hook.Add("PlayerDisconnected","ZCityMetaSafety_Persist",function()
    if M.dirty then M.Save() end
end,-2)
hook.Add("ShutDown","ZCityMetaSafety_Persist",function()M.Save()end)
timer.Create("ZCityMetaSafety_Tick",1,0,function()M.Tick()end)
-- The module is loaded before the combat delegates exist; activation calls Tick later.

include("zc_guilt_justice/roles.lua")

-- One-time rescale of unapplied brain penalties only; never heal live injuries.
if not M.loadError then
    local changed={}
    for id,r in pairs(M.accounts) do
        if r.brainDoseVersion==nil or r.brainDoseVersion==1 then
            changed[id]={brain=r.brain,ready=r.ready,version=r.brainDoseVersion}
            r.brain=(r.brain or 0)*0.5
            r.ready=(r.ready or 0)*0.5
            r.brainDoseVersion=2
        end
    end
    if next(changed) then
        M.dirty=true
        if not M.Save() then
            for id,old in pairs(changed) do
                local r=M.accounts[id]
                r.brain=old.brain;r.ready=old.ready;r.brainDoseVersion=old.version
            end
            M.loadError=true
            ErrorNoHalt("[BrainBalance] Queued-dose migration could not be saved; deferred processing paused.\n")
        end
    end
end

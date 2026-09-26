-- Authoritative, per-life karma review ledger. Server only.
if not SERVER then return end
ZCityGuiltJustice = ZCityGuiltJustice or {}
local J = ZCityGuiltJustice
include("zc_guilt_justice/meta.lua")
J.Version = "20260916.1"
J.cases = J.cases or {}
J.nextId = J.nextId or 1000000
J.hostility = J.hostility or {}
J.limits = J.limits or {}
J.loading = J.loading or setmetatable({}, {__mode="k"})
J.respected = J.respected or {}
function J.Finite(n) return isnumber(n) and n==n and math.abs(n)<math.huge end
function J.Player(p) return IsValid(p) and p:IsPlayer() end
function J.ID(p) return J.Player(p) and (p:IsBot() and "bot:"..p:UserID() or p:SteamID64()) end
function J.Find(id)
    for _,p in ipairs(player.GetAll()) do if J.ID(p)==id then return p end end
end
function J.Balance(p)
    if not J.Player(p) then return end
    local pending=ZCityMetaSafety.Balance(p)
    if pending~=nil then return pending end
    local n=p.Karma
    if not J.Finite(n) and p.guilt_GetValue then n=p:guilt_GetValue() end
    return J.Finite(n) and n or nil
end
function J.Change(p,delta)
    local deferred,change=ZCityMetaSafety.Change(p,delta)
    if deferred then return change end
    local before=J.Balance(p)
    if not before or not J.Finite(delta) then return 0 end
    p.Karma=math.Clamp(before+delta,-60,zb and zb.MaxKarma or 120)
    p:SetNetVar("Karma",p.Karma)
    if p.guilt_SetValue then p:guilt_SetValue(p.Karma) end
    return p.Karma-before
end
-- Data-only audit: no per-hit, no zero-result settlement, no acknowledgement spam.
local logKinds={settled=true,forgive=true,report=true,respect=true,
    offline_refund=true,refund_requires_review=true,retired_auto_debt=true,bounty_settlement=true}
local logFields={"case","victim","attacker","account","transaction","loss","bounty",
    "credit","paid","waived","amount","karma","price","adjustment","round"}
function J.Log(kind,entry)
    if not logKinds[kind] or not istable(entry) then return false end
    local function nonzero(key)
        local n=entry[key];return J.Finite(n) and math.abs(n)>0.000001
    end
    if kind=="settled" and not (nonzero("loss") or nonzero("bounty") or nonzero("credit")) then return false end
    if kind=="respect" and not nonzero("paid") then return false end
    if kind=="bounty_settlement" and not nonzero("adjustment") then return false end
    if kind=="forgive" and not (nonzero("waived") or nonzero("paid")) then return false end
    local record={kind=kind,time=os.time()}
    for _,key in ipairs(logFields) do
        local value=entry[key]
        if J.Finite(value) then record[key]=math.Round(value,4)
        elseif isstring(value) then record[key]=string.sub(value,1,160) end
    end
    local text=util.TableToJSON(record)
    if not text then return false end
    file.CreateDir("zc_guilt_justice")
    file.Append("zc_guilt_justice/"..os.date("%Y%m%d")..".txt",text.."\n")
    return true
end

function J.RegisterLife(v,life)
    if life.justiceId then return life end
    J.nextId=J.nextId+1
    assert(J.nextId<4294967295,"Justice case ID exhausted")
    life.justiceId=J.nextId;life.victimId=J.ID(v);life.victim=v
    life.created=life.created or CurTime();life.byAccount={}
    J.cases[life.justiceId]=life
    return life
end
function J.Pair(life,a)
    J.RegisterLife(life.victim or a,life)
    local id=J.ID(a);if not id then return end
    local p=life.attackers[a] or life.byAccount[id] or {charged=0}
    life.attackers[a]=p;life.byAccount[id]=p
    if not p.account then
        p.account=id;p.name=a:GetNWString("PlayerName",a:Nick())
        p.debits=math.max(0,p.charged or 0);p.credits=0
        p.bountyPaid=0;p.life=life;p.entity=a
    end
    return p
end
function J.Outstanding(p) return math.max(0,(p.debits or 0)-(p.credits or 0)) end
local queuePath="zc_guilt_justice/refunds.txt"
if not J.refunds then
    local raw=file.Read(queuePath,"DATA")
    local data=raw and util.JSONToTable(raw,false,true)
    J.refunds=istable(data) and data.version==1 and data.entries or {}
    J.queueLocked=raw~=nil and not (istable(data) and data.version==1 and istable(data.entries))
end
function J.SaveRefunds()
    if J.queueLocked then return false end
    file.CreateDir("zc_guilt_justice")
    local raw=util.TableToJSON({version=1,entries=J.refunds},true)
    if not raw or #raw>524288 then return false end
    local old=file.Read(queuePath,"DATA")
    if old then file.Write("zc_guilt_justice/refunds-backup.txt",old) end
    file.Write(queuePath,raw)
    return file.Read(queuePath,"DATA")==raw
end
function J.ReturnLoss(p,amount,reason)
    amount=math.min(math.max(amount,0),J.Outstanding(p))
    if amount<=0 then return true,0 end
    local a=J.Find(p.account);local paid=0
    if J.Player(a) and not J.loading[a] then paid=math.max(0,J.Change(a,amount))
    else
        local key=J.session..":"..tostring(p.life.justiceId)..":"..p.account..":"..reason
        if J.refunds[key] then return false,0 end
        J.refunds[key]={account=p.account,amount=amount,status="pending",time=os.time()}
        if not J.SaveRefunds() then J.refunds[key]=nil;return false,0 end
    end
    p.credits=(p.credits or 0)+amount;p.charged=J.Outstanding(p)
    return true,paid
end
function J.KarmaLoaded(a)
    if not J.Player(a) then return end
    J.loading[a]=nil
    for key,r in pairs(J.refunds) do
        if r.account==J.ID(a) and J.Finite(r.amount) and r.amount>0 and r.amount<=60 then
            if r.status=="reserved" then
                r.status="review"
                J.Log("refund_requires_review",{account=r.account,transaction=key,amount=r.amount})
            end
            if r.status=="pending" then
                r.before=J.Balance(a);r.after=math.min(zb.MaxKarma,r.before+r.amount)
                r.status="reserved"
                if J.SaveRefunds() then
                    local paid=J.Change(a,r.amount);r.status="done"
                    J.Log("offline_refund",{account=r.account,paid=paid,transaction=key})
                end
            end
        end
    end
    J.SaveRefunds()
end
include("zc_guilt_justice/policy.lua")
J.session=J.session or (tostring(os.time()).."-"..util.CRC(tostring(SysTime())))
local allowedStatus={pending=true,reserved=true,done=true,review=true}
for key,r in pairs(J.refunds) do
    if not istable(r) or not isstring(r.account) or #r.account~=17
        or not r.account:match("^%d+$") or not J.Finite(r.amount)
        or r.amount<=0 or r.amount>60 or not allowedStatus[r.status] then
        J.queueLocked=true
        ErrorNoHalt("[GuiltJustice] Invalid saved refund queue; offline refunds paused.\n")
        break
    end
end
local loaded=J.KarmaLoaded
J.KarmaLoaded=function(p)
    if not J.Player(p) then return end
    J.loading[p]=nil
    if J.queueLocked then return end
    for _,r in pairs(J.refunds) do
        if r.account==J.ID(p) and (r.status=="pending" or r.status=="reserved") then loaded(p);return end
    end
end

-- Native ZCity experience persistence. Hydrate before any absolute write.
zb=zb or {}
zb.Experience=zb.Experience or {}
local E=zb.Experience
E.PlayerInstances=E.PlayerInstances or {}
E.Active=E.Active or false
E.Persistence=E.Persistence or {}
E.PersistenceVersion="20260923.hydration1"
local fields={"skill","experience","deaths","kills","suicides"}
local allowed={skill=true,experience=true,deaths=true,kills=true,suicides=true}
local function finite(n) return isnumber(n) and n==n and math.abs(n)<math.huge end
local function connected() return mysql and mysql.IsConnected and mysql:IsConnected() end
local function state(sid)
    local s=E.Persistence[sid]
    if not s then s={pending={},loaded=false,baseKnown=false};E.Persistence[sid]=s end
    return s
end
-- Adopt pre-fix caches exactly once. Disconnected caches contain provisional
-- earnings, not stored totals; preserve those values until the row is read.
for sid,values in pairs(E.PlayerInstances) do
    if not E.Persistence[sid] then
        local s=state(sid)
        s.loaded=E.Active and connected() or false
        s.baseKnown=s.loaded
        if not s.loaded then
            for _,key in ipairs(fields) do
                local n=tonumber(values[key]) or 0
                if finite(n) and n~=0 then s.pending[key]={sum=n,floor=math.max(0,n)} end
            end
        end
    end
end
local function append(pending,key,amount)
    local p=pending[key] or {sum=0,floor=0}
    p.sum=p.sum+amount;p.floor=math.max(0,p.floor+amount);pending[key]=p
end
local function restore(first,last)
    for key,p in pairs(last) do
        local a=first[key]
        first[key]=a and {sum=a.sum+p.sum,floor=math.max(p.floor,a.floor+p.sum)} or p
    end
    return first
end
function E.IsReady(p)
    local s=IsValid(p) and E.Persistence[p:SteamID64()]
    return E.Active and connected() and s and s.loaded==true and not s.loading or false
end
function E.LoadPlayer(p)
    if not IsValid(p) or not p:IsPlayer() or p:IsBot() then return false end
    local sid=p:SteamID64();local s=state(sid)
    E.PlayerInstances[sid]=E.PlayerInstances[sid] or {}
    if not E.Active or not connected() or s.loading then return false end
    if s.loaded and next(s.pending)==nil then return true end
    local cached=s.loaded and E.PlayerInstances[sid] or nil
    s.loading=true;s.loaded=false
    local q=mysql:Select("zb_experience")
    for _,key in ipairs(fields) do q:Select(key) end
    q:Where("steamid",sid)
    local function receive(rows,ok)
        if not ok or not IsValid(p) or p:SteamID64()~=sid or not connected() then s.loading=false;return end
        local row=istable(rows) and rows[1]
        local values={}
        local pending=s.pending;s.pending={};s.inflight=pending
        for _,key in ipairs(fields) do
            local base=tonumber(row and row[key]) or 0
            if not finite(base) then base=0 end
            local delta=pending[key]
            values[key]=delta and math.max(delta.floor,base+delta.sum) or math.max(0,base)
        end
        local write=row and mysql:Update("zb_experience") or mysql:Insert("zb_experience")
        local method=row and "Update" or "Insert"
        if row then write:Where("steamid",sid) else write:Insert("steamid",sid) end
        write[method](write,"steam_name",p:Name())
        for _,key in ipairs(fields) do write[method](write,key,values[key]) end
        write:Callback(function(_,success)
            if not success then return end
            s.inflight=nil;s.loading=false;s.loaded=true;s.baseKnown=true
            E.PlayerInstances[sid]=values
            if next(s.pending)~=nil then E.LoadPlayer(p) end
        end)
        local success,err=pcall(write.Execute,write)
        if not success then
            s.pending=restore(pending,s.pending);s.inflight=nil;s.loading=false;s.loaded=false
            ErrorNoHalt("[ZCity XP] Hydration write failed; earnings retained. "..tostring(err).."\n")
        end
    end
    q:Callback(receive)
    if cached then receive({cached},true);return E.IsReady(p) end
    local ok,err=pcall(q.Execute,q)
    if not ok then s.loading=false;ErrorNoHalt("[ZCity XP] Hydration read failed; earnings retained. "..tostring(err).."\n") end
    return E.IsReady(p)
end
function E.Add(p,key,amount)
    if not IsValid(p) or not allowed[key] or not finite(amount) then return false end
    local sid=p:SteamID64();local s=state(sid)
    append(s.pending,key,amount)
    -- One native read/merge/write owns the transaction. An in-flight request
    -- keeps subsequent changes in pending rather than publishing stale totals.
    return E.LoadPlayer(p)
end
function E.Value(p,key)
    local sid=p:SteamID64();local data=E.PlayerInstances[sid] or {}
    local s=E.Persistence[sid]
    local value=s and s.baseKnown and (tonumber(data[key]) or 0) or 0
    local flight=s and s.inflight and s.inflight[key]
    if flight then value=math.max(flight.floor,value+flight.sum) end
    local pending=s and s.pending[key]
    if pending then value=math.max(pending.floor,value+pending.sum) end
    return value
end
hook.Add("DatabaseConnected","ExperienceCreateData",function()
    local q=mysql:Create("zb_experience")
    q:Create("steamid","VARCHAR(20) NOT NULL")
    q:Create("steam_name","VARCHAR(32) NOT NULL")
    q:Create("skill","FLOAT NOT NULL")
    for _,key in ipairs({"experience","deaths","kills","suicides"}) do q:Create(key,"INT NOT NULL") end
    q:PrimaryKey("steamid")
    q:Callback(function(_,ok)
        if not ok then return end
        E.Active=true
        for _,p in ipairs(player.GetHumans()) do E.LoadPlayer(p) end
    end)
    q:Execute()
end)
hook.Add("PlayerInitialSpawn","ZB_Exp_OnInitSpawn",function(p) E.LoadPlayer(p) end)
local P=FindMetaTable("Player")
function P:GetExp() return math.Round(E.Value(self,"experience")) end
function P:GetSkill() return E.Value(self,"skill") end
function P:GetDeaths() return E.Value(self,"deaths") end
function P:GetKills() return E.Value(self,"kills") end
function P:GetSuicides() return E.Value(self,"suicides") end
function P:GiveExp(amount)
    if not finite(amount) then return false end
    local ready=E.IsReady(self)
    local persisted=E.Add(self,"experience",amount)
    if not ready and not persisted then return false end
    local points=math.min(amount/5,10)*(1+(self.EA_HasAccess and self:EA_HasAccess() and 2 or 0))
    self:PS_AddPoints(math.Round(points*math.min(player.GetCount()/10,1)))
    return true
end
function P:GiveSkill(n) return E.Add(self,"skill",n) end
function P:GiveDeaths(n) return E.Add(self,"deaths",n) end
function P:GiveKills(n) return E.Add(self,"kills",n) end
function P:GiveSuicides(n) return E.Add(self,"suicides",n) end
util.AddNetworkString("zb_xp_get")
net.Receive("zb_xp_get",function(_,p)
    if not E.IsReady(p) or (p.ZCXPRequestAt or 0)>CurTime() then return end
    p.ZCXPRequestAt=CurTime()+0.5
    local target=net.ReadEntity()
    if not IsValid(target) or not target:IsPlayer() or not E.IsReady(target) then return end
    if hg and hg.SpecDM and not hg.SpecDM.CanExchange(p,target) then return end
    net.Start("zb_xp_get");net.WriteEntity(target);net.WriteFloat(target:GetSkill());net.WriteInt(target:GetExp(),19);net.Send(p)
end)

-- Player-specific karma locks. Fixed while zombified; a non-decreasing floor
-- after death/cleanup until the next round starts. No global karma disable.
local K=ZC_POSTMORTEM_KARMA or {players={},accounts={}}
ZC_POSTMORTEM_KARMA=K
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function identity(p) return p:IsBot() and ("bot:"..p:UserID()) or p:SteamID64() end
local function rawField(p,key)
    local fields=p.GetTable and p:GetTable() or p
    return fields[key]
end
local function stillZombie(s,p)
    local c=s.context
    local actor=c.data.players[p]
    return (p.PlayerClassName=="headcrabzombie" or (actor and actor.phase=="rising")) and s.hard and p:Alive() and not c.stopped and ZC_HMCD_MUTATORS.current==c
        and zb and zb.ROUND_STATE==1 and zb.ROUND_START==c.stamp
        and CurrentRound()==c.mode and c.mode.Type==c.variant
end
function K.Value(p,value)
    local s=K.players[p]
    if not s then return value end
    if not stillZombie(s,p) then s.hard=false end
    if s.hard then value=s.saved
    else
        value=math.max(s.floor,finite(value) and value or s.floor,finite(p.Karma) and p.Karma or s.floor)
        s.floor=value
    end
    p.Karma=value
    return value
end
local function wrap(p,s,key,factory)
    local current=p[key]
    if type(current)~="function" or current==s.wrappers[key] then return end
    local original=current
    s.previous[key]=rawField(p,key)
    local wrapper=factory(original)
    s.wrappers[key]=wrapper
    p[key]=wrapper
end
function K.Install(p,s)
    wrap(p,s,"SetNetVar",function(original)
        return function(self,key,value,...)
            if key=="Karma" and K.players[self] then value=K.Value(self,value) end
            return original(self,key,value,...)
        end
    end)
    wrap(p,s,"guilt_SetValue",function(original)
        return function(self,value,...)
            if K.players[self] then
                local old=value;value=K.Value(self,value)
                if old~=value then self:SetNetVar("Karma",value) end
            end
            return original(self,value,...)
        end
    end)
end
function K.Enforce(p)
    local s=K.players[p];if not s or not IsValid(p) then return end
    K.Install(p,s)
    local before=p.Karma
    local value=K.Value(p,before)
    if before~=value then p:SetNetVar("Karma",value) end
end
function K.Capture(p,context)
    local id=identity(p)
    local s=K.accounts[id]
    if not s then
        local value=tonumber(p.Karma)
        if not finite(value) then value=tonumber(p:GetNetVar("Karma",100)) end
        if not finite(value) then value=100 end
        s={saved=value,floor=value,previous={},wrappers={}}
        K.accounts[id]=s
    end
    s.context=context;s.hard=true;s.ply=p
    K.players[p]=s
    K.Install(p,s)
    K.StartTimer()
end
function K.Release(p)
    local s=K.players[p];if not s then return end
    s.hard=false;K.Enforce(p)
end
function K.Clear()
    for p,s in pairs(K.players) do
        if IsValid(p) then
            for key,wrapper in pairs(s.wrappers) do
                if p[key]==wrapper then p[key]=s.previous[key] end
            end
        end
    end
    K.players={};K.accounts={}
    timer.Remove("zc_postmortem_karma_lock")
end
function K.Status(p)
    local s=K.players[p]
    if not s then return "off" end
    return (s.hard and "locked=" or "floor=")..string.format("%.2f",s.hard and s.saved or s.floor)
end
hook.Add("ZB_StartRound","zc_postmortem_karma_reset",function() K.Clear() end)
hook.Add("ZB_EndRound","zc_postmortem_karma_release",function()
    for p in pairs(K.players) do K.Release(p) end
end)
hook.Add("PlayerDeath","zc_postmortem_karma_release",function(p) K.Release(p) end)
hook.Add("PlayerSilentDeath","zc_postmortem_karma_release",function(p) K.Release(p) end)
hook.Add("PlayerDisconnected","zc_postmortem_karma_disconnect",function(p)
    local s=K.players[p];if s then s.hard=false;s.ply=nil end
end)
hook.Add("PlayerInitialSpawn","zc_postmortem_karma_reconnect",function(p)
    local s=K.accounts[identity(p)]
    if not s then return end
    for old,record in pairs(K.players) do if record==s then K.players[old]=nil end end
    s.hard=false;s.ply=p;s.previous={};s.wrappers={}
    K.players[p]=s;K.Install(p,s);K.Enforce(p);K.StartTimer()
end)
function K.StartTimer()
    timer.Create("zc_postmortem_karma_lock",0.1,0,function()
        for p in pairs(K.players) do
            if IsValid(p) then K.Enforce(p) else K.players[p]=nil end
        end
        if not next(K.players) then timer.Remove("zc_postmortem_karma_lock") end
    end)
end
if next(K.players) then K.StartTimer() end

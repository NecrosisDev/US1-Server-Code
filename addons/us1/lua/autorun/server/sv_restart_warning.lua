-- Restart Warning v2: persistent schedules and explicit staff controls.
-- No os.time/os.date in the per-second loop; clock sampled on load and hourly.
-- v2.2.0: maintenance reason (persisted), ULX !restart helpers, 15-minute notice window,
-- chat notices at 10m/5m/2m/1m/30s/10s, staff-only Cancel button request (restartwarn_cancelreq).
-- Staff rights (UI cohesion U5, zc_goobos/sv_staff.lua): scheduling needs the ULX right "ulx restart" (the !restart
-- command's own access); cancelling also accepts "ulx restartcancel". IsAdmin() only when ULib is not installed.
if not SERVER then return end
AddCSLuaFile("autorun/client/cl_restart_warning.lua")
if not ZCStaff then include("zc_goobos/sv_staff.lua") end
local function canRestart(p) return IsValid(p) and ZCStaff.Can(p,"restart") end
local function canCancel(p) return canRestart(p) or (IsValid(p) and ZCStaff.Allowed(p,"ulx restartcancel")) end
local C=include("restart_warning/sv_clock.lua")
local PATH="restart_warning/settings.json"
local BACKUP="restart_warning/settings-backup.json" -- GMod file.Write does not permit .bak
local old=ZC_RESTART_WARNING
local R={Version="2.2.0",triggered=old and old.triggered or false}
ZC_RESTART_WARNING=R
util.AddNetworkString("restartwarn_start")
util.AddNetworkString("restartwarn_cancel")
util.AddNetworkString("restartwarn_state")
util.AddNetworkString("restartwarn_ready")
util.AddNetworkString("restartwarn_cancelreq")
local WINDOW=900 -- players see the notice for the final fifteen minutes
local REASON_MAX=140
local MIN_AHEAD,MAX_AHEAD=30,7*86400
R.Window=WINDOW
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
-- Counts UTF-8 characters; nil for malformed text or C1 control characters.
local function utf8count(s)
    local i,n,len=1,0,#s
    while i<=len do
        local c=s:byte(i)
        local size=c<0x80 and 1 or (c>=0xC2 and c<=0xDF) and 2 or (c>=0xE0 and c<=0xEF) and 3 or (c>=0xF0 and c<=0xF4) and 4 or nil
        if not size or i+size-1>len then return nil end
        for k=i+1,i+size-1 do
            local b=s:byte(k)
            if b<0x80 or b>0xBF then return nil end
        end
        if c==0xC2 and s:byte(i+1)<=0x9F then return nil end
        i=i+size; n=n+1
    end
    return n
end
-- Staff-written reason: one printable line of at most 140 characters.
-- Returns clean text; nil for "no reason"; nil,message when invalid.
function R.CleanReason(raw)
    if raw==nil then return nil end
    if type(raw)~="string" then return nil,"The reason must be text." end
    if #raw>REASON_MAX*4 then return nil,"The reason is too long (140 characters at most)." end
    local s=raw:gsub("%s+"," ")
    s=s:match("^ *(.-) *$")
    if s=="" then return nil end
    if s:find("%c") then return nil,"The reason cannot contain control characters." end
    local count=utf8count(s)
    if not count then return nil,"The reason contains unreadable characters." end
    if count>REASON_MAX then return nil,"The reason is too long ("..count.."/140 characters)." end
    return s
end
function R.FormatDuration(seconds)
    local s=math.max(0,math.ceil(seconds or 0))
    if s<60 then return s.."s" end
    if s<3600 then
        local m,r=math.floor(s/60),s%60
        return r==0 and (m.." min") or (m.."m "..r.."s")
    end
    if s<86400 then
        local h,m=math.floor(s/3600),math.floor(s/60)%60
        return m==0 and (h.."h") or (h.."h "..m.."m")
    end
    local d,h=math.floor(s/86400),math.floor(s/3600)%24
    return h==0 and (d.."d") or (d.."d "..h.."h")
end
local function times(raw)
    if type(raw)~="string" or #raw>100 then return nil end
    local out,seen={},{}
    for item in (raw..","):gmatch("(.-),") do
        local h,m=item:match("^%s*(%d%d):(%d%d)%s*$")
        if not h or tonumber(h)>23 or tonumber(m)>59 then return nil end
        local s=h..":"..m
        if not seen[s] then out[#out+1]=s; seen[s]=true end
    end
    if #out<1 or #out>8 then return nil end
    table.sort(out); return out
end
local function valid(t)
    if type(t)~="table" or t.version~=1 or not ({server=true,eastern=true})[t.timezone]
        or type(t.times)~="table" or #t.times<1 or #t.times>8 then return false end
    for _,s in ipairs(t.times) do if type(s)~="string" or not s:match("^%d%d:%d%d$") then return false end end
    if not times(table.concat(t.times,",")) then return false end
    for _,key in ipairs({"skipThrough","override"}) do
        if t[key]~=nil and (not finite(t[key]) or t[key]<0 or t[key]>4102444800) then return false end
    end
    if t.reason~=nil and R.CleanReason(t.reason)~=t.reason then return false end
    return true
end
local raw=file.Read(PATH,"DATA")
local config
if raw~=nil then config=util.JSONToTable(raw)
else config={version=1,timezone="server",times={"06:00","18:00"}} end
if (raw==nil and file.Exists(PATH,"DATA")) or not valid(config) then
    R.error="Restart settings are invalid. Scheduling is stopped; restore settings.json from settings-backup.json."
    config={version=1,timezone="server",times={"06:00","18:00"}}
end
local epoch,mono=os.time(),SysTime()
local function now() return epoch+SysTime()-mono end
local function sample() epoch,mono=os.time(),SysTime() end
local function clearWarning()
    R.warningEnd=nil
    R.noticeStage=nil; R.nextNotice=nil
    net.Start("restartwarn_cancel"); net.Broadcast()
end
local function arm()
    R.due=not R.error and C.Next(config,now()) or nil
    R.warningEnd=nil
end
arm()
local function token()
    return util.CRC((util.TableToJSON(config) or "")..":"..tostring(R.due or 0))
end
-- quiet=true persists without clearing the countdown or re-arming (used once the restart is issued).
local function save(nextConfig,quiet)
    local before=file.Read(PATH,"DATA")
    local body=util.TableToJSON(nextConfig,true)
    if not body then return false,"Could not encode restart settings." end
    file.CreateDir("restart_warning")
    -- Keep a verified previous configuration before replacing the primary file.
    local backup=before or util.TableToJSON(config,true)
    file.Write(BACKUP,backup)
    if file.Read(BACKUP,"DATA")~=backup then return false,"Backup write failed; schedule unchanged." end
    file.Write(PATH,body)
    if file.Read(PATH,"DATA")~=body then
        if before then file.Write(PATH,before) else file.Delete(PATH) end
        if file.Read(PATH,"DATA")~=before then
            R.error="Saving and restoring restart settings failed. Scheduling stopped; restore settings-backup.json."
            R.due=nil; clearWarning()
        end
        return false,R.error or "Save failed; previous schedule restored."
    end
    config=nextConfig
    if not quiet then clearWarning(); arm() end
    return true
end
-- The reason belongs to the one-time restart it was given with, never to a daily slot.
local function activeReason()
    if config.reason~=nil and config.override~=nil and config.override==R.due then return config.reason end
    return ""
end
local function isManual() return config.manual==true and config.override==R.due end
function R.Status()
    local at=now()
    local sn,sd,st=C.Format(at,"server")
    local en,ed,et=C.Format(at,"eastern")
    local data={available=true,version=R.Version,token=token(),timezone=config.timezone,times=table.concat(config.times,", "),
        serverNow=sn,easternNow=en,canChange=not R.error and not R.triggered,error=R.error or "",
        manual=isManual(),reason=activeReason(),
        nextAt=R.due or 0,left=R.due and math.max(0,R.due-at) or 0,override=config.override and config.override==R.due or false,
        serverDate=sd,serverTime=st,easternDate=ed,easternTime=et}
    if R.due then
        data.serverNext,data.serverDate,data.serverTime=C.Format(R.due,"server")
        data.easternNext,data.easternDate,data.easternTime=C.Format(R.due,"eastern")
    end
    return data
end
function R.Change(p,action,expected,value)
    if not (canRestart(p) or (action=="cancel" and canCancel(p))) then return false,"You need the ulx restart access right." end
    if R.error or R.triggered then return false,R.error or "Restart already issued; it cannot be cancelled now." end
    if expected~=token() then return false,"Schedule changed. Review the refreshed times and try again." end
    if type(value)~="string" or #value>700 then return false,"Invalid restart request." end
    local at=now(); local cfg=table.Copy(config); local message
    local announced=false
    if action=="cancel" then
        if not R.due then return false,"No pending restart." end
        -- Players were told about it: a manual or reasoned restart, or one inside the notice window.
        announced=isManual() or activeReason()~="" or R.due-at<=WINDOW
        cfg.skipThrough=math.max(cfg.skipThrough or 0,R.due)
        cfg.override=nil; cfg.manual=nil; cfg.reason=nil
        message="Next restart cancelled. The following daily restart is still scheduled."
    elseif action=="next" then
        local request=util.JSONToTable(value)
        if type(request)~="table" or not ({server=true,eastern=true})[request.timezone] then return false,"Choose server or Eastern time." end
        local due,why=C.Parse(request.date,request.time,request.timezone)
        if not due then return false,why end
        if due-at<MIN_AHEAD or due-at>MAX_AHEAD then return false,"Choose a time at least 30 seconds and at most seven days ahead." end
        local reason,bad=R.CleanReason(request.reason)
        if bad then return false,bad end
        if request.reason==nil and activeReason()~="" then reason=activeReason() end -- moving keeps the stated reason
        cfg.skipThrough=math.max(cfg.skipThrough or 0,R.due or 0,due)
        cfg.override=due; cfg.manual=nil; cfg.reason=reason
        message="Next restart moved to "..C.Format(due,"eastern")..". Daily restarts resume after this override and the replaced slot."
    elseif action=="daily" then
        local request=util.JSONToTable(value)
        if type(request)~="table" or not ({server=true,eastern=true})[request.timezone] then return false,"Choose server or Eastern time." end
        local schedule=times(request.times)
        if not schedule then return false,"Enter one to eight 24-hour times, separated by commas (06:00, 18:00)." end
        cfg={version=1,timezone=request.timezone,times=schedule}
        local due=C.Next(cfg,at)
        if not due or due-at<30 then return false,"The next daily time is less than 30 seconds away. Choose a later time." end
        message="Daily restart schedule saved. Previous cancellation or one-time override cleared."
    else return false,"Unknown restart action." end
    local ok,why=save(cfg)
    if ok and announced then PrintMessage(HUD_PRINTTALK,"[Maintenance] Restart cancelled by "..p:Nick()..".") end
    return ok,ok and message or why
end
-- Presentation only: the authoritative schedule and restart path remain here.
local function remainingTime()
    if R.warningEnd then return math.max(0,R.warningEnd-SysTime()) end
    return R.due and math.max(0,R.due-now()) or nil
end
local function sendState(p)
    local seconds=remainingTime()
    if R.error or R.triggered or not seconds or seconds>WINDOW then return end
    net.Start("restartwarn_state")
    net.WriteFloat(seconds)
    net.WriteBool(isManual())
    net.WriteString(activeReason()) -- v2.2 additive field; older clients stop reading before it
    if IsValid(p) then net.Send(p) else net.Broadcast() end
end
-- Chat milestones inside the notice window (seconds remaining).
local STAGES={10,30,60,120,300,600}
local function stageFor(seconds)
    for _,stage in ipairs(STAGES) do if seconds<=stage then return stage end end
end
R.StageFor=stageFor
local JOKES={[120]="Please finish your current bad decision.",[60]="The server hamster has requested a union break.",
    [30]="Please keep all limbs inside the current reality.",[10]="Turning it off and on again. Very advanced stuff."}
local function announce()
    local seconds=remainingTime()
    if R.error or R.triggered or not seconds or seconds>WINDOW then return end
    local stage=stageFor(seconds)
    if stage and stage~=R.noticeStage then
        local reason=activeReason()
        local line="[Maintenance] Restart in "..R.FormatDuration(stage)
        -- The reason line never carries a joke; jokes stay on unexplained restarts.
        if reason~="" then line=line..": "..reason
        else line=line.."."..(JOKES[stage] and (" "..JOKES[stage]) or "") end
        PrintMessage(HUD_PRINTTALK,line)
        R.noticeStage=stage
        R.nextNotice=nil
    end
    if not R.nextNotice or SysTime()>=R.nextNotice then
        sendState()
        R.nextNotice=SysTime()+5
    end
end
-- A joining client can request the current warning, never schedule a restart.
local readyAt=setmetatable({}, {__mode="k"})
net.Receive("restartwarn_ready",function(length,p)
    if length~=0 or not IsValid(p) or not p:IsPlayer() then return end
    if readyAt[p] and SysTime()<readyAt[p] then return end
    readyAt[p]=SysTime()+10
    sendState(p)
end)
-- The card's Cancel button when ULX is not installed (with ULX it runs "ulx restartcancel"). The client only draws it
-- for staff; authority is re-checked here and
-- in R.Change, and it can only cancel a restart whose notice is currently on screen.
local cancelAt=setmetatable({}, {__mode="k"})
net.Receive("restartwarn_cancelreq",function(length,p)
    if length~=0 or not IsValid(p) or not p:IsPlayer() then return end
    if cancelAt[p] and SysTime()<cancelAt[p] then return end
    cancelAt[p]=SysTime()+2
    if not canCancel(p) then return end
    local seconds=remainingTime()
    local ok,message
    if not seconds or seconds>WINDOW then ok,message=false,"No restart notice is showing."
    else ok,message=R.Change(p,"cancel",token(),"") end
    p:ChatPrint("[Maintenance] "..message)
    print("[RestartWarning] "..p:Nick().." cancel button: "..(ok and "cancelled" or message))
end)
-- seconds (default 30, the F8 button) and reason are optional; bounds match R.Change "next".
function R.RequestManual(p,seconds,reason)
    if not canRestart(p) then return false,"You need the ulx restart access right." end
    if R.error or R.triggered then return false,R.error or "Restart already issued." end
    if R.warningEnd or isManual() then return false,"A restart countdown is already running. Type !restart cancel (or use F8 > Server > Restarts) first." end
    if seconds==nil then seconds=30 end
    if not finite(seconds) or seconds<MIN_AHEAD or seconds>MAX_AHEAD then return false,"Choose a time between 30 seconds and seven days ahead." end
    local clean,bad=R.CleanReason(reason)
    if bad then return false,bad end
    local cfg=table.Copy(config); cfg.override=now()+seconds; cfg.manual=true; cfg.reason=clean
    local ok,why=save(cfg); if not ok then return false,why end
    PrintMessage(HUD_PRINTTALK,"[Maintenance] Restart in "..R.FormatDuration(seconds)..(clean and (": "..clean) or "").." - by "..p:Nick())
    R.noticeStage=stageFor(seconds) -- the line above replaces the milestone it falls in
    announce()
    return true,"Restart queued in "..R.FormatDuration(seconds)..". Type !restart cancel (or use F8 > Server > Restarts) to stop it."
end
-- "now" (30 s), "30s", "10m", "1h30m", "2d", bare minutes ("15"), or a server-clock "HH:MM"
-- (today, else tomorrow). Returns seconds from now, or nil,message.
local WHEN_HELP="Use 30s, 10m, 1h30m or a server time like 18:30."
local UNIT_ORDER,UNIT_SECONDS={d=1,h=2,m=3,s=4},{d=86400,h=3600,m=60,s=1}
function R.ParseWhen(text,at)
    if type(text)~="string" then return nil,WHEN_HELP end
    local s=text:lower():gsub("%s","")
    if s=="" or #s>16 then return nil,WHEN_HELP end
    at=at or now()
    local seconds
    if s=="now" then seconds=MIN_AHEAD
    elseif s:match("^%d+$") then seconds=tonumber(s)*60
    elseif s:match("^%d%d?:%d%d$") then
        local h,m=s:match("^(%d%d?):(%d%d)$")
        h,m=tonumber(h),tonumber(m)
        if h>23 or m>59 then return nil,"Use a 24-hour server time such as 18:30." end
        local clock=string.format("%02d:%02d",h,m)
        for day=0,1 do
            local _,date=C.Format(at+day*86400,"server")
            local due=C.Parse(date,clock,"server")
            if due and due>at then seconds=due-at; break end
        end
        if not seconds then return nil,"That server time does not exist today or tomorrow." end
    else
        local last,total,bad=0,0,false
        local rest=s:gsub("(%d+)([dhms])",function(n,u)
            if UNIT_ORDER[u]<=last or #n>6 then bad=true end
            last=UNIT_ORDER[u]; total=total+tonumber(n)*UNIT_SECONDS[u]
            return ""
        end)
        if bad or rest~="" or last==0 then return nil,WHEN_HELP end
        seconds=total
    end
    if seconds<MIN_AHEAD or seconds>MAX_AHEAD then return nil,"Choose a time between 30 seconds and seven days ahead." end
    return seconds
end
-- Replace original named scheduler hooks/timers. Initial load arms immediately,
-- so map changes and hourly clock resync cannot undo a saved cancellation.
hook.Remove("InitPostEntity","RestartWarning_Init")
timer.Create("RestartWarning_Resync",3600,0,function()
    sample() -- preserve an already-due restart instead of silently skipping it
    if R.due and R.due>now() and not R.warningEnd and not R.triggered then R.due=C.Next(config,now()) end
end)
timer.Create("RestartWarning_Check",1,0,function()
    if not R.due or R.triggered then return end
    local remaining=R.due-now()
    if remaining<=10 and not R.warningEnd then
        local seconds=remaining>0 and remaining or 10 -- a stalled server still gives a warning
        R.warningEnd=SysTime()+seconds
        net.Start("restartwarn_start"); net.WriteFloat(seconds); net.Broadcast()
        -- Keep the legacy final-ten-second packet for already connected v2 clients.
    end
    announce()
    if R.warningEnd and SysTime()>=R.warningEnd then
        R.triggered=true -- never retry an issued restart
        if config.reason~=nil then -- the reason belongs to this restart only
            local cfg=table.Copy(config); cfg.reason=nil
            pcall(save,cfg,true)
        end
        if PhysgunCrashHandler and type(PhysgunCrashHandler.RestartWithCrashScreen)=="function" then
            PhysgunCrashHandler.RestartWithCrashScreen()
        else game.ConsoleCommand("_restart\n") end
    end
end)
hook.Add("ShutDown","RestartWarning_Shutdown",function()
    timer.Remove("RestartWarning_Check"); timer.Remove("RestartWarning_Resync")
end)
-- Load receipt: proves which version actually ran (US1 autorefresh is unreliable).
file.CreateDir("restart_warning")
file.Write("restart_warning/loaded.txt",R.Version.." "..os.time())
print("[RestartWarning] v"..R.Version..(R.error and (" DISABLED: "..R.error) or " loaded (persistent schedule, low-libc mode)"))

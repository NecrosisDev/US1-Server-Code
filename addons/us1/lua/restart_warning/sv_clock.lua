-- Gregorian/US Eastern conversion, independent of the server or client's timezone.
-- US DST rules effective since 2007: second Sunday March / first Sunday November.
local C={}
local floor=math.floor
function C.Epoch(y,m,d,h,n,s)
    if m<=2 then y=y-1 end
    local era=floor(y/400); local yy=y-era*400
    local mm=m+(m>2 and -3 or 9)
    local days=era*146097+yy*365+floor(yy/4)-floor(yy/100)+floor((153*mm+2)/5)+d-1-719468
    return days*86400+(h or 0)*3600+(n or 0)*60+(s or 0)
end
function C.Parts(epoch)
    local days=floor(epoch/86400); local secs=epoch-days*86400
    local z=days+719468; local era=floor(z/146097); local doe=z-era*146097
    local yy=floor((doe-floor(doe/1460)+floor(doe/36524)-floor(doe/146096))/365)
    local y=yy+era*400; local doy=doe-(365*yy+floor(yy/4)-floor(yy/100))
    local mp=floor((5*doy+2)/153); local d=doy-floor((153*mp+2)/5)+1
    local m=mp+(mp<10 and 3 or -9); if m<=2 then y=y+1 end
    return {year=y,month=m,day=d,hour=floor(secs/3600),min=floor(secs/60)%60,sec=floor(secs%60)}
end
local function sunday(y,m,n)
    local weekday=(floor(C.Epoch(y,m,1)/86400)+4)%7 -- Sunday=0
    return 1+(7-weekday)%7+(n-1)*7
end
function C.EasternOffset(epoch)
    local y=C.Parts(epoch).year
    local start=C.Epoch(y,3,sunday(y,3,2),7) -- 02:00 EST
    local stop=C.Epoch(y,11,sunday(y,11,1),6) -- 02:00 EDT
    return epoch>=start and epoch<stop and -14400 or -18000
end
function C.Local(epoch,zone)
    if zone=="server" then return os.date("*t",epoch) end
    return C.Parts(epoch+C.EasternOffset(epoch))
end
function C.Offset(epoch,zone)
    if zone=="eastern" then return C.EasternOffset(epoch) end
    local t=C.Local(epoch,zone)
    return C.Epoch(t.year,t.month,t.day,t.hour,t.min,t.sec)-floor(epoch)
end
local function same(t,p)
    return t.year==p.year and t.month==p.month and t.day==p.day and t.hour==p.hour and t.min==p.min
end
function C.Resolve(t,zone)
    if zone=="server" then
        local e=os.time({year=t.year,month=t.month,day=t.day,hour=t.hour,min=t.min,sec=0})
        if e and same(t,C.Local(e,zone)) then return e end
    elseif zone=="eastern" then
        local wall=C.Epoch(t.year,t.month,t.day,t.hour,t.min)
        -- First occurrence only for repeated fall-back times; spring gap is rejected.
        for _,offset in ipairs({14400,18000}) do
            local e=wall+offset
            if same(t,C.Local(e,zone)) then return e end
        end
    end
    return nil,"That local time does not exist (daylight-saving clock change)."
end
function C.Parse(date,time,zone)
    if type(date)~="string" or type(time)~="string" then return nil,"Enter a date and time." end
    local y,m,d=date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    local h,n=time:match("^(%d%d):(%d%d)$")
    y,m,d,h,n=tonumber(y),tonumber(m),tonumber(d),tonumber(h),tonumber(n)
    if not y or not h or y<2007 or y>2099 or m<1 or m>12 or d<1 or d>31 or h>23 or n>59 then return nil,"Use YYYY-MM-DD and 24-hour HH:MM." end
    local t={year=y,month=m,day=d,hour=h,min=n}
    if not same(t,C.Parts(C.Epoch(y,m,d,h,n))) then return nil,"Invalid calendar date." end
    return C.Resolve(t,zone)
end
function C.Format(epoch,zone)
    local t=C.Local(epoch,zone)
    local date=string.format("%04d-%02d-%02d",t.year,t.month,t.day)
    local time=string.format("%02d:%02d",t.hour,t.min)
    local offset=C.Offset(epoch,zone)
    local name=zone=="eastern" and (offset==-14400 and "EDT" or "EST") or "server"
    local a=math.abs(offset)
    return date.." "..time.." "..name..string.format(" (UTC%s%02d:%02d)",offset<0 and "-" or "+",floor(a/3600),floor(a/60)%60),date,time
end
function C.Next(config,now)
    if config.override and config.override>now then return config.override end
    local after=math.max(now,config.skipThrough or 0)
    local t=C.Local(after,config.timezone)
    local day=C.Epoch(t.year,t.month,t.day)
    local best
    for i=0,8 do
        local p=C.Parts(day+i*86400)
        for _,time in ipairs(config.times) do
            local h,n=time:match("^(%d%d):(%d%d)$")
            p.hour,p.min=tonumber(h),tonumber(n)
            local e=C.Resolve(p,config.timezone)
            if e and e>after and (not best or e<best) then best=e end
        end
        if best then return best end
    end
end
return C

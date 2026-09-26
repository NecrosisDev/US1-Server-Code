-- ZCity Maintenance Division. Informative, non-modal, and entirely cosmetic.
-- GMod globals/APIs this file touches (for harness mocking):
--   CLIENT, CreateClientConVar, Color, SysTime, RealTime, ScrW, ScrH,
--   hook.Add, math.Clamp/min/max/ceil/floor,
--   surface.CreateFont/SetFont/GetTextSize/SetDrawColor/DrawRect/DrawOutlinedRect/PlaySound,
--   draw.RoundedBox/RoundedBoxEx/SimpleText,
--   net.Receive/ReadFloat/ReadBool/ReadString/BytesLeft/Start/SendToServer,
--   util.NetworkStringToID, chat.AddText, concommand.Add, RunConsoleCommand, ULib (optional: ucl.query, cmds.translatedCmds),
--   vgui.Create, IsValid, LocalPlayer, GetConVar, cvars.AddChangeCallback,
--   string.format/gsub/match/sub, table.concat, TEXT_ALIGN_RIGHT/TEXT_ALIGN_CENTER.
if not CLIENT then return end

local sounds = CreateClientConVar("zc_restart_sounds", "1", true, false, "Play quiet restart countdown cues", 0, 1)
local state, lastTick, scale
-- ZCity dock tokens (cl_observer.lua Dock card): near-black panel, dark-red edge, red/green accents.
local panel = Color(15, 15, 17, 232)
local shadow = Color(0, 0, 0, 90)
local edge = Color(83, 19, 23, 255)
local white = Color(235, 235, 235)
local dim = Color(170, 170, 170)
local red = Color(194, 58, 61)
local green = Color(119, 157, 135)
local clear = Color(0, 0, 0, 0) -- hides DButton's built-in label; Paint draws the text
local cancelBtn, btnRect, confirmUntil, cooldownUntil

-- fit() results, keyed by font, width and text; cleared when the fonts are rebuilt.
local fitCache, fitCount = {}, 0

local function face()
    local cv = GetConVar("hg_font")
    local name = cv and cv:GetString() or ""
    return name ~= "" and name or "Bahnschrift"
end
local function fonts()
    scale = math.Clamp(math.min(ScrW()/1920, ScrH()/1080), 0.65, 1.5)
    fitCache, fitCount = {}, 0
    local f = face()
    for name, size in pairs({Label=15, Title=28, Body=20, Small=17, Clock=58}) do
        surface.CreateFont("ZCRestart"..name, {
            font = f,
            size = math.floor(size*scale), weight = name=="Body" and 500 or 700, antialias = true
        })
    end
end
fonts()
hook.Add("OnScreenSizeChanged", "RestartWarning_Fonts", fonts)
if cvars and cvars.AddChangeCallback then cvars.AddChangeCallback("hg_font", fonts, "RestartWarning_Fonts") end

-- Control chars -> spaces, trim, cap at 560 bytes. Width-fitting happens at draw time.
local function sanitizeReason(s)
    if type(s) ~= "string" then return "" end
    s = s:gsub("%c", " ")
    s = s:match("^%s*(.-)%s*$") or ""
    if #s > 560 then s = s:sub(1, 560) end
    return s
end

-- span is the largest seconds value seen for the current countdown; it is the progress-bar
-- denominator and is reset whenever a fresh countdown (not a continuation) begins.
local function receiveState(seconds, manual, modern, reason)
    if type(seconds)~="number" or seconds~=seconds or seconds<0 or seconds>900 then return end
    -- The v2 packet is also sent for older clients. Do not reset modern state with it.
    if not modern and state and state.modern and not state.preview then return end
    local fresh = not state or state.cancelled or state.preview
    local span = fresh and seconds or math.max(state.span or seconds, seconds)
    state = {ends=SysTime()+seconds, manual=manual, modern=modern, reason=reason or "", span=math.max(span,1)}
    if fresh then lastTick=nil end
end
net.Receive("restartwarn_state", function()
    local seconds=net.ReadFloat()
    local manual=net.ReadBool()
    local reason=""
    -- Additive v2.2 field; an older server's packet ends before it.
    if net.BytesLeft and (net.BytesLeft() or 0)>0 then reason=net.ReadString() end
    receiveState(seconds, manual, true, sanitizeReason(reason))
end)
net.Receive("restartwarn_start", function() receiveState(net.ReadFloat(), false, false, "") end)
net.Receive("restartwarn_cancel", function()
    if state and not state.preview then state={cancelled=true, ends=SysTime()+4} end
    lastTick=nil
end)
local function requestState()
    if util.NetworkStringToID("restartwarn_ready")==0 then return end
    net.Start("restartwarn_ready")
    net.SendToServer()
end
hook.Add("InitPostEntity", "RestartWarning_Ready", requestState)

-- Preview never sends a server request, changes a schedule or issues a reconnect.
local PREVIEW_HELP = "Show the restart notice locally, as a preview: zc_restart_preview [seconds 1-900] [reason]. Nothing restarts; zc_restart_preview_stop hides it."
concommand.Add("zc_restart_preview", function(_, _, args)
    if state and not state.preview and (not state.cancelled or state.ends>SysTime()) then
        chat.AddText(red, "[ZCity Maintenance] A real notice is active; preview unavailable.")
        return
    end
    args = args or {}
    local seconds = tonumber(args[1]) or 12
    if seconds~=seconds then seconds=12 end
    seconds = math.Clamp(seconds, 1, 900)
    local reason=""
    if #args>1 then
        local words={}
        for i=2,#args do words[#words+1]=args[i] end
        reason = sanitizeReason(table.concat(words, " "))
    end
    state = {ends=SysTime()+seconds, manual=true, preview=true, modern=true, reason=reason, span=math.max(seconds,1)}
    lastTick=nil
end, nil, PREVIEW_HELP)
concommand.Add("zc_restart_preview_stop", function() if state and state.preview then state=nil end end, nil, "Hide a zc_restart_preview notice.")

local function fitRaw(text, font, width)
    surface.SetFont(font)
    if surface.GetTextSize(text)<=width then return text end
    while #text>0 and surface.GetTextSize(text.."...")>width do text=text:sub(1,-2) end
    return text.."..."
end
local function fit(text, font, width)
    local key = font.."\0"..math.floor(width).."\0"..text
    local out = fitCache[key]
    if out then return out end
    if fitCount >= 64 then fitCache, fitCount = {}, 0 end
    out = fitRaw(text, font, width)
    fitCache[key] = out
    fitCount = fitCount + 1
    return out
end

-- 2026-09-25 HUD pass: GoobOS tokens (written into the same colour objects once the theme exists) and the kit plate.
local themed=false
local function syncTheme()
    if themed then return end
    local T = ZCGoobApps and ZCGoobApps.Theme
    if not (T and T.glass and T.edge) then return end
    themed=true
    local function set(c, src, a) c.r, c.g, c.b = src.r, src.g, src.b if a then c.a = a end end
    set(panel, T.glass, T.glass.a) set(edge, T.edge) set(white, T.text) set(dim, T.muted) set(red, T.accent) set(green, T.green)
end
local function box(x, y, w, h, radius)
    local K = ZCGoobApps and ZCGoobApps.Kit
    if K and K.HudPlate then K.HudPlate(x, y, w, h) return end
    draw.RoundedBox(radius, x+2, y+2, w, h, shadow)
    draw.RoundedBox(radius, x, y, w, h, panel)
    surface.SetDrawColor(edge)
    surface.DrawOutlinedRect(x, y, w, h)
end

-- Staff rights (UI cohesion U5): who sees Cancel. Presentation only - the server checks again. With ULib the local
-- player's own ULX access ("ulx restartcancel" or "ulx restart"), re-read once a second; without it IsAdmin().
local rights={at=0}
local function refreshRights(me)
    local now=RealTime()
    if now<rights.at then return end
    rights.at=now+1
    local ucl=ULib and ULib.ucl
    if not (ucl and ucl.query) then
        rights.cancel, rights.restart = me:IsAdmin() or me:IsSuperAdmin(), false
        return
    end
    local okCancel, cancel = pcall(ucl.query, me, "ulx restartcancel")
    local okRestart, restart = pcall(ucl.query, me, "ulx restart")
    rights.cancel, rights.restart = okCancel and cancel==true, okRestart and restart==true
end
local function canCancel(me)
    refreshRights(me)
    return rights.cancel or rights.restart
end
-- The ULX command when ULX is installed, so the cancel is logged ("#A cancelled the pending restart"); the guarded
-- net request otherwise.
local function sendCancel()
    local ulxCmds = ULib and ULib.cmds and ULib.cmds.translatedCmds
    if ulxCmds and ulxCmds["ulx restartcancel"] and rights.cancel then RunConsoleCommand("ulx", "restartcancel") return end
    if ulxCmds and ulxCmds["ulx restart"] and rights.restart then RunConsoleCommand("ulx", "restart", "cancel") return end
    if util.NetworkStringToID("restartwarn_cancelreq")~=0 then
        net.Start("restartwarn_cancelreq")
        net.SendToServer()
    end
end

-- Two-step confirm: 1st click arms a 3s confirm window; a 2nd click inside it fires the
-- cancel; a click outside either window is treated as a fresh 1st click.
local function cancelClick(btn)
    local now=RealTime()
    if cooldownUntil and now<cooldownUntil then return end
    if confirmUntil and now<confirmUntil then
        sendCancel()
        confirmUntil=nil
        cooldownUntil=now+3
        btn:SetText("Cancelling...")
        btn:SetEnabled(false)
    else
        confirmUntil=now+3
        btn:SetText("Confirm cancel")
    end
end

-- Lazily-created, parentless DButton: never MakePopup, never gui.EnableScreenClicker.
-- It only receives clicks when the game has already released the cursor elsewhere
-- (context menu, chat, F8), so it never fights normal play for mouse/keyboard focus.
local function ensureCancelButton()
    if IsValid(cancelBtn) then return cancelBtn end
    local b=vgui.Create("DButton")
    b:SetText("Cancel restart")
    b:SetKeyboardInputEnabled(false)
    b:SetTextColor(clear)
    b.DoClick=function(self) cancelClick(self) end
    b.Paint=function(self, w, h)
        draw.RoundedBoxEx(4, 0, 0, w, h, panel, false, false, true, true)
        surface.SetDrawColor(edge)
        surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText(self:GetText(), "ZCRestartSmall", w/2, h/2, self:IsHovered() and white or red, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    b.Think=function(self)
        local now=RealTime()
        if cooldownUntil and now>=cooldownUntil then cooldownUntil=nil; self:SetEnabled(true); self:SetText("Cancel restart") end
        if confirmUntil and now>=confirmUntil then confirmUntil=nil; self:SetText("Cancel restart") end
        if not btnRect or now-btnRect.t>0.25 then self:SetVisible(false) return end
        self:SetVisible(true)
        local bw, bh = 118*scale, 24*scale
        self:SetSize(bw, bh)
        self:SetPos(btnRect.x+btnRect.w-bw, btnRect.y+btnRect.h)
    end
    cancelBtn=b
    return b
end

hook.Add("HUDPaint", "RestartWarning_Draw", function()
    if not state then
        if IsValid(cancelBtn) then cancelBtn:Remove() end
        cancelBtn=nil; btnRect=nil
        return
    end
    local remaining=state.ends-SysTime()
    if (state.cancelled and remaining<=0) or remaining < -45 then
        state=nil
        if IsValid(cancelBtn) then cancelBtn:Remove() end
        cancelBtn=nil; btnRect=nil
        return
    end
    local n=math.max(0, math.ceil(remaining))
    local final=not state.cancelled and n<=10
    local waiting=not state.cancelled and n==0
    local real=not state.preview and not state.cancelled and remaining>0
    local me=LocalPlayer()
    local isAdmin=real and IsValid(me) and canCancel(me)
    if not isAdmin and IsValid(cancelBtn) then cancelBtn:Remove(); cancelBtn=nil; btnRect=nil end

    syncTheme()
    local accent=state.cancelled and green or red
    local span=math.max(state.span or 1, 1)
    local fraction=state.cancelled and 1 or math.Clamp(remaining/span, 0, 1)
    local x, y, w, h

    if remaining>120 and not state.cancelled then
        -- Compact strip for the long tail of a countdown, top-left (the top centre is the GoobOS notification lane).
        w=math.floor(math.min(560*scale, ScrW()-32)); h=math.floor(44*scale); x=math.floor(16*scale); y=math.floor(16*scale)
        box(x, y, w, h, 4)
        local pad=math.floor(14*scale)
        draw.SimpleText("RESTART", "ZCRestartLabel", x+pad, y+math.floor(5*scale), dim)
        local reasonText=state.reason~="" and state.reason or (state.manual and "Staff restart" or "Scheduled server restart")
        draw.SimpleText(fit(reasonText, "ZCRestartSmall", w-pad*2-90*scale), "ZCRestartSmall", x+pad, y+math.floor(21*scale), white)
        draw.SimpleText(string.format("%02d:%02d", math.floor(n/60), n%60), "ZCRestartSmall", x+w-pad, y+math.floor(12*scale), white, TEXT_ALIGN_RIGHT)
        surface.SetDrawColor(red)
        surface.DrawRect(x+2, y+h-3, math.floor((w-4)*fraction), 2)
    else
        -- Full card inside the final two minutes, at the final ten seconds, or when cancelled.
        w=math.floor(math.min(700*scale, ScrW()-32)); h=math.floor((isAdmin and 200 or 180)*scale); x=math.floor((ScrW()-w)/2); y=math.floor(final and 0.12*ScrH() or 28*scale)
        box(x, y, w, h, 4)
        local pad=24*scale
        local label=state.preview and "PREVIEW" or "RESTART"
        draw.SimpleText(label, "ZCRestartLabel", x+pad, y+20*scale, accent)
        local badge=state.cancelled and "CANCELLED" or state.manual and "STAFF" or "SCHEDULED"
        draw.SimpleText(badge, "ZCRestartLabel", x+w-pad, y+20*scale, dim, TEXT_ALIGN_RIGHT)
        local title=state.cancelled and "Restart cancelled" or waiting and "Restart requested" or "Server restart"
        if waiting and state.preview then title="Preview complete" end
        draw.SimpleText(title, "ZCRestartTitle", x+pad, y+54*scale, white)
        local timeText=state.cancelled and "OK" or waiting and "--:--" or string.format("%02d:%02d", math.floor(n/60), n%60)
        draw.SimpleText(timeText, "ZCRestartClock", x+w-pad, y+44*scale, accent, TEXT_ALIGN_RIGHT)
        -- Plain lines only (owner 2026-09-25: no flavour text in the HUD).
        local line=state.cancelled and "Normal play continues."
            or (waiting and remaining < -15) and "Taking longer than expected. Check the server list."
            or waiting and "The server is restarting."
            or "The server restarts when the countdown ends."
        local body=state.reason~="" and state.reason or line
        local hint="You will disconnect briefly. Rejoin when the server is back."
        if state.cancelled then hint="The countdown was cancelled."
        elseif state.preview then hint="Preview only. Nothing will restart."
        elseif waiting then hint="If you disconnect, rejoin in a moment." end
        draw.SimpleText(fit(body, "ZCRestartBody", w-pad*2), "ZCRestartBody", x+pad, y+111*scale, white)
        draw.SimpleText(fit(hint, "ZCRestartSmall", w-pad*2), "ZCRestartSmall", x+pad, y+143*scale, dim)
        if isAdmin then
            draw.SimpleText(fit("Staff: type !restart cancel, or free the cursor and click Cancel", "ZCRestartSmall", w-pad*2), "ZCRestartSmall", x+pad, y+164*scale, dim)
        end
        surface.SetDrawColor(edge)
        surface.DrawRect(x+pad, y+h-12*scale, w-pad*2, 3*scale)
        surface.SetDrawColor(accent)
        surface.DrawRect(x+pad, y+h-12*scale, (w-pad*2)*fraction, 3*scale)
    end

    if isAdmin then
        btnRect={x=x, y=y, w=w, h=h, t=RealTime()}
        ensureCancelButton()
    end

    if not state.cancelled and n~=lastTick then
        lastTick=n
        if sounds:GetBool() and (n==10 or (n>=1 and n<=5)) then surface.PlaySound("buttons/blip1.wav") end
    end
end)

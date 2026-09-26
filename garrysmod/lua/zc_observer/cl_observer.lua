if not CLIENT then return end
local previous=ZCObserver
if previous and previous.Shutdown then previous.Shutdown() end
local O={Version="20260924.observer4",legacy={}}
-- Keep debrief data across the no-restart UI refresh.
if previous then
    for _,key in ipairs({"Snapshot","Pending","PendingUntil","ReceivedAt","Revision","DeadSince"}) do O[key]=previous[key] end
end
ZCObserver=O
local bg=Color(17,24,35,246)
local card=Color(32,44,62,235)
local text=Color(226,237,251)
local dim=Color(147,173,202)
local cyan=Color(99,202,244)
local rose=Color(235,137,157)
surface.CreateFont("ZCObserver.Title",{font="Roboto",size=28,weight=700,antialias=true})
surface.CreateFont("ZCObserver.Body",{font="Roboto",size=16,weight=400,antialias=true})
surface.CreateFont("ZCObserver.Small",{font="Roboto",size=13,weight=500,antialias=true})

local function enabled()
    local me=LocalPlayer()
    return IsValid(me) and me:GetNWBool("ZCObserverEnabled",false)
end
local function replay()
    local viewer=ZCKillcamView
    return viewer and viewer.ObserverState and viewer.ObserverState() or {}
end
local function pretty(value)
    return tostring(value or "Unknown"):gsub("^weapon_", ""):gsub("_", " ")
end
local function roundId() return math.floor(zb and zb.ROUND_START or 0) end
local function close()
    if IsValid(O.Frame) then O.Frame:Remove() end
    O.Frame=nil
end
-- 2026-09-24 (owner: "remove that block of text"): Pat's Spectator HUD (workshop 3686174019, mounted server-side,
-- client hooks below) is retired for good, not only while the observer is on. A workshop addon's client autorun can
-- register its hooks AFTER this file loads, so the removal repeats every 2 s and on InitPostEntity, and its two
-- hooks are no longer in the legacy list (which would have put them back on O.Shutdown()).
local function retirePat()
    hook.Remove("HUDPaint","PAT_SpectatorAssist_HUD")
    hook.Remove("OnPlayerChat","PAT_SpectatorAssist_SystemMessages")
    -- 2026-09-24 (late, owner: "get rid of this white text"): "[ZCITY] Spectate ESP" (workshop 3695771892) drew the
    -- "Disable / Enable display of nicknames on ALT" hint and the old name/health tags; ZCObserver.ESP (bottom of this
    -- file) replaces both. Its net receiver (ZCity_Spectator_Health_Sync -> ply.ZCitySpectatorHealth) is kept.
    hook.Remove("HUDPaint","ZCity_Spectate_ALT_ESP")
end
retirePat()
timer.Create("ZCObserver.RetirePat", 2, 0, retirePat)
hook.Add("InitPostEntity", "ZCObserver.RetirePat", retirePat)
local legacy={
    {"HUDPaint","FUCKINGSAMENAMEUSEDINHOOKFUCKME"},
}
local function ownLegacy(on)
    for _,item in ipairs(legacy) do
        local event,id=item[1],item[2]
        local fn=(hook.GetTable()[event] or {})[id]
        if on then
            if fn then O.legacy[id]=fn; hook.Remove(event,id) end
        elseif O.legacy[id] and not fn then hook.Add(event,id,O.legacy[id]) end
    end
end
function O.Shutdown()
    close(); ownLegacy(false)
    if IsValid(O.Tile) then O.Tile:Remove() end
    if O.DockCleanup then O.DockCleanup() end
end

net.Receive("ZCObserverSnapshot",function()
    local len=net.ReadUInt(16)
    if len<2 or len>24000 then return end
    local raw=net.ReadData(len)
    local value=raw and util.JSONToTable(raw)
    if not istable(value) or not enabled() then return end
    if value.clear then O.Pending=nil; O.Snapshot=nil; O.Revision=(O.Revision or 0)+1; close(); return end
    if value.map~=game.GetMap() or tonumber(value.round)~=roundId() then return end
    if not istable(value.injuries) or #value.injuries>24 or not istable(value.condition) then return end
    if LocalPlayer():Alive() then O.Pending=value; O.PendingUntil=RealTime()+2; return end
    O.Snapshot=value; O.ReceivedAt=RealTime(); O.Revision=(O.Revision or 0)+1
end)

local function label(parent, content, font, color, height)
    local p=vgui.Create("DLabel",parent)
    p:Dock(TOP); p:DockMargin(14,4,14,2); p:SetTall(height or 24)
    p:SetFont(font or "ZCObserver.Body"); p:SetTextColor(color or text)
    p:SetText(tostring(content)); p:SetWrap(true)
    return p
end
local function button(parent, title, fn)
    local p=vgui.Create("DButton",parent)
    p:SetText(title); p:SetFont("ZCObserver.Small"); p:SetTextColor(text)
    p:SetKeyboardInputEnabled(false)
    p.Paint=function(self,w,h)
        self.blend=Lerp(math.Clamp(FrameTime()*14,0,1),self.blend or 0,self:IsHovered() and 1 or 0)
        draw.RoundedBox(9,0,0,w,h,Color(51,103,157,110+self.blend*110))
    end
    p.DoClick=fn
    return p
end
local function block(parent,height)
    local p=vgui.Create("DPanel",parent)
    p:Dock(TOP); p:DockMargin(0,0,0,10); p:SetTall(height)
    p.Paint=function(_,w,h) draw.RoundedBox(12,0,0,w,h,card) end
    return p
end
local groups={[0]="body",[1]="head",[2]="chest",[3]="abdomen",[4]="left arm",[5]="right arm",[6]="left leg",[7]="right leg",[10]="gear"}

function O.Open()
    if not enabled() then return end
    close()
    local state=replay()
    if state.highlight or state.playing then return end
    local frame=vgui.Create("DFrame")
    O.Frame=frame
    frame:SetTitle(""); frame:ShowCloseButton(false); frame:SetDraggable(false)
    frame:SetSize(math.min(920,ScrW()-64),math.min(690,ScrH()-96)); frame:Center(); frame:MakePopup()
    frame:DockPadding(18,76,18,18)
    local born=RealTime()
    frame.Paint=function(_,w,h)
        draw.RoundedBox(18,0,0,w,h,bg)
        draw.RoundedBoxEx(18,0,0,w,62,Color(29,42,61,255),true,true,false,false)
        draw.SimpleText("[GoobOS]", "ZCObserver.Small",24,14,cyan)
        draw.SimpleText("AFTERLIFE", "ZCObserver.Title",24,31,text)
        draw.SimpleText("DEBRIEF  /  REPLAY  /  SPECTATE", "ZCObserver.Small",w-76,37,dim,TEXT_ALIGN_RIGHT)
    end
    local exit=button(frame,"×",close); exit:SetSize(34,32)
    frame.PerformLayout=function(self,w,h) exit:SetPos(w-48,15) end
    local footer=vgui.Create("DPanel",frame); footer:Dock(BOTTOM); footer:SetTall(40); footer.Paint=function() end
    local status=label(footer,"Your recordings and reports stay with the existing replay system.","ZCObserver.Small",dim,36)
    local tabs=vgui.Create("DPanel",frame); tabs:Dock(TOP); tabs:SetTall(38); tabs:DockMargin(0,0,0,12); tabs.Paint=function() end
    local scroll=vgui.Create("DScrollPanel",frame); scroll:Dock(FILL)
    local page="debrief"
    local function action(name,index)
        local view=ZCKillcamView
        if not view or not view.ObserverAction then status:SetText("Replay integration is not loaded yet."); return end
        local ok,reason=view.ObserverAction(name,index)
        if not ok then status:SetText(reason or "This action is unavailable.")
        elseif name=="save" then status:SetText("Save requested. The replay system will confirm the result.")
        elseif name=="report" then close()
        else close() end
    end
    local function fill()
        scroll:Clear()
        local snapshot=O.Snapshot
        local s=replay()
        if page=="replays" then
            if not s.seq then
                local empty=block(scroll,112)
                label(empty,"No replay available for this life","ZCObserver.Title",text,36)
                label(empty,"A recording appears here only when the replay system sends an eligible sequence.",nil,dim,52)
            else
                for index,inst in ipairs(s.seq.instances or {}) do
                    local row=block(scroll,130)
                    label(row,string.format("%02d   %s",index,tostring(inst.attacker or "Recorded moment")),"ZCObserver.Title",text,34)
                    label(row,string.format("%s  ·  %.1f harm  ·  %.1fs before death",pretty(inst.wep),tonumber(inst.dmg) or 0,tonumber(inst.ago) or 0),nil,dim,28)
                    local actions=vgui.Create("DPanel",row); actions:Dock(BOTTOM); actions:DockMargin(14,0,14,12); actions:SetTall(32); actions.Paint=function() end
                    local watch=button(actions,"Watch moment",function() action("watch",index) end); watch:Dock(LEFT); watch:SetWide(124)
                    local report=button(actions,"Report",function() action("report",index) end); report:Dock(LEFT); report:DockMargin(8,0,0,0); report:SetWide(86)
                    report:SetEnabled(inst.reportable==true)
                    report:SetTooltip(inst.reportable and "Submit this recorded incident for review" or "Not eligible for a replay report")
                end
                local actions=block(scroll,48)
                local save=button(actions,"Save this life",function() action("save",1) end); save:Dock(LEFT); save:DockMargin(8,8,8,8); save:SetWide(132)
                local tactical=button(actions,"Tactical review",function() action("tactical",1) end); tactical:Dock(LEFT); tactical:DockMargin(0,8,8,8); tactical:SetWide(132)
            end
            local archive=button(scroll,"Open replay archive",function() close(); RunConsoleCommand("zc_killcam") end)
            archive:Dock(TOP); archive:SetTall(38)
        elseif page=="timeline" then
            local hits=snapshot and snapshot.injuries or {}
            if #hits==0 then label(scroll,"No recent injuries were captured for this life.",nil,dim,48) end
            for i=#hits,1,-1 do
                local hit=hits[i]
                local row=block(scroll,88)
                label(row,string.format("−%.1fs   %s",tonumber(hit.ago) or 0,tostring(hit.name or "Unknown")),nil,text,28)
                label(row,string.format("%s  ·  %s  ·  %.2f harm",pretty(hit.weapon),groups[hit.group] or "body",tonumber(hit.harm) or 0),nil,dim,42)
            end
        else
            local summary=block(scroll,116)
            label(summary,"Your last moments","ZCObserver.Title",text,36)
            label(summary,snapshot and (snapshot.selfInflicted and "The engine recorded self-inflicted death." or "Recorded death source: "..pretty(snapshot.cause)) or "A personal debrief will appear after your next death.",nil,dim,50)
            if snapshot then
                local vitals=snapshot.condition or {}
                local condition=block(scroll,86)
                label(condition,"FINAL CONDITION","ZCObserver.Small",cyan,22)
                label(condition,string.format("Blood  %.0f mL       Pulse  %.0f       Pain  %.0f",tonumber(vitals.blood) or 0,tonumber(vitals.pulse) or 0,tonumber(vitals.pain) or 0),nil,text,36)
                local contributors,total={},0
                for _,hit in ipairs(snapshot.injuries or {}) do
                    local key=(hit.sid and hit.sid~="") and hit.sid or hit.name
                    local item=contributors[key] or {name=hit.name,harm=0}; contributors[key]=item
                    item.harm=item.harm+(tonumber(hit.harm) or 0); total=total+(tonumber(hit.harm) or 0)
                end
                local sorted={}; for _,item in pairs(contributors) do sorted[#sorted+1]=item end
                table.sort(sorted,function(a,b) return a.harm>b.harm end)
                label(scroll,"RECENT INJURY CONTRIBUTIONS","ZCObserver.Small",cyan,28)
                for i=1,math.min(5,#sorted) do
                    local item=sorted[i]; local row=block(scroll,62)
                    local share=total>0 and item.harm/total or 0
                    row.Paint=function(_,w,h)
                        draw.RoundedBox(10,0,0,w,h,card)
                        draw.RoundedBox(2,14,h-12,math.max(1,(w-28)*share),3,cyan)
                    end
                    label(row,string.format("%s   %.0f%%",tostring(item.name),share*100),nil,text,32)
                end
                label(scroll,"Harm is injury severity, not HP damage. A contribution does not establish the cause of death.","ZCObserver.Small",dim,44)
            end
        end
    end
    for _,item in ipairs({{"Debrief","debrief"},{"Injury timeline","timeline"},{"Replay moments","replays"}}) do
        local tab=button(tabs,item[1],function() page=item[2]; fill() end)
        tab:Dock(LEFT); tab:SetWide(142); tab:DockMargin(0,0,8,0)
    end
    local revision=O.Revision
    local replayId=state.id
    frame.Think=function(self)
        if not enabled() or not IsValid(LocalPlayer()) then close(); return end
        local current=replay()
        if current.highlight or current.playing then close(); return end
        if revision~=O.Revision or replayId~=current.id then revision=O.Revision; replayId=current.id; fill() end
        local t=math.Clamp((RealTime()-born)/0.18,0,1); self:SetAlpha(255*t*t*(3-2*t))
    end
    fill()
end
concommand.Add("zc_observer",O.Open)

-- The shared launcher owns tile geometry. Fixed Home coordinates are only
-- valid for the legacy two-button shell, not the responsive GoobOS grid.
local function installApp(chat)
    if not IsValid(chat) or not IsValid(chat.phoneHome) then return end
    local grid=IsValid(chat.goobGrid) and chat.goobGrid or nil
    local parent=grid or chat.phoneHome
    local current=chat.ZCObserverApp
    if IsValid(current) then
        if current:GetParent()==parent then O.Tile=current; return end
        current:Remove() -- migrate an old overlay or a rebuilt launcher
    end
    local tile=button(parent,"",function() chat:SetActive(false); O.Open() end)
    O.Tile=tile; chat.ZCObserverApp=tile
    tile.ZCObserverGrid=grid; tile.ZCAppID="afterlife"
    tile:SetSize(grid and 100 or 104,grid and 104 or 98)
    tile:SetTooltip("Afterlife: debrief and replay moments")
    tile.Paint=function(self,w,h)
        if grid then
            local theme=ZCGoobApps and ZCGoobApps.Theme
            local accent=theme and theme.accent or cyan
            draw.RoundedBox(12,0,0,w,h,theme and (self:IsHovered() and theme.hover or theme.card) or card)
            draw.RoundedBox(14,w/2-26,12,52,52,Color(accent.r,accent.g,accent.b,35))
            surface.SetDrawColor(accent)
            surface.DrawOutlinedRect(w/2-14,26,28,24,2)
            surface.DrawLine(w/2-8,41,w/2-2,32)
            surface.DrawLine(w/2-2,32,w/2+4,42)
            surface.DrawLine(w/2+4,42,w/2+10,36)
            draw.SimpleText("Afterlife","GoobBody",w/2,83,theme and theme.text or text,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
        else
            draw.RoundedBox(15,23,4,58,58,Color(49,93,116))
            surface.SetDrawColor(cyan); surface.DrawOutlinedRect(38,19,28,24,2)
            surface.DrawLine(44,34,50,25); surface.DrawLine(50,25,56,35); surface.DrawLine(56,35,62,29)
            draw.SimpleText("Afterlife","DermaDefaultBold",w/2,74,text,TEXT_ALIGN_CENTER)
        end
    end
    if grid then
        if ZCGoobApps and ZCGoobApps.Layout then
            ZCGoobApps.Layout(chat,chat:GetWide(),chat:GetTall())
        end
        grid:Layout()
    end
end
local nextUpdate=0
hook.Add("Think","ZCObserver.Lifecycle",function()
    if RealTime()<nextUpdate then return end
    nextUpdate=RealTime()+0.15
    local on=enabled(); ownLegacy(on)
    if not on then close(); if IsValid(O.Tile) then O.Tile:Remove(); O.Tile=nil end return end
    local me=LocalPlayer()
    if me:Alive() then O.DeadSince=nil else O.DeadSince=O.DeadSince or RealTime() end
    if O.Pending then
        if RealTime()>O.PendingUntil or O.Pending.round~=roundId() then O.Pending=nil
        elseif not me:Alive() then
            O.Snapshot=O.Pending; O.Pending=nil; O.ReceivedAt=RealTime(); O.Revision=(O.Revision or 0)+1
        end
    end
    if O.Snapshot and (me:Alive() or O.Snapshot.round~=roundId()) then O.Snapshot=nil; O.Revision=(O.Revision or 0)+1; close() end
    local chat=hg and hg.chat
    installApp(chat)
    if IsValid(O.Tile) and IsValid(chat) then
        local home=chat:GetActive() and chat.phonePage=="home"
        if IsValid(O.Tile.ZCObserverGrid) then
            -- Keep visibility inherited from Home; relayout once on navigation,
            -- not every Think. Never overwrite grid-owned tile coordinates.
            if O.Tile.ZCObserverHomeVisible~=home then
                O.Tile.ZCObserverHomeVisible=home
                O.Tile.ZCObserverGrid:Layout()
            end
        else
            O.Tile:SetPos(144,chat:GetTall()-44>=242 and 119 or 14)
            O.Tile:SetVisible(home)
        end
    end
end)

-- Spectator dock card style: near-black translucent panel + dark-red accent, hg_font/Bahnschrift
-- family - matching zc_killcam's overlay tokens (cl_life.lua PANEL/EDGE colours and its face()
-- font helper, read 2026-09-23) rather than the blue GoobOS chrome the debrief popup above still
-- uses. Kept as dedicated fonts/colours scoped to this card so the debrief frame's own look is
-- untouched.
local function dockFace()
    local cv=GetConVar("hg_font")
    local name=cv and cv:GetString() or ""
    return name~="" and name or "Bahnschrift"
end
local espNameSize={} -- player -> {name,w,h}; measured once per name, cleared when the fonts are rebuilt
local function dockFonts()
    espNameSize={}
    surface.CreateFont("ZCObserver.DockHead",{font=dockFace(),size=10,weight=600,antialias=true})
    surface.CreateFont("ZCObserver.DockName",{font=dockFace(),size=18,weight=600,antialias=true})
    surface.CreateFont("ZCObserver.DockTeam",{font=dockFace(),size=12,weight=500,antialias=true})
    surface.CreateFont("ZCObserver.DockBar",{font=dockFace(),size=12,weight=600,antialias=true})
    surface.CreateFont("ZCObserver.EspName",{font=dockFace(),size=15,weight=600,antialias=true})
    surface.CreateFont("ZCObserver.EspSmall",{font=dockFace(),size=11,weight=600,antialias=true})
end
dockFonts()
hook.Add("OnScreenSizeChanged","ZCObserver.DockFonts",dockFonts)
cvars.AddChangeCallback("hg_font",dockFonts,"ZCObserver.DockFonts")

-- Colours cached once (no per-frame Color() allocations).
local dockPanel=Color(15,15,17,232)
local dockShadow=Color(0,0,0,90)
local dockEdge=Color(83,19,23,255)
local dockDim=Color(170,170,170)
local dockWhite=Color(235,235,235)
local dockBarBg=Color(12,12,12,235)
local dockHealthy=Color(119,157,135)
local dockWounded=Color(215,153,74)
local dockDowned=Color(194,58,61)
local dockDead=Color(65,63,65)
local dockFill=Color(119,157,135)
local dockAvatarFade=Color(15,15,17,0)
local dockBot=Color(61,62,64)
local dockTarget,dockShown,dockPhase,dockPhaseAt=nil,nil,"hidden",0
local dockName,dockTeam,dockTeamColour="","",dockDim
local dockAvatar,dockAvatarTarget=nil,nil
local dockFraction=0

local function dockClearAvatar()
    if IsValid(dockAvatar) then dockAvatar:Remove() end
    dockAvatar=nil; dockAvatarTarget=nil
end
O.DockCleanup=dockClearAvatar

local function dockFit(text,font,width)
    surface.SetFont(font)
    if surface.GetTextSize(text)<=width then return text end
    local length=string.utf8len(text)
    repeat
        length=length-1
        text=string.utf8sub(text,1,length)
    until length<=0 or surface.GetTextSize(text.."…")<=width
    return text.."…"
end

-- Dock revamp (owner 2026-09-24, late: "revamp the spectator ESP that shows player name and health"): a tighter
-- card - 42 px avatar (the voice orb around it is 75% of the old ring), name + team on one column, state word and
-- health percentage on the right, a 5 px health strip along the bottom. Same anchor, same fade/slide.
local DOCK_W,DOCK_H,DOCK_AV=400,68,42
local function dockSetTarget(target)
    if not IsValid(target) or not target:IsPlayer() then return end
    dockShown=target
    dockName=target:Nick()
    local teamId=target:Team()
    dockTeam=team.GetName(teamId) or ""
    dockTeamColour=team.GetColor(teamId) or dockDim
    local width=math.min(DOCK_W,ScrW()-32)
    local textW=math.max(16,width-DOCK_AV-28-14-110) -- avatar + gutters + the state column on the right
    dockName=dockFit(dockName,"ZCObserver.DockName",textW)
    dockTeam=dockFit(dockTeam,"ZCObserver.DockTeam",textW)
    dockAvatarTarget=nil
    if not target:IsBot() then
        if not IsValid(dockAvatar) then
            dockAvatar=vgui.Create("AvatarImage")
            dockAvatar:SetMouseInputEnabled(false)
            dockAvatar:SetKeyboardInputEnabled(false)
            dockAvatar:SetPaintedManually(true)
            dockAvatar:SetSize(DOCK_AV,DOCK_AV)
        end
        dockAvatar:SetPlayer(target,64)
        dockAvatarTarget=target
    end
    dockFraction=target:Alive() and math.Clamp(target:Health()/math.max(1,target:GetMaxHealth()),0,1) or 0
end

local function mixInto(out,a,b,t)
    out.r=Lerp(t,a.r,b.r); out.g=Lerp(t,a.g,b.g); out.b=Lerp(t,a.b,b.b)
end
local function dockMix(a,b,t) mixInto(dockFill,a,b,t) end

-- State word + colour for the bar. Organism fields (blood/pain/pulse, ZCObserver.Debrief above)
-- are only ever networked to a spectator once, at their OWN death - there is no continuous
-- organism feed for an arbitrary live spectate target. So this reads the same signals the rest of
-- the gamemode already networks to every client: Alive(), Health() vs GetMaxHealth(), and the
-- fake-tier downed state (GetNWEntity("FakeRagdoll"), set server-side in
-- homigrad/fake/sv_tier_0.lua while a player is knocked down but not dead; cl_fake.lua's own
-- spectate-target resolver treats a valid FakeRagdoll the same way).
-- PROVISIONAL(2026-09-23, the 50% Wounded cutoff and the Healthy/Wounded/Downed/Dead word choice
-- are a guess - no canonical threshold or state-word list was found in the codebase, ratify-by:
-- 2026-10-07)
local function dockState(target)
    if not IsValid(target) or not target:IsPlayer() or not target:Alive() then return "Dead",dockDead end
    if IsValid(target:GetNWEntity("FakeRagdoll")) then return "Downed",dockDowned end
    local hp,max=target:Health(),math.max(1,target:GetMaxHealth())
    if hp<=max*0.5 then return "Wounded",dockWounded end
    return "Healthy",dockHealthy
end

-- The blood-scaled health the retired workshop ESP's server half still feeds (ply.ZCitySpectatorHealth, 0-100 =
-- blood/50, 2 Hz, only to spectators); Health() vs GetMaxHealth() when it is absent.
local function syncedHealth(p)
    local synced=p.ZCitySpectatorHealth
    if isnumber(synced) then return math.Clamp(synced/100,0,1) end
    return math.Clamp(p:Health()/math.max(1,p:GetMaxHealth()),0,1)
end

hook.Add("HUDPaint","ZCObserver.Dock",function()
    if not enabled() then dockClearAvatar(); dockTarget=nil; dockShown=nil; dockPhase="hidden"; O.DockShownPly=nil; return end
    local me=LocalPlayer()
    if not IsValid(me) or me:Alive() then
        dockClearAvatar(); dockTarget=nil; dockShown=nil; dockPhase="hidden"; O.DockShownPly=nil
        return
    end
    if IsValid(O.Frame) or gui.IsGameUIVisible() or input.IsKeyDown(KEY_TAB) then return end
    if RealTime()-(O.DeadSince or RealTime())<6 then return end
    if hg and IsValid(hg.chat) and hg.chat:GetActive() then return end
    local state=replay()
    if state.active then return end -- replay/highlight UI owns its entire handoff
    local target=me:GetNWEntity("spect")
    if not IsValid(target) or not target:IsPlayer() then target=nil end
    -- free roam (gamemode viewmode 3 = OBS_MODE_ROAMING; the NW entity keeps the last target) watches nobody:
    -- no card (owner 2026-09-24 late)
    if me:GetNWInt("viewmode",1)==3 then target=nil end
    local now=RealTime()
    if target~=dockTarget then
        dockTarget=target
        if dockShown then dockPhase="out"; dockPhaseAt=now
        elseif target then dockSetTarget(target); dockPhase="in"; dockPhaseAt=now end
    end
    if dockPhase=="out" and now-dockPhaseAt>=0.15 then
        dockShown=nil
        if IsValid(dockTarget) then dockSetTarget(dockTarget); dockPhase="in"; dockPhaseAt=now
        else dockClearAvatar(); dockPhase="hidden" end
    end
    if dockPhase=="hidden" or not IsValid(dockShown) then O.DockShownPly=nil; return end
    O.DockShownPly=dockShown -- GoobOS voice: the column leaves this player to the dock (voice.lua V.PaintDockOrb)
    local transition=math.Clamp((now-dockPhaseAt)/0.15,0,1)
    if dockPhase=="in" and transition>=1 then dockPhase="shown" end
    transition=transition*transition*(3-2*transition)
    local alpha=dockPhase=="out" and 1-transition or dockPhase=="in" and transition or 1
    local slide=dockPhase=="out" and transition*8 or dockPhase=="in" and (1-transition)*8 or 0
    local w=math.min(DOCK_W,ScrW()-32); local h=DOCK_H
    local x=(ScrW()-w)/2; local y=ScrH()-h-42+slide
    surface.SetAlphaMultiplier(alpha)
    draw.RoundedBox(6,x-8,y-3,w+16,h+8,dockShadow)
    draw.RoundedBox(6,x,y,w,h,dockEdge)
    draw.RoundedBox(6,x+1,y+1,w-2,h-2,dockPanel)
    draw.RoundedBox(0,x+1,y+8,2,h-16,dockTeamColour)
    local ax,ay=x+14,y+(h-DOCK_AV)/2
    local voice=ZCGoobApps and ZCGoobApps.Voice
    -- the spectated player's voice ring goes under the avatar as discs, its electricity over it (voice.lua V.PaintDockOrb)
    if voice and isfunction(voice.PaintDockOrb) then pcall(voice.PaintDockOrb,dockShown,ax,ay,DOCK_AV,alpha*255,"under",dockPanel) end
    draw.RoundedBox(0,ax-2,ay-2,DOCK_AV+4,DOCK_AV+4,dockTeamColour)
    draw.RoundedBox(0,ax,ay,DOCK_AV,DOCK_AV,dockBot)
    if IsValid(dockShown) and not dockShown:IsBot() and IsValid(dockAvatar) and dockAvatarTarget==dockShown then
        dockAvatar:SetPos(ax,ay)
        dockAvatar:PaintManual()
        if alpha<1 then
            dockAvatarFade.a=(1-alpha)*255
            draw.RoundedBox(0,ax,ay,DOCK_AV,DOCK_AV,dockAvatarFade)
        end
    end
    if voice and isfunction(voice.PaintDockOrb) then pcall(voice.PaintDockOrb,dockShown,ax,ay,DOCK_AV,alpha*255,"over") end
    local tx=ax+DOCK_AV+14
    draw.SimpleText("SPECTATING","ZCObserver.DockHead",tx,y+8,dockDim)
    draw.SimpleText(dockName,"ZCObserver.DockName",tx,y+19,dockWhite)
    draw.SimpleText(dockTeam,"ZCObserver.DockTeam",tx,y+40,dockTeamColour)
    local label,colour=dockState(dockShown)
    local fraction=label=="Dead" and 0 or syncedHealth(dockShown)
    dockFraction=Lerp(1-math.exp(-FrameTime()*9),dockFraction,fraction)
    if label=="Dead" then dockMix(dockDead,dockDead,0)
    elseif label=="Downed" then dockMix(dockDowned,dockDowned,0)
    elseif fraction<=0.5 then dockMix(dockDowned,dockWounded,fraction*2)
    else dockMix(dockWounded,dockHealthy,(fraction-0.5)*2) end
    dockFill.a=label=="Downed" and (180+math.sin(now*2.4)*55) or 255
    draw.SimpleText(label,"ZCObserver.DockBar",x+w-14,y+17,colour,TEXT_ALIGN_RIGHT)
    if label~="Dead" then draw.SimpleText(math.Round(dockFraction*100).."%","ZCObserver.DockName",x+w-14,y+31,dockWhite,TEXT_ALIGN_RIGHT) end
    draw.RoundedBox(2,x+1,y+h-6,w-2,5,dockBarBg)
    if dockFraction>0.001 then draw.RoundedBox(2,x+1,y+h-6,(w-2)*dockFraction,5,dockFill) end
    surface.SetAlphaMultiplier(1)
end)

-- === Spectator ESP (owner 2026-09-24, late) =======================================================================
-- Replaces "[ZCITY] Spectate ESP" (workshop 3695771892, lua/autorun/client/cl_zcity_spectate_esp.lua), whose
-- HUDPaint hook is retired in retirePat() above - its white "Disable / Enable display of nicknames on ALT" hint
-- went with it. Its server half is untouched and still feeds ply.ZCitySpectatorHealth (syncedHealth above).
-- Every living player gets a tag at head height (over the ragdoll when they are down): name on a dark plate with a
-- team stripe, the same health ramp as the dock underneath, "DOWNED" while knocked down. Near tags are solid, far
-- ones fade to a third. ALT still toggles the names, silently, and never while typing into chat/console/a field.
local ESP_RANGE,ESP_MAX=1600,24
local espNames,espAltWas=true,false
local espPlate=Color(12,12,14,205)
local espBarBg=Color(0,0,0,170)
local espFill=Color(0,0,0)
local espLift=Vector(0,0,12)
local function espTyping()
    if gui.IsConsoleVisible() or gui.IsGameUIVisible() then return true end
    if hg and IsValid(hg.chat) and hg.chat:GetActive() then return true end
    local focus=vgui.GetKeyboardFocus()
    return IsValid(focus) and isfunction(focus.IsEditing) and focus:IsEditing()==true
end
hook.Add("HUDPaint","ZCObserver.ESP",function()
    local me=LocalPlayer()
    if not IsValid(me) then return end
    if me:Alive() and me:GetObserverMode()==OBS_MODE_NONE then return end
    local alt=input.IsKeyDown(KEY_LALT) or input.IsKeyDown(KEY_RALT)
    if alt and not espAltWas and not espTyping() then espNames=not espNames end
    espAltWas=alt
    if not espNames or IsValid(O.Frame) or gui.IsGameUIVisible() or replay().active then return end
    local eye=EyePos()
    local spect=me:GetNWEntity("spect")
    local u=math.Clamp(math.min(ScrW()/1920,ScrH()/1080),0.62,1.5)
    local pad,barH=math.floor(6*u),math.max(2,math.floor(3*u))
    local drawn=0
    local voice=ZCGoobApps and ZCGoobApps.Voice -- GoobOS voice inside the tag (voice.lua V.TagVoiceWidth/V.PaintTagVoice)
    for _,p in ipairs(player.GetAll()) do
        if drawn>=ESP_MAX then break end
        if p~=me and p:Alive() and not p:IsDormant() then
            local downed=IsValid(p:GetNWEntity("FakeRagdoll"))
            local body=p:GetNWEntity("Ragdoll")
            if not IsValid(body) and downed then body=p:GetNWEntity("FakeRagdoll") end
            local pos=IsValid(body) and (body:GetPos()+espLift) or (p:EyePos()+espLift)
            local dist=eye:Distance(pos)
            if dist<=ESP_RANGE and not (p==spect and dist<64) then
                local sp=pos:ToScreen()
                if sp.visible then
                    local near=1-math.Clamp(dist/ESP_RANGE,0,1)
                    local name=p:Nick()
                    local size=espNameSize[p]
                    if not size or size.name~=name then
                        surface.SetFont("ZCObserver.EspName")
                        local w,h=surface.GetTextSize(name)
                        size={name=name,w=w,h=h}
                        espNameSize[p]=size
                    end
                    local tw,th=size.w,size.h
                    -- a speaking player's tag widens for the voice visualizer (owner 2026-09-24 late: voice lives in the
                    -- ESP tag, spectators only, off with ALT like the rest of it); 0 while silent, eases shut after
                    local vw=(voice and isfunction(voice.TagVoiceWidth)) and voice.TagVoiceWidth(p,u) or 0
                    local bw=math.max(tw+pad*2+4,math.floor(76*u))+vw
                    local bh=th+pad+barH+math.floor(5*u)
                    local bx,by=math.floor(sp.x-bw/2),math.floor(sp.y-bh-4)
                    local tc=team.GetColor(p:Team()) or dockDim
                    local frac=syncedHealth(p)
                    if downed then mixInto(espFill,dockDowned,dockDowned,0)
                    elseif frac<=0.5 then mixInto(espFill,dockDowned,dockWounded,frac*2)
                    else mixInto(espFill,dockWounded,dockHealthy,(frac-0.5)*2) end
                    espFill.a=255
                    surface.SetAlphaMultiplier(0.35+0.65*near)
                    if vw>0 then pcall(voice.PaintTagVoice,p,bx,by,bw,bh,"under",u,0.35+0.65*near) end -- outline, superadmin electricity, burst
                    draw.RoundedBox(4,bx,by,bw,bh,espPlate)
                    draw.RoundedBox(0,bx,by+4,2,bh-8,tc)
                    draw.SimpleText(name,"ZCObserver.EspName",sp.x+1-math.floor(vw/2),by+math.floor(pad/2),dockWhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_TOP)
                    if vw>0 then pcall(voice.PaintTagVoice,p,bx+bw-vw,by+math.floor(pad/2),vw,th,"bars",u,0.35+0.65*near) end -- the visualizer
                    draw.RoundedBox(2,bx+pad,by+bh-barH-math.floor(3*u),bw-pad*2,barH,espBarBg)
                    if frac>0.001 then draw.RoundedBox(2,bx+pad,by+bh-barH-math.floor(3*u),math.floor((bw-pad*2)*frac),barH,espFill) end
                    if downed then draw.SimpleText("DOWNED","ZCObserver.EspSmall",sp.x,by+bh+2,dockDowned,TEXT_ALIGN_CENTER,TEXT_ALIGN_TOP) end
                    surface.SetAlphaMultiplier(1)
                    drawn=drawn+1
                end
            end
        end
    end
end)

local I=ZCityInteractions
local offer,nonce,waiting,nextRequest=nil,0,nil,0
local held,fired,armedAt=false,false,nil
local actionToken
local notice,noticeUntil
local liveLabel -- label of the last live grab, shown while its entry rewinds after key-up
-- Live grab: the server started the paired entry at stage 1. Its replicated
-- phase clock, not armedAt, is the progress; there is no stage 2.
local function entryState()
    local g=ZCityHostage and ZCityHostage.Gameplay
    local p=LocalPlayer()
    if not g or not g.EntryProgress or not IsValid(p) or g.Role(p)~="captor" then return end
    local phase=p:GetNWString("zch_phase")
    if phase=="" then return end
    return phase,g.EntryProgress(p)
end
-- Truncated display name for a live target; players only, never the attacker.
local function targetName(t)
    if not IsValid(t) or not t.IsPlayer or not t:IsPlayer() then return end
    local n=t.GetPlayerName and t:GetPlayerName() or t:Nick()
    if not n or n=="" then return end
    return #n>18 and string.sub(n,1,18) or n
end
-- Being grabbed, from the victim's own view: the offer/session flow never
-- hands the victim an offer (I.QuickChoice only answers the session's captor),
-- so this reads the replicated role/phase directly instead.
local function victimCue()
    local p=LocalPlayer()
    if not IsValid(p) or p:GetNWString("zch_role")~="victim" then return end
    local phase=p:GetNWString("zch_phase")
    if phase~="entry" and phase~="entry_reverse" and phase~="attempt" then return end
    return "Being grabbed","hold to resist"
end
local function send(stage)
    if not offer then return end
    net.Start("zci_quick_press") net.WriteUInt(offer.token,32) net.WriteUInt(stage,8) net.SendToServer()
end
local function cancel()
    if held and not fired then send(0) end
    held=false fired=false armedAt=nil offer=nil
end
local function inputAvailable()
    return system.HasFocus() and not gui.IsGameUIVisible() and not vgui.CursorVisible()
end
local function nearby(p)
    if p:GetNWInt("zch_session")~=0 or p:GetNWInt("zsf_id")~=0 or p:GetNWString("zci_native")~="" then return true end
    local g=ZCityHostage and ZCityHostage.Gameplay
    local reach=g and g.TraceReach(p) or 180
    local trace=util.TraceHull({start=p:EyePos(),endpos=p:EyePos()+p:GetAimVector()*math.max(180,reach),
        mins=Vector(-5,-5,-5),maxs=Vector(5,5,5),filter=p,mask=MASK_SHOT})
    return IsValid(trace.Entity) and (trace.Entity:IsPlayer() or trace.Entity:IsRagdoll())
end
-- The circle owns the shortcut: cl_context always loads first (sh_core), so the
-- former quick-grab fallback here never ran (B7). The ring only shows offers.
concommand.Add("+zci_action",function() if I.CirclePress then I.CirclePress("shortcut") end end)
concommand.Add("-zci_action",function() if I.CircleRelease then I.CircleRelease() end cancel() end)
net.Receive("zci_quick_offer",function()
    local reply=net.ReadUInt(16) local token=net.ReadUInt(32) local target=net.ReadEntity()
    local label=net.ReadString() local duration=net.ReadFloat() local danger=net.ReadBool()
    if reply~=nonce or held then return end
    waiting=nil
    offer=token~=0 and {token=token,target=target,label=label,danger=danger,duration=math.Clamp(duration,.2,1),expires=CurTime()+.8} or nil
    if offer then notice=nil end
end)
net.Receive("zci_quick_armed",function()
    local token=net.ReadUInt(32)
    if held and not fired and offer and offer.token==token then
        armedAt=CurTime();offer.expires=CurTime()+3
        if net.ReadBool() then offer.live=true liveLabel=offer.label end
    end
end)
net.Receive("zci_quick_result",function()
    local token=net.ReadUInt(32) local ok=net.ReadBool() local why=net.ReadString()
    if token~=actionToken then return end
    offer=nil armedAt=nil
    notice=why~="" and why or nil noticeUntil=CurTime()+2.5
    -- Keep held/fired until key-up; completion never chains into another action.
end)
hook.Add("Think","ZCityInteractions.QuickPrompt",function()
    local p=LocalPlayer()
    if not IsValid(p) or not p:Alive() or not I.ContextEnabled() or not inputAvailable() then
        cancel() waiting=nil return
    end
    if I.CircleOpen and I.CircleOpen() then cancel() waiting=nil return end
    if held then
        if not offer then return end
        if CurTime()>offer.expires then cancel() return end
        if offer.live then
            -- Session ended under a held key (interrupted): drop the prompt, keep
            -- held until key-up so nothing chains into another action.
            local phase=entryState()
            if phase then offer.seen=true elseif offer.seen then offer=nil armedAt=nil end
        elseif armedAt and not fired and CurTime()-armedAt>=offer.duration then fired=true send(2) end
        return
    end
    if CurTime()<nextRequest then return end
    nextRequest=CurTime()+.35
    if not nearby(p) then offer=nil return end
    if waiting and CurTime()-waiting<1.5 then return end
    if util.NetworkStringToID("zci_quick_request")==0 then return end
    nonce=nonce%65535+1 waiting=CurTime()
    net.Start("zci_quick_request") net.WriteUInt(nonce,16) net.SendToServer()
end)
-- Bound key for prompts: the keybinds menu owns it when present, the engine bind otherwise.
function I.QuickKey()
    local kb=hg and hg.keybinds
    local text=kb and kb.GetShortcutText and kb.GetShortcutText("zci_action")
    if text and text~="" then return string.upper(text) end
    local bound=input.LookupBinding("+zci_action")
    return bound and string.upper(bound) or nil
end
-- Structured state for the crosshair prompt. state: ready | hold | danger | rewind | victim | denied | checking
function I.QuickState()
    if I.CircleOpen and I.CircleOpen() then return I.CircleState() end
    local p=LocalPlayer()
    local active=IsValid(p) and (p:GetNWInt("zch_session")~=0 or p:GetNWInt("zsf_id")~=0 or p:GetNWString("zci_native")~="")
    if active and I.InteractionFeedback then
        local label,hint,meter,progress=I.InteractionFeedback(p)
        if label then return I.CircleVictim(p) and "victim" or "active",label,hint,progress,false end
    end
    if notice and CurTime()<noticeUntil then return "denied",notice end
    local phase,entry=entryState()
    if phase=="entry_reverse" then return "rewind","Letting go",nil,entry or 0,false end
    if not offer or CurTime()>offer.expires then
        local vLabel,vSub=victimCue()
        if vLabel then return "victim",vLabel,vSub end
        -- Look-at prompts (loot, pickup, doors; homigrad/sh_inventory.lua) fill
        -- the ring only when no offer, refusal, check or victim cue owns it.
        local look=isfunction(I.LookAtPrompt) and I.LookAtPrompt() or nil
        if istable(look) and look.state and look.label then
            return look.state,look.label,look.sub,look.progress,false,look.key,look.mod,look.subColor,look.ent
        end
        return
    end
    local label,extra=string.match(offer.label,"^(.-) · (.+)$")
    label=label or offer.label
    local progress=armedAt and not fired and math.Clamp((CurTime()-armedAt)/offer.duration,0,1) or nil
    if offer.live then progress=entry or (phase=="hold" and 1) or 0 end
    local state=(held and (offer.danger and "danger" or "hold")) or (offer.danger and "danger" or "ready")
    local sub
    if held then
        sub=armedAt and "target held · keep holding" or "confirming…"
    else
        local name=targetName(offer.target)
        sub=name and (extra and ("hold · "..name.." · "..extra) or ("hold · "..name)) or extra
    end
    return state,label,sub,progress,held
end
function I.QuickText()
    if notice and CurTime()<noticeUntil then return "Interaction",notice end
    if not offer or CurTime()>offer.expires then return end
    local bound=input.LookupBinding("+zci_action")
    local hint=bound and ("Hold ["..string.upper(bound).."] Â· "..offer.label)
        or (offer.label.." Â· Bind a key to +zci_action")
    if held and not armedAt then hint="Confirming targetâ€¦" end
    local target=offer.target
    local title=IsValid(target) and target:IsPlayer() and (target.GetPlayerName and target:GetPlayerName() or target:Nick()) or "Interaction"
    return title,hint,armedAt and not fired and math.Clamp((CurTime()-armedAt)/offer.duration,0,1) or nil
end

-- The crosshair prompt owns quick-action display; older panels calling this draw nothing.
function I.QuickFeedback() end
-- Crosshair-anchored quick prompt. Matches the Z-City HUD (Bahnschrift, warm
-- beige / gold, flat). Draws nothing unless the server offered an action.
local beige,white,muted=Color(255,235,200),Color(245,245,245),Color(201,204,208)
local gold,red,track,redText=Color(235,170,65),Color(179,38,30),Color(55,60,67,230),Color(255,180,171)
local shadow=Color(0,0,0,200)
local disc=Color(0,0,0,115)
-- Added with the 2026-09-22 presentation pass. No new hues: the leading edge is
-- a lighter gold, the burst reuses gold, the dim ring is the track colour.
local headGlow,flash=Color(255,240,210),Color(255,255,255)
local dimRing,dangerFill=Color(58,63,71),Color(60,10,10,128)
local subTint=Color(255,255,255) -- look-at subColor, faded with the ring
-- Fade multiplies each cached color's own base alpha; never allocate a Color
-- per frame. Keyed by color identity so unrelated tables (quad/tri) are untouched.
local baseAlpha={[beige]=255,[muted]=255,[gold]=255,[red]=255,[track]=230,[redText]=255,[shadow]=200,[disc]=115,
    [headGlow]=255,[flash]=255,[dimRing]=255,[dangerFill]=128}
local function applyFade(a)
    for color,base in pairs(baseAlpha) do color.a=math.floor(base*a) end
end
-- 2026-09-25 HUD pass: the same colour objects take the GoobOS token values (in place, so baseAlpha keys hold).
-- headGlow is derived (midpoint of gold and white); dimRing uses edge, dangerFill uses line.
local themed=false
local function syncTheme()
    if themed then return end
    local T=ZCGoobApps and ZCGoobApps.Theme
    if not (T and T.edge and T.glass) then return end
    themed=true
    local function set(c,src) c.r,c.g,c.b=src.r,src.g,src.b end
    set(beige,T.text) set(white,T.text) set(muted,T.muted) set(gold,T.gold) set(red,T.accent)
    set(track,T.glass) set(redText,T.red) set(dimRing,T.edge) set(dangerFill,T.line)
    headGlow.r,headGlow.g,headGlow.b=math.floor((T.gold.r+255)/2),math.floor((T.gold.g+255)/2),math.floor((T.gold.b+255)/2)
end
local SEG=48
local unit={}
for i=0,SEG do local a=math.rad(i/SEG*360-90) unit[i]={math.cos(a),math.sin(a)} end
local quad={{},{},{},{}}
local tri={{},{},{}}
-- One scratch colour for the ramped arc. Mutated per segment, never allocated.
local ramp=Color(0,0,0,0)
-- Draw the segment range (i0,i1]; every other ring helper is built on this so
-- there is a single place that touches the polygon buffer.
local function arcSeg(cx,cy,r0,r1,i0,i1,color)
    surface.SetDrawColor(color) draw.NoTexture()
    for i=i0+1,i1 do
        local a,b=unit[(i-1)%SEG],unit[i%SEG]
        quad[1].x,quad[1].y=cx+a[1]*r1,cy+a[2]*r1
        quad[2].x,quad[2].y=cx+b[1]*r1,cy+b[2]*r1
        quad[3].x,quad[3].y=cx+b[1]*r0,cy+b[2]*r0
        quad[4].x,quad[4].y=cx+a[1]*r0,cy+a[2]*r0
        surface.DrawPoly(quad)
    end
end
local function arc(cx,cy,r0,r1,fraction,color)
    arcSeg(cx,cy,r0,r1,0,math.floor(SEG*math.Clamp(fraction,0,1)),color)
end
-- Progress arc with a dim tail brightening into the leading edge. The tail is
-- what stops a filling ring reading as a flat block of colour.
local function arcRamped(cx,cy,r0,r1,fraction,color,tail)
    local last=math.floor(SEG*math.Clamp(fraction,0,1))
    if last<=0 then return end
    draw.NoTexture()
    for i=1,last do
        local t=last>1 and (i-1)/(last-1) or 1
        local a=tail+(1-tail)*t
        ramp.r,ramp.g,ramp.b,ramp.a=color.r,color.g,color.b,math.floor(color.a*a)
        arcSeg(cx,cy,r0,r1,i-1,i,ramp)
    end
end
-- Same ramp wound the other way, for the victim's resist arc.
local function arcRampedCCW(cx,cy,r0,r1,fraction,color,tail)
    local last=math.floor(SEG*math.Clamp(fraction,0,1))
    if last<=0 then return end
    draw.NoTexture()
    for i=1,last do
        local t=last>1 and (i-1)/(last-1) or 1
        local a=tail+(1-tail)*t
        ramp.r,ramp.g,ramp.b,ramp.a=color.r,color.g,color.b,math.floor(color.a*a)
        arcSeg(cx,cy,r0,r1,SEG-i,SEG-i+1,ramp)
    end
end
-- Dashed ring for the unavailable state: keeps the silhouette so the element
-- never changes shape, only treatment.
local function arcDashed(cx,cy,r0,r1,color)
    for i=1,SEG do
        if (i%6)>=2 then arcSeg(cx,cy,r0,r1,i-1,i,color) end
    end
end
-- Filled disc via a triangle fan over the same precomputed unit circle.
local function fillDisc(cx,cy,r,color)
    surface.SetDrawColor(color) draw.NoTexture()
    for i=1,SEG do
        local a,b=unit[i-1],unit[i]
        tri[1].x,tri[1].y=cx,cy
        tri[2].x,tri[2].y=cx+a[1]*r,cy+a[2]*r
        tri[3].x,tri[3].y=cx+b[1]*r,cy+b[2]*r
        surface.DrawPoly(tri)
    end
end
-- Leading-edge dot plus a soft halo, positioned on the arc head by segment
-- index so it follows either winding direction.
local function arcHead(cx,cy,radius,segIndex,color,size)
    local u=unit[segIndex%SEG]
    local hx,hy=cx+u[1]*radius,cy+u[2]*radius
    ramp.r,ramp.g,ramp.b,ramp.a=color.r,color.g,color.b,math.floor(color.a*0.28)
    fillDisc(hx,hy,size*1.7,ramp)
    fillDisc(hx,hy,size,color)
end
local built,fontCV
local function fonts()
    fontCV=fontCV or GetConVar("hg_font")
    local cv=fontCV
    local face=cv and cv:GetString() or ""
    if face=="" then face="Bahnschrift" end
    local key=ScrH().."|"..face
    if built==key then return end
    built=key
    surface.CreateFont("ZCIPromptKey",{font=face,size=ScreenScale(7),weight=1100,antialias=true})
    surface.CreateFont("ZCIPromptLabel",{font=face,size=ScreenScale(9),weight=1100,antialias=true})
    -- Tap prompts show constantly (every dropped gun, every door): quieter label.
    surface.CreateFont("ZCIPromptLabelTap",{font=face,size=ScreenScale(7.5),weight=700,antialias=true})
    -- Key names longer than three characters ("SHIFT") must fit inside the ring.
    surface.CreateFont("ZCIPromptKeySmall",{font=face,size=ScreenScale(4.5),weight=1100,antialias=true})
    surface.CreateFont("ZCIPromptSub",{font=face,size=ScreenScale(6.5),weight=500,antialias=true})
end
local short={MOUSE1="M1",MOUSE2="M2",MOUSE3="M3",MOUSE4="M4",MOUSE5="M5",MWHEELUP="MW↑",MWHEELDOWN="MW↓"}
local function shortKey(bound)
    bound=bound and string.upper(bound) or nil
    return bound and (short[bound] or (#bound<=3 and bound) or string.sub(bound,1,3)) or "?"
end
-- Four-way offset outline instead of a single hard drop shadow: legible over
-- bright geometry without a blur pass.
local offs={{-1,0},{1,0},{0,-1},{0,1}}
local function text(str,font,x,y,color)
    for i=1,4 do draw.SimpleText(str,font,x+offs[i][1],y+offs[i][2],shadow,TEXT_ALIGN_CENTER,TEXT_ALIGN_TOP) end
    draw.SimpleText(str,font,x,y,color,TEXT_ALIGN_CENTER,TEXT_ALIGN_TOP)
end
local function glyph(str,font,x,y,color)
    for i=1,4 do draw.SimpleText(str,font,x+offs[i][1],y+offs[i][2],shadow,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER) end
    draw.SimpleText(str,font,x,y,color,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
end
-- shown/alpha drive the fade; on fade-out the last non-nil state keeps drawing
-- (from `last`) until alpha reaches 0, instead of popping away. Appearing is
-- eased-out over .14s and scales 0.92 -> 1.00; leaving is eased-in over .10s to
-- 0.96. Faster in than out is what reads as "arrived" rather than "switched on".
local IN_TIME,OUT_TIME=0.14,0.10
local BURST_TIME=0.30
local shown,alpha=false,0
local last={}
local burstStart,prevProgress=-10,nil
-- Edge-triggered cues only. The prompt is deliberately SILENT on appear: it
-- shows whenever a valid target is in reach, so a cue there would fire
-- constantly. Both paths are ones the gamemode already plays through
-- surface.PlaySound (homigrad/cl_*), so nothing new ships or needs FastDL.
local promptSound=CreateClientConVar("zci_prompt_sound","1",true,false,
    "Play the interaction prompt's confirm and refusal cues")
local prevDenied=false
-- Target switch while visible: the ring and disc hold, the glyph and text dip
-- (old text out over SWAP_OUT, new text in over SWAP_IN) instead of popping.
local SWAP_OUT,SWAP_IN=0.08,0.10
local wasShown,swapAt=false,-10
local cur,old={},{}
function I.DrawQuickPrompt()
    if not I.QuickState then return false end
    local state,label,sub,progress,held,lookKey,lookMod,subColor,lookEnt=I.QuickState()
    shown=state~=nil
    local prevShown=wasShown
    wasShown=shown
    if shown then
        last.state,last.label,last.sub,last.progress,last.held=state,label,sub,progress,held
        last.key,last.mod,last.subColor,last.ent=lookKey,lookMod,subColor,lookEnt
    end
    alpha=math.Clamp(alpha+(shown and 1 or -1)*FrameTime()/(shown and IN_TIME or OUT_TIME),0,1)
    if alpha<=0 then return false end
    state,label,sub,progress,held=last.state,last.label,last.sub,last.progress,last.held
    lookKey,lookMod,subColor,lookEnt=last.key,last.mod,last.subColor,last.ent
    if not state then return false end
    fonts()
    syncTheme()
    local eased=shown and (1-(1-alpha)^3) or (alpha*alpha*alpha)
    local entry=shown and (.92+.08*eased) or (.96+.04*eased)
    applyFade(eased)
    local cx,cy=ScrW()*.5,ScrH()*.5+ScreenScale(22)
    local danger=state=="danger"
    local rewind=state=="rewind"
    local denied=state=="denied"
    local checking=state=="checking"
    -- Tap (look-at use: pick up, open, search): thin muted ring, no progress fill;
    -- the glyph keeps its dark disc so the key reads over bright walls.
    local tap=state=="tap"
    -- Refusal fires once on the transition into denied, never per frame.
    if denied~=prevDenied then
        if denied and promptSound:GetBool() then surface.PlaySound("buttons/button10.wav") end
        prevDenied=denied
    end
    -- A completed hold bursts the ring outward as it fades; only progress==1
    -- counts, so a reset (nil/lower) never leaves the burst latched on.
    if progress and progress>=1 and (not prevProgress or prevProgress<1) then
        burstStart=CurTime()
        if promptSound:GetBool() then surface.PlaySound("buttons/button14.wav") end
    end
    prevProgress=progress
    local burst=(CurTime()-burstStart)/BURST_TIME
    if burst>=1 then burst=nil end
    local r1=ScreenScale(8)*entry local r0=r1-math.max(3,ScreenScale(1.6))
    if danger then r0=r1-math.max(3.5,ScreenScale(1.9)) end
    if tap then r0=r1-2 end
    local ringColor=danger and red or ((rewind or denied or tap) and muted or gold)
    local glyphColor=danger and redText or ((rewind or denied) and muted or beige)
    -- Danger carries a slow outer halo so a lethal action is not just a colour.
    if danger then
        local halo=.5+.5*math.sin(CurTime()*6)
        ramp.r,ramp.g,ramp.b,ramp.a=red.r,red.g,red.b,math.floor(red.a*.22*halo)
        arcSeg(cx,cy,r1+ScreenScale(1.2),r1+ScreenScale(2.6),0,SEG,ramp)
        fillDisc(cx,cy,r0,dangerFill)
    else
        fillDisc(cx,cy,r0,disc)
    end
    if tap then
        arcSeg(cx,cy,r0,r1,0,SEG,muted)
    elseif denied then
        arcDashed(cx,cy,r0,r1,dimRing)
    elseif checking then
        -- Indeterminate sweep: the ring stays, so the shape never breaks.
        local head=math.floor((CurTime()*0.9)%1*SEG)
        arcSeg(cx,cy,r0,r1,0,SEG,track)
        arcSeg(cx,cy,r0,r1,head,head+10,beige)
    else
        arcSeg(cx,cy,r0,r1,0,SEG,track)
        if progress then
            -- The victim's resist arc runs the other way, so escaping reads as
            -- opposing the captor's fill rather than repeating it.
            local filled=math.floor(SEG*math.Clamp(progress,0,1))
            if state=="victim" then
                arcRampedCCW(cx,cy,r0,r1,progress,ringColor,.35)
                if filled>0 then arcHead(cx,cy,(r0+r1)*.5,SEG-filled,headGlow,(r1-r0)*.62) end
            else
                arcRamped(cx,cy,r0,r1,progress,ringColor,.35)
                if filled>0 then arcHead(cx,cy,(r0+r1)*.5,filled,headGlow,(r1-r0)*.62) end
            end
        end
    end
    if burst then
        local grow=r1*(1+.35*burst)
        ramp.r,ramp.g,ramp.b,ramp.a=gold.r,gold.g,gold.b,math.floor(gold.a*(1-burst))
        arcSeg(cx,cy,grow-math.max(2,ScreenScale(.9)),grow,0,SEG,ramp)
    end
    local bound=(state=="victim" or (I.CircleOpen and I.CircleOpen())) and input.LookupBinding("+use") or I.QuickKey()
    if state=="active" then bound=input.LookupBinding(LocalPlayer():GetNWString("zci_native")=="fiberwire" and "+attack" or "+reload") end
    -- A look-at prompt names its own key; the binding fallbacks are for offers.
    local menuFallback=not lookKey and not bound and (state=="ready" or state=="danger")
    local key=lookKey or shortKey(menuFallback and input.LookupBinding("+use") or bound)
    if label~=cur.label or key~=cur.key or lookEnt~=cur.ent then
        if prevShown and cur.label~=nil then
            old.label,old.sub,old.key,old.mod,old.subColor,old.tap,old.fallback=cur.label,cur.sub,cur.key,cur.mod,cur.subColor,cur.tap,cur.fallback
            swapAt=CurTime()
        end
        cur.label,cur.key,cur.ent=label,key,lookEnt
    end
    cur.sub,cur.mod,cur.subColor,cur.tap,cur.fallback=sub,lookMod,subColor,tap,menuFallback
    local textMul=1
    local ts=CurTime()-swapAt
    if ts<SWAP_OUT then
        textMul=1-ts/SWAP_OUT
        label,sub,key,lookMod,subColor,tap,menuFallback=old.label,old.sub,old.key,old.mod,old.subColor,old.tap,old.fallback
    elseif ts<SWAP_OUT+SWAP_IN then
        textMul=(ts-SWAP_OUT)/SWAP_IN
    end
    local textFade=eased*textMul
    if textMul<1 then applyFade(textFade) end
    if denied then
        -- A cross in place of the key: the action is gone, the shape is not.
        local d=r0*.52
        surface.SetDrawColor(muted) draw.NoTexture()
        surface.DrawLine(cx-d,cy-d,cx+d,cy+d) surface.DrawLine(cx+d,cy-d,cx-d,cy+d)
    else
        -- The glyph flashes to white for the first third of the burst.
        local gc=glyphColor
        if burst and burst<.34 then gc=flash end
        glyph(key,(utf8.len(key) or #key)>3 and "ZCIPromptKeySmall" or "ZCIPromptKey",cx,cy,gc)
        -- Optional modifier chip left of the ring: "M2 + (E)", "ALT + (SHIFT)".
        if lookMod then
            surface.SetFont("ZCIPromptSub")
            local tw,th=surface.GetTextSize(lookMod)
            local pad=math.max(2,ScreenScale(1.2))
            local w,h=tw+pad*2,th+pad
            local x=cx-r1-ScreenScale(6)-w
            draw.RoundedBox(4,x,cy-h*.5,w,h,disc)
            glyph(lookMod,"ZCIPromptSub",x+w*.5,cy,glyphColor)
            glyph("+","ZCIPromptSub",cx-r1-ScreenScale(3),cy,muted)
        end
    end
    if I.CircleChoices then
        local previous,nextLabel,index,count=I.CircleChoices()
        if previous then
            local function short(s) return utf8.len(s)>25 and (utf8.sub(s,1,24).."…") or s end
            draw.SimpleText(short(previous),"ZCIPromptSub",cx-ScreenScale(17),cy-ScreenScale(12),muted,TEXT_ALIGN_RIGHT,TEXT_ALIGN_CENTER)
            draw.SimpleText(short(nextLabel),"ZCIPromptSub",cx+ScreenScale(17),cy-ScreenScale(12),muted,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER)
            draw.SimpleText(index.." / "..count,"ZCIPromptSub",cx,cy-ScreenScale(18),muted,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
        end
    end
    local y=cy+r1+ScreenScale(2)
    text(label,tap and "ZCIPromptLabelTap" or "ZCIPromptLabel",cx,y,glyphColor)
    if sub or key=="?" then
        local subCol=(progress and not danger and not rewind and gold) or muted
        if IsColor(subColor) or istable(subColor) and subColor.r then
            subTint.r,subTint.g,subTint.b,subTint.a=subColor.r,subColor.g,subColor.b,math.floor((subColor.a or 255)*textFade)
            subCol=subTint
        end
        text(menuFallback and ("Hold "..I.Binding("+use","Use")..": interact") or sub,"ZCIPromptSub",cx,y+ScreenScale(tap and 8 or 9.5),subCol)
    end
    return true
end
-- The loot/pickup look-at provider hides the legacy hint box only while the
-- ring can draw its prompts (cl_hud.lua reads this with I.ContextEnabled()).
I.LookAtSupported=true
I.LookAtLongKeys=true -- the key glyph shrinks for names longer than three characters
hook.Add("HUDPaint","ZCityInteractions.QuickPromptDraw",function()
    local p=LocalPlayer()
    if not IsValid(p) or not p:Alive() or not I.ContextEnabled() then return end
    I.DrawQuickPrompt()
end)

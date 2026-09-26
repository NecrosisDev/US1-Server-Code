if not CLIENT then return end
local Model = include("zc_reinforcements/hud_model.lua")
local state, receivedAt
net.Receive("ZCReinforcementHUD", function()
    local s = {phase=net.ReadUInt(3)}
    if s.phase == 0 then state=nil; return end
    for _, key in ipairs({"total","dead","deathsLeft","yes","required","spawned","planned","seconds"}) do
        s[key] = net.ReadUInt(16)
    end
    s.eligible=net.ReadBool(); s.voted=net.ReadBool()
    s.guard=net.ReadBool(); s.stopped=net.ReadBool()
    state, receivedAt = s, RealTime()
end)
-- Physical number keys; leave chat, console and VGUI keyboard input alone.
local chatOpen = false
hook.Add("StartChat", "ZCReinforcementVote_ChatInput", function() chatOpen=true end)
hook.Add("FinishChat", "ZCReinforcementVote_ChatInput", function() chatOpen=false end)
local function canVote()
    local ply = LocalPlayer()
    return state and state.phase == 2 and state.eligible and RealTime()-receivedAt <= 4
        and IsValid(ply) and not ply:Alive() and not chatOpen and not ply:IsTyping()
        and not gui.IsGameUIVisible() and not gui.IsConsoleVisible()
        and not vgui.CursorVisible() and not IsValid(vgui.GetKeyboardFocus())
end
local heldYes, heldNo = input.IsKeyDown(KEY_1), input.IsKeyDown(KEY_2)
local nextRequestAt = 0
hook.Add("Think", "ZCReinforcementVote_Keys", function()
    local yes, no = input.IsKeyDown(KEY_1), input.IsKeyDown(KEY_2)
    local pressedYes, pressedNo = yes and not heldYes, no and not heldNo
    -- Track releases even while unavailable: opening voting/closing chat cannot cast a held key.
    heldYes, heldNo = yes, no
    if not canVote() or RealTime() < nextRequestAt or yes == no then return end
    if pressedYes or pressedNo then
        nextRequestAt = RealTime() + 1.05
        RunConsoleCommand("zc_reinforcements_vote", pressedYes and "yes" or "no")
    end
end)
hook.Add("PlayerBindPress", "ZCReinforcementVote_ConsumeSlots", function(_, bind, _, code)
    if canVote() and (code == KEY_1 or code == KEY_2)
        and (bind == "slot1" or bind == "slot2") then return true end
end)

local scale, fontFace
local function fonts()
    local nextScale = math.Clamp(ScrW()/1920, 0.8, 1.25)
    if scale == nextScale and fontFace then return end
    scale = nextScale
    local cv = GetConVar("hg_font")
    local face = cv and cv:GetString() or ""
    if face == "" then face = "Bahnschrift" end
    fontFace = face
    surface.CreateFont("ZCReinforceTitle", {font=face,size=math.floor(14*scale),weight=700})
    surface.CreateFont("ZCReinforceMain", {font=face,size=math.floor(22*scale),weight=600})
    surface.CreateFont("ZCReinforceDetail", {font=face,size=math.max(12,math.floor(14*scale)),weight=500})
end
cvars.AddChangeCallback("hg_font", function() fontFace = nil end, "ZCReinforcementVote_Fonts")
local bg=Color(15,19,24,235)
local white=Color(238,242,246)
local muted=Color(170,182,194)
local gold=Color(217,174,95)
local blue=Color(109,187,220)
local track=Color(46,55,65)
local function fitted(text, font, center, y, color, maxWidth)
    surface.SetFont(font)
    local tw = surface.GetTextSize(text)
    if tw <= maxWidth then draw.SimpleText(text,font,center,y,color,TEXT_ALIGN_CENTER); return end
    local line, lines = "", {}
    for word in string.gmatch(text,"%S+") do
        local candidate = line == "" and word or line .. " " .. word
        if surface.GetTextSize(candidate) > maxWidth and line ~= "" then
            lines[#lines+1]=line; line=word
        else line=candidate end
    end
    lines[#lines+1]=line
    for i, value in ipairs(lines) do
        draw.SimpleText(value,font,center,y+(i-1)*17*scale,color,TEXT_ALIGN_CENTER)
    end
end
-- The box eases in and out over 0.25 s (RealTime) instead of vanishing 4 s after the last update; the last view
-- stays up while it fades out, and the progress fill eases toward the server value.
local vis, visAt, shownView, fillFrac = 0, RealTime(), nil, nil
hook.Add("HUDPaint", "ZCReinforcementVote_HUD", function()
    local ply = LocalPlayer()
    local rnow = RealTime()
    local dt = math.Clamp(rnow - visAt, 0, 0.1)
    visAt = rnow
    local live = state and IsValid(ply) and not ply:Alive() and rnow-receivedAt <= 4
    if live then shownView = Model.View(state) end
    vis = math.Approach(vis, live and 1 or 0, dt / 0.25)
    if vis <= 0 or not shownView then shownView, fillFrac = nil, nil return end
    local ease = vis * vis * (3 - 2 * vis)
    fonts()
    local view = shownView
    fillFrac = fillFrac and (fillFrac + (view.fraction - fillFrac) * (1 - math.exp(-dt * 10))) or view.fraction
    local w=math.min(510*scale,ScrW()-24)
    local h=(view.controls and 158 or 132)*scale
    local x,y=math.floor((ScrW()-w)/2), math.floor(math.max(24,52*scale) - (1 - ease) * 8)
    surface.SetAlphaMultiplier(ease)
    -- 2026-09-25 HUD pass: GoobOS plate and tokens (gold, green for ready, text, muted, line for the track).
    local K = ZCGoobApps and ZCGoobApps.Kit
    local T = ZCGoobApps and ZCGoobApps.Theme
    if T then
        white.r, white.g, white.b = T.text.r, T.text.g, T.text.b
        muted.r, muted.g, muted.b = T.muted.r, T.muted.g, T.muted.b
        gold.r, gold.g, gold.b = T.gold.r, T.gold.g, T.gold.b
        blue.r, blue.g, blue.b = T.green.r, T.green.g, T.green.b
        track.r, track.g, track.b = T.line.r, T.line.g, T.line.b
    end
    local accent=view.tone == "ready" and blue or gold
    if K and K.HudPlate then K.HudPlate(x,y,w,h) else draw.RoundedBox(6,x,y,w,h,bg) end
    draw.RoundedBox(2,x+18*scale,y+14*scale,3*scale,15*scale,accent)
    draw.SimpleText(view.title,"ZCReinforceTitle",x+29*scale,y+14*scale,muted)
    fitted(view.main,"ZCReinforceMain",ScrW()/2,y+39*scale,white,w-28*scale)
    fitted(view.detail,"ZCReinforceDetail",ScrW()/2,y+76*scale,muted,w-28*scale)
    if view.controls then
        fitted(view.controls,"ZCReinforceDetail",ScrW()/2,y+103*scale,accent,w-28*scale)
    end
    draw.RoundedBox(2,x+18*scale,y+h-13*scale,w-36*scale,3*scale,track)
    local fill=(w-36*scale)*fillFrac
    if fill > 0 then draw.RoundedBox(2,x+18*scale,y+h-13*scale,fill,3*scale,accent) end
    surface.SetAlphaMultiplier(1)
end)

-- Private membership reminder; the native Homicide briefing remains in charge of allegiance.
local NET = "zc_gang_mentality"
local C = {generation = -1, active = false}
local titles = {[1] = "Bloodz", [2] = "Groove"}
local colors = {[1] = Color(235, 90, 90), [2] = Color(95, 220, 115)}
surface.CreateFont("ZC_Gang_Reminder", {font = "Tahoma", size = 20, weight = 700, antialias = true})
net.Receive(NET, function()
    local generation, active, gang = net.ReadUInt(32), net.ReadBool(), net.ReadUInt(2)
    local variant, stamp = net.ReadString(), net.ReadFloat()
    if generation < C.generation or (generation == C.generation and C.retired and active) then return end
    if generation > C.generation then C.retired = false end
    if not active and C.active and generation == C.generation then C.retired = true end
    C.generation, C.active, C.gang, C.variant, C.stamp = generation, active, gang, variant, stamp
end)
local function Request()
    if not IsValid(LocalPlayer()) then return end
    net.Start(NET); net.SendToServer()
end
hook.Add("InitPostEntity", NET, Request)
timer.Simple(1, Request)
hook.Add("HUDPaint", NET, function()
    local p = LocalPlayer()
    if not C.active or not titles[C.gang] or not IsValid(p) or not p:Alive()
        or p:Team() == TEAM_SPECTATOR or not zb or zb.ROUND_STATE ~= 1
        or zb.ROUND_START ~= C.stamp or not zb.modes or not CurrentRound then return end
    local mode = CurrentRound()
    if mode ~= zb.modes.hmcd or mode.Type ~= C.variant then return end
    draw.SimpleText("Gang Mentality: " .. titles[C.gang], "ZC_Gang_Reminder", ScrW()/2, ScrH()*0.78,
        colors[C.gang], TEXT_ALIGN_CENTER)
    draw.SimpleText("Your gang is not your allegiance.", "ZC_Gang_Reminder", ScrW()/2, ScrH()*0.78+26,
        color_white, TEXT_ALIGN_CENTER)
end)

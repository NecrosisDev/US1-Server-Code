-- A single recipient-only snapshot. No target entity, identity or live updates are sent.
local marker, latest = nil, -1
local WINDOW = ZC_HMCD_MUTATOR_INFO.SightingDuration
local function finite(n) return type(n) == "number" and n == n and math.abs(n) < math.huge end
net.Receive("zc_informant_sighting", function()
    local generation, active = net.ReadUInt(32), net.ReadBool()
    if generation < latest then return end
    if not active then latest = generation; marker = nil; return end
    local pos, deadline, observed = net.ReadVector(), net.ReadFloat(), net.ReadFloat()
    if generation == latest then return end -- duplicate packets never refresh the countdown
    latest = generation
    marker = nil
    if not isvector(pos) or not finite(pos.x) or not finite(pos.y) or not finite(pos.z)
        or not finite(deadline) or not finite(observed) or deadline <= CurTime() then return end
    marker = {pos = pos, untilTime = math.min(deadline, CurTime() + WINDOW), observed = observed}
end)
hook.Add("PostCleanupMap", "zc_informant_sighting", function() marker = nil end)
hook.Add("HUDPaint", "zc_informant_sighting", function()
    if not marker then return end
    local ply, now = LocalPlayer(), CurTime()
    if now >= marker.untilTime or not IsValid(ply) or not ply:Alive()
        or (ply.organism and ply.organism.otrub) or IsValid(ply.FakeRagdoll) then marker = nil; return end
    local screen = marker.pos:ToScreen()
    -- Draw through walls in the view direction; don't misrepresent a point behind the camera.
    if not screen.visible then return end
    local x, y = math.Clamp(screen.x, 40, ScrW() - 40), math.Clamp(screen.y, 45, ScrH() - 65)
    local left = math.max(0, marker.untilTime - now)
    local alpha = math.floor(255 * math.min(1, left / WINDOW))
    local size = 8 + 5 * math.min(1, left / WINDOW)
    surface.SetDrawColor(255, 190, 80, alpha)
    surface.DrawLine(x, y-size, x+size, y)
    surface.DrawLine(x+size, y, x, y+size)
    surface.DrawLine(x, y+size, x-size, y)
    surface.DrawLine(x-size, y, x, y-size)
    surface.DrawRect(x-25, y+size+6, 50 * math.min(1,left/WINDOW), 2)
    draw.SimpleText("LAST SEEN", "DermaDefaultBold", x, y-size-18, Color(255,190,80,alpha), TEXT_ALIGN_CENTER)
    draw.SimpleText(string.format("%.1fs", left), "DermaDefault", x, y+size+12, Color(255,190,80,alpha), TEXT_ALIGN_CENTER)
end)

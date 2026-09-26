if not CLIENT then return end
local MODE = MODE or (zb and zb.modes and zb.modes.shitterhunt) -- nil outside the loader: a lone autorefresh patches the registered mode
if not MODE then return end
local white = Color(245, 245, 245)
local accent = Color(215, 180, 100)

function MODE:DrawHuntBlind(seconds)
    surface.SetDrawColor(0, 0, 0, 255)
    surface.DrawRect(0, 0, ScrW(), ScrH())
    draw.SimpleText("SHITTERHUNT", "Trebuchet24", ScrW() * 0.5, ScrH() * 0.42, accent, TEXT_ALIGN_CENTER)
    draw.SimpleText("The Shitter team is hiding. Hunt begins in " .. math.ceil(seconds) .. "s", "Trebuchet24", ScrW() * 0.5, ScrH() * 0.50, white, TEXT_ALIGN_CENTER)
end

-- Draw after ordinary world/HUD rendering; does not alter global camera/material state.
function MODE:PostDrawHUD()
    if zb.ROUND_STATE ~= 1 then return end
    local seconds = self:BlindRemaining(LocalPlayer(), CurTime())
    if seconds > 0 then self:DrawHuntBlind(seconds) end
end

function MODE:RenderScreenspaceEffects()
    if zb.ROUND_STATE ~= 1 or self:BlindRemaining(LocalPlayer(), CurTime()) <= 0 then return end
    surface.SetDrawColor(0, 0, 0, 255)
    surface.DrawRect(0, 0, ScrW(), ScrH())
end

function MODE:HUDPaint()
    local p = LocalPlayer()
    if not IsValid(p) then return end
    local text
    if zb.ROUND_STATE == 3 then
        text = GetGlobalString("ZCShitterhuntResult", "Shitterhunt ended.")
    elseif zb.ROUND_STATE == 1 then
        if self:BlindRemaining(p, CurTime()) > 0 then return end
        local role = p:GetNWInt("ZCShitterhuntRole", 0)
        local left = math.max(0, math.ceil(GetGlobalFloat("ZCShitterhuntEnd", CurTime()) - CurTime()))
        if role == self.RoleShitter and p:Alive() then
            text = "Shitter team: survive! A fart reveals your area every 30s."
        elseif role == self.RoleHunter and p:Alive() then
            text = "Hunt the Shitter team: " .. GetGlobalInt("ZCShitterhuntRemaining", 0) .. " remaining. Listen for farts."
        else
            text = "Shitterhunt — spectating"
        end
        text = text .. "  |  " .. string.format("%d:%02d", math.floor(left / 60), left % 60)
    else
        text = "Shitterhunt — karma below 50 hides; everyone else hunts."
    end
    draw.SimpleTextOutlined(text, "Trebuchet24", ScrW() * 0.5, ScrH() * 0.12, white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, Color(0, 0, 0))
end

function MODE:RoundStart()
    if zb.RemoveFade then zb.RemoveFade() end
end

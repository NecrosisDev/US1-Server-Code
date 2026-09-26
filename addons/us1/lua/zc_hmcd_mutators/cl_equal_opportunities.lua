-- Private local loadout state. Actual innocent/traitor flags stay under ZCity's control.
local NET = "zc_equal_opportunities"
local old = ZC_EQUAL_OPPORTUNITIES_CLIENT
if old and old.Restore then old.Restore() end
local C = {generation = -1, active = false}
surface.CreateFont("ZC_Equal_ReminderTitle", {font = "Tahoma", size = 20, weight = 700, antialias = true})
surface.CreateFont("ZC_Equal_ReminderBody", {font = "Tahoma", size = 20, weight = 500, antialias = true})
ZC_EQUAL_OPPORTUNITIES_CLIENT = C
local function Mode()
    if not zb or not zb.modes or not CurrentRound then return end
    local mode = CurrentRound()
    if mode == zb.modes.hmcd and mode.Type == C.variant then return mode end
end
local function Active()
    local p = LocalPlayer()
    return C.active and IsValid(p) and p:Alive() and zb and zb.ROUND_STATE == 1 and Mode()
end
function C.Restore()
    if C.mode and C.mode.HUDPaint == C.wrapper then C.mode.HUDPaint = C.original end
    C.mode, C.wrapper, C.original = nil, nil, nil
end
local function InstallBriefing(mode)
    if mode.HUDPaint == C.wrapper then return end
    C.Restore()
    if type(mode.HUDPaint) ~= "function" then return end
    local original = mode.HUDPaint
    C.mode, C.original = mode, original
    C.wrapper = function(self, ...)
        local p = LocalPlayer()
        if not Active() then return original(self, ...) end
        local role = mode.SubRoles and mode.SubRoles[p.SubRole]
        local objective = role and role.Objective
        local simpleText = draw.SimpleText
        if not p.isTraitor and role then
            -- Scoped to this player's native briefing draw; never impersonate a traitor to render HUD.
            role.Objective = "You are still innocent. Use your equipment to survive and stop the two traitors."
        elseif p.isTraitor and not p.MainTraitor then
            -- The native assistant briefing assumes an empty kit, which this mutation replaces.
            draw.SimpleText = function(text, ...)
                if text == "You are equipped with nothing. Help other traitors win." then
                    text = "You have your full chosen kit. Help the other traitor win."
                end
                return simpleText(text, ...)
            end
        end
        local args, count = {...}, select("#", ...)
        local ok, err = xpcall(function() original(self, unpack(args, 1, count)) end, debug.traceback)
        if role then role.Objective = objective end
        draw.SimpleText = simpleText
        if not ok then error(err) end
    end
    mode.HUDPaint = C.wrapper
end
net.Receive(NET, function()
    local generation, active = net.ReadUInt(32), net.ReadBool()
    local role, variant = net.ReadString(), net.ReadString()
    if generation < C.generation then return end
    -- A retired player cannot be reactivated by an older packet from the same event.
    if generation == C.generation and C.retired and active then return end
    local p = LocalPlayer()
    if generation > C.generation then C.retired = false end
    C.generation, C.active, C.role, C.variant = generation, active, role, variant
    if not active then C.retired = true end
    if IsValid(p) then p.SubRole = role ~= "" and role or nil end
    if active and Mode() then InstallBriefing(Mode()) else C.Restore() end
end)
hook.Add("Think", "zc_equal_opportunities", function()
    if not C.active then return end
    if not Active() then C.Restore() return end
    local p = LocalPlayer()
    p.SubRole = C.role -- The native delayed briefing must not erase this player's selected kit.
    InstallBriefing(Mode())
end)
local controls = {
    traitor_infiltrator = "Hold ALT + E: break neck from behind  |  ALT + R: swap ragdoll appearance",
    traitor_infiltrator_soe = "Hold ALT + E: break neck from behind  |  ALT + R: swap ragdoll appearance",
    traitor_assasin = "Hold ALT + E: disarm a nearby player",
    traitor_assasin_soe = "Hold ALT + E: disarm a nearby player"
}
hook.Add("HUDPaint", "zc_equal_opportunities", function()
    if not Active() then return end
    local p, mode = LocalPlayer(), Mode()
    local info = mode.SubRoles and mode.SubRoles[C.role]
    local color = p.isTraitor and Color(235, 90, 80) or Color(120, 220, 145)
    local y = ScrH() * 0.78
    -- Keep the larger class/allegiance reminder visible throughout active participation.
    draw.SimpleText("Equal Opportunities: " .. (info and info.Name or C.role), "ZC_Equal_ReminderTitle", ScrW() / 2, y, color, TEXT_ALIGN_CENTER)
    draw.SimpleText(p.isTraitor and "You are one of the two traitors. Your objective is unchanged."
        or "You are still innocent. Equipment does not reveal allegiance.", "ZC_Equal_ReminderBody", ScrW() / 2, y + 26, color, TEXT_ALIGN_CENTER)
    -- Native ability HUD is traitor-only, while its server abilities already check SubRole.
    if not p.isTraitor then
        local text = controls[C.role]
        if text then draw.SimpleText(text, "DermaDefault", ScrW() / 2, y + 56, color_white, TEXT_ALIGN_CENTER) end
        local ability = p.Ability_NeckBreak or p.Ability_Disarm
        if ability and type(ability.Progress) == "number" then
            draw.RoundedBox(2, ScrW() / 2 - 100, y + 75, 200, 5, Color(20, 20, 20, 200))
            draw.RoundedBox(2, ScrW() / 2 - 100, y + 75, 200 * math.Clamp(ability.Progress / 100, 0, 1), 5, color)
        end
        if C.role == "traitor_chemist" then
            local row = 0
            for name, amount in SortedPairs(p.PassiveAbility_ChemicalAccumulation or {}) do
                if type(amount) == "number" and amount > 0.1 then
                    draw.SimpleText(name .. ": " .. math.Round(amount), "DermaDefault", ScrW() - 20,
                        ScrH() / 2 + row * 18, Color(235, 170, 70), TEXT_ALIGN_RIGHT)
                    row = row + 1
                end
            end
        end
    end
end)

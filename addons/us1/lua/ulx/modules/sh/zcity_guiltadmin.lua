-- Nativized 2026-09-24 from workshop 3685034437 lua/ulx/modules/sh/zcity_guiltadmin.lua (verbatim). ULX finds modules in
-- every lua/ search path, so this loose copy is picked up exactly like the workshop one.
if SERVER then
    AddCSLuaFile()
end

if not ulx or not ULib then return end

local CATEGORY = "Z-City"

function ulx.guiltadmin(calling_ply)
    if not IsValid(calling_ply) or not calling_ply:IsPlayer() then return end

    if SERVER then
        net.Start("zcity_guilt_admin_openmenu")
        net.Send(calling_ply)
    end

    ulx.fancyLogAdmin(calling_ply, "#A opened the guilt admin menu")
end

local guiltadmin = ulx.command(CATEGORY, "ulx guiltadmin", ulx.guiltadmin, "!guiltadmin")
guiltadmin:defaultAccess(ULib.ACCESS_ADMIN)
guiltadmin:help("Opens the Z-City guilt admin menu.")
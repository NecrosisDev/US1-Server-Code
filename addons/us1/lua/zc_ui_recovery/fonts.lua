if SERVER then return end
local hg_font = ConVarExists("hg_font") and GetConVar("hg_font") or CreateClientConVar("hg_font", "Bahnschrift", true, false, "change every text font to selected because ui customization is cool")
local font = function() -- hg_coolvetica:GetBool() and "Coolvetica" or "Bahnschrift"
    local usefont = "Bahnschrift"

    if hg_font:GetString() != "" then
        usefont = hg_font:GetString()
    end

    return usefont
end

surface.CreateFont("ZCity_VerySuperTiny", {
	font = font(),
	size = ScreenScale(5),
	weight = 200
})

surface.CreateFont("ZCity_SuperTiny", {
	font = font(),
	size = ScreenScale(6),
	weight = 200
})

surface.CreateFont("ZCity_Fixed_SuperTiny", {
	font = font(),
	size = 18,
	weight = 200
})

surface.CreateFont("ZCity_Tiny", {
	font = font(),
	size = ScreenScale(8),
	weight = 200
})

surface.CreateFont("ZCity_Fixed_Tiny", {
	font = font(),
	size = 25,
	weight = 200
})

surface.CreateFont("ZCity_Small", {
	font = font(),
	size = ScreenScale(15),
	weight = 200
})

surface.CreateFont("ZCity_Medium", {
	font = font(),
	size = ScreenScale(25),
	weight = 200
})

surface.CreateFont("ZCity_Fixed_Medium", {
	font = font(),
	size = 55,
	weight = 200
})

surface.CreateFont("ZCity_Big", {
	font = font(),
	size = ScreenScale(35),
	weight = 200
})

surface.CreateFont("ZCity_Fixed_Big", {
	font = font(),
	size = 300,
	weight = 200
})

surface.CreateFont("ZCity_Fixed_Medium_Light", {
	font = font(),
	size = 25,
	weight = 200
})

surface.CreateFont("ZCity_Fixed_Medium_Light_Blur", {
	font = font(),
	size = 25,
	weight = 200,
	blursize = 4
})

surface.CreateFont("ZCity_Fixed_Icons_Small", {
	font = "fontello",
	size = 22,
	weight = 500
})
--//

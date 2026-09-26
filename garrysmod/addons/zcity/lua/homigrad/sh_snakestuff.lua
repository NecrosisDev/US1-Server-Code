-- Owner-requested simple radial cursor. Retire the networked worm in both realms.
if SERVER then
    util.AddNetworkString("zmeyka_net")
    net.Receive("zmeyka_net",function()end)
    return
end
	function draw.Circle( x, y, radius, seg )
		local cir = {}

		table.insert( cir, { x = x, y = y, u = 0.5, v = 0.5 } )
		for i = 0, seg do
			local a = math.rad( ( i / seg ) * -360 )
			table.insert( cir, { x = x + math.sin( a ) * radius, y = y + math.cos( a ) * radius, u = math.sin( a ) / 2 + 0.5, v = math.cos( a ) / 2 + 0.5 } )
		end

		local a = math.rad( 0 ) -- This is needed for non absolute segment counts
		table.insert( cir, { x = x + math.sin( a ) * radius, y = y + math.cos( a ) * radius, u = math.sin( a ) / 2 + 0.5, v = math.cos( a ) / 2 + 0.5 } )

		surface.DrawPoly( cir )
	end

for _,event in ipairs({"radialOptions","RadialMenuPressed","ContextMenuOpen","ContextMenuClosed"}) do
    hook.Remove(event,"zmeyka_test")
end
hook.Remove("ContextMenuOpen","zmeyka_new")
hook.Remove("HUDPaint","debildebilich")
hook.Remove("HUDPaint","new_snake") hook.Remove("Think","new_snake")
net.Receive("zmeyka_net",function()end)
hg.start_snake=function()end
concommand.Remove("zmeyka_settings")
hook.Add("PostRenderVGUI","ZCity.RadialCircleCursor",function()
    local panel=MENUPANELHUYHUY
    if not IsValid(panel) or not panel:IsVisible() or gui.IsGameUIVisible() then return end
    local x,y=input.GetCursorPos()
    local radius=math.Clamp(ScrH()/1080*8,6,12)
    draw.NoTexture() surface.SetDrawColor(235,241,250,65)
    draw.Circle(x,y,radius,32)
    surface.DrawCircle(x,y,radius,235,241,250,155)
end)

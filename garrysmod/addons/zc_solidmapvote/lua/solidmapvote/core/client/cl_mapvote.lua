
SolidMapVote.isOpen = SolidMapVote.isOpen or false
SolidMapVote.isNominating = SolidMapVote.isNominating or false

function SolidMapVote.open(maps, endTime, length)
    SolidMapVote.close()
    if ValidPanel(SolidMapVote.Nominate) then SolidMapVote.Nominate:Remove() end
    SolidMapVote.Nominate, SolidMapVote.isNominating = nil, false
    SolidMapVote.isOpen = true
    gui.EnableScreenClicker(true)
    SolidMapVote.Menu = vgui.Create('SolidMapVote')
    SolidMapVote.Menu:SetMaps(maps)
    if endTime and length then SolidMapVote.Menu:SetTime(endTime, length) end
end
function SolidMapVote.close()
    if ValidPanel(SolidMapVote.Menu) then SolidMapVote.Menu:Remove() end
    SolidMapVote.Menu, SolidMapVote.isOpen = nil, false
    gui.EnableScreenClicker(SolidMapVote.isNominating == true)
end
function SolidMapVote.PlayerName(id)
    return steamworks.GetPlayerName(id) or 'Unknown player'
end
function SolidMapVote.VotePower(ply)
    if not IsValid(ply) or ply:IsBot() then return 0 end
    local power = SolidMapVote.Config['Vote Power'](ply)
    if type(power) ~= 'number' or power ~= power or math.abs(power) == math.huge then return 1 end
    return math.Clamp(power, 1, 100)
end

function SolidMapVote.GetMapConfigInfo( map )
    for _, mapData in pairs( SolidMapVote[ 'Config' ][ 'Specific Maps' ] ) do
        if map == mapData.filename then
            return mapData
        end
    end

    return {
        filename = map,
        displayname = string.Replace( map, '_', ' ' ),
        image = SolidMapVote[ 'Config' ][ 'Missing Image' ],
        width = SolidMapVote[ 'Config' ][ 'Missing Image Size' ].width,
        height = SolidMapVote[ 'Config' ][ 'Missing Image Size' ].height
    }
end

hook.Add('PlayerBindPress', 'SolidMapVote.StopMovement', function(ply, bind)
    if not ValidPanel(SolidMapVote.Menu) or not SolidMapVote.Menu:IsVisible() then return end
    if (bind == 'messagemode' or bind == 'messagemode2') and SolidMapVote.Config['Enable Chat'] then return end
    if bind == '+voicerecord' and SolidMapVote.Config['Enable Voice'] then return end
    if bind == 'toggleconsole' or bind == 'cancelselect' then return end
    return true
end)

local matBlur = Material( 'pp/blurscreen' )
hook.Add( 'HUDPaint', 'SolidMapVote.DrawBackgroundBlur', function()
    if SolidMapVote.isOpen then
        surface.SetDrawColor( 255, 255, 255, 255 )
        surface.SetMaterial( matBlur )

        for i = 1, 3 do
            matBlur:SetFloat( '$blur', i )
            matBlur:Recompute()
            render.UpdateScreenEffectTexture()
            surface.DrawTexturedRect( 0, 0, ScrW(), ScrH() )
        end
    end
end )

concommand.Add( 'solidmapvote_nomination_menu', function()
    if SolidMapVote.isOpen then return end
    if SolidMapVote.isNominating then
        if ValidPanel( SolidMapVote.Nominate ) then
            SolidMapVote.Nominate:Remove()
            SolidMapVote.isNominating = false
            gui.EnableScreenClicker( SolidMapVote.isNominating )
        end

        return
    end

    SolidMapVote.isNominating = true
    gui.EnableScreenClicker( SolidMapVote.isNominating )
    SolidMapVote.Nominate = vgui.Create( 'SolidMapVoteNomination' )
end )

concommand.Add( 'solidmapvote_close_ui', function()
    SolidMapVote.close()
end )

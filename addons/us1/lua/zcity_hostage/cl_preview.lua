local frame
concommand.Add("zch_preview", function()
    if IsValid(frame) then frame:Remove() end
    frame = vgui.Create("DFrame")
    frame:SetSize(math.min(ScrW() - 40, 1200), math.min(ScrH() - 40, 800))
    frame:Center()
    frame:SetTitle("Hostage Set animation library")
    frame:MakePopup()

    local list = vgui.Create("DListView", frame)
    list:Dock(LEFT)
    list:SetWide(math.min(510, frame:GetWide() * 0.48))
    list:AddColumn("Animation")
    local status = vgui.Create("DLabel", frame)
    status:Dock(BOTTOM)
    status:SetTall(44)
    status:SetWrap(true)
    status:SetText("Select a clip. This preview does not move or animate any player.")
    local panel = vgui.Create("DModelPanel", frame)
    panel:Dock(FILL)
    panel:SetModel("models/player/group01/male_07.mdl")
    panel:SetLookAt(Vector(0, 0, 35))
    panel:SetCamPos(Vector(110, 100, 75))
    panel:SetFOV(45)
    local selected, started, duration
    function panel:LayoutEntity(ent)
        if not selected then return end
        local elapsed = RealTime() - started
        ent:SetCycle(selected.loop and (elapsed / duration) % 1 or math.min(elapsed / duration, 1))
        ent:SetPlaybackRate(0)
    end
    for _, clip in ipairs(ZCityHostage.Catalog) do
        local row = list:AddLine(clip.name)
        row.Clip = clip
    end
    function list:OnRowSelected(_, row)
        local clip = row.Clip
        local ent = panel:GetEntity()
        if not IsValid(ent) then return end
        local id, seconds = ent:LookupSequence(clip.sequence)
        if not id or id < 0 or not seconds or seconds <= 0 then
            selected = nil
            status:SetText("Animation not mounted. Install the complete addon and DynaBase content, then reconnect/restart the client.")
            return
        end
        selected, started, duration = clip, RealTime(), seconds
        ent:ResetSequence(id)
        ent:SetCycle(0)
        status:SetText(clip.sequence .. " | " .. string.format("%.2f seconds", duration)
            .. (clip.paired and " | Paired clip: preview shows one role only."
                or clip.requires_positioning and " | Requires gameplay positioning/collision handling." or ""))
    end
end)

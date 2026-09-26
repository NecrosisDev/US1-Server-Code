-- Read-only incident summaries; every action is validated by the server.
if not CLIENT then return end
ZCityGuiltReview = ZCityGuiltReview or {}
local C=ZCityGuiltReview
C.Version="20260916.1"
if IsValid(C.frame) then C.frame:Remove() end
local rows={}
local function send(row,action)
    net.Start("zc_guilt_action_v3")
    net.WriteUInt(row.caseid,32)
    net.WriteString(row.steamid64)
    net.WriteString(action)
    net.SendToServer()
end
local function text(parent,value,size)
    local p=vgui.Create("DLabel",parent)
    p:Dock(TOP);p:DockMargin(12,5,12,5);p:SetTall(size or 25)
    p:SetText(value);p:SetWrap(true);p:SetAutoStretchVertical(true)
    return p
end
local function button(parent,label,fn,enabled)
    local b=vgui.Create("DButton",parent)
    b:Dock(TOP);b:DockMargin(12,4,12,4);b:SetTall(34)
    b:SetText(label);b:SetEnabled(enabled~=false);b.DoClick=fn
    return b
end
function C.Show(inputRows)
    if GetGlobalBool("zc_meta_review_hold",false) then inputRows={} end
    rows=inputRows
    if IsValid(C.frame) then C.frame:Remove() end
    if #rows==0 then return end
    local f=vgui.Create("DFrame");C.frame=f
    f:SetSize(math.min(860,ScrW()-40),math.min(570,ScrH()-60))
    f:Center();f:SetTitle("Incident review and forgiveness");f:MakePopup()
    local list=vgui.Create("DListView",f)
    list:Dock(LEFT);list:SetWide(280);list:DockMargin(8,8,8,8)
    list:SetMultiSelect(false);list:AddColumn("Player");list:AddColumn("State"):SetFixedWidth(88)
    local detail=vgui.Create("DScrollPanel",f);detail:Dock(FILL);detail:DockMargin(0,8,8,8)
    local function select(row)
        detail:Clear()
        text(detail,row.name or "Disconnected player",30)
        text(detail,string.format("Target karma used: %.1f",row.victimKarma or 0))
        text(detail,string.format("Automatic loss: %.1f karma",row.loss or 0))
        text(detail,string.format("Bounty paid: +%.1f karma",row.bounty or 0))
        text(detail,string.format("Available refund: %.1f karma",row.refundable or 0))
        if not row.decided then
            if row.canForgive then
                button(detail,string.format("Forgive (+%.1f karma)",row.refundable or 0),function()send(row,"forgive")end)
            end
            if row.respectEligible then
                local n=row.respectReward or 0
                button(detail,n>0 and string.format("Give Respect (+%.1f karma)",n) or "Give Respect (acknowledgement)",function()send(row,"respect")end)
            end
            button(detail,(row.karma or 0)>0 and "Keep penalty" or "Acknowledge",function()send(row,"keep")end)
        else text(detail,"Decision saved: "..tostring(row.decision)) end
        if row.canReport then button(detail,"Report abuse to staff",function()send(row,"report")end) end
        text(detail,"Closing or ignoring this menu adds no penalty. Forgiveness returns only this incident's remaining loss. It does not heal injuries or revoke a valid bounty.",70)
    end
    for _,row in ipairs(rows) do
        local line=list:AddLine(row.name or "Disconnected player",row.decided and "Reviewed" or "Pending")
        line.review=row
    end
    list.OnRowSelected=function(_,_,line)select(line.review)end
    select(rows[1])
end
net.Receive("zc_guilt_review_v3",function()
    local raw=net.ReadString();if #raw>55000 then return end
    local data=util.JSONToTable(raw,false,true)
    if not istable(data) or #data>64 then return end
    for _,r in ipairs(data) do
        if not istable(r) or not isnumber(r.caseid) or not isstring(r.steamid64) then return end
    end
    C.Show(data)
end)
hook.Remove("HUDPaint","ZCITY_GUILT_Prompt")
hook.Remove("Think","ZCITY_GUILT_CloseResolvedMenu")
local pressed=false
hook.Add("HUDPaint","ZCityGuiltReview_Prompt",function()
    if not (ZCITY_GUILT and ZCITY_GUILT.Config and ZCITY_GUILT.Config.MenuEnabled == true) then pressed=false;return end
    if GetGlobalBool("zc_meta_review_hold",false) then pressed=false;return end
    local p=LocalPlayer()
    if not IsValid(p) or p:GetNWInt("ZCITY_GUILT_PENDING_COUNT",0)<=0 then pressed=false;return end
    if IsValid(C.frame) or gui.IsGameUIVisible() or IsValid(vgui.GetKeyboardFocus()) then pressed=false;return end
    draw.SimpleText("Press F to review this incident","DermaDefaultBold",ScrW()/2,ScrH()-42,color_white,TEXT_ALIGN_CENTER)
    local down=input.IsKeyDown(KEY_F)
    if down and not pressed then RunConsoleCommand("zcity_guilt_menu") end
    pressed=down
end)
local function installReviewPrompt()
    hook.Remove("HUDPaint","ZCITY_GUILT_Prompt")
    hook.Remove("Think","ZCITY_GUILT_CloseResolvedMenu")
end
hook.Add("InitPostEntity","ZCityGuiltReview_Install",installReviewPrompt)
hook.Add("OnReloaded","ZCityGuiltReview_Reload",function()timer.Simple(0,installReviewPrompt)end)
timer.Simple(0,installReviewPrompt)

hook.Add("Think","ZCityGuiltReview_MetaGuard",function()
    if GetGlobalBool("zc_meta_review_hold",false) and IsValid(C.frame) then C.frame:Remove() end
end)

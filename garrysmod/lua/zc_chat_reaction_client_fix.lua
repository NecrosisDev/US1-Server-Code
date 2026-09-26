local M=ZCChatMedia
if not M then return end
function M.UpdateRowActions(row, chat)
    local open = IsValid(chat) and chat:GetActive() and chat.phonePage ~= "home"
    if IsValid(row.ZCReactionAdd) then
        row.ZCReactionAdd:SetVisible(open)
    end
    if IsValid(row.ZCReportButton) then
        row.ZCReportButton:SetVisible(open and (row:IsHovered() or row.ZCReportButton:IsHovered()))
    end
end


local function attach(c)
 if not IsValid(c) or c.ZCReactionVisibilityFixed then return end
 c.ZCReactionVisibilityFixed=true
 local previous=c.Think
 c.Think=function(self)
  previous(self)
  for _,r in ipairs(self.entries or {}) do if IsValid(r) then
   if IsValid(r.ZCReactionAdd) then r.ZCReactionAdd.Think=nil end
   if IsValid(r.ZCReportButton) then r.ZCReportButton.Think=nil end
   M.UpdateRowActions(r,self)
  end end
 end
end
attach(hg and hg.chat)
hook.Add("Think","ZCChatReactionVisibilityRepair",function() attach(hg and hg.chat) end)

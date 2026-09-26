-- Bound only publication, never treatment. Preserve the final value after release.
local function PublishModeValues(self)
    if not IsValid(self) then return end
    local now = CurTime()
    local due = self.net_cooldown2 or 0
    if due > now + 0.11 then due = now end -- Clock reset / stale inherited deadline.
    if now >= due then
        self.ZCModePublishPending = nil
        self.net_cooldown2 = now + 0.1
        self:SetNetVar("modeValues", self.modeValues)
        return
    end
    if self.ZCModePublishPending then return end
    local token = {}
    self.ZCModePublishPending = token
    timer.Simple(math.max(0, due - now), function()
        if not IsValid(self) or self.ZCModePublishPending ~= token then return end
        self.ZCModePublishPending = nil
        self.net_cooldown2 = CurTime() + 0.1
        self:SetNetVar("modeValues", self.modeValues)
    end)
end

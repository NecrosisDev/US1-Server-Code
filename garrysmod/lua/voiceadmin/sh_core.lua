VoiceAdmin = VoiceAdmin or {}
local VA = VoiceAdmin

VA.VERSION = "0.1.0"
VA.PROTOCOL = 1

VA.Config = VA.Config or {
    Permission = "voiceadmin.use",
    MaxReasonBytes = 256,
    MaxNetBits = 16384,
    LockTTL = 20,
    RequestTTL = 15,
    KickVerifySeconds = 4,
    BanVerifySeconds = 3,
    IpcPollSeconds = 0.10,
    IpcBurst = 4,
}

VA.Net = {
    LockRequest = "va_lock_req",
    LockResult = "va_lock_result",
    Propose = "va_propose",
    Preview = "va_preview",
    Confirm = "va_confirm",
    Cancel = "va_cancel",
    Amend = "va_amend",
    Result = "va_result",
}

VA.Action = {
    FREEZE = 1,
    UNFREEZE = 2,
    KICK = 3,
    BAN = 4,
}

VA.ActionName = {
    [1] = "freeze",
    [2] = "unfreeze",
    [3] = "kick",
    [4] = "ban",
}

VA.Duration = {
    NONE = 0,
    TEMPORARY = 1,
    PERMANENT = 2,
}

function VA.NormalizeReason(reason)
    if not isstring(reason) then return nil, "reason is not a string" end
    reason = string.Trim(reason)
    reason = reason:gsub("%s+", " ")
    if reason:find("[%z\1-\31\127]") then
        return nil, "reason contains control characters"
    end
    if reason:find('"', 1, true) then
        return nil, "reason cannot contain literal quotation marks"
    end
    if #reason > VA.Config.MaxReasonBytes then
        return nil, "reason is too long"
    end
    return reason
end

function VA.DurationText(kind, minutes)
    if kind == VA.Duration.PERMANENT then return "permanent" end
    if kind == VA.Duration.TEMPORARY then
        minutes = tonumber(minutes) or 0
        if minutes % 10080 == 0 then return tostring(minutes / 10080) .. " week(s)" end
        if minutes % 1440 == 0 then return tostring(minutes / 1440) .. " day(s)" end
        if minutes % 60 == 0 then return tostring(minutes / 60) .. " hour(s)" end
        return tostring(minutes) .. " minute(s)"
    end
    return "none"
end

function VA.SafeId(value)
    value = tostring(value or ""):lower()
    if not value:match("^[a-z0-9_%-]+$") then return nil end
    if #value < 1 or #value > 64 then return nil end
    return value
end

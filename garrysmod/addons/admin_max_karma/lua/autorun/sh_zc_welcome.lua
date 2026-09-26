-- ZCity Welcome v2: ordered pages, staff editor and verified persistent saves.
-- Reopen with !guide / zc_info. Admins and superadmins can manage the guide.
local MAX_PAGES, MAX_TITLE, MAX_BODY, MAX_JSON = 32, 80, 8000, 56000
local DATA = "zc_welcome.txt"
local SYNC, ACTION, RESULT, REQUEST = "zc_welcome_sync_v2", "zc_welcome_action_v2", "zc_welcome_result_v2", "zc_welcome_request_v2"
local function Staff(p) return IsValid(p) and (p:IsAdmin() or p:IsSuperAdmin()) end
local DEFAULT_PAGES = {
	{ title = "RULES", body = "Server rules go here.\n\n(Admins: press EDIT below to write this page in-game.)" },
	{ title = "ZCITY MECHANICS", body = "How the core systems work - medical, karma, voice, the C-menu.\n\n(Admins: press EDIT below to write this page in-game.)" },
	{ title = "GAMEMODES", body = "The round types in rotation and how each is played.\n\n(Admins: press EDIT below to write this page in-game.)" },
	{ title = "CHANGES FROM VANILLA", body = "What this server changes and adds compared to stock ZCity.\n\n(Admins: press EDIT below to write this page in-game.)" },
	{ title = "BINDS", body = "Useful keybinds and console commands.\n\n(Admins: press EDIT below to write this page in-game.)" },
	{ title = "Mutations", body = "" },
}

local function ValidPages(pages)
    if not istable(pages) or #pages < 1 or #pages > MAX_PAGES then return false end
    local seen, count = {}, 0
    for k, page in pairs(pages) do
        if type(k) ~= "number" or k < 1 or k > #pages or k ~= math.floor(k) then return false end
        count = count + 1
        if not istable(page) or type(page.id) ~= "number" or page.id < 1 or page.id > 4294967294
            or page.id ~= math.floor(page.id) or seen[page.id] then return false end
        if not isstring(page.title) or #page.title > MAX_TITLE or page.title:Trim() == "" or page.title:find("%c") then return false end
        if not isstring(page.body) or #page.body > MAX_BODY then return false end
        seen[page.id] = true
    end
    return count == #pages
end
local function FindPage(pages, id)
    for i, page in ipairs(pages) do if page.id == id then return i, page end end
end
if SERVER then
    AddCSLuaFile()
    for _, name in ipairs({SYNC, ACTION, RESULT, REQUEST, "zc_welcome_edit", "zc_welcome_request"}) do util.AddNetworkString(name) end
    local state, loadError
    local session = tostring(os.time()) .. ":" .. tostring(SysTime())
    local nextAction, nextRequest = setmetatable({}, {__mode = "k"}), setmetatable({}, {__mode = "k"})
    local function Token() return session .. ":" .. state.revision end
    local function Encode(value)
        local json = util.TableToJSON(value, true)
        if not json or #json > MAX_JSON then return nil, "Guide is too large (56 KB total limit). Shorten a page before saving." end
        return json
    end
    local function VerifiedWrite(path, data)
        local ok = pcall(file.Write, path, data)
        return ok and file.Read(path, "DATA") == data
    end
    local function Backup(raw, label)
        file.CreateDir("zc_welcome_backups")
        local name = "zc_welcome_backups/" .. os.date("%Y%m%d-%H%M%S") .. "_" .. util.CRC(session .. ":" .. label) .. ".txt"
        return VerifiedWrite(name, raw)
    end
    local function Load()
        local raw = file.Read(DATA, "DATA")
        if raw then
            local ok, data = pcall(util.JSONToTable, raw)
            if ok and istable(data) and data.version == 2 and ValidPages(data.pages)
                and type(data.revision) == "number" and data.revision >= 1 and data.revision == math.floor(data.revision)
                and type(data.nextId) == "number" and data.nextId >= 1 and data.nextId <= 4294967295 and data.nextId == math.floor(data.nextId) then
                local largest = 0
                for _, page in ipairs(data.pages) do largest = math.max(largest, page.id) end
                if data.nextId > largest and Encode(data) then state = data return end
            elseif ok and istable(data) and #data >= 1 and #data <= MAX_PAGES then
                local migrated = table.Copy(data)
                -- Only the old four/five-page formats need the previously requested new tabs.
                if #migrated == 4 or #migrated == 5 then
                    for i = #migrated + 1, #DEFAULT_PAGES do migrated[i] = table.Copy(DEFAULT_PAGES[i]) end
                end
                for i, page in ipairs(migrated) do if istable(page) then page.id = i end end
                local candidate = {version = 2, revision = 1, nextId = #migrated + 1, pages = migrated}
                local encoded = Encode(candidate)
                if ValidPages(migrated) and encoded then
                    state = candidate
                    if not Backup(raw, "migration") then
                        loadError = "Could not back up the existing guide. Page management is locked until the DATA folder is writable."
                    elseif not VerifiedWrite(DATA, encoded) then
                        VerifiedWrite(DATA, raw)
                        loadError = "Could not save the guide migration. Original backup is in data/zc_welcome_backups."
                    end
                    return
                end
            end
            loadError = "Saved guide could not be loaded safely. Original file was left untouched; restore a valid guide before editing."
        end
        local pages = table.Copy(DEFAULT_PAGES)
        for i, page in ipairs(pages) do page.id = i end
        state = {version = 2, revision = 1, nextId = #pages + 1, pages = pages}
    end
    Load()
    local function SyncTo(p)
        net.Start(SYNC)
        net.WriteString(Token())
        net.WriteString(util.TableToJSON(state.pages))
        net.WriteString(loadError or "")
        if IsValid(p) then net.Send(p) else net.Broadcast() end
    end
    local function Reply(p, sequence, success, message, id)
        net.Start(RESULT)
        net.WriteUInt(sequence, 16)
        net.WriteBool(success)
        net.WriteString(message)
        net.WriteUInt(id or 0, 32)
        net.Send(p)
    end
    local function Commit(candidate)
        candidate.revision = state.revision + 1
        local encoded, err = Encode(candidate)
        if not encoded then return false, err end
        local previous = Encode(state)
        if not VerifiedWrite("zc_welcome_pending.txt", encoded) then return false, "Save failed: unable to verify the temporary DATA file. Your edit was not applied." end
        if not Backup(previous, "before_" .. candidate.revision) then return false, "Save failed: unable to create a backup. Your edit was not applied." end
        if not VerifiedWrite(DATA, encoded) then
            local restored = VerifiedWrite(DATA, previous)
            return false, restored and "Save failed. The previous guide was restored." or "Save failed. Previous guide is backed up in data/zc_welcome_backups."
        end
        state = candidate
        return true
    end
    net.Receive(REQUEST, function(len, p)
        if len ~= 0 or not IsValid(p) or (nextRequest[p] or 0) > CurTime() then return end
        nextRequest[p] = CurTime() + 1
        SyncTo(p)
    end)
    hook.Add("PlayerInitialSpawn", "ZCWelcome_Sync", function(p)
        timer.Simple(5, function() if IsValid(p) then SyncTo(p) end end)
    end)
    -- Legacy clients send array positions, which are unsafe after a reorder. Never accept those writes.
    net.Receive("zc_welcome_edit", function(_, p)
        if Staff(p) then p:ChatPrint("The welcome editor has been updated. Reconnect before editing the guide.") end
    end)
    net.Receive("zc_welcome_request", function() end)
    net.Receive(ACTION, function(len, p)
        if not Staff(p) or len > 9000 * 8 or len < 24 then return end
        local sequence, action = net.ReadUInt(16), net.ReadUInt(3)
        local token, id = net.ReadString(), net.ReadUInt(32)
        local function Fail(message) Reply(p, sequence, false, message, id) end
        if loadError then Fail(loadError) return end
        if (nextAction[p] or 0) > CurTime() then Fail("Please wait a moment before another change.") return end
        nextAction[p] = CurTime() + 0.15
        if token ~= Token() then
            SyncTo(p)
            Fail("The guide changed since this editor was opened. Your draft is still here; copy it, reopen the editor, then try again.")
            return
        end
        local candidate = table.Copy(state)
        local index, page = FindPage(candidate.pages, id)
        if action ~= 2 and not page then Fail("That page no longer exists.") return end
        local title, body
        if action == 1 or action == 2 or action == 5 then
            title = net.ReadString():Trim()
            if title == "" or #title > MAX_TITLE or title:find("%c") then Fail("Use a page name of 1-80 bytes without line breaks.") return end
        end
        if action == 1 then
            body = net.ReadString()
            if #body > MAX_BODY then Fail("Page text is too long (8,000-byte limit). Your draft has been kept.") return end
            page.title, page.body = title, body
        elseif action == 2 then
            if #candidate.pages >= MAX_PAGES then Fail("The guide supports up to 32 pages.") return end
            if candidate.nextId >= 4294967295 then Fail("Page ID limit reached.") return end
            id = candidate.nextId
            candidate.nextId = id + 1
            candidate.pages[#candidate.pages + 1] = {id = id, title = title, body = ""}
        elseif action == 3 then
            local position = net.ReadUInt(8)
            if position < 1 or position > #candidate.pages then Fail("Choose a valid page position.") return end
            if position == index then Reply(p, sequence, true, "Page is already in that position.", id) return end
            table.remove(candidate.pages, index)
            table.insert(candidate.pages, position, page)
        elseif action == 4 then
            if #candidate.pages == 1 then Fail("Keep at least one page in the guide.") return end
            table.remove(candidate.pages, index)
            id = candidate.pages[math.min(index, #candidate.pages)].id
        elseif action == 5 then
            page.title = title
        else Fail("Unknown page action.") return end
        if not ValidPages(candidate.pages) then Fail("Page data is invalid; nothing was changed.") return end
        local ok, err = Commit(candidate)
        if not ok then Fail(err) return end
        SyncTo()
        Reply(p, sequence, true, "Saved. All players now have the updated guide.", id)
        print("[ZCWelcome] " .. p:Nick() .. " saved page action " .. action .. " (revision " .. state.revision .. ")")
    end)
    return
end

-- ======================= CLIENT =======================
local pages = table.Copy(DEFAULT_PAGES)
for i, page in ipairs(pages) do page.id = i end
local revision, loadError, sequence, pending = "", "", 0, nil
local manager
local BG, PANEL = Color(18, 18, 22, 250), Color(28, 28, 34)
local ACCENT, TEXT, DIM = Color(255, 230, 0), Color(225, 225, 225), Color(140, 140, 140)
surface.CreateFont("ZCWelcome_Title", {font = "Bahnschrift", size = 28, weight = 900, antialias = true})
surface.CreateFont("ZCWelcome_Tab", {font = "Bahnschrift", size = 17, weight = 700, antialias = true})
surface.CreateFont("ZCWelcome_Body", {font = "Bahnschrift", size = 17, weight = 500, antialias = true})
local function Request()
    net.Start(REQUEST)
    net.SendToServer()
end
local function CanManage() return Staff(LocalPlayer()) and revision ~= "" and loadError == "" and not pending end
local function RefreshControls()
    if IsValid(ZCWelcomeFrame) and ZCWelcomeFrame.RefreshControls then ZCWelcomeFrame.RefreshControls() end
    if IsValid(manager) and manager.RefreshControls then manager.RefreshControls() end
end
local function Feedback(message, bad)
    if IsValid(ZCWelcomeFrame) then ZCWelcomeFrame.SetStatus(message) end
    if bad then Derma_Message(message, "Welcome guide", "OK") end
end
local function Send(action, id, title, body, position, token, onSuccess)
    if not CanManage() then Feedback(loadError ~= "" and loadError or "Wait for the guide to finish syncing before making changes.", true) return end
    if action == 1 or action == 2 or action == 5 then
        local name = (title or ""):Trim()
        if name == "" or #name > MAX_TITLE or name:find("%c") then Feedback("Use a page name of 1-80 bytes without line breaks.", true) return end
    end
    if action == 1 and #(body or "") > MAX_BODY then Feedback("Page text is too long (8,000-byte limit). Your draft has been kept.", true) return end
    sequence = (sequence + 1) % 65536
    local request = {sequence = sequence, onSuccess = onSuccess}
    pending = request
    RefreshControls()
    net.Start(ACTION)
    net.WriteUInt(sequence, 16)
    net.WriteUInt(action, 3)
    net.WriteString(token or revision)
    net.WriteUInt(id or 0, 32)
    if action == 1 or action == 2 or action == 5 then net.WriteString(title or "") end
    if action == 1 then net.WriteString(body or "") end
    if action == 3 then net.WriteUInt(position, 8) end
    net.SendToServer()
    timer.Simple(10, function()
        if pending ~= request then return end
        pending = nil
        RefreshControls()
        Request()
        Feedback("No save confirmation arrived. Your draft is still here. Check the refreshed guide before trying again.", true)
    end)
end
net.Receive(SYNC, function()
    local token, raw, err = net.ReadString(), net.ReadString(), net.ReadString()
    if #raw > MAX_JSON then return end
    local ok, data = pcall(util.JSONToTable, raw)
    if not ok or not ValidPages(data) then return end
    pages, revision, loadError = data, token, err
    if IsValid(ZCWelcomeFrame) then ZCWelcomeFrame.Refresh() end
    if IsValid(manager) then manager.Refresh() end
end)
net.Receive(RESULT, function()
    local seq, success, message, id = net.ReadUInt(16), net.ReadBool(), net.ReadString(), net.ReadUInt(32)
    if not pending or pending.sequence ~= seq then return end
    local request = pending
    pending = nil
    if success and request.onSuccess then request.onSuccess(id) end
    RefreshControls()
    Feedback(message, not success)
end)
local function Button(parent, label, x, y, w, fn)
    local b = vgui.Create("DButton", parent)
    b:SetPos(x, y); b:SetSize(w, 30); b:SetText(label); b:SetFont("ZCWelcome_Tab")
    b:SetTextColor(TEXT)
    b.Paint = function(s, pw, ph)
        draw.RoundedBox(4, 0, 0, pw, ph, s:IsEnabled() and (s:IsHovered() and Color(70, 66, 35) or Color(44, 44, 52)) or Color(30, 30, 35))
    end
    b.DoClick = fn
    return b
end
local function OpenManager(owner, startId)
    if not CanManage() then return end
    if IsValid(manager) then manager:Remove() end
    local frame = vgui.Create("DFrame")
    manager = frame
    local w, h = math.min(680, ScrW() - 40), math.min(460, ScrH() - 60)
    frame:SetSize(w, h); frame:Center(); frame:SetTitle("Manage guide pages"); frame:MakePopup()
    frame.Paint = function(_, pw, ph) draw.RoundedBox(6, 0, 0, pw, ph, BG) end
    local note = vgui.Create("DLabel", frame)
    note:SetPos(16, 32); note:SetSize(w - 32, 25); note:SetTextColor(TEXT)
    note:SetText("The first page opens by default. Changes save and sync to everyone.")
    local list = vgui.Create("DListView", frame)
    list:SetPos(16, 64); list:SetSize(w - 196, h - 80); list:SetMultiSelect(false)
    list:AddColumn("Order"):SetFixedWidth(48)
    list:AddColumn("Page")
    local selected = startId
    local buttons = {}
    local function Current() return FindPage(pages, selected) end
    local function Rename()
        local _, page = Current(); if not page then return end
        local id, token = page.id, revision
        Derma_StringRequest("Rename page", "Page name:", page.title, function(name)
            Send(5, id, name, nil, nil, token)
        end)
    end
    local function Move(position)
        local _, page = Current(); if not page then return end
        Send(3, page.id, nil, nil, position)
    end
    local x, y = w - 164, 64
    buttons.add = Button(frame, "Add page", x, y, 148, function()
        local token = revision
        Derma_StringRequest("Add page", "Name the new blank page:", "New page", function(name)
            Send(2, 0, name, nil, nil, token, function(id)
                selected = id
                if IsValid(frame) then frame:Remove() end
                if IsValid(owner) then owner.EditPage(id) end
            end)
        end)
    end)
    buttons.rename = Button(frame, "Rename", x, y + 38, 148, Rename)
    buttons.up = Button(frame, "Move up", x, y + 76, 148, function() local i = Current(); if i and i > 1 then Move(i - 1) end end)
    buttons.down = Button(frame, "Move down", x, y + 114, 148, function() local i = Current(); if i and i < #pages then Move(i + 1) end end)
    buttons.position = Button(frame, "Move to...", x, y + 152, 148, function()
        local index, page = Current(); if not page then return end
        local id, token, count = page.id, revision, #pages
        Derma_StringRequest("Move page", "Position from 1 to " .. count .. ":", tostring(index), function(value)
            local pos = tonumber(value)
            if not pos or pos ~= math.floor(pos) or pos < 1 or pos > count then Feedback("Enter a whole page position from 1 to " .. count .. ".", true) return end
            Send(3, id, nil, nil, pos, token)
        end)
    end)
    buttons.delete = Button(frame, "Delete page...", x, y + 190, 148, function()
        local _, page = Current(); if not page then return end
        local id, token, title = page.id, revision, page.title
        Derma_Query("Delete '" .. title .. "' and its text? A server-side backup is saved first.", "Delete guide page",
            "Delete", function() Send(4, id, nil, nil, nil, token, function(nextId) selected = nextId; if IsValid(frame) then frame.Refresh() end end) end, "Cancel")
    end)
    function frame.RefreshControls()
        local index, page = Current()
        local allowed = CanManage()
        buttons.add:SetEnabled(allowed and #pages < MAX_PAGES)
        buttons.rename:SetEnabled(allowed and page ~= nil)
        buttons.up:SetEnabled(allowed and index ~= nil and index > 1)
        buttons.down:SetEnabled(allowed and index ~= nil and index < #pages)
        buttons.position:SetEnabled(allowed and page ~= nil and #pages > 1)
        buttons.delete:SetEnabled(allowed and page ~= nil and #pages > 1)
    end
    list.OnRowSelected = function(_, _, row) selected = row.pageId; frame.RefreshControls() end
    function frame.Refresh()
        if not FindPage(pages, selected) then selected = pages[1].id end
        list:Clear()
        for i, page in ipairs(pages) do
            local row = list:AddLine(i, page.title)
            row.pageId = page.id
            if page.id == selected then list:SelectItem(row) end
        end
        frame.RefreshControls()
    end
    frame.Refresh()
end
local function OpenWelcome()
    if IsValid(ZCWelcomeFrame) then ZCWelcomeFrame:MakePopup(); Request(); return end
    Request()
    local w, h = math.min(860, ScrW() - 40), math.min(640, ScrH() - 60)
    local frame = vgui.Create("DFrame")
    ZCWelcomeFrame = frame
    frame:SetSize(w, h); frame:Center(); frame:SetTitle(""); frame:ShowCloseButton(false); frame:MakePopup()
    frame.Paint = function(_, pw, ph)
        draw.RoundedBox(6, 0, 0, pw, ph, BG)
        draw.SimpleText("GOOB'S ZCITY VANILLA+", "ZCWelcome_Title", 24, 18, ACCENT)
        draw.SimpleText("server information", "ZCWelcome_Tab", 24, 49, DIM)
    end
    local currentId = pages[1].id
    local editing, editId, editToken, originalTitle, originalBody = false, nil, nil, nil, nil
    local titleEntry, bodyEntry, saveBtn, cancelBtn, editBtn, manageBtn
    local tabButtons = {}
    local tabBar = vgui.Create("DHorizontalScroller", frame)
    tabBar:SetPos(24, 82); tabBar:SetSize(w - 48, 32); tabBar:SetOverlap(-4); tabBar.Paint = nil
    local bodyPanel = vgui.Create("DPanel", frame)
    local bodyHeight = h - 122 - (Staff(LocalPlayer()) and 116 or 66)
    bodyPanel:SetPos(24, 122); bodyPanel:SetSize(w - 48, bodyHeight)
    bodyPanel.Paint = function(_, pw, ph) draw.RoundedBox(4, 0, 0, pw, ph, PANEL) end
    local bodyLabel = vgui.Create("RichText", bodyPanel)
    bodyLabel:Dock(FILL); bodyLabel:DockMargin(14, 12, 8, 12); bodyLabel:SetVerticalScrollbarEnabled(true)
    bodyLabel.PerformLayout = function(s) s:SetFontInternal("ZCWelcome_Body"); s:SetFGColor(TEXT) end
    local status = vgui.Create("DLabel", frame)
    status:SetPos(24, h - 59); status:SetSize(w - 204, 45); status:SetWrap(true); status:SetTextColor(DIM)
    status:SetText("Reopen any time with !guide")
    function frame.SetStatus(text) status:SetText(text) end
    local function Dirty()
        return editing and IsValid(titleEntry) and (titleEntry:GetValue() ~= originalTitle or bodyEntry:GetValue() ~= originalBody)
    end
    local function Close()
        if pending then Feedback("Wait for the save confirmation before closing.", true) return end
        if Dirty() then Derma_Query("Discard your unsaved page edits?", "Close guide", "Discard", function() frame:Remove() end, "Keep editing")
        else frame:Remove() end
    end
    frame.Close = Close
    frame.OnRemove = function() if IsValid(manager) then manager:Remove() end end
    Button(frame, "X", w - 48, 14, 28, Close)
    Button(frame, "GOT IT", w - 156, h - 48, 132, Close)
    function frame.RefreshControls()
        for _, b in pairs(tabButtons) do b:SetEnabled(not editing and not pending) end
        if IsValid(editBtn) then editBtn:SetEnabled(CanManage() and not editing) end
        if IsValid(manageBtn) then manageBtn:SetEnabled(CanManage() and not editing) end
        if IsValid(saveBtn) then saveBtn:SetEnabled(CanManage()) end
        if IsValid(cancelBtn) then cancelBtn:SetEnabled(not pending) end
    end
    local function KillEditor()
        editing = false
        for _, panel in pairs({titleEntry, bodyEntry, saveBtn, cancelBtn}) do if IsValid(panel) then panel:Remove() end end
        titleEntry, bodyEntry, saveBtn, cancelBtn = nil, nil, nil, nil
        bodyPanel:SetVisible(true)
    end
    local function ShowPage(id)
        local _, page = FindPage(pages, id)
        page = page or pages[1]
        currentId = page.id
        bodyLabel:SetText(""); bodyLabel:InsertColorChange(225, 225, 225, 255); bodyLabel:AppendText(page.body); bodyLabel:GotoTextStart()
        for pageId, b in pairs(tabButtons) do b.active = pageId == currentId end
    end
    local function BuildTabs()
        for _, b in pairs(tabButtons) do if IsValid(b) then b:Remove() end end
        tabButtons = {}; tabBar.Panels = {}
        for _, page in ipairs(pages) do
            local id = page.id
            local b = vgui.Create("DButton", tabBar)
            surface.SetFont("ZCWelcome_Tab")
            local tw = surface.GetTextSize(page.title)
            b:SetSize(tw + 26, 32); b:SetText(""); b.title = page.title
            b.Paint = function(s, pw, ph)
                local col = s.active and ACCENT or (s:IsHovered() and TEXT or DIM)
                draw.SimpleText(s.title, "ZCWelcome_Tab", pw / 2, ph / 2 - 2, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                if s.active then surface.SetDrawColor(ACCENT); surface.DrawRect(6, ph - 3, pw - 12, 2) end
            end
            b.DoClick = function() if not editing and not pending then ShowPage(id) end end
            tabButtons[id] = b; tabBar:AddPanel(b)
        end
        tabBar:InvalidateLayout(true)
    end
    function frame.Refresh()
        BuildTabs()
        if not editing then ShowPage(currentId)
        elseif editToken ~= revision and not pending then frame.SetStatus("Guide changed. Copy your draft before reopening this editor to save.") end
        if loadError ~= "" then frame.SetStatus(loadError) end
        frame.RefreshControls()
    end
    function frame.EditPage(id)
        if editing or not CanManage() then return end
        local _, page = FindPage(pages, id); if not page then return end
        ShowPage(id)
        editing, editId, editToken = true, id, revision
        originalTitle, originalBody = page.title, page.body
        bodyPanel:SetVisible(false)
        titleEntry = vgui.Create("DTextEntry", frame)
        titleEntry:SetPos(24, 122); titleEntry:SetSize(w - 48, 28); titleEntry:SetFont("ZCWelcome_Tab"); titleEntry:SetText(page.title)
        bodyEntry = vgui.Create("DTextEntry", frame)
        bodyEntry:SetPos(24, 156); bodyEntry:SetSize(w - 48, bodyHeight - 34); bodyEntry:SetMultiline(true); bodyEntry:SetFont("ZCWelcome_Body"); bodyEntry:SetText(page.body)
        saveBtn = Button(frame, "SAVE", w - 148, h - 102, 124, function()
            Send(1, editId, titleEntry:GetValue(), bodyEntry:GetValue(), nil, editToken, function(savedId)
                if not IsValid(frame) then return end
                KillEditor(); ShowPage(savedId); frame.RefreshControls()
            end)
        end)
        cancelBtn = Button(frame, "Cancel edit", w - 284, h - 102, 124, function()
            KillEditor(); ShowPage(currentId); frame.RefreshControls(); frame.SetStatus("Edit cancelled.")
        end)
        frame.SetStatus("Edit the page name above and its text below. Save applies it to everyone.")
        frame.RefreshControls()
    end
    if Staff(LocalPlayer()) then
        editBtn = Button(frame, "EDIT PAGE", 24, h - 102, 144, function() frame.EditPage(currentId) end)
        manageBtn = Button(frame, "MANAGE PAGES", 180, h - 102, 164, function() OpenManager(frame, currentId) end)
        -- Editing controls share this row; hide the ordinary controls while editing.
        local refresh = frame.RefreshControls
        function frame.RefreshControls()
            editBtn:SetVisible(not editing); manageBtn:SetVisible(not editing); refresh()
        end
    end
    frame.Refresh()
end
hook.Add("InitPostEntity", "ZCWelcome_FirstJoin", function()
    Request()
    timer.Simple(8, OpenWelcome)
end)
concommand.Add("zc_info", OpenWelcome)
hook.Add("OnPlayerChat", "ZCWelcome_ChatOpen", function(p, text)
    if p == LocalPlayer() and text:lower():Trim() == "!guide" then OpenWelcome(); return true end
end)

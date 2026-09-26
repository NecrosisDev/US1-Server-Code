-- GoobOS chat links (US1, 2026-09-25).
--   "!settings" said on its own opens that app for whoever said it and never reaches chat.
--   "!settings preferences" - alone or inside any sentence - stays in chat, and every reader sees it tidied
--   into a link, "Settings › Preferences", that opens GoobOS on that page. A word that is not a page stays
--   plain text after the app link ("!settings foo" is a link to Settings, then "foo").
-- Shared: the app words and the release gate. Server: the bare command. Client: the pages, the opener and
-- the render pass zc_chat_media/client.lua runs from M.FilterRowText. Render-only, like the rest of that
-- pass: stored text, reports, spoilers and restored history keep exactly what the player typed.
if SERVER then AddCSLuaFile() end

ZCGoobLinks = ZCGoobLinks or {}
local L = ZCGoobLinks
L.Version = "20260925.2"

-- New US1 features ship locked to one tester until the owner lifts the lock: 0 off, 1 tester only,
-- 2 everyone. Replicated, so "zc_goob_links 2" in the server console releases it with no map change.
local modeVar = CreateConVar("zc_goob_links", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "GoobOS chat links: 0 off, 1 tester only, 2 everyone")
local testerVar = CreateConVar("zc_goob_links_tester", "76561198011536179", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "SteamID64 that gets GoobOS chat links while zc_goob_links is 1")

function L.Allowed(ply)
    local mode = modeVar:GetInt()
    if mode >= 2 then return true end
    return mode == 1 and IsValid(ply) and ply:SteamID64() == string.Trim(testerVar:GetString())
end

-- Ids are apps.lua A.Register ids ("home" is the launcher). Every word was checked against the say
-- commands on US1 on 2026-09-25 - ULX/ULib, and the exact-match HG_PlayerSay commands (!pointshop,
-- !playtime, !indicators, !logs, !reinforce) - and none collides. "chat" is left out: you are in it.
L.Apps = {
    {id = "home", title = "GoobOS", words = {"goobos", "phone", "home"}},
    {id = "settings", title = "Settings", words = {"settings", "setting", "options"}},
    {id = "arcade", title = "Arcade", words = {"arcade"}},
    {id = "shop", title = "Shop", words = {"shop"}},
    {id = "wardrobe", title = "Wardrobe", words = {"wardrobe"}},
    {id = "progress", title = "Progress", words = {"progress", "achievements"}},
    {id = "replays", title = "Replays", words = {"replays", "replay"}},
    {id = "feed", title = "CityLeak", words = {"cityleak", "feed"}},
    {id = "messages", title = "Messages", words = {"messages"}},
    {id = "camera", title = "Camera", words = {"camera"}},
    {id = "voice", title = "Voice", words = {"voice"}},
    {id = "donate", title = "Donate", words = {"donate"}}
}
L.ByWord = {}
for _, app in ipairs(L.Apps) do
    for _, word in ipairs(app.words) do L.ByWord[word] = app end
end

if SERVER then
    -- The !pointshop / !playtime seam: HG_PlayerSay, matched on the raw third argument (the table slot is
    -- what furrify and the brain-damage garble rewrite), trimmed and case-folded but EXACT, so a sentence
    -- that mentions !settings is still a message. Swallowed after: ZChat drops a message whose first slot
    -- is empty. The client opens the app through apps.lua's own "goobos <id>" command, so this does not
    -- depend on the client half of this file having loaded. HOOK_LOW (ULib) runs it after the rewriters
    -- at normal priority: sv_comunication's "huy" turns a hypoxic player's slot into "...", which would
    -- otherwise put a stray "..." in chat whenever it ran after the swallow.
    hook.Add("HG_PlayerSay", "ZCGoobLinks_Open", function(ply, txtTbl, txt)
        if not isstring(txt) or not L.Allowed(ply) then return end
        local word = string.match(string.lower(string.Trim(txt)), "^!(%a+)$")
        local app = word and L.ByWord[word]
        if not app then return end
        ply:ConCommand("goobos " .. app.id)
        if istable(txtTbl) then txtTbl[1] = "" end
    end, HOOK_LOW)
    -- Load receipt: autorefresh is off on US1, so this is how an SSH check proves a map change loaded it.
    file.CreateDir("zc_goob_links")
    file.Write("zc_goob_links/loaded.txt", L.Version .. " " .. os.date("!%Y-%m-%d %H:%M:%S") .. "\n")
    return
end

-- Link blue (#58A6FF). Each link in a row gets its own blue channel (255, 254, ...), so the parsed markup
-- blocks trace back to their link: hg.markup keeps the tag's colour on every block, the pieces of a
-- wrapped label included. No identity tier or mention colour has this red and green.
local LINK_R, LINK_G, LINK_B, MAX_LINKS = 88, 166, 255, 8

local function entry(label, words, value)
    return {label = label, words = words, value = value}
end

-- shop.lua and progress.lua keep {query, filter}; either may not exist yet if the app never opened.
local function filterState(id, filter)
    local A = ZCGoobApps
    local state = A.State[id] or {}
    A.State[id] = state
    state.filter, state.query = filter, ""
end

-- What a link can open inside each app. apply(page) writes the state that app's own tab control writes,
-- and the build A.Launch/A.Open runs next reads it back. A page behind a search box clears the search,
-- or a filter the reader typed last week would hide the page being linked.
L.Pages = {
    arcade = {
        list = {entry("Blackjack", {"blackjack"}, "blackjack"), entry("Mines", {"mines"}, "mines"),
            entry("Match", {"match"}, "match"), entry("Duels", {"duels"}, "duels"),
            entry("Ledger", {"ledger"}, "ledger"), entry("History", {"history"}, "history")},
        -- arcade.lua C.tab; its build moves a tab the current scope does not allow back to "match".
        apply = function(page)
            local C = ZCGoobApps.State.arcade
            if C then C.tab = page.value end
        end
    },
    wardrobe = {
        list = {entry("Identity", {"identity"}, 1), entry("Clothing", {"clothing", "clothes"}, 2),
            entry("Body", {"body"}, 3), entry("Accessories", {"accessories"}, 4), entry("Looks", {"looks"}, 5)},
        apply = function(page)
            local A = ZCGoobApps
            A.State.wardrobe = A.State.wardrobe or {}
            A.State.wardrobe.tab = page.value
        end
    },
    shop = {
        list = {entry("All", {"all"}, "All"), entry("Available", {"available"}, "Available"), entry("Owned", {"owned"}, "Owned")},
        apply = function(page) filterState("shop", page.value) end
    },
    progress = {
        list = {entry("All", {"all"}, "All"), entry("In progress", {"in progress"}, "In progress"),
            entry("Completed", {"completed"}, "Completed")},
        apply = function(page) filterState("progress", page.value) end
    },
    replays = {
        list = {entry("All", {"all"}, 1), entry("My deaths", {"my deaths", "deaths"}, 2), entry("Highlights", {"highlights"}, 3)},
        -- replays.lua builds S at file load (queue, rows); only the filter moves, and dirty rebuilds the list.
        apply = function(page)
            local S = ZCGoobApps.State.replays
            if S then S.filter, S.dirty = page.value, true end
        end
    },
    feed = {
        list = {entry("Latest", {"latest"}, "feed"), entry("Create", {"create", "post"}, "compose"),
            entry("My profile", {"my profile", "profile"}, "profile")},
        -- feed_ui.lua's own tab click, field for field.
        apply = function(page)
            local C = ZCGoobFeed and ZCGoobFeed.Client
            if C then C.view, C.author, C.before, C.commentBefore, C.feedItems, C.autoLoading = page.value, nil, nil, nil, {}, false end
        end
    }
}

-- Settings pages are read live: the pages other addons register beside Preferences (hg.settings.pages, e.g. the
-- crosshair editor), the phone sections from ZCPhoneSettings, and every category hg.settings holds right now,
-- opened as a search - in Preferences, or in the page that claims the category. Fixed words come first, then
-- pages, and an earlier entry wins a tie with a later one of the same name ("!settings crosshair" is the page).
local SETTINGS_FIXED = {
    {label = "Preferences", words = {"preferences", "prefs", "game"}, tab = "Preferences"},
    {label = "Keybinds", words = {"keybinds", "keys", "binds", "controls"}, tab = "Keybinds"}
}

-- Chat text is matched as it sits in the markup, where M.Escape has turned < and > into entities.
local function chatEscape(text)
    return (string.gsub(string.gsub(text, "<", "&lt;"), ">", "&gt;"))
end
L.ChatEscape = chatEscape

L.Pages.settings = {
    list = function()
        local list = {}
        for i, page in ipairs(SETTINGS_FIXED) do list[i] = page end
        -- settings.lua lists a page only when it has a build function (and opens Preferences for any other tab).
        local claimed = {}
        local pages = hg and hg.settings and hg.settings.pages
        for name, page in pairs(istable(pages) and pages or {}) do
            if isstring(name) and istable(page) and isfunction(page.build) then
                local words = {chatEscape(string.lower(name))}
                for _, alt in ipairs({page.title, page.short}) do
                    if isstring(alt) and alt ~= "" then words[#words + 1] = chatEscape(string.lower(alt)) end
                end
                list[#list + 1] = {label = isstring(page.title) and page.title or name, words = words, tab = name}
                for _, category in ipairs(istable(page.categories) and page.categories or {}) do claimed[category] = name end
            end
        end
        local S = ZCPhoneSettings
        for _, name in ipairs((S and S.Sections) or {}) do
            if isstring(name) then list[#list + 1] = {label = name, words = {chatEscape(string.lower(name))}, tab = "Phone", section = name} end
        end
        local categories = hg and hg.settings and hg.settings.tbl
        for name in pairs(istable(categories) and categories or {}) do
            if isstring(name) then list[#list + 1] = {label = name, words = {chatEscape(string.lower(name))}, tab = claimed[name] or "Preferences", query = name} end
        end
        return list
    end,
    -- settings.lua state.tab / phoneSection / query: what its sidebar and search box write.
    apply = function(page)
        local A = ZCGoobApps
        local state = A.State.settings or {}
        A.State.settings = state
        state.tab, state.query = page.tab, page.query or ""
        if page.section then state.phoneSection = page.section end
    end
}

function L.PageList(id)
    local pages = L.Pages[id]
    if not pages then return nil end
    if isfunction(pages.list) then return pages.list() end
    return pages.list
end

-- Longest page word that starts at byte i of lower (already lower-cased) and ends on a word boundary.
local function matchPage(list, lower, i)
    local best, last
    for _, page in ipairs(list) do
        for _, word in ipairs(page.words) do
            local e = i + #word - 1
            if (not last or e > last) and string.sub(lower, i, e) == word and not string.find(string.sub(lower, e + 1, e + 1), "[%w_]") then
                best, last = page, e
            end
        end
    end
    return best, last
end
L.MatchPage = matchPage

local function escape(text)
    return (string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

local function unescape(text)
    return (string.gsub(string.gsub(string.gsub(text, "&gt;", ">"), "&lt;", "<"), "&amp;", "&"))
end

-- One run of text with no tags in it. A token is "!" and an app word, glued to no word and no other "!"
-- on either side; one or more spaces and a page word may follow it.
local function linkRun(run, links)
    local lower = string.lower(run)
    local out, pos, from = {}, 1, 1
    while #links < MAX_LINKS do
        local s, e, word = string.find(lower, "!(%a+)", from)
        if not s then break end
        local app = L.ByWord[word]
        local before = s > 1 and string.sub(lower, s - 1, s - 1) or ""
        if app and not string.find(before, "[%w_!]") and not string.find(string.sub(lower, e + 1, e + 1), "[%w_]") then
            local page, last = nil, e
            local list = L.PageList(app.id)
            local _, gap = string.find(lower, "^ +", e + 1)
            if list and gap then
                local found, stop = matchPage(list, lower, gap + 1)
                if found then page, last = found, stop end
            end
            local label = page and (app.title .. " › " .. page.label) or app.title
            links[#links + 1] = {id = app.id, page = page, label = label}
            out[#out + 1] = string.sub(run, pos, s - 1)
            out[#out + 1] = string.format("<color=%d,%d,%d>%s</color>", LINK_R, LINK_G, LINK_B - #links + 1, escape(label))
            pos, from = last + 1, last + 1
        else
            from = e + 1
        end
    end
    out[#out + 1] = string.sub(run, pos)
    return table.concat(out)
end

-- Markup text arrives escaped (M.Format turns every < and > a player typed into an entity), so every
-- "<...>" in it is a tag the chat wrote itself; only the text between tags is scanned.
local function eachRun(text, fn)
    local out, pos = {}, 1
    while pos <= #text do
        local open = string.find(text, "<", pos, true)
        if not open then
            out[#out + 1] = fn(string.sub(text, pos))
            break
        end
        if open > pos then out[#out + 1] = fn(string.sub(text, pos, open - 1)) end
        local close = string.find(text, ">", open, true)
        if not close then
            out[#out + 1] = string.sub(text, open)
            break
        end
        out[#out + 1] = string.sub(text, open, close)
        pos = close + 1
    end
    return table.concat(out)
end

L.Rows = L.Rows or setmetatable({}, {__mode = "k"})

-- Called from zc_chat_media M.FilterRowText (pcall'd there). Only a build of the row's own text records
-- its links: M.ReplyLabel runs the same pass over the grouped copy for the reply quote.
function L.RenderRow(row, text)
    if type(text) ~= "string" or not string.find(text, "!", 1, true) or not L.Allowed(LocalPlayer()) then
        if row and text == row.text then row.ZCGoobLinks = nil end
        return text
    end
    local links = {}
    -- The speaker's name is a run of its own (IdentityMarkup, or the Player element): a player named
    -- "!shop" does not turn the header of everything they say into a link.
    local name = isstring(row.ZCSenderName) and row.ZCSenderName or nil
    local out = eachRun(text, function(run)
        if name and unescape(string.Trim(run)) == name then return run end
        return linkRun(run, links)
    end)
    if text == row.text then
        row.ZCGoobLinks = links[1] and links or nil
        if row.ZCGoobLinks then L.Rows[row] = true end
    end
    return out
end

function L.Open(id, page)
    local A = ZCGoobApps
    if not (A and isfunction(A.Launch)) then return false end
    local pages = page and L.Pages[id]
    if pages and pages.apply then
        local ok, err = pcall(pages.apply, page)
        if not ok then ErrorNoHalt("[GoobOS links] " .. tostring(err) .. "\n") end
    end
    -- Already on that app: SetPhonePage would ignore the same page, so rebuild it on the new state.
    local phone = hg and hg.chat
    if page and IsValid(phone) and phone:GetActive() and phone.phonePage == id and isfunction(A.Open) then
        A.Open(phone, id)
        if isfunction(A.Sync) then A.Sync(phone) end
        return true
    end
    return A.Launch(id) == true
end

local function reducedMotion()
    return ZCPhoneSettings and isfunction(ZCPhoneSettings.ReducedMotion) and ZCPhoneSettings.ReducedMotion() or false
end

local function clearButtons(row)
    for _, button in ipairs(row.ZCGoobLinkButtons or {}) do
        if IsValid(button) then button:Remove() end
    end
    row.ZCGoobLinkButtons, row.ZCGoobLinkMarkup = nil, nil
end

-- The underline follows cl_zchat.lua's typewriter (onDrawText in BuildMarkup): it draws as far as the
-- label's text has been revealed, and at once when motion is reduced or the typewriter is off.
local function revealed(row, button)
    local block = button.ZCBlock
    if not row.ZCTypewriterStart or not block.ZCRevealBefore or reducedMotion() then return 1 end
    if ZCPhoneSettings and isfunction(ZCPhoneSettings.Get) and ZCPhoneSettings.Get("typewriter") == 0 then return 1 end
    local shown = (CurTime() - row.ZCTypewriterStart) * (row.ZCTypewriterRate or 45) - block.ZCRevealBefore
    return math.Clamp(shown / button.ZCChars, 0, 1)
end

local function paintLink(button, w, h)
    local row = button:GetParent()
    local alpha = IsValid(row) and ZCChatMedia and isfunction(ZCChatMedia.Alpha) and ZCChatMedia.Alpha(row) or 0
    if alpha <= 0 then return end
    local shown = revealed(row, button)
    if shown <= 0 then return end
    local hovered = button:IsHovered()
    surface.SetDrawColor(LINK_R, LINK_G, LINK_B, alpha * (hovered and 1 or 0.55))
    surface.DrawRect(0, h - 2, math.ceil(w * shown), hovered and 2 or 1)
end

-- One transparent button over each block of each link label, at the spot row:Paint draws that block
-- (markup:draw at ZCTextX, below the bubble inset and any reply quote).
function L.Place(row)
    clearButtons(row)
    local links, markup = row.ZCGoobLinks, row.markup
    row.ZCGoobLinkMarkup = markup
    if not links or not istable(markup) or not istable(markup.blocks) then return end
    local top = (row.ZCBubble and 4 or 0) + (row.ZCQuoteHeight or 0)
    local buttons = {}
    for _, block in ipairs(markup.blocks) do
        local c = block.text and block.colour
        local link = c and tonumber(c.r) == LINK_R and tonumber(c.g) == LINK_G and links[LINK_B - (tonumber(c.b) or 0) + 1]
        if link then
            surface.SetFont(block.font)
            local shown = string.gsub(block.text, "%s+$", "")
            local w = surface.GetTextSize(shown)
            if w > 0 then
                local button = vgui.Create("DButton", row)
                button:SetText("")
                button:SetCursor("hand")
                button:SetKeyboardInputEnabled(false)
                button:SetTooltip("Open " .. link.label)
                button.ZCBlock = block
                button.ZCChars = math.max(1, string.utf8len and string.utf8len(block.text) or #block.text)
                button.ZCBaseX, button.ZCBaseY = (row.ZCTextX or 0) + block.offset.x, top + block.offset.y
                button:SetPos(button.ZCBaseX, button.ZCBaseY)
                button:SetSize(w, block.height or block.thisY or 16)
                button.Paint = paintLink
                button.DoClick = function() L.Open(link.id, link.page) end
                buttons[#buttons + 1] = button
            end
        end
    end
    row.ZCGoobLinkButtons = buttons
    -- As for the report button: the row needs mouse input before its children can be clicked.
    if buttons[1] then row:SetMouseInputEnabled(true) end
end

local function chatOpen()
    local chat = hg and hg.chat
    return IsValid(chat) and chat:GetActive() and chat.phonePage == "chat" and not IsValid(chat.ZCDirectory)
        and not (ZCChatMedia and IsValid(ZCChatMedia.Picker))
end

-- Only rows that carry links are walked. Buttons are made here rather than in RenderRow, which runs
-- inside the row's PerformLayout; they follow the drop-in animation and take clicks only while the
-- chat page is open, the same rule UpdateRowActions applies to the report button.
hook.Add("Think", "ZCGoobLinks_Rows", function()
    if next(L.Rows) == nil then return end
    local allowed, open, still = L.Allowed(LocalPlayer()), chatOpen(), reducedMotion()
    for row in pairs(L.Rows) do
        if not IsValid(row) then
            L.Rows[row] = nil
        elseif not allowed or not row.ZCGoobLinks then
            clearButtons(row)
            L.Rows[row] = nil
        else
            if row.markup ~= row.ZCGoobLinkMarkup then L.Place(row) end
            local dy = still and 0 or math.floor((row.yAnim or 0) + 0.5)
            local clickable = open and not (ZCChatThreads and isfunction(ZCChatThreads.Visible) and not ZCChatThreads.Visible(row))
            for _, button in ipairs(row.ZCGoobLinkButtons or {}) do
                if IsValid(button) then
                    if button.ZCDy ~= dy then
                        button.ZCDy = dy
                        button:SetPos(button.ZCBaseX, button.ZCBaseY + dy)
                    end
                    if button.ZCClickable ~= clickable then
                        button.ZCClickable = clickable
                        button:SetMouseInputEnabled(clickable)
                    end
                end
            end
        end
    end
end)

-- "goobos_link settings crosshair" does what clicking that link does (binds, testing). Gated like the
-- links themselves: until the owner releases the feature, nobody else gets a new command either.
concommand.Add("goobos_link", function(_, _, args)
    if not L.Allowed(LocalPlayer()) then return end
    local app = L.ByWord[string.lower(args[1] or "")]
    if not app then
        print("goobos_link <app> [page]: unknown app")
        return
    end
    local page
    if args[2] then
        local rest = chatEscape(string.lower(table.concat(args, " ", 2)))
        local found, last = matchPage(L.PageList(app.id) or {}, rest, 1)
        if found and last == #rest then page = found end
    end
    L.Open(app.id, page)
end)

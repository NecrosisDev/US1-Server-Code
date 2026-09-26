if not CLIENT then return end
local A, T = ZCGoobApps, ZCGoobApps.Theme
-- kit.lua is a hard dependency for this file; fetched once at file scope (see shop.lua's own
-- note). buildWardrobe() still checks `K` and shows a message instead of a blank app if missing.
local K = A.Kit

function A.SafeName(name)
    return isstring(name) and #name >= 1 and #name <= 64 and name:match("^[%w _%-]+$") ~= nil
end

function A.ModelData(draft)
    local models = hg.Appearance.PlayerModels or {}
    for sex = 1, 2 do
        if models[sex] and models[sex][draft.AModel] then return models[sex][draft.AModel], sex end
    end
end

function A.CleanDraft(value)
    if not istable(value) or not A.ModelData(value) or not isstring(value.AName) then return end
    local copy = table.Copy(value)
    copy.AClothes = istable(copy.AClothes) and copy.AClothes or {}
    copy.AAttachments = istable(copy.AAttachments) and copy.AAttachments or {}
    copy.ABodygroups = istable(copy.ABodygroups) and copy.ABodygroups or {}
    local color = istable(copy.AColor) and copy.AColor or T.accent
    copy.AColor = Color(math.Clamp(tonumber(color.r) or 105, 0, 255), math.Clamp(tonumber(color.g) or 201, 0, 255), math.Clamp(tonumber(color.b) or 255, 0, 255))
    return copy
end

function A.CanWear(id, paid)
    if not paid then return true end
    local p = LocalPlayer()
    if not IsValid(p) then return false end
    return hg.Appearance.GetAccessToAll and hg.Appearance.GetAccessToAll(p) or p.PS_HasItem and p:PS_HasItem(id) or false
end

function A.ShuffleOutfit(draft)
    local ap = hg.Appearance
    local model, sex = A.ModelData(draft)
    if not model then return false end
    local function pick(source, allowed)
        local keys = {}
        for id, data in pairs(source or {}) do
            if not allowed or allowed(id, data) then keys[#keys + 1] = id end
        end
        return #keys > 0 and keys[math.random(#keys)] or nil
    end
    draft.AClothes = draft.AClothes or {}
    for slot in pairs(model.submatSlots or {}) do draft.AClothes[slot] = pick(ap.Clothes[sex]) or "normal" end
    draft.ABodygroups = {}
    for group, bySex in pairs(ap.Bodygroups or {}) do
        draft.ABodygroups[group] = pick(bySex[sex], function(_, variant) return A.CanWear(variant.ID, variant[2]) end)
    end
    local faces = (ap.FacemapsSlots or {})[(ap.FacemapsModels or {})[model.mdl]]
    draft.AFacemap = pick(faces) or "Default"
    draft.AAttachments = {}
    local placements = {}
    for id, data in pairs(hg.Accessories or {}) do
        if data.placement and not data.disallowinappearance and A.CanWear(id, data.bPointShop) then
            placements[data.placement] = placements[data.placement] or {}
            placements[data.placement][id] = data
        end
    end
    for _, choices in SortedPairs(placements) do
        if #draft.AAttachments < 3 then draft.AAttachments[#draft.AAttachments + 1] = pick(choices) end
    end
    return true
end

function A.SetAccessory(draft, id)
    local info = hg.Accessories[id]
    if not info or info.disallowinappearance or not A.CanWear(id, info.bPointShop) then return false end
    local nextList = {}
    for _, existing in ipairs(draft.AAttachments or {}) do
        local old = hg.Accessories[existing]
        if existing ~= id and old and old.placement ~= info.placement then nextList[#nextList + 1] = existing end
    end

    if #nextList >= 3 then return false end
    nextList[#nextList + 1] = id
    draft.AAttachments = nextList
    return true
end

function A.SaveAppearance(draft)
    local ap = hg.Appearance
    local name = ap.SelectedAppearance:GetString()
    if not A.SafeName(name) then return false, "The selected appearance filename is invalid." end
    local copy = A.CleanDraft(draft)
    if not copy then return false, "Check your character name and appearance choices." end
    copy = ap.NormalizeAppearanceTable and ap.NormalizeAppearanceTable(copy) or copy
    local valid, result = pcall(ap.AppearanceValidater, copy)
    if not valid or not result then return false, "Check your character name and appearance choices." end
    ap.CreateAppearanceFile(name, copy)
    net.Start("OnlyGet_Appearance")
    net.WriteTable(copy)
    net.SendToServer()
    return true, "Saved on this computer and sent to the server."
end


local function clearAccessories(entity)
    for _, model in pairs(entity.modelAccess or {}) do
        if IsValid(model) then model:Remove() end
    end

    entity.modelAccess = {}
end

function A.ApplyPreview(panel, draft)
    local ap = hg.Appearance
    local model, sex = A.ModelData(draft)
    if not model then return end
    if not IsValid(panel.Entity) or panel.Entity:GetModel() ~= model.mdl then
        if IsValid(panel.Entity) then clearAccessories(panel.Entity) end
        panel:SetModel(model.mdl)
    end

    local ent = panel.Entity
    if not IsValid(ent) then return end
    local col = draft.AColor or T.accent
    -- Worn-accessory models are kept between re-skins (hover previews re-apply the draft many times);
    -- only a colour change rebuilds them, because tinted accessories take the colour when created.
    local colorKey = col.r .. "," .. col.g .. "," .. col.b
    if ent.GoobColorKey ~= colorKey then
        clearAccessories(ent)
        ent.GoobColorKey = colorKey
    end
    ent:SetSubMaterial()
    ent:SetSkin(0)
    ent.GetPlayerColor = function() return Vector(col.r / 255, col.g / 255, col.b / 255) end
    ent:SetNWVector("PlayerColor", ent:GetPlayerColor())
    local mats = ent:GetMaterials()
    for slot, path in pairs(model.submatSlots or {}) do
        for index, mat in ipairs(mats) do
            if mat == path then ent:SetSubMaterial(index - 1, (ap.Clothes[sex] or {})[(draft.AClothes or {})[slot]] or (ap.Clothes[sex] or {}).normal) end
        end
    end

    for index, mat in ipairs(mats) do
        local faces = (ap.FacemapsSlots or {})[mat]
        if faces and faces[draft.AFacemap] then ent:SetSubMaterial(index - 1, faces[draft.AFacemap]) end
    end

    for _, group in ipairs(ent:GetBodyGroups()) do
        ent:SetBodygroup(group.id, 0)
        local definitions = (ap.Bodygroups or {})[group.name]
        local variant = definitions and definitions[sex] and definitions[sex][(draft.ABodygroups or {})[group.name]]
        if variant then
            for index, submodel in pairs(group.submodels or {}) do
                if submodel == variant[1] then ent:SetBodygroup(group.id, index) end
            end
        end
    end

    -- Same pose the ZCity appearance editor uses; models without it fall back to their idle.
    local seq = ent:LookupSequence("idle_suitcase")
    if not seq or seq < 0 then seq = ent:LookupSequence("idle_all_01") end
    ent:SetSequence((seq and seq >= 0) and seq or 0)
    -- ApplyPreviewScale never existed anywhere in this addon (no definition, no other caller), and
    -- the height/body sliders that would drive it are themselves dead (guarded on ap.NormalizeHeight,
    -- which also does not exist) -- dropped rather than left as a silent no-op that looks like a
    -- working scale hook.
end

-- Accent presets (mockup 04's swatch row: red, blue, green, gold, grey). The last swatch opens the
-- full colour mixer.
local ACCENT_PRESETS = {Color(192, 0, 0), Color(70, 130, 220), Color(119, 218, 181), Color(247, 199, 115), Color(150, 150, 150), Color(235, 235, 235)}
local ACCESSORY_FILTERS = {"All", "Head", "Face", "Body"}
local FILTER_PLACEMENTS = {Head = {head = true, ears = true}, Face = {face = true}, Body = {torso = true, spine = true}}
local CLOTHING_REGION = {main = "torso", pants = "legs", boots = "boots"}

local function accessoryIcon(id)
    local data = hg.Accessories and hg.Accessories[id]
    if not data or not A.AccessoryIconSpec then return nil end
    return {key = "item:" .. tostring(id), spec = A.AccessoryIconSpec(data), glyph = "hanger"}
end

local function portraitIcon(mdl)
    if not isstring(mdl) then return nil end
    return {key = "pm:" .. mdl, spec = {mdl = mdl, portrait = true}, glyph = "hanger"}
end

local function itemIcon(id)
    local item = id and hg.PointShop and hg.PointShop.Items and hg.PointShop.Items[id]
    if not item or not A.ItemIconSpec then return nil end
    return {key = "item:" .. tostring(id), spec = A.ItemIconSpec(item), glyph = "hanger"}
end

-- Row styled "Jacket   Leather · brown ›", with an optional baked icon on the left.
local function wardrobeRow(parent, label, value, onClick, icon)
    local row = vgui.Create("DButton", parent)
    row:Dock(TOP)
    row:DockMargin(0, 0, 0, 6)
    row:SetTall(40)
    row:SetText("")
    row:SetCursor("hand")
    row.DoClick = onClick
    row.GoobLabel = label
    row.Paint = function(s, w, h)
        local hover = K.Hover(s)
        K.Card(0, 0, w, h, T.cardGlass)
        if hover > 0.01 then draw.RoundedBox(4, 0, 0, w, h, K.Alpha(T.white, 14 * hover)) end
        local x = 12
        if icon and A.Icons then
            A.Icons.Draw(icon.key, icon.spec, 5, 5, h - 10, icon.glyph)
            x = h + 2
        end
        K.Text(K.Fit(label, K.Font(13, 500), 70), 13, 500, x, h / 2, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        K.Text(K.Fit(tostring(value), K.Font(13, 500), w - x - 96), 13, 500, x + 70, h / 2, T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        K.Text("›", 16, 600, w - 14, h / 2, T.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
    return row
end

-- Full-width action button (Shuffle outfit, Add accessory, Save/Load/Delete a look, ...).
-- opts = {glyph=, primary=bool, danger=bool}.
-- UI cohesion (2026-09-26): the shared K.Button; this wrapper keeps the file's call sites.
local function kitButton(parent, text, onClick, opts)
    opts = opts or {}
    local b = K.Button(parent, {label = text, click = onClick, glyph = opts.glyph, align = TEXT_ALIGN_LEFT,
        kind = opts.danger and "danger" or (opts.primary and "primary" or "secondary")})
    b:DockMargin(0, 0, 0, 6)
    return b
end

-- Section caption: 12px/600 caps muted (STYLE, tokens.md).
local function caption(parent, text)
    local c = K.Panel(parent)
    c:Dock(TOP)
    c:SetTall(22)
    c:DockMargin(0, 10, 0, 4)
    local upper = string.upper(text)
    c.Paint = function(_, _, h) K.Text(upper, 12, 600, 0, h / 2, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
    return c
end

-- Label + K.Toggle row for the on/off pickers (scale-head, random-on-spawn).
local function wardrobeToggleRow(parent, label, get, set)
    local row = K.Panel(parent)
    row:Dock(TOP)
    row:DockMargin(0, 0, 0, 6)
    row:SetTall(40)
    row.Paint = function(_, w, h)
        K.Card(0, 0, w, h, T.cardGlass)
        K.Text(K.Fit(label, K.Font(13, 500), w - 60), 13, 500, 12, h / 2, T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local toggle = K.Toggle(row, get(), set)
    row.Think = function(s)
        toggle:SetPos(s:GetWide() - 46, 9)
        toggle:SetValue(get())
    end
    return row
end

-- Picker tile (grid mode) and row (list mode). row = {id, name, locked, icon = {key, spec, glyph}}.
local function paintPickerTile(s, w, h)
    local row, on = s.Row, s.Selected
    local hover = K.Hover(s)
    K.Card(0, 0, w, h, T.cardGlass, on and T.accent or nil)
    if hover > 0.01 then draw.RoundedBox(4, 1, 1, w - 2, h - 2, K.Alpha(T.main, 40 * hover)) end
    local size = math.floor(math.min(w - 12, h - 30))
    local x = math.floor((w - size) / 2)
    if row.icon and A.Icons then
        A.Icons.Draw(row.icon.key, row.icon.spec, x, 6, size, row.icon.glyph)
    else
        draw.RoundedBox(4, x, 6, size, size, T.hover)
        K.Glyph(row.glyph or "empty", w / 2, 6 + size / 2, math.floor(size * 0.4), T.muted)
    end
    if row.locked then
        draw.RoundedBox(8, w - 42, 9, 34, 16, K.Alpha(T.ink, 220))
        K.Text("Shop", 10, 700, w - 25, 17, T.gold, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    if on then K.Glyph("check", 17, 17, 14, T.accent) end
    K.Text(K.Fit(row.name, K.Font(12, 500), w - 8), 12, 500, w / 2, h - 12, row.locked and T.muted or T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

local function paintPickerRow(s, w, h)
    local row, on = s.Row, s.Selected
    local hover = K.Hover(s)
    K.Card(0, 0, w, h, T.cardGlass, on and T.accent or nil)
    if hover > 0.01 then draw.RoundedBox(4, 1, 1, w - 2, h - 2, K.Alpha(T.white, 14 * hover)) end
    local x = 12
    if row.icon and A.Icons then
        A.Icons.Draw(row.icon.key, row.icon.spec, 4, 4, h - 8, row.icon.glyph)
        x = h + 4
    end
    local right = 14
    if row.locked then
        draw.RoundedBox(8, w - 46, h / 2 - 8, 36, 16, K.Alpha(T.ink, 220))
        K.Text("Shop", 10, 700, w - 28, h / 2, T.gold, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        right = 54
    elseif on then
        K.Glyph("check", w - 22, h / 2, 14, T.accent)
        right = 34
    end
    K.Text(K.Fit(row.name, K.Font(14, 500), w - x - right), 14, 500, x, h / 2, row.locked and T.muted or T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

local function buildWardrobe(root)
    if not K then
        A.Status(root, "GoobOS kit failed to load; try reopening the phone.")
        return
    end

    local ap = hg and hg.Appearance
    if not ap or not ap.PlayerModels or not ap.LoadAppearanceFile then
        A.Status(root, "The wardrobe is not available yet.")
        return
    end

    A.RequestShop()
    local state = A.State.wardrobe or {}
    A.State.wardrobe = state
    state.tab = state.tab or 1
    if not state.draft then
        local ok, saved = pcall(ap.LoadAppearanceFile, ap.SelectedAppearance:GetString())
        state.draft = ok and A.CleanDraft(saved) or nil
        state.draft = state.draft or A.CleanDraft(ap.SkeletonAppearanceTable)
    end

    if not state.draft then
        A.Status(root, "No compatible appearance models are available.", T.red)
        return
    end

    local draft = state.draft
    -- Forward declared: bottomBar (below) needs `changed`/`rebuild` before either is assigned,
    -- and openPicker/rebuild are mutually referential.
    local changed, rebuild

    -- Status line: the single place every picker action reports through (notice:SetText).
    local noticeRow = K.Panel(root)
    noticeRow:Dock(TOP)
    noticeRow:SetTall(20)
    noticeRow:DockMargin(0, 0, 0, 8)
    local notice = vgui.Create("DLabel", noticeRow)
    notice:SetFont(K.Font(13, 500))
    notice:SetTextColor(T.muted)
    notice:SetText(state.dirty and "Unsaved look · kept while you browse" or "Your look, your city.")
    notice:SetWrap(false)
    notice.Think = function(s)
        s:SetPos(0, 0)
        s:SetSize(math.max(1, noticeRow:GetWide() - 90), noticeRow:GetTall())
    end
    local dirtyChip = K.Panel(noticeRow)
    dirtyChip.Think = function(s)
        s:SetPos(math.max(0, noticeRow:GetWide() - 84), 0)
        s:SetSize(84, noticeRow:GetTall())
    end
    dirtyChip.Paint = function(_, w, h)
        if not state.dirty then return end
        draw.RoundedBox(4, 0, 2, w, h - 4, T.card)
        K.Dot(8, h / 2 - 3, 6, T.gold)
        K.Text("Unsaved", 11, 600, 20, h / 2, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    -- Sticky bottom bar: Discard (secondary) / Save & apply (primary).
    local bottomBar = K.Panel(root)
    bottomBar:Dock(BOTTOM)
    bottomBar:SetTall(44)
    bottomBar:DockMargin(0, 10, 0, 0)

    local discard = vgui.Create("DButton", bottomBar)
    discard:SetText("")
    discard:SetCursor("hand")
    discard.DoClick = function()
        if IsValid(root.GoobConfirmShade) then root.GoobConfirmShade:Remove() end
        local _, shade = K.Modal(root, "Discard this draft?", "Your saved appearance will be restored.", {
            {"Cancel", nil},
            {"Discard", function()
                local ok, saved = pcall(ap.LoadAppearanceFile, ap.SelectedAppearance:GetString())
                local clean = ok and A.CleanDraft(saved)
                if clean then
                    state.draft = clean
                    changed()
                    state.dirty = false
                    notice:SetText("Saved appearance restored.")
                    rebuild()
                else
                    notice:SetText("Saved appearance could not be loaded; your draft is intact.")
                end
            end, danger = true}
        })
        root.GoobConfirmShade = shade
    end
    discard.Paint = function(s, w, h)
        local hover = K.Hover(s)
        draw.RoundedBox(4, 0, 0, w, h, T.card)
        if hover > 0.01 then draw.RoundedBox(4, 0, 0, w, h, K.Alpha(T.white, 14 * hover)) end
        K.Text("Discard", 15, 600, w / 2, h / 2, T.red, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    local save = vgui.Create("DButton", bottomBar)
    save:SetText("")
    save:SetCursor("hand")
    save.DoClick = function()
        local ok, message = A.SaveAppearance(state.draft)
        notice:SetText(message)
        if ok then state.dirty = false end
    end
    save.Paint = function(s, w, h)
        local hover = K.Hover(s)
        draw.RoundedBox(4, 0, 0, w, h, T.green)
        if hover > 0.01 then draw.RoundedBox(4, 0, 0, w, h, K.Alpha(T.white, 18 * hover)) end
        K.Text("Save & apply", 15, 700, w / 2, h / 2, T.bg, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    bottomBar.PerformLayout = function(_, w, h)
        local gap = 8
        local each = (w - gap) / 2
        discard:SetPos(0, 0)
        discard:SetSize(each, h)
        save:SetPos(each + gap, 0)
        save:SetSize(each, h)
    end

    -- Two columns: left = live 3D preview (preview.lua), right = tabs + rows. Sized from Think
    -- (nested Dock(FILL) invalidation does not always cascade -- owner report 2026-09-23).
    local columns = K.Panel(root)
    columns:Dock(FILL)

    local preview = A.CreatePreviewWidget(columns)
    local right = K.Panel(columns)
    right:Dock(NODOCK)

    local tabs = K.Tabs(right, {"Identity", "Clothing", "Body", "Accessories", "Looks"}, state.tab, function(index)
        state.tab = index
        rebuild()
    end)
    tabs:Dock(TOP)

    local rowsScroll = A.Scroll(right)
    rowsScroll:DockMargin(0, 6, 0, 0)
    local content = K.Panel(rowsScroll)
    content:Dock(TOP)
    content.PerformLayout = function(s) s:SizeToChildren(false, true) end

    local columnsLayout = {}
    local function layoutColumns()
        local w, h = columns:GetWide(), columns:GetTall()
        if w <= 0 or h <= 0 then return end
        if w == columnsLayout.w and h == columnsLayout.h then return end
        columnsLayout.w, columnsLayout.h = w, h
        if w < A.PREVIEW_STACK_BREAKPOINT then
            local previewH = math.min(190, math.floor(h * 0.42))
            preview:SetPos(0, 0)
            preview:SetSize(w, previewH)
            right:SetPos(0, previewH + 8)
            right:SetSize(w, math.max(1, h - previewH - 8))
        else
            local previewW = math.floor(w * 0.42)
            preview:SetPos(0, 0)
            preview:SetSize(previewW, h)
            right:SetPos(previewW + 8, 0)
            right:SetSize(math.max(1, w - previewW - 8), h)
        end
    end

    columns.Think = function()
        local ok, err = pcall(layoutColumns)
        if not ok then ErrorNoHalt("[GoobOS] wardrobe layout failed: " .. tostring(err) .. "\n") end
    end

    changed = function()
        draft = state.draft
        state.dirty = true
        notice:SetText("Unsaved look · kept while you browse")
        preview:SetBase(draft)
    end

    preview:SetBase(draft)

    -- Picker: covers the right column only, so the 3D preview stays visible while choosing (the old
    -- full-app sheet hid it). Hovering a choice previews it on the model (the original ZCity
    -- appearance editor's hover-to-try) and the camera zooms to the part being picked.
    -- spec = {title, rows, selected, onSelect(id) -> false keeps it open, tryOn(id) (hover), region,
    --         grid = bool (icon tiles), filters = {labels}, filter(row, label) -> bool}
    local function closePicker()
        if IsValid(root.selector) then root.selector:Remove() end
        root.selector = nil
        preview:SetBase(state.draft)
        preview:Focus("all")
        preview:SetChip(nil)
    end

    local function openPicker(spec)
        if IsValid(root.selector) then root.selector:Remove() end
        local picker = K.Panel(right)
        root.selector = picker
        picker:SetZPos(900)
        picker:SetMouseInputEnabled(true)
        picker.Paint = function(_, w, h) draw.RoundedBox(4, 0, 0, w, h, K.Alpha(T.bg, 245)) end
        picker.Think = function(s)
            local pw, ph = right:GetWide(), right:GetTall()
            if s:GetWide() ~= pw or s:GetTall() ~= ph then
                s:SetPos(0, 0)
                s:SetSize(pw, ph)
            end
        end
        picker:Think()
        preview:Focus(spec.region or "all")

        local back = vgui.Create("DButton", picker)
        back:Dock(TOP)
        back:SetTall(32)
        back:SetText("")
        back:SetCursor("hand")
        back.DoClick = closePicker
        back.Paint = function(s, w, h)
            local hover = K.Hover(s)
            if hover > 0.01 then draw.RoundedBox(4, 0, 0, w, h, K.Alpha(T.white, 10 * hover)) end
            K.Text(K.Fit("‹  " .. spec.title, K.Font(15, 600), w - 8), 15, 600, 4, h / 2, T.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        if spec.custom then return picker end

        local filterLabel = spec.filters and spec.filters[1]
        local fillList
        if spec.filters then
            local seg = K.Segmented(picker, spec.filters, 1, function(_, label)
                filterLabel = label
                fillList()
            end)
            seg:Dock(TOP)
            seg:DockMargin(0, 2, 0, 6)
        end

        local query = ""
        local entry = A.Entry(picker, "Search " .. string.lower(spec.title), "", function(q)
            query = q
            fillList()
        end)
        entry:SetFont(K.Font(14, 500))

        -- List mode parents rows straight to the scroll panel (A.Sheet's proven pattern); grid mode
        -- lays tiles out in one panel whose height follows the tile count.
        local scroll = A.Scroll(picker)
        local list = scroll
        if spec.grid then
            list = K.Panel(scroll)
            list:Dock(TOP)
            list.Think = function(s)
                if s.Empty then return end
                local children = s:GetChildren()
                local signature = s:GetWide() .. ":" .. #children
                if signature == s.GoobLayout then return end
                s.GoobLayout = signature
                local height = K.GridLayout(children, s:GetWide(), 84, 108, 6, 6)
                if s:GetTall() ~= height then
                    s:SetTall(math.max(1, height))
                    scroll:InvalidateLayout()
                end
            end
        end
        local hoverId, shownId, lastSeen = nil, nil, 0

        picker.Think = function(s)
            local pw, ph = right:GetWide(), right:GetTall()
            if s:GetWide() ~= pw or s:GetTall() ~= ph then
                s:SetPos(0, 0)
                s:SetSize(pw, ph)
            end
            -- Hover preview with a short hold so crossing the gap between two choices does not flicker.
            local want = hoverId
            if want ~= nil then lastSeen = RealTime() elseif RealTime() - lastSeen < 0.3 then want = shownId end
            if want ~= shownId and spec.tryOn then
                shownId = want
                if want == nil then
                    preview:SetBase(state.draft)
                    preview:SetChip(nil)
                    preview:Focus(spec.region or "all")
                else
                    local label = spec.tryOn(want)
                    preview:SetChip(label and ("Fitting: " .. label) or nil)
                end
            end
        end

        fillList = function()
            list:Clear()
            hoverId = nil
            local count = 0
            for _, row in ipairs(spec.rows) do
                if A.Matches(row.name, query) and (not spec.filter or spec.filter(row, filterLabel)) then
                    count = count + 1
                    local b = vgui.Create("DButton", list)
                    b:SetText("")
                    b:SetCursor("hand")
                    b:SetTooltip(row.locked and (row.name .. " · buy it in the Shop") or row.name)
                    local wornSet = istable(spec.selected) and spec.selected or nil
                    b.Row, b.Selected = row, wornSet and wornSet[row.id] == true or row.id == spec.selected
                    if spec.grid then
                        b:SetSize(84, 108)
                        b.Paint = paintPickerTile
                    else
                        b:Dock(TOP)
                        b:DockMargin(0, 0, 0, 5)
                        b:SetTall(row.icon and 42 or 36)
                        b.Paint = paintPickerRow
                    end
                    b.OnCursorEntered = function() hoverId = row.id end
                    b.OnCursorExited = function() if hoverId == row.id then hoverId = nil end end
                    b.DoClick = function()
                        if row.locked then
                            notice:SetText(row.name .. " is in the Shop. Buy it there to wear it.")
                            return
                        end
                        if spec.onSelect(row.id) ~= false then
                            closePicker()
                            changed()
                            rebuild()
                        end
                    end
                end
            end
            if spec.grid then list.GoobLayout, list.Empty = nil, count == 0 end
            if count == 0 then
                A.Status(list, "No matching choices.")
                if spec.grid then list:SetTall(40) end
            end
        end
        fillList()
        return picker
    end

    -- Temporary draft for hover previews: a copy with one field changed, never state.draft itself.
    local function tryDraft(mutate)
        local temp = table.Copy(state.draft)
        mutate(temp)
        preview:SetBase(temp)
    end

    local function choices(source, paid, iconFor)
        local result = {}
        for _, row in ipairs(A.SortedRows(source, function(_, k) return k end)) do
            result[#result + 1] = {
                id = row.id,
                name = tostring(row.id),
                locked = paid and not A.CanWear(row.data.ID, row.data[2]) or false,
                icon = iconFor and iconFor(row.id, row.data) or nil
            }
        end
        return result
    end

    local function modelPicker()
        local rows = {}
        for _, models in pairs(ap.PlayerModels) do
            for name, data in pairs(models) do
                rows[#rows + 1] = {
                    id = name,
                    name = name,
                    icon = portraitIcon(data.mdl)
                }
            end
        end
        table.sort(rows, function(a, b) return a.name < b.name end)
        openPicker({
            title = "Models",
            rows = rows,
            selected = draft.AModel,
            grid = true,
            region = "head",
            onSelect = function(id)
                draft.AModel = id
                draft.AFacemap = "Default"
                draft.ABodygroups = {}
            end
        })
    end

    local function accessoryPicker()
        local worn = {}
        for _, id in ipairs(draft.AAttachments or {}) do worn[id] = true end
        local rows = {}
        for _, row in ipairs(A.SortedRows(hg.Accessories, function(v, k) return v.name or k end)) do
            local v = row.data
            if row.id ~= "none" and not v.disallowinappearance then
                rows[#rows + 1] = {
                    id = row.id,
                    name = v.name or row.id,
                    placement = v.placement,
                    locked = not A.CanWear(row.id, v.bPointShop),
                    icon = accessoryIcon(row.id)
                }
            end
        end
        openPicker({
            title = "Accessories",
            rows = rows,
            -- A worn set (not a single selected id): up to three accessories can be worn at once, and
            -- each shows the check mark seen elsewhere ("Owned/Equipped").
            selected = worn,
            grid = true,
            filters = ACCESSORY_FILTERS,
            filter = function(row, label)
                local set = FILTER_PLACEMENTS[label]
                return not set or set[row.placement] == true
            end,
            tryOn = function(id)
                local info = hg.Accessories[id]
                preview:SetBase(state.draft)
                preview:Fit({ID = id})
                preview:Focus(A.PreviewRegionFor(info and info.placement))
                return info and (info.name or id) or tostring(id)
            end,
            onSelect = function(id)
                -- Tapping a worn item takes it off (owner audit: pickers gave no way to remove one
                -- except the "Worn" list on tab 4).
                if worn[id] then
                    table.RemoveByValue(draft.AAttachments, id)
                    notice:SetText((hg.Accessories[id].name or id) .. " removed.")
                    return
                end

                local info = hg.Accessories[id]
                local swappedName
                for _, existing in ipairs(draft.AAttachments or {}) do
                    local old = hg.Accessories[existing]
                    if old and info and old.placement == info.placement then swappedName = old.name or existing end
                end

                if not A.SetAccessory(draft, id) then
                    notice:SetText("Remove an accessory first; three slots are available.")
                    return false
                end

                -- Same-slot swap: tell the player what just happened instead of silently replacing it.
                if swappedName then notice:SetText("Swapped " .. swappedName .. " for " .. (info.name or id) .. ".") end
            end
        })
    end

    -- Accent: preset swatches (mockup 04) plus a "+" swatch that opens the full mixer.
    local function accentRow(parent)
        local row = K.Panel(parent)
        row:Dock(TOP)
        row:DockMargin(0, 0, 0, 6)
        row:SetTall(40)
        row:SetMouseInputEnabled(true)
        row:SetCursor("hand")
        local count = #ACCENT_PRESETS + 1
        local function swatchX(i) return 78 + (i - 1) * 26 end
        row.Paint = function(s, w, h)
            K.Card(0, 0, w, h, T.cardGlass)
            K.Text("Accent", 13, 500, 12, h / 2, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            local col = draft.AColor or T.accent
            local mx = s:CursorPos()
            for i = 1, count do
                local x = swatchX(i)
                if x + 20 > w - 6 then break end
                local preset = ACCENT_PRESETS[i]
                local on = preset and preset.r == col.r and preset.g == col.g and preset.b == col.b
                if on or (s:IsHovered() and mx >= x and mx < x + 20) then draw.RoundedBox(11, x - 2, h / 2 - 12, 24, 24, on and T.white or T.muted) end
                if preset then
                    draw.RoundedBox(10, x, h / 2 - 10, 20, 20, preset)
                else
                    draw.RoundedBox(10, x, h / 2 - 10, 20, 20, col)
                    K.Text("+", 14, 700, x + 10, h / 2, T.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
            end
        end
        row.OnMousePressed = function(s, code)
            if code ~= MOUSE_LEFT then return end
            local mx = s:CursorPos()
            for i = 1, count do
                local x = swatchX(i)
                if mx >= x - 3 and mx < x + 23 then
                    local preset = ACCENT_PRESETS[i]
                    if preset then
                        draft.AColor = Color(preset.r, preset.g, preset.b)
                        changed()
                    else
                        local picker = openPicker({title = "Accent colour", custom = true, region = "torso"})
                        local mixer = vgui.Create("DColorMixer", picker)
                        mixer:Dock(TOP)
                        mixer:SetTall(170)
                        mixer:DockMargin(0, 4, 0, 0)
                        mixer:SetPalette(false)
                        mixer:SetAlphaBar(false)
                        mixer:SetWangs(true)
                        mixer:SetColor(draft.AColor or T.accent)
                        mixer.ValueChanged = function(_, c)
                            draft.AColor = Color(c.r, c.g, c.b)
                            changed()
                        end
                    end
                    return
                end
            end
        end
        return row
    end

    rebuild = function()
        content:Clear()
        draft = state.draft
        local md, sex = A.ModelData(draft)
        if not md then
            A.Status(content, "This model is no longer available.", T.red)
            return
        end

        local tab = state.tab or 1

        if tab == 1 then
            caption(content, "Identity")
            A.Entry(content, "Character name", draft.AName, function(v)
                state.draft.AName = v
                state.dirty = true
                notice:SetText("Unsaved name")
            end)
            wardrobeRow(content, "Model", draft.AModel, modelPicker, portraitIcon(md.mdl))

        elseif tab == 2 then
            caption(content, "Clothing")
            kitButton(content, "Shuffle outfit", function()
                if A.ShuffleOutfit(draft) then changed(); rebuild() end
            end, {glyph = "dice"})

            for _, part in ipairs({"main", "pants", "boots"}) do
                if md.submatSlots and md.submatSlots[part] then
                    local title = ({main = "Jacket", pants = "Pants", boots = "Boots"})[part]
                    wardrobeRow(content, title, tostring((draft.AClothes or {})[part] or "normal"), function()
                        openPicker({
                            title = title,
                            rows = choices(ap.Clothes[sex]),
                            selected = (draft.AClothes or {})[part] or "normal",
                            region = CLOTHING_REGION[part],
                            tryOn = function(id)
                                tryDraft(function(temp)
                                    temp.AClothes = temp.AClothes or {}
                                    temp.AClothes[part] = id
                                end)
                                return tostring(id)
                            end,
                            onSelect = function(id)
                                draft.AClothes = draft.AClothes or {}
                                draft.AClothes[part] = id
                            end
                        })
                    end)
                end
            end

            local faces = (ap.FacemapsSlots or {})[(ap.FacemapsModels or {})[md.mdl]] or {}
            wardrobeRow(content, "Face", tostring(draft.AFacemap or "Default"), function()
                openPicker({
                    title = "Faces",
                    rows = choices(faces),
                    selected = draft.AFacemap or "Default",
                    region = "face",
                    tryOn = function(id)
                        tryDraft(function(temp) temp.AFacemap = id end)
                        return tostring(id)
                    end,
                    onSelect = function(id) draft.AFacemap = id end
                })
            end)

            -- Spec-uncovered: the mockup's notes put the accent swatches here (no tab is named for them).
            caption(content, "Accent colour")
            accentRow(content)

        elseif tab == 3 then
            caption(content, "Bodygroups")
            for group, bySex in SortedPairs(ap.Bodygroups or {}) do
                if bySex[sex] then
                    local current = (draft.ABodygroups or {})[group]
                    local variant = current and bySex[sex][current]
                    wardrobeRow(content, string.NiceName(group), tostring(current or "Default"), function()
                        local rows = choices(bySex[sex], true, function(_, data) return itemIcon(data.ID) end)
                        -- HANDS ships a real "None" variant meaning the same thing as the synthetic
                        -- "Default" row inserted below; showing both was a confusing duplicate.
                        for i = #rows, 1, -1 do if rows[i].id == "None" then table.remove(rows, i) end end
                        table.insert(rows, 1, {
                            id = "",
                            name = "Default"
                        })

                        openPicker({
                            title = string.NiceName(group),
                            rows = rows,
                            selected = current or "",
                            region = string.upper(group) == "HANDS" and "hands" or "all",
                            tryOn = function(id)
                                tryDraft(function(temp)
                                    temp.ABodygroups = temp.ABodygroups or {}
                                    temp.ABodygroups[group] = id ~= "" and id or nil
                                end)
                                return id ~= "" and tostring(id) or "Default"
                            end,
                            onSelect = function(id)
                                draft.ABodygroups = draft.ABodygroups or {}
                                draft.ABodygroups[group] = id ~= "" and id or nil
                            end
                        })
                    end, variant and itemIcon(variant.ID) or nil)
                end
            end

            if ap.NormalizeHeight then
                caption(content, "Proportions")
                if ap.Sliders and not ap.Sliders.IsEnabled() then A.Status(content, "Scaling is currently disabled by the server.") end
                for _, spec in ipairs({{"AHeight", "Height"}, {"ABodySize", "Body size"}}) do
                    local key, title = spec[1], spec[2]
                    A.Label(content, title .. " (%)", K.Font(13, 500), T.muted)
                    local slider = vgui.Create("DNumSlider", content)
                    slider:Dock(TOP)
                    slider:SetTall(36)
                    slider:SetText("")
                    slider:SetMin(ap.HeightMin)
                    slider:SetMax(ap.HeightMax)
                    slider:SetDecimals(0)
                    slider:SetValue(ap.NormalizeHeight(draft[key]))
                    slider.OnValueChanged = function(_, value)
                        draft[key] = ap.NormalizeHeight(value)
                        changed()
                    end

                    wardrobeToggleRow(content, "Scale head with " .. string.lower(title), function() return draft[key .. "ResizeHead"] end, function(v)
                        draft[key .. "ResizeHead"] = v
                        changed()
                    end)
                end
            end

        elseif tab == 4 then
            caption(content, "Worn · " .. #(draft.AAttachments or {}) .. " of 3")
            for _, id in ipairs(draft.AAttachments or {}) do
                wardrobeRow(content, "Remove", tostring((hg.Accessories[id] or {}).name or id), function()
                    table.RemoveByValue(draft.AAttachments, id)
                    changed()
                    rebuild()
                end, accessoryIcon(id))
            end

            kitButton(content, "Add accessory", accessoryPicker, {glyph = "hanger", primary = true})

        elseif tab == 5 then
            caption(content, "Saved looks")
            local presetName = A.Entry(content, "Name this look", "", nil)
            if ap.SavePreset and ap.GetPresetList and ap.LoadPreset then
                kitButton(content, "Save as a look", function()
                    local name = string.Trim(presetName:GetValue())
                    if not A.SafeName(name) then
                        notice:SetText("Use 1–64 letters, numbers, spaces, dashes or underscores.")
                        return
                    end

                    local function savePreset()
                        ap.SavePreset(name, table.Copy(draft))
                        notice:SetText("Look saved · " .. name)
                    end

                    if table.HasValue(ap.GetPresetList(), name) then
                        if IsValid(root.GoobConfirmShade) then root.GoobConfirmShade:Remove() end
                        local _, shade = K.Modal(root, "Replace saved look?", name, {
                            {"Cancel", nil},
                            {"Replace", savePreset, primary = true}
                        })
                        root.GoobConfirmShade = shade
                    else
                        savePreset()
                    end
                end, {primary = true})

                local function presetRows()
                    local rows = {}
                    for _, name in ipairs(ap.GetPresetList()) do
                        rows[#rows + 1] = {
                            id = name,
                            name = name
                        }
                    end
                    return rows
                end

                kitButton(content, "Load a saved look", function()
                    openPicker({
                        title = "Saved looks",
                        rows = presetRows(),
                        tryOn = function(name)
                            local clean = A.CleanDraft(ap.LoadPreset(name))
                            if clean then preview:SetBase(clean) end
                            return name
                        end,
                        onSelect = function(name)
                            local clean = A.CleanDraft(ap.LoadPreset(name))
                            if not clean then
                                notice:SetText("That saved look is not compatible with the current wardrobe.")
                                return false
                            end

                            state.draft = clean
                        end
                    })
                end)

                if ap.DeletePreset then
                    kitButton(content, "Delete a saved look", function()
                        openPicker({
                            title = "Delete a look",
                            rows = presetRows(),
                            onSelect = function(name)
                                if IsValid(root.GoobConfirmShade) then root.GoobConfirmShade:Remove() end
                                local _, shade = K.Modal(root, "Delete saved look?", name .. " will be removed from this computer.", {
                                    {"Cancel", nil},
                                    {"Delete", function()
                                        if A.SafeName(name) then
                                            ap.DeletePreset(name)
                                            notice:SetText("Deleted look · " .. name)
                                            closePicker()
                                        end
                                    end, danger = true}
                                })
                                root.GoobConfirmShade = shade
                                return false
                            end
                        })
                    end, {danger = true})
                end
            end

            -- Spec-uncovered: Random-on-spawn has no tab of its own, so it lives here in Looks.
            if ap.ForcedRandom then
                caption(content, "Spawn")
                wardrobeToggleRow(content, "Random appearance on spawn", function() return ap.ForcedRandom:GetBool() end, function(v)
                    RunConsoleCommand("hg_appearance_force_random", v and "1" or "0")
                end)
            end
        end
    end

    rebuild()
end

-- apps.lua's A.Open already xpcalls the synchronous build() call, but that
-- wrap doesn't cover errors thrown later from Think/rebuild closures created
-- here. Wrap the body directly too, so the owner sees a message in console
-- and on the panel instead of a silently blank app either way.
local function build(root)
    local ok, err = pcall(buildWardrobe, root)
    if not ok then
        ErrorNoHalt("[GoobOS] wardrobe build failed: " .. tostring(err) .. "\n")
        root:Clear()
        A.Status(root, "[GoobOS] wardrobe build failed: " .. tostring(err), T.red)
    end
end

A.Register("wardrobe", "Wardrobe", "Make yourself at home", "icon16/user_suit.png", Color(191, 164, 255), build)

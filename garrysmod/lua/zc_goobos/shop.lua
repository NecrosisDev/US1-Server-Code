if not CLIENT then return end
local A, T = ZCGoobApps, ZCGoobApps.Theme
-- kit.lua is a hard dependency for this file (apps.lua auto-includes it before any app's build()
-- can run); fetched once at file scope since the tile painters below sit outside buildShop().
-- buildShop() still checks `K` itself and shows a message instead of a blank app if it is missing.
local K = A.Kit
A.ShopVersion = "20260924.shop2"

function A.ShopState(item, vars)
    if not istable(vars) or vars.loaded ~= true then return "Profile loading", false end
    if vars.unlimited or (vars.items and vars.items[item.ID]) then return "Owned", false end
    local currency = item.ISDONATE and "DZP" or "ZP"
    local price = tonumber(item.PRICE)
    if not price or price < 0 then return "Unavailable", false end
    local balance = tonumber(vars[item.ISDONATE and "donpoints" or "points"]) or 0
    return (balance < price and "Need " .. (price - balance) or tostring(price)) .. " " .. currency, balance >= price
end

function A.RequestShop()
    if (A.NextShopRequest or 0) > RealTime() then return end
    if not hg or not hg.PointShop or not hg.PointShop.SendNET then return end
    A.NextShopRequest = RealTime() + 2
    -- Observe the existing profile cache; no callback queue or receiver takeover.
    hg.PointShop:SendNET("SendPointShopVars")
end

function A.Buy(item)
    local p = LocalPlayer()
    if not IsValid(p) then return false end
    local _, allowed = A.ShopState(item, p.PS_MyItensens)
    if not allowed or (A.ShopPending and A.ShopPending.untilTime > RealTime()) then return false end
    A.ShopPending = {
        id = item.ID,
        untilTime = RealTime() + 8
    }

    hg.PointShop:SendNET("BuyItem", {item.ID})
    -- The stock Derma_Message + myinstants sting (sh_pointshop.lua's hg_pointshop_send_notificate)
    -- would otherwise pop over the phone on top of the toast below; suppress it for the same window
    -- A.ShopPending waits on.
    hg.PointShop.SuppressNotifyUntil = RealTime() + 8
    return true
end

-- "Accessory · Head slot" line for the buy/owned sheets (mockup 04 "Other states").
local SLOT_NAMES = {head = "Head", face = "Face", ears = "Ears", torso = "Torso", spine = "Back"}
function A.ShopSlotLabel(item)
    local acc = hg and hg.Accessories and hg.Accessories[item.ID]
    if acc then return "Accessory · " .. (SLOT_NAMES[acc.placement] or string.NiceName(tostring(acc.placement or "worn"))) .. " slot" end
    return "Clothing item"
end

-- Tile geometry: the price pill is inlaid on the icon's bottom-right corner, the item name has its
-- own ellipsised line below (NAME_H), and the card gets a hover wash plus a 1 px outline when the
-- item is fitted on the preview (accent) or equipped (main red), as mockup 04 shows.
local TILE_MIN_W, TILE_H, NAME_H = 92, 126, 26

local function drawIconTile(tile, w, h, fitted, hover)
    local item = tile.Item
    K.Card(0, 0, w, h, T.cardGlass, fitted and T.accent or (tile.Equipped and T.main or nil))
    if hover > 0.01 then draw.RoundedBox(4, 1, 1, w - 2, h - 2, K.Alpha(T.main, 40 * hover)) end

    local iconH = h - NAME_H
    local pad = 7
    local size = math.floor(math.min(w - pad * 2, iconH - pad * 2))
    local ix, iy = math.floor((w - size) / 2), pad + math.floor(math.max(0, (iconH - pad * 2 - size) / 2))
    A.Icons.Draw(tile.IconKey, tile.IconSpec, ix, iy, size, "bag")

    if tile.Owned then
        local label = tile.Equipped and "EQUIPPED" or "OWNED"
        local font = K.Font(10, 700)
        surface.SetFont(font)
        local bw = surface.GetTextSize(label) + 10
        draw.RoundedBox(3, 5, 5, bw, 15, K.Alpha(T.green, 235))
        draw.SimpleText(label, font, 5 + bw / 2, 12, T.bg, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    K.Text(K.Fit(item.NAME or item.ID, K.Font(12, 500), w - 10), 12, 500, w / 2, h - NAME_H / 2, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    -- Price pill: text is computed when the grid is (re)built, so Paint allocates nothing.
    local text = tile.PriceText
    local pending = A.ShopPending and A.ShopPending.id == item.ID and A.ShopPending.untilTime > RealTime()
    if pending then text = "…" end
    local font = K.Font(10, 700)
    surface.SetFont(font)
    local pillW, pillH = surface.GetTextSize(text) + 12, 17
    local px, py = w - pillW - 5, iconH - pillH - 3
    draw.RoundedBox(8, px, py, pillW, pillH, tile.Allowed and K.Alpha(T.gold, 235) or K.Alpha(T.ink, 215))
    draw.SimpleText(text, font, px + pillW / 2, py + pillH / 2, tile.Allowed and T.bg or (tile.Owned and T.green or T.muted), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- Two side-by-side sheet buttons (mockup: Cancel | Buy).
local function sheetButtons(sheet, shade, specs)
    local row = K.Panel(sheet)
    row:Dock(BOTTOM)
    row:SetTall(38)
    row.Buttons = {}
    for index, spec in ipairs(specs) do
        local b = vgui.Create("DButton", row)
        b:SetText("")
        b:SetCursor("hand")
        b.DoClick = function()
            shade:Close()
            if spec[2] then spec[2]() end
        end
        b.Paint = function(s, w, h)
            local hover = K.Hover(s)
            draw.RoundedBox(4, 0, 0, w, h, spec.primary and T.main or T.card)
            if hover > 0.01 then draw.RoundedBox(4, 0, 0, w, h, K.Alpha(T.white, 16 * hover)) end
            K.Text(spec[1], 15, 600, w / 2, h / 2, spec.danger and T.red or T.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        row.Buttons[index] = b
    end
    row.PerformLayout = function(s, w, h)
        local count, gap = #s.Buttons, 8
        local each = math.floor((w - gap * (count - 1)) / count)
        for index, b in ipairs(s.Buttons) do
            b:SetPos((index - 1) * (each + gap), 0)
            b:SetSize(each, h)
        end
    end
    return row
end

-- Item sheet (buy confirm / owned actions): caption, icon + name + slot, question, detail, buttons.
local function itemSheet(root, tile, caption, question, detail, buttons)
    if IsValid(root.GoobConfirmShade) then root.GoobConfirmShade:Remove() end
    local sheet, shade = K.Sheet(root, 196)
    root.GoobConfirmShade = shade
    local item = tile.Item
    local slot = A.ShopSlotLabel(item)
    local head = K.Panel(sheet)
    head:Dock(FILL)
    head.Paint = function(_, w)
        K.Text(caption, 11, 700, 0, 0, T.accent)
        A.Icons.Draw(tile.IconKey, tile.IconSpec, 0, 22, 46, "bag")
        K.Text(K.Fit(item.NAME or item.ID, K.Font(16, 600), w - 58), 16, 600, 56, 26, T.text)
        K.Text(K.Fit(slot, K.Font(12, 500), w - 58), 12, 500, 56, 48, T.muted)
        K.Text(K.Fit(question, K.Font(15, 600), w), 15, 600, 0, 78, T.text)
        if detail then K.Text(K.Fit(detail, K.Font(12, 500), w), 12, 500, 0, 100, T.muted) end
    end
    sheetButtons(sheet, shade, buttons)
    return sheet, shade
end

local function buildShop(root, phone)
    if not K then
        A.Status(root, "GoobOS kit failed to load; try reopening the phone.")
        return
    end

    if not hg or not hg.PointShop or not A.Icons then
        A.Status(root, "The shop is not available yet.")
        return
    end

    A.RequestShop()
    local state = A.State.shop or {
        query = "",
        filter = "All"
    }

    A.State.shop = state
    -- Forward declared: the header's search entry and filter call grid.RefreshShop() before the grid exists.
    local grid

    -- Share the same base draft Wardrobe uses, so both apps show one consistent look. If the
    -- wardrobe was never opened this session, load it here the same way wardrobe.lua does.
    local ap = hg.Appearance
    local function ensureBaseDraft()
        if not ap or not ap.LoadAppearanceFile or not A.ModelData or not A.CleanDraft then return nil end
        local ws = A.State.wardrobe
        if not ws then
            ws = {}
            A.State.wardrobe = ws
        end
        if not ws.draft then
            local ok, saved = pcall(ap.LoadAppearanceFile, ap.SelectedAppearance:GetString())
            ws.draft = ok and A.CleanDraft(saved) or nil
            ws.draft = ws.draft or (ap.SkeletonAppearanceTable and A.CleanDraft(ap.SkeletonAppearanceTable))
        end
        return ws.draft
    end

    -- Transient status toast over the grid column (purchase feedback). The mockup has no status line,
    -- so nothing shows until there is something to say; it fades after a few seconds.
    local toast = {text = nil, color = T.text, at = 0}
    local function setStatus(text, color)
        toast.text, toast.color, toast.at = text, color or T.text, RealTime()
    end

    -- Header (mockup 04): balance chip (tap = refresh profile), search, All/Available/Owned. One row
    -- when the body is wide enough, otherwise the chip gets its own row (the 384 px mockup).
    local header = K.Panel(root)
    header:Dock(TOP)
    header:SetTall(34)
    header:DockMargin(0, 0, 0, 8)

    local balance = vgui.Create("DButton", header)
    balance:SetText("")
    balance:SetCursor("hand")
    balance:SetTooltip("Tap to refresh your profile")
    balance.Amount = "Connecting…"
    balance.DoClick = function()
        A.NextShopRequest = 0
        A.RequestShop()
        setStatus("Refreshing your profile…", T.muted)
    end
    balance.Paint = function(s, w, h)
        local hover = K.Hover(s)
        draw.RoundedBox(4, 0, 0, w, h, T.card)
        if hover > 0.01 then draw.RoundedBox(4, 0, 0, w, h, K.Alpha(T.white, 12 * hover)) end
        K.Text(K.Fit(s.Amount, K.Font(13, 700), w - 16), 13, 700, w / 2, h / 2, T.gold, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    local filterOptions = {"All", "Available", "Owned"}
    local filterIndex = ({All = 1, Available = 2, Owned = 3})[state.filter] or 1
    local segmented = K.Segmented(header, filterOptions, filterIndex, function(_, label)
        state.filter = label
        grid.RefreshShop()
    end)

    local search = vgui.Create("DTextEntry", header)
    search:SetFont(K.Font(14, 500))
    search:SetUpdateOnType(true)
    search:SetText(state.query)
    search.Paint = function(s, w, h)
        draw.RoundedBox(4, 0, 0, w, h, T.card)
        if s:HasFocus() then
            surface.SetDrawColor(T.main)
            surface.DrawOutlinedRect(1, 1, w - 2, h - 2)
        end
        if s:GetValue() == "" and not s:HasFocus() then
            K.Text(w >= 170 and "Search accessories" or "Search", 13, 500, 10, h / 2, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        else
            s:DrawTextEntryText(T.text, T.accent, T.text)
        end
    end
    search.OnValueChange = function(_, v)
        state.query = v
        grid.RefreshShop()
    end

    header.Think = function(s)
        local w = s:GetWide()
        if w <= 1 or w == s.LaidW then return end
        s.LaidW = w
        local segW = 210
        if w >= 500 then
            s:SetTall(34)
            balance:SetPos(0, 0)
            balance:SetSize(132, 34)
            segmented:SetPos(w - segW, 1)
            segmented:SetSize(segW, 32)
            search:SetPos(140, 0)
            search:SetSize(math.max(40, w - 140 - segW - 8), 34)
        else
            segW = math.min(segW, math.floor(w * 0.55))
            s:SetTall(70)
            balance:SetPos(0, 0)
            balance:SetSize(w, 30)
            search:SetPos(0, 36)
            search:SetSize(math.max(40, w - segW - 8), 34)
            segmented:SetPos(w - segW, 37)
            segmented:SetSize(segW, 32)
        end
    end

    -- Two columns: preview (42%) + grid, stacked below A.PREVIEW_STACK_BREAKPOINT. Sized from Think
    -- (nested Dock(FILL) invalidation does not always cascade -- owner report 2026-09-23).
    local columns = K.Panel(root)
    columns:Dock(FILL)

    local preview = A.CreatePreviewWidget(columns)
    local right = K.Panel(columns)
    local gridScroll = A.Scroll(right)
    gridScroll:DockPadding(0, 0, 0, 0)
    local empty = K.EmptyState(right, "bag", "No accessories match", "Try another search or filter.")
    empty:Dock(NODOCK)
    empty:SetVisible(false)

    local comingSoon = K.EmptyState(right, "bag", "New items are on the way", "Everything that used to be here is now free in your Wardrobe.")
    comingSoon:Dock(NODOCK)
    comingSoon:SetVisible(false)

    local hovered, selected

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
        empty:SetPos(0, 0)
        empty:SetSize(right:GetWide(), right:GetTall())
        comingSoon:SetPos(0, 0)
        comingSoon:SetSize(right:GetWide(), right:GetTall())
    end

    -- Preview follows the hovered (else selected) item. A short hold stops it snapping back to the
    -- plain model while the pointer crosses the gap between two tiles.
    local shown, lastSeen = false, 0
    columns.Think = function()
        local ok, err = pcall(layoutColumns)
        if not ok then ErrorNoHalt("[GoobOS] shop layout failed: " .. tostring(err) .. "\n") end
        local want = hovered or selected
        if want then lastSeen = RealTime() elseif RealTime() - lastSeen < 0.35 then want = shown end
        if want ~= shown then
            shown = want
            preview:Fit(want or nil)
            local acc = want and hg.Accessories and hg.Accessories[want.ID]
            preview:SetChip(want and ((acc and "Fitting: " or "Selected: ") .. (want.NAME or want.ID)) or nil)
            preview:Focus(acc and A.PreviewRegionFor(acc.placement) or "all")
        end
    end
    columns.PaintOver = function(_, w, h)
        if not toast.text then return end
        local age = RealTime() - toast.at
        if age > 5 then
            toast.text = nil
            return
        end
        local alpha = K.Reduced() and 1 or math.Clamp((5 - age) / 0.6, 0, 1)
        local font = K.Font(13, 600)
        local text = K.Fit(toast.text, font, w - 60)
        surface.SetFont(font)
        local tw = surface.GetTextSize(text) + 28
        local x = math.floor((w - tw) / 2)
        draw.RoundedBox(4, x, h - 40, tw, 30, K.Alpha(T.glassHi, 245 * alpha))
        draw.SimpleText(text, font, w / 2, h - 25, K.Alpha(toast.color, 255 * alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    preview:SetBase(ensureBaseDraft())

    -- Grid: tiles fill the column width evenly (min TILE_MIN_W), re-laid only when width or tile
    -- count changes; the scroll canvas follows the grid's height.
    grid = K.Panel(gridScroll)
    grid:Dock(TOP)
    grid.Think = function(s)
        local children = s:GetChildren()
        local signature = s:GetWide() .. ":" .. #children
        if signature == s.GoobLayout then return end
        s.GoobLayout = signature
        local height = K.GridLayout(children, s:GetWide(), TILE_MIN_W, TILE_H, 8, 8)
        if s:GetTall() ~= height then
            s:SetTall(math.max(1, height))
            gridScroll:InvalidateLayout()
        end
    end

    local function wardrobeDraft()
        return ensureBaseDraft()
    end

    local function openTile(tile)
        local item = tile.Item
        local vars = LocalPlayer().PS_MyItensens
        if tile.Owned then
            local acc = hg.Accessories and hg.Accessories[item.ID]
            local draft = wardrobeDraft()
            if not acc or not draft or not A.SetAccessory then
                setStatus("Owned · set it up in Wardrobe.", T.green)
                return
            end
            if tile.Equipped then
                itemSheet(root, tile, "OWNED", "Take " .. (item.NAME or item.ID) .. " off?", "Your look changes in Wardrobe; save it there.", {
                    {"Keep it", nil},
                    {"Take off", function()
                        table.RemoveByValue(draft.AAttachments, item.ID)
                        A.State.wardrobe.dirty = true
                        preview:SetBase(draft)
                        grid.RefreshShop()
                        setStatus("Taken off · save your look in Wardrobe.", T.muted)
                    end, primary = true}
                })
            else
                itemSheet(root, tile, "OWNED", "Wear " .. (item.NAME or item.ID) .. "?", "Adds it to your look; save it in Wardrobe.", {
                    {"Not now", nil},
                    {"Try on in Wardrobe", function()
                        if not A.SetAccessory(draft, item.ID) then
                            setStatus("Three accessories are worn; remove one in Wardrobe first.", T.red)
                            return
                        end
                        A.State.wardrobe.dirty = true
                        -- Land on Accessories (tab 4), not Identity, so the item just tried on is
                        -- immediately visible in the picker/worn list.
                        A.State.wardrobe.tab = 4
                        if IsValid(phone) and phone.SetPhonePage then phone:SetPhonePage("wardrobe") end
                    end, primary = true}
                })
            end
            return
        end
        if not tile.Allowed then
            local text = A.ShopState(item, vars)
            setStatus(string.sub(text, 1, 5) == "Need " and "You need " .. string.sub(text, 6) .. " more." or text, T.muted)
            return
        end
        local price = tonumber(item.PRICE)
        local currency = item.ISDONATE and "DZP" or "ZP"
        local balancePts = istable(vars) and tonumber(vars[item.ISDONATE and "donpoints" or "points"])
        local after = (price and balancePts) and ("Balance after: " .. tostring(math.max(balancePts - price, 0)) .. " " .. currency) or nil
        itemSheet(root, tile, "CONFIRM PURCHASE", "Buy " .. (item.NAME or item.ID) .. " for " .. tile.PriceText .. "?", after, {
            {"Cancel", nil},
            {"Buy", function() if A.Buy(item) then setStatus("Purchase requested. Waiting for your profile…", T.muted) end end, primary = true}
        })
    end

    function grid.RefreshShop()
        grid:Clear()
        hovered = nil -- the hovered tile is gone; its OnCursorExited will never fire
        local vars = LocalPlayer().PS_MyItensens
        local ws = A.State.wardrobe
        local count, totalCatalog = 0, 0
        local free = hg.PointShop.FreeItems
        for _, row in ipairs(A.SortedRows(hg.PointShop.Items, function(v) return v.NAME or v.ID end)) do
            local item = row.data
            -- Owner decision 2026-09-26: the existing catalog (everything free-tagged) is handed out
            -- in the Wardrobe and no longer listed for sale here. totalCatalog (ignoring search/filter)
            -- decides which empty state to show below: "nothing left to sell" vs "no search match".
            if not (free and free[item.ID]) then
                totalCatalog = totalCatalog + 1
                local owned = istable(vars) and (vars.unlimited or (vars.items or {})[item.ID]) and true or false
                if A.Matches(item.NAME or item.ID, state.query) and (state.filter == "All" or state.filter == "Owned" and owned or state.filter == "Available" and not owned) then
                    count = count + 1
                    local tile = vgui.Create("DButton", grid)
                    tile:SetText("")
                    tile:SetSize(TILE_MIN_W, TILE_H)
                    tile:SetCursor("hand")
                    tile:SetTooltip(item.NAME or item.ID)
                    tile.Item = item
                    tile.Owned = owned
                    tile.Equipped = owned and ws and ws.draft and table.HasValue(ws.draft.AAttachments or {}, item.ID) or false
                    tile.PriceText, tile.Allowed = A.ShopState(item, vars)
                    tile.IconKey = "item:" .. tostring(item.ID)
                    tile.IconSpec = A.ItemIconSpec(item)
                    tile.Paint = function(s, w, h) drawIconTile(s, w, h, item == shown, K.Hover(s)) end
                    tile.OnCursorEntered = function() hovered = item end
                    tile.OnCursorExited = function() if hovered == item then hovered = nil end end
                    tile.DoClick = function()
                        selected = item
                        openTile(tile)
                    end
                end
            end
        end
        grid.GoobLayout = nil
        empty:SetVisible(count == 0 and totalCatalog > 0)
        comingSoon:SetVisible(count == 0 and totalCatalog == 0)
    end

    grid.RefreshShop()
    root.Think = function(s)
        if (s.nextRefresh or 0) > RealTime() then return end
        s.nextRefresh = RealTime() + 0.25
        local vars = LocalPlayer().PS_MyItensens
        if vars ~= s.lastVars then
            s.lastVars = vars
            grid.RefreshShop()
            if istable(vars) and vars.loaded then
                balance.Amount = vars.unlimited and "Full access" or tostring(vars.points or 0) .. " ZP · " .. tostring(vars.donpoints or 0) .. " DZP"
            else
                balance.Amount = "Profile loading…"
            end
        end

        if A.ShopPending then
            local pending = A.ShopPending
            if istable(vars) and (vars.unlimited or (vars.items or {})[pending.id]) then
                A.ShopPending = nil
                setStatus("Added to your wardrobe.", T.green)
            elseif pending.untilTime <= RealTime() then
                A.ShopPending = nil
                setStatus("Purchase not confirmed. Tap your balance to refresh.", T.red)
                A.RequestShop()
            end
        end
    end
end

-- apps.lua's A.Open already xpcalls the synchronous build() call, but that wrap doesn't cover errors
-- thrown later from Think/RefreshShop closures created here. Wrap the body directly too, so the
-- owner sees a message in console and on the panel instead of a silently blank app either way.
local function build(root, phone)
    local ok, err = pcall(buildShop, root, phone)
    if not ok then
        ErrorNoHalt("[GoobOS] shop build failed: " .. tostring(err) .. "\n")
        root:Clear()
        A.Status(root, "[GoobOS] shop build failed: " .. tostring(err), T.red)
    end
end

A.Register("shop", "Shop", "Find your next look", "icon16/basket.png", T.gold, build)

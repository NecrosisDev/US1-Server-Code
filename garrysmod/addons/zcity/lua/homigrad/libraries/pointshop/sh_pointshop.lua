--
hg.PointShop = hg.PointShop or {}

local PLUGIN = hg.PointShop

PLUGIN.Items = PLUGIN.Items or {}

-- 2026-09-26: the appearance catalog's items (84 accessories + 18 glove bodygroups) are handed
-- out to everyone regardless of hg_appearance_access_for_all (owner decision). Keyed to the exact
-- existing catalog ids so future non-free shop items are unaffected; stamped at creation time in
-- new_appearance/sh_accessories.lua and sh_shared.lua so it never races either catalog-building hook.
PLUGIN.FreeItems = PLUGIN.FreeItems or {}
-- 2026-09-26 (live probe after the first push): creation-time stamping missed 64 of 158 items, because
-- a hot reload re-runs the catalog hooks against items the previous load had already created. So the rule
-- is now structural instead: an item is free unless it is explicitly for sale. Future paid items pass
-- tData = {ForSale = true} to CreateItem. Explicit true entries above still count; unknown ids are not free.
setmetatable(PLUGIN.FreeItems, {__index = function(_, uid)
    local item = PLUGIN.Items[uid]
    return item ~= nil and not (istable(item.DATA) and item.DATA.ForSale == true)
end})

function PLUGIN:CreateItem( uid, strName, strModel, strBodyGroups, iSkin, vecPos, intPrice, bIsDPoints, tData, fCallback, fov )
    PLUGIN.Items[uid] = {
        ID = uid,
        NAME = strName,
        MDL = strModel or "models/dav0r/hoverball.mdl",
        BODYGROUP = strBodyGroups or "00000",
        SKIN = iSkin or 0,
        VPos = vecPos or Vector(0,0,0),
        PRICE = intPrice,
        ISDONATE = bIsDPoints or false,
        DATA = tData or {},
        CALLBACK = fCallback or nil,
        FOV = fov or 15
    }
end

--PLUGIN:CreateItem("test_item_1","TEST ITEM","models/dav0r/hoverball.mdl",Vector(0,0,0),100)
--PLUGIN:CreateItem("hat","TEST ITEM","models/dav0r/hoverball.mdl",Vector(0,0,0),100)

if SERVER then
    --Player(2):PS_AddItem( "test_item_1" )
end

if CLIENT then
    -- This used to be a LIFO stack serving a FIFO protocol. Two requests in flight -- opening the shop
    -- while the appearance menu is still loading, which is one click apart -- resolved in reverse order, and
    -- the server also pushes this table UNSOLICITED (profile load, balance change), which popped somebody's
    -- callback and fed it the wrong payload while the real reply later found an empty stack and hung the
    -- caller forever. Oldest first, and an unsolicited push consumes nothing.
    local callbacks = {}

    net.Receive("hg_pointshop_net",function()
        local vars = net.ReadTable()
        if not istable(vars) then return end
        vars.items = istable(vars.items) and vars.items or {}
        LocalPlayer().PS_MyItensens = vars

        local waiting = table.remove(callbacks, 1)
        if waiting then waiting(vars) end
    end)

    function PLUGIN:SendNET(strFunc,tVars,callback)
        net.Start( "hg_pointshop_net" )
            net.WriteString( strFunc )
            net.WriteTable( tVars or {} )
        net.SendToServer()

        if callback then
            callbacks[#callbacks + 1] = callback
        end
    end 

    local plyMeta = FindMetaTable("Player")

    -- Nil until the first reply lands. Every caller here used to index straight through it, so anything
    -- asking before the server had answered threw; the appearance editor only survives because it builds
    -- itself inside the reply callback. Unknown is "not owned", never an error.
    function plyMeta:PS_HasItem( uid )
        if PLUGIN.FreeItems[ uid ] then return true end
        local pointshopVars = LocalPlayer().PS_MyItensens
        if not istable(pointshopVars) or not istable(pointshopVars.items) then return false end
        return pointshopVars.items[ uid ] or false
    end

    net.Receive("hg_pointshop_send_notificate",function()
        local txt = net.ReadString()
        -- 2026-09-26: a phone purchase (zc_goobos/shop.lua) already reports the result as an in-app
        -- toast; this stock Derma_Message + myinstants sting used to double up over it. Suppressed only
        -- for the few seconds a phone buy is in flight (PLUGIN.SuppressNotifyUntil, set by shop.lua's
        -- A.Buy) so a non-phone caller (e.g. a future !pointshop-only path) still gets the popup.
        -- One-shot: the server sends exactly one notification per buy attempt, so only the reply to the
        -- phone's own buy is swallowed; a !pointshop purchase inside the window still gets its popup.
        if PLUGIN.SuppressNotifyUntil and PLUGIN.SuppressNotifyUntil > RealTime() then PLUGIN.SuppressNotifyUntil = nil return end
        sound.PlayURL("https://www.myinstants.com/media/sounds/short-notice.mp3","mono",function() Derma_Message(txt, "Result", "OK") end)
    end)
end

hook.Add("Think","ZPointshopLoaded",function()
    hook.Run("ZPointshopLoaded")
    hook.Remove("Think","ZPointshopLoaded")
end)
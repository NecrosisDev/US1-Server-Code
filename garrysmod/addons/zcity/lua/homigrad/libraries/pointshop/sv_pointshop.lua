--
hg.Pointshop = hg.Pointshop or {}

local PLUGIN = hg.Pointshop
PLUGIN.PlayerInstances = PLUGIN.PlayerInstances or {}

-- WHY THIS FILE CHANGED (2026-09-22)
--
-- Every one of the 7855 rows in hg_pointshop held 0 points and no items, while
-- zb_experience for the same players had climbed to 85060 XP. The faucet was
-- firing correctly on every kill and round end (sv_experience.lua:107 calls
-- PS_AddPoints); the shop threw the points away.
--
-- The cause was three `util.IsBinaryModuleInstalled("mysqloo")` tests. This
-- server has no mysqloo -- lua/bin does not exist -- but it does not need one:
-- sv_database.lua connects with dbmodule = "sqlite" and the mysql wrapper
-- speaks sqlite fully, so DatabaseConnected fires and both tables are real.
-- The shop was asking whether a particular BINARY was present when the thing it
-- needed to know was whether the DATABASE was connected. Those tests now ask
-- that question instead, through PS_IsReady().
--
-- GetPointshopVars was the worst of the three: on every call it REPLACED the
-- player's instance with a fresh zeroed table, destroying the row
-- PlayerInitialSpawn had just loaded. That is why PS_HasItem always returned
-- false and why players were told "<item> - not bought, removed" by
-- new_appearance/sv_init.lua for things they owned.
--
-- The guards matter more now than they did while the shop was inert.
-- PS_SetPoints issues an ABSOLUTE `UPDATE ... SET points = <value>`, so a write
-- from a profile that has not finished loading overwrites a real stored balance
-- with a fabricated zero. Nothing could be lost while every balance was 0; the
-- moment the faucet works, that stops being true. Hence: reads are always safe
-- and never persist anything, and every writer proves PS_IsReady() first.

local function freshVars()
    return { donpoints = 0, points = 0, items = {}, loaded = false }
end

-- Loads a player's row, or inserts one, and marks the instance loaded so
-- writers are allowed to touch it. Safe to call more than once: a second call
-- while a query is in flight is dropped, and the deadline (rather than a plain
-- boolean) means a dropped query or an errored callback cannot lock a player
-- out of their own profile for the rest of the map.
function PLUGIN:LoadPlayer( ply )
    if not IsValid(ply) or not ply:IsPlayer() then return end

    local name = ply:Name()
    local steamID64 = ply:SteamID64()
    if not steamID64 then return end

    local current = PLUGIN.PlayerInstances[steamID64]
    if istable(current) and current.loading and current.loading > CurTime() then return end

    if not PLUGIN.Active then
        -- No database yet. Give them a provisional instance so nothing errors,
        -- but leave loaded = false so no write can flush these zeroes over the
        -- row that is still sitting in the table. DatabaseConnected retries.
        if not istable(current) then PLUGIN.PlayerInstances[steamID64] = freshVars() end
        return
    end

    current = istable(current) and current or freshVars()
    current.loaded = false
    current.loading = CurTime() + 30
    PLUGIN.PlayerInstances[steamID64] = current

    local query = mysql:Select("hg_pointshop")
        query:Select("donpoints")
        query:Select("points")
        query:Select("items")
        query:Where("steamid", steamID64)
        query:Callback(function(result)
            if not IsValid(ply) then return end

            local vars = PLUGIN.PlayerInstances[steamID64] or freshVars()
            PLUGIN.PlayerInstances[steamID64] = vars
            vars.loading = nil

            if istable(result) and #result > 0 and result[1].donpoints then
                local updateQuery = mysql:Update("hg_pointshop")
                    updateQuery:Update("steam_name", name)
                    updateQuery:Where("steamid", steamID64)
                updateQuery:Execute()

                vars.donpoints = tonumber(result[1].donpoints) or 0
                vars.points = tonumber(result[1].points) or 0
                -- A malformed or empty items blob must not come back as nil:
                -- PS_HasItem and PS_AddItem both index this table directly.
                vars.items = util.JSONToTable(result[1].items or "") or {}
                vars.loaded = true

                hook.Run( "PS_PlayerLoaded", ply, steamID64 )
            else
                local insertQuery = mysql:Insert("hg_pointshop")
                    insertQuery:Insert("steamid", steamID64)
                    insertQuery:Insert("steam_name", name)
                    insertQuery:Insert("donpoints", 0)
                    insertQuery:Insert("points", 0)
                    insertQuery:Insert("items", util.TableToJSON({}))
                insertQuery:Execute()

                vars.donpoints = 0
                vars.points = 0
                vars.items = {}
                vars.loaded = true

                hook.Run( "PS_PlayerLoaded", ply, steamID64 )
            end

            PLUGIN:NET_SendPointShopVars( ply )
        end)
    query:Execute()
end

hook.Add("DatabaseConnected", "PointshopCreateData", function()
	local query

	query = mysql:Create("hg_pointshop")
		query:Create("steamid", "VARCHAR(20) NOT NULL")
		query:Create("steam_name", "VARCHAR(32) NOT NULL")
		query:Create("donpoints", "FLOAT NOT NULL")
		query:Create("points", "FLOAT NOT NULL")
        query:Create("items", "TEXT NOT NULL")
		query:PrimaryKey("steamid")
	query:Execute()

    --hook.Run("ZPointshopLoaded")

    PLUGIN.Active = true

    -- Join race: anyone who spawned before the database answered is holding a
    -- provisional instance with no row behind it. The table exists now, so load
    -- them properly rather than leaving them unable to earn for the map.
    for _, ply in ipairs(player.GetHumans()) do
        PLUGIN:LoadPlayer( ply )
    end
end)

--local query = mysql:Drop("zb_experience")
--query:Execute()

hook.Add( "PlayerInitialSpawn","Pointshop_OnInitSpawn", function( ply )
    PLUGIN:LoadPlayer( ply )
end)


local plyMeta = FindMetaTable("Player")

-- Never wipes, never persists. A player whose profile has not arrived gets a
-- zeroed table so that readers (PS_HasItem, the net reply) cannot error, but
-- that table is marked unloaded, so PS_IsReady refuses every writer until the
-- real row lands. It is stored rather than rebuilt per call so that the
-- identity of the table is stable for anything holding a reference.
function plyMeta:GetPointshopVars()
    local steamID64 = self:SteamID64()
    if not steamID64 then return freshVars() end

    local vars = PLUGIN.PlayerInstances[steamID64]
    if not istable(vars) then
        vars = freshVars()
        PLUGIN.PlayerInstances[steamID64] = vars
    end

    -- Defensive: older instances (and a hot reload landing mid-map) can carry a
    -- nil items table or a string balance.
    if not istable(vars.items) then vars.items = {} end
    vars.points = tonumber(vars.points) or 0
    vars.donpoints = tonumber(vars.donpoints) or 0

    return vars
end

-- The single question every writer asks. Not "is mysqloo installed" -- this
-- server runs sqlite and always has -- but "is there a real row behind this
-- player that I am allowed to overwrite".
function plyMeta:PS_IsReady()
    if not PLUGIN.Active then return false end

    local steamID64 = self:SteamID64()
    if not steamID64 then return false end

    local vars = PLUGIN.PlayerInstances[steamID64]
    return istable(vars) and vars.loaded == true
end

-- Owner, 2026-09-22: "start all at zero, give unlimited to admins+".
--
-- There is already exactly one definition of who gets everything --
-- hg.Appearance.GetAccessToAll (new_appearance/sh_shared.lua), which covers
-- admin, superadmin, a per-SteamID allowlist and the server-wide
-- hg_appearance_access_for_all convar, and which the appearance strip and all
-- four editor call sites already obey. Deferring to it means the shop and the
-- wardrobe can never disagree about who is privileged; defining a second rule
-- here is how they would drift. The IsAdmin fallback only matters if the
-- appearance library has not loaded yet.
--
-- Note this is SPENDING power, not a stored balance: the row keeps its real
-- value, nothing is written, and revoking somebody's rank takes the privilege
-- away with it rather than leaving an inflated number behind.
local UNLIMITED = 999999999

function plyMeta:PS_HasUnlimited()
    if hg.Appearance and isfunction(hg.Appearance.GetAccessToAll) then
        return hg.Appearance.GetAccessToAll(self) and true or false
    end
    return self:IsAdmin() or self:IsSuperAdmin()
end

function plyMeta:PS_AddPoints( ammout, callback )
    ammout = tonumber(ammout)
    if not ammout or ammout ~= ammout then return false, "How." end
    if ammout < 1 then
        return false, "How."
    end

    if not self:PS_IsReady() then return false, "Your Point Shop profile is still loading." end

    local pointshopVars = self:GetPointshopVars()

    if not self:PS_SetPoints(pointshopVars.points + ammout) then
        return false, "Your Point Shop profile is still loading."
    end

    if callback then
        callback( self )
    end

    return true, ammout .. " points added !pointshop to open a pointshop"
end

function plyMeta:PS_SetPoints( value )
    if not self:PS_IsReady() then return false end

    value = tonumber(value)
    if not value or value ~= value then return false end
    if value < 0 then value = 0 end

	local steamID64 = self:SteamID64()
    local pointshopVars = self:GetPointshopVars()

    local updateQuery = mysql:Update("hg_pointshop")
		updateQuery:Update("points", value)
		updateQuery:Where("steamid", steamID64)
	updateQuery:Execute()

    pointshopVars.points = value

    return true
end

function plyMeta:PS_TakePoints( ammout, callback )
    ammout = tonumber(ammout)
    if not ammout or ammout ~= ammout or ammout < 0 then return false, "How." end

    if not self:PS_IsReady() then return false, "Your Point Shop profile is still loading." end

    -- Unlimited spends nothing: no debit, no absolute write, stored balance
    -- untouched. The callback still runs, so the item is still granted and
    -- still persists -- what they own is real, only the price is waived.
    if self:PS_HasUnlimited() then
        if callback then
            callback( self )
        end
        return true, "Granted (unlimited)."
    end

    local pointshopVars = self:GetPointshopVars()

    if ammout > pointshopVars.points then
        return false, "Not enough ZPoints."
    end

    if not self:PS_SetPoints(pointshopVars.points - ammout) then
        return false, "Your Point Shop profile is still loading."
    end

    if callback then
        callback( self )
    end

    return true, ammout .. " ZPoints spent."
end

-- ATTACK THE D POINT

function plyMeta:PS_AddDPoints( ammout, callback )
    ammout = tonumber(ammout)
    if not ammout or ammout ~= ammout then return false, "How." end
    if ammout < 1 then
        return false, "How."
    end

    if not self:PS_IsReady() then return false, "Your Point Shop profile is still loading." end

    local pointshopVars = self:GetPointshopVars()

    if not self:PS_SetDPoints(pointshopVars.donpoints + ammout) then
        return false, "Your Point Shop profile is still loading."
    end

    if callback then
        callback( self )
    end

    return true, ammout .. " DZPoints added !pointshop to open a pointshop"
end

function plyMeta:PS_SetDPoints( value )
    if not self:PS_IsReady() then return false end

    value = tonumber(value)
    if not value or value ~= value then return false end
    if value < 0 then value = 0 end

	local steamID64 = self:SteamID64()
    local pointshopVars = self:GetPointshopVars()

    local updateQuery = mysql:Update("hg_pointshop")
		updateQuery:Update("donpoints", value)
		updateQuery:Where("steamid", steamID64)
	updateQuery:Execute()

    pointshopVars.donpoints = value

    return true
end

function plyMeta:PS_TakeDPoints( ammout, callback )
    ammout = tonumber(ammout)
    if not ammout or ammout ~= ammout or ammout < 0 then return false, "How." end

    if not self:PS_IsReady() then return false, "Your Point Shop profile is still loading." end

    -- Unlimited covers the donate currency too, or an admin could reach every
    -- ordinary item and none of the donate ones.
    if self:PS_HasUnlimited() then
        if callback then
            callback( self )
        end
        return true, "Granted (unlimited)."
    end

    local pointshopVars = self:GetPointshopVars()

    if ammout > pointshopVars.donpoints then
        return false, "Not enough DZPoints."
    end

    if not self:PS_SetDPoints(pointshopVars.donpoints - ammout) then
        return false, "Your Point Shop profile is still loading."
    end

    if callback then
        callback( self )
    end

    return true, ammout .. " DZPoints spent."
end

-- Items functions

function plyMeta:PS_SetItems( tItems )
    if not self:PS_IsReady() then return false end
    if not istable(tItems) then return false end

    local steamID64 = self:SteamID64()
    local pointshopVars = self:GetPointshopVars()

    local updateQuery = mysql:Update("hg_pointshop")
		updateQuery:Update("items", util.TableToJSON(tItems))
		updateQuery:Where("steamid", steamID64)
	updateQuery:Execute()

    pointshopVars.items = tItems

    return true
end

function plyMeta:PS_AddItem( uid )
    if not hg.PointShop.Items[uid] then return false end

    local pointshopVars = self:GetPointshopVars()

    pointshopVars.items[ uid ] = true

    return self:PS_SetItems(pointshopVars.items)
end

function plyMeta:PS_HasItem( uid )
    -- 2026-09-26: the appearance catalog's items are free for everyone (owner decision), tagged by
    -- id in hg.PointShop.FreeItems at creation time (new_appearance/sh_accessories.lua,
    -- new_appearance/sh_shared.lua). This is the one server-side ownership check every consumer goes
    -- through (new_appearance/sv_init.lua's CheckAttachments, the buy path below), so it can never
    -- disagree with the client's mirror of the same rule in sh_pointshop.lua.
    if hg.PointShop.FreeItems and hg.PointShop.FreeItems[ uid ] then return true end

    local pointshopVars = self:GetPointshopVars()
    --PrintTable(pointshopVars)
    if not pointshopVars then return false end
    return pointshopVars.items[ uid ] or false
end

--print(Player(2):PS_HasItem( "test_item_1" ))

-- networking and other

util.AddNetworkString("hg_pointshop_net")

function PLUGIN:NET_SendPointShopVars( ply )
    if not IsValid(ply) then return end

    local vars = ply:GetPointshopVars()

    -- An unlimited player is SHOWN a balance that affords anything, so the shop
    -- UI stops greying out every item -- but the table that goes on the wire is
    -- a copy. Inflating the stored one would persist the fake number on the
    -- next write and leave it behind if the rank were ever removed.
    if ply:PS_HasUnlimited() then
        vars = { donpoints = UNLIMITED, points = UNLIMITED, items = vars.items, loaded = vars.loaded, unlimited = true }
    end

    net.Start( "hg_pointshop_net" )
        net.WriteTable( vars )
    net.Send( ply )
end

--PLUGIN:NET_SendPointShopVars( Player(2) )

util.AddNetworkString("hg_pointshop_send_notificate")

function PLUGIN:NET_BuyItem( ply, uid )
    -- The nil test has to come FIRST. It used to sit below an ISDONATE read of
    -- the same table, so any client sending an unknown uid -- which the net
    -- dispatch happily forwards -- indexed a nil value and threw server-side.
    if not isstring(uid) or not hg.PointShop.Items[uid] then
        print(ply, "[PS-ZCity] The player is trying to buy invalid item.", "UID: "..tostring(uid) )
        return
    end

    local item = hg.PointShop.Items[uid]

    if not ply:PS_IsReady() then
        net.Start( "hg_pointshop_send_notificate" )
            net.WriteString( "Your Point Shop profile is still loading." )
        net.Send( ply )
        return
    end

    if ply:PS_HasItem( uid ) then PLUGIN:NET_SendPointShopVars( ply ) return end

    local yes = false
    local reason = ""

    -- The early `if item.ISDONATE then return end` that used to stand above the
    -- nil check also made this branch unreachable, so donate items could never
    -- be bought with the currency that exists for them.
    if item.ISDONATE then
        yes, reason = ply:PS_TakeDPoints(item.PRICE, function() ply:PS_AddItem( uid ) end)
    else
        yes, reason = ply:PS_TakePoints(item.PRICE, function() ply:PS_AddItem( uid ) end)
    end

    net.Start( "hg_pointshop_send_notificate" )
        net.WriteString(reason)
    net.Send( ply )

    PLUGIN:NET_SendPointShopVars( ply )
end

function PLUGIN:NET_GetBuyedItems( ply )
    PLUGIN:NET_SendPointShopVars( ply )
end

net.Receive("hg_pointshop_net",function( _, ply )
    if ply.PSNetCD and ply.PSNetCD > CurTime() then return end

    ply.PSNetCD = CurTime() + 0.2 -- 2026-09-23: was 0.01; the shop never needs 100 requests/s from one client

    local str = net.ReadString()
    local funcstring = PLUGIN[ "NET_" .. str ]

    if not funcstring then print(ply, "[PS-ZCity] Player trying to call an invalid function!", "NAME: "..str ) return end
    local vars = net.ReadTable()
    if table.Count(vars) > 5 then print(ply, "[PS-ZCity] The player is trying to send a bunch of vars to the net.", "NAME: "..str ) return end

    funcstring( PLUGIN, ply, unpack(vars) )
end)

-- !pointshop has been here all along. It was never broken -- it opened a shop that had nothing to show,
-- because every balance was 0 and every item read as unowned, so it looked broken instead.
--
-- Two things it genuinely did not do. It compared the raw text EXACTLY, so "!Pointshop" or a stray trailing
-- space missed; and it never touched txtTbl, so the command was fanned out to everyone as an ordinary chat
-- message. ZChat drops a message whose first slot is empty (zchat/sh_chat.lua:227-232 reads txtTbl[1] back
-- over `text` and returns early when it is ""), which is how a command stops being a thing you said.
--
-- The THIRD argument stays the one tested, deliberately: it is the raw text, while txtTbl[1] is what the
-- rewriting listeners mutate (furrify and the brain-damage garble, sv_comunication.lua:127,133). Matching on
-- the raw text is why a garbled player can still open their own shop.
hook.Add("HG_PlayerSay","OpenPointShop",function(ply, txtTbl, txt)
    if not isstring(txt) then return end
    -- Trimmed and case-folded, but still an EXACT match: "check out !pointshop" is somebody talking, and
    -- swallowing that would delete a real message.
    if string.lower(string.Trim(txt)) ~= "!pointshop" then return end

    ply:ConCommand("hg_pointshop")

    if istable(txtTbl) then txtTbl[1] = "" end
end)

-- Autorefresh re-includes this file on write, with PLUGIN.PlayerInstances
-- surviving in place. Those instances were built by whichever version of the
-- file was loaded before, so they carry no `loaded` flag and every writer would
-- refuse them until the players reconnected. Re-read them from the table that
-- is already open instead. Costs one select per connected player, once, and
-- only when the database is already up.
if PLUGIN.Active then
    for _, ply in ipairs(player.GetHumans()) do
        PLUGIN:LoadPlayer( ply )
    end
end

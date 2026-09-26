if not ulx or not ULib then return end

local CATEGORY = "Persistent Props"

function ulx.persistentpropsmenu(calling_ply)
    net.Start("PersistentProps_RequestList")
    net.Send(calling_ply)
end

local menuCmd = ulx.command(CATEGORY, "ulx persistentpropsmenu", ulx.persistentpropsmenu, "!pprops")
menuCmd:defaultAccess(ULib.ACCESS_ADMIN)
menuCmd:help("Open the persistent prop manager.")

function ulx.persistentpropsreload(calling_ply)
    if not PersistentProps then return end
    PersistentProps:RespawnAll()
    ulx.fancyLogAdmin(calling_ply, "#A reloaded all persistent props for #s", game.GetMap())
end

local reloadCmd = ulx.command(CATEGORY, "ulx persistentpropsreload", ulx.persistentpropsreload, "!ppropsreload")
reloadCmd:defaultAccess(ULib.ACCESS_ADMIN)
reloadCmd:help("Reload all persistent props for the current map.")

function ulx.persistentpropswipe(calling_ply)
    if not PersistentProps then return end
    PersistentProps:WipeMap()
    ulx.fancyLogAdmin(calling_ply, "#A wiped all persistent props for #s", game.GetMap())
end

local wipeCmd = ulx.command(CATEGORY, "ulx persistentpropswipe", ulx.persistentpropswipe, "!ppropswipe")
wipeCmd:defaultAccess(ULib.ACCESS_SUPERADMIN)
wipeCmd:help("Wipe all persistent props for the current map.")

function ulx.persistentpropsremove(calling_ply, id)
    if not PersistentProps then return end

    local ok, err = PersistentProps:RemoveByID(id)
    if not ok then
        ULib.tsayError(calling_ply, "Remove failed: " .. tostring(err), true)
        return
    end

    ulx.fancyLogAdmin(calling_ply, "#A removed persistent prop id #s", tostring(id))
end

local removeCmd = ulx.command(CATEGORY, "ulx persistentpropsremove", ulx.persistentpropsremove, "!ppropsremove")
removeCmd:addParam{type = ULib.cmds.StringArg, hint = "id"}
removeCmd:defaultAccess(ULib.ACCESS_ADMIN)
removeCmd:help("Remove a persistent prop by ID.")

function ulx.persistentpropstel(calling_ply, id)
    if not PersistentProps then return end

    local _, entry = PersistentProps:FindByID(id)
    if not entry then
        ULib.tsayError(calling_ply, "Prop not found.", true)
        return
    end

    calling_ply:SetPos(Vector(entry.pos.x or 0, entry.pos.y or 0, entry.pos.z or 0) + Vector(0, 0, 32))
    ulx.fancyLogAdmin(calling_ply, "#A teleported to persistent prop id #s", tostring(id))
end

local tpCmd = ulx.command(CATEGORY, "ulx persistentpropsteleport", ulx.persistentpropstel, "!ppropstp")
tpCmd:addParam{type = ULib.cmds.StringArg, hint = "id"}
tpCmd:defaultAccess(ULib.ACCESS_ADMIN)
tpCmd:help("Teleport to a persistent prop by ID.")
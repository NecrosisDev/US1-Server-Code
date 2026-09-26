zb = zb or {}

if (CLIENT) then
    local entityMeta = FindMetaTable("Entity")
    local playerMeta = FindMetaTable("Player")

    zb.net = zb.net or {}
    zb.net.globals = zb.net.globals or {}

    net.Receive("zbGlobalVarSet", function()
        local key, var = net.ReadString(), net.ReadType()

    	zb.net.globals[key] = var

        hook.Run("OnGlobalVarSet", key, var)
    end)

    net.Receive("zbNetVarSet", function()
        local index = net.ReadUInt(16)

		local key = net.ReadString()
    	local var = net.ReadType()
		
        zb.net[index] = zb.net[index] or {}
        zb.net[index][key] = var

		-- print(index, key)
		
		if IsValid(Entity(index)) then
			hook.Run("OnNetVarSet", index, key, var)
		else
			zb.net[index].waiting = true
		end
    end)
	
    net.Receive("zbNetVarDelete", function()
    	zb.net[net.ReadUInt(16)] = nil
    end)

    net.Receive("zbLocalVarSet", function()
    	local key = net.ReadString()
    	local var = net.ReadType()

    	zb.net[LocalPlayer():EntIndex()] = zb.net[LocalPlayer():EntIndex()] or {}
    	zb.net[LocalPlayer():EntIndex()][key] = var

    	hook.Run("OnLocalVarSet", key, var)
    end)

    function GetNetVar(key, default) -- luacheck: globals GetNetVar
    	local value = zb.net.globals[key]

    	return value != nil and value or default
    end

    function entityMeta:GetNetVar(key, default)
    	local index = self:EntIndex()

    	if (zb.net[index] and zb.net[index][key] != nil) then
    		return zb.net[index][key]
    	end

    	return default
    end

    playerMeta.GetLocalVar = entityMeta.GetNetVar

	hook.Add("InitPostEntity", "OnRequestFullUpdate_zb", function()
		LocalPlayer():SyncVars()
	end)

	function playerMeta:SyncVars()
		net.Start("ZB_request_fullupdate")
		net.SendToServer()
	end
else
	util.AddNetworkString("ZB_request_fullupdate")

	net.Receive("ZB_request_fullupdate",function(len,ply)
		ply.cooldown_sendnet = ply.cooldown_sendnet or 0
		if ply.cooldown_sendnet < CurTime() then
			ply.cooldown_sendnet = CurTime() + 1

			ply:SyncVars()
		end
	end)

	gameevent.Listen( "OnRequestFullUpdate" )
	hook.Add("OnRequestFullUpdate", "OnRequestFullUpdate_zb", function(data)
		local id = data.userid
		local ply = Player(id)
		
		ply:SyncVars()
	end)
	
	
    local entityMeta = FindMetaTable("Entity")
    local playerMeta = FindMetaTable("Player")

    zb.net = zb.net or {}
    zb.net.list = zb.net.list or {}
    zb.net.locals = zb.net.locals or {}
    zb.net.globals = zb.net.globals or {}

    util.AddNetworkString("zbGlobalVarSet")
    util.AddNetworkString("zbLocalVarSet")
    util.AddNetworkString("zbNetVarSet")
    util.AddNetworkString("zbNetVarDelete")

    local function CheckBadType(name, object)
		return false
    	--[[if (isfunction(object)) then
    		ErrorNoHalt("Net var '" .. name .. "' contains a bad object type!")

    		return true
    	elseif (istable(object)) then
    		for k, v in pairs(object) do
    			if (CheckBadType(name, k) or CheckBadType(name, v)) then
    				return true
    			end
    		end
    	end--]]
    end

    function GetNetVar(key, default)
    	local value = zb.net.globals[key]

    	return value != nil and value or default
    end

    function SetNetVar(key, value, receiver, unreliable)
    	if (CheckBadType(key, value)) then return end
    	--if (GetNetVar(key) == value) then return end
		
    	zb.net.globals[key] = value

    	net.Start("zbGlobalVarSet", unreliable)
    	net.WriteString(key)
    	net.WriteType(value)

    	if (receiver == nil) then
    		net.Broadcast()
    	else
    		net.Send(receiver)
    	end
    end
	
    function playerMeta:SyncVars()
        if ZCWoundQueue then ZCWoundQueue.BeforeSync() end
    	for k, v in pairs(zb.net.globals) do
    		net.Start("zbGlobalVarSet")
    			net.WriteString(k)
    			net.WriteType(v)
    		net.Send(self)
    	end

    	for k, v in pairs(zb.net.locals[self] or {}) do
    		net.Start("zbLocalVarSet")
    			net.WriteString(k)
    			net.WriteType(v)
    		net.Send(self)
    	end

    	for entity, data in pairs(zb.net.list) do
    		if (IsValid(entity)) then
    			local index = entity:EntIndex()

    			for k, v in pairs(data) do
    				net.Start("zbNetVarSet")
    					net.WriteUInt(index, 16)
    					net.WriteString(k)
    					net.WriteType(v)
    				net.Send(self)
    			end
			else
				zb.net.list[entity] = nil
    		end
    	end
    end
	
    function playerMeta:GetLocalVar(key, default)
    	if (zb.net.locals[self] and zb.net.locals[self][key] != nil) then
    		return zb.net.locals[self][key]
    	end

    	return default
    end

    function playerMeta:SetLocalVar(key, value)
    	if (CheckBadType(key, value)) then return end

    	zb.net.locals[self] = zb.net.locals[self] or {}
    	zb.net.locals[self][key] = value

    	net.Start("zbLocalVarSet")
    		net.WriteString(key)
    		net.WriteType(value)
    	net.Send(self)
    end

    function entityMeta:GetNetVar(key, default)
    	if (zb.net.list[self] and zb.net.list[self][key] != nil) then
    		return zb.net.list[self][key]
    	end

    	return default
    end

    function entityMeta:SetNetVar(key, value, receiver)
    	if (CheckBadType(key, value)) then return end

		zb.net.list[self] = zb.net.list[self] or {}

		--if not hg.IsChanged(value, key, zb.net.list[self]) then return end

    	if (zb.net.list[self][key] != value) then
    		zb.net.list[self][key] = value 
    	end
		
		self:SendNetVar(key, receiver)
	end

    -- ZC_WOUND_QUEUE_BEGIN: server-only state publication; wire format unchanged.
    if ZCWoundQueue and ZCWoundQueue.Flush then ZCWoundQueue.Flush() end
    local woundQueueEnabled = CreateConVar("zc_wound_net_queue", "1", FCVAR_ARCHIVE,
        "Coalesce wound broadcasts within a tick and omit repeated empty lists", 0, 1)
    local function weakEntities() return setmetatable({}, {__mode = "k"}) end
    local pendingWounds, emptyWounds = weakEntities(), weakEntities()
    local woundKeys = {wounds = true, arterialwounds = true}
    local woundStats = {requested = 0, queued = 0, coalesced = 0, emptySkipped = 0,
        sent = 0, bytes = 0, fallback = 0, invalidDiscarded = 0}
    ZCWoundQueue = {Version = "20260919.1", Stats = woundStats}

    -- Freeze the requested payload, including mutable Vector/Angle values.
    -- Unknown shapes retain the original immediate send path.
    local function copyWounds(value)
        if not istable(value) or getmetatable(value) then return nil end
        local copy = {}
        for index, wound in pairs(value) do
            if not isnumber(index) or not istable(wound) or getmetatable(wound) then return nil end
            local row = {}
            for field, v in pairs(wound) do
                if not isnumber(field) then return nil end
                if isvector(v) then row[field] = Vector(v.x, v.y, v.z)
                elseif isangle(v) then row[field] = Angle(v.p, v.y, v.r)
                elseif isnumber(v) or isstring(v) or isbool(v) then row[field] = v
                else return nil end
            end
            copy[index] = row
        end
        return copy
    end

    local function sendNetVarNow(entity, key, receiver, value)
        net.Start("zbNetVarSet")
        net.WriteUInt(entity:EntIndex(), 16)
        net.WriteString(key)
        net.WriteType(value)
        local bytes = woundKeys[key] and net.BytesWritten() or 0
        if receiver == nil then net.Broadcast() else net.Send(receiver) end
        if woundKeys[key] then
            woundStats.sent = woundStats.sent + 1
            woundStats.bytes = woundStats.bytes + bytes
            emptyWounds[entity] = emptyWounds[entity] or {}
            -- A targeted update can differ from the last broadcast.
            emptyWounds[entity][key] = receiver == nil and istable(value) and next(value) == nil or nil
        end
    end

    local function sendQueuedWound(entity, key, value)
        if not IsValid(entity) or not zb.net.list[entity] then
            woundStats.invalidDiscarded = woundStats.invalidDiscarded + 1
            return
        end
        if woundQueueEnabled:GetBool() and next(value) == nil and emptyWounds[entity] and emptyWounds[entity][key] then
            woundStats.emptySkipped = woundStats.emptySkipped + 1
            return
        end
        sendNetVarNow(entity, key, nil, value)
    end

    local function flushWound(entity, key)
        local entries = pendingWounds[entity]
        if not entries or entries[key] == nil then return end
        local value = entries[key]
        entries[key] = nil
        if next(entries) == nil then pendingWounds[entity] = nil end
        sendQueuedWound(entity, key, value)
    end

    function ZCWoundQueue.Flush()
        local work = pendingWounds
        pendingWounds = weakEntities()
        for entity, entries in pairs(work) do
            for key, value in pairs(entries) do sendQueuedWound(entity, key, value) end
        end
    end

    function ZCWoundQueue.BeforeSync()
        -- Preserve send ordering: broadcast old pending data before the full
        -- targeted snapshot. Invalidate empty-cache assumptions after a resync.
        ZCWoundQueue.Flush()
        emptyWounds = weakEntities()
    end

    function ZCWoundQueue.Forget(entity)
        pendingWounds[entity], emptyWounds[entity] = nil, nil
    end

    hook.Add("Tick", "ZC_WoundNetFlush", ZCWoundQueue.Flush)

    function entityMeta:SendNetVar(key, receiver)
        local value = zb.net.list[self] and zb.net.list[self][key]
        if woundKeys[key] then
            woundStats.requested = woundStats.requested + 1
            if receiver == nil and woundQueueEnabled:GetBool() then
                local snapshot = copyWounds(value)
                if snapshot then
                    local entries = pendingWounds[self]
                    if not entries then entries = {}; pendingWounds[self] = entries end
                    if entries[key] ~= nil then woundStats.coalesced = woundStats.coalesced + 1 end
                    entries[key] = snapshot
                    woundStats.queued = woundStats.queued + 1
                    return
                end
                woundStats.fallback = woundStats.fallback + 1
            end
            -- Targeted sends, disabling the queue and unsupported payloads
            -- remain immediate and cannot be overwritten by an older queue.
            flushWound(self, key)
        end
        sendNetVarNow(self, key, receiver, value)
    end
    -- ZC_WOUND_QUEUE_END

    function entityMeta:ClearNetVars(receiver)
        if ZCWoundQueue then ZCWoundQueue.Forget(self) end
    	zb.net.list[self] = nil
    	zb.net.locals[self] = nil

    	net.Start("zbNetVarDelete")
    	net.WriteUInt(self:EntIndex(), 16)

    	if (receiver == nil) then
    		net.Broadcast()
    	else
    		net.Send(receiver)
    	end
    end
	
	hook.Add("EntityRemoved","ZB_clear_net",function(ent,fullUpdate)
		ent:ClearNetVars()
	end)

	hook.Add("PlayerDisconnected","ZB_clear_net",function(ply)
		ply:ClearNetVars()
	end)
end
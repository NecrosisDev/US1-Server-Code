-- Native inventory owner: permission first, one physical weapon, then commit.
hg.InventoryWeaponTransfers=hg.InventoryWeaponTransfers or setmetatable({}, {__mode="k"})
local utility={hg_sling=true,hg_flashlight=true,hg_brassknuckles=true}
local function stackOwner(w)
    for _,name in ipairs({"weapon_hg_grenade_tpik","weapon_hg_snowball","weapon_hg_bugbait"}) do
        local owner=weapons.GetStored(name)
        if owner and owner.PickupFunc and w.PickupFunc==owner.PickupFunc then return true end
    end
    return false
end
function hg.TransferInventoryWeapon(ply,ent,class)
    local I=ZCityInteractions
    if not I or not I.CanLoot(ply,ent) or not ent.inventory or not ent.inventory.Weapons
        or not ply.inventory or not ply.inventory.Weapons then return false end
    local inventory=ent.inventory local record=inventory.Weapons[class]
    if not record then return false end
    if ent:IsPlayer() and IsValid(ent:GetActiveWeapon()) and ent:GetActiveWeapon():GetClass()==class then return false end
    if isentity(record) and not IsValid(record) then inventory.Weapons[class]=nil return false end
    local tx={system="inventory",a=ply,v=ent,phase="commit",cancel=function(s) s.cancelled=true end}
    local actors={ply,ent}
    local body=IsValid(ent.FakeRagdoll) and ent.FakeRagdoll
    if body then actors[#actors+1]=body end
    local receiver=I.Receiver(ent)
    if IsValid(receiver) and receiver~=ent then actors[#actors+1]=receiver end
    if not I.Reserve(tx,actors) then return false end
    local sourceLife=I.PolicyLives[ent] or 0 local actorLife=I.PolicyLives[ply] or 0
    local sourceOrg=ent.organism local actorOrg=ply.organism
    local actorInventory=ply.inventory local sourceBody=ent.FakeRagdoll
    local w,created,snapshot,merge,merged,accepted,utilityAttempt
    local reason="The item could not be transferred."
    local function sameSource()
        return IsValid(ent) and ent.inventory==inventory and ent.organism==sourceOrg
            and (I.PolicyLives[ent] or 0)==sourceLife
    end
    local function eligible(detached)
        return not tx.cancelled and sameSource() and IsValid(ply) and ply.organism==actorOrg
            and ply.inventory==actorInventory and ent.FakeRagdoll==sourceBody
            and (I.PolicyLives[ply] or 0)==actorLife
            and (inventory.Weapons[class]==record or (detached and inventory.Weapons[class]==nil))
            and I.CanLoot(ply,ent,tx)
    end
    local ok,err=xpcall(function()
        w=isentity(record) and IsValid(record) and record or (ent:IsPlayer() and ent:GetWeapon(class))
        if not IsValid(w) then
            if not istable(record) and record~=true then return end
            w=ents.Create(class) created=true
            if not IsValid(w) then return end
            if not I.Reserve(tx,{w}) then return end
            w:SetPos(ent:GetPos()) w:SetAngles(ent:GetAngles())
            w.IsSpawned=true w.init=true w:SetNoDraw(true)
            w:Spawn()
            if not IsValid(w) then return end
            w:SetNoDraw(true) w:AddSolidFlags(FSOLID_NOT_SOLID)
            if w.SetInfo and istable(record) then w:SetInfo(record) end
        elseif not I.Reserve(tx,{w}) then return end
        if not IsValid(w) or w:GetClass()~=class or w.NoDrop then return end
        if IsValid(w:GetOwner()) and w:GetOwner()~=ent then return end
        if not w:IsWeapon() then
            if not utility[class] or ply.inventory.Weapons[class] or not eligible() or not w.TakeByPlayer
                or ply:GetNetVar("Inventory",actorInventory)~=actorInventory then return end
            utilityAttempt=true
            w:TakeByPlayer(ply)
            accepted=ply.inventory.Weapons[class]==true and not IsValid(w)
            return
        end
        local existing=ply:GetWeapon(class)
        if IsValid(existing) then
            reason=stackOwner(w) and "Not enough room for the whole stack." or "You already have this weapon."
            if not stackOwner(w) or type(existing.count)~="number" or type(w.count)~="number"
                or existing.count<0 or w.count<=0 or existing.count%1~=0 or w.count%1~=0
                or existing.count+w.count>3 then return end
            merge={weapon=existing,before=existing.count,amount=w.count}
            if not I.Reserve(tx,{existing}) then return end
        elseif w.PickupFunc and not stackOwner(w) then
            reason="This item cannot be taken through inventory."
            return -- unknown consuming pickup functions need their own owner contract
        end
        if not merge and (not hg.weaponInv or not ply.weaponInv or hg.weaponInv.CanInsert(ply,w)==false) then
            reason="Your weapon slots are full." return
        end
        snapshot={owner=w:GetOwner(),parent=w:GetParent(),pos=w:GetPos(),ang=w:GetAngles(),nodraw=w:GetNoDraw(),
            flags=w:GetSolidFlags(),spawned=w.IsSpawned,init=w.init,equip=w.DontEquipInstantly,
            active=ent:IsPlayer() and ent:GetActiveWeapon() or NULL}
        tx.player=ply tx.weapon=w tx.merge=merge~=nil
        hg.InventoryWeaponTransfers[w]=tx
        w.IsSpawned=false w.init=false
        -- PickupWeapon bypasses PlayerCanPickupWeapon in Source. The explicit
        -- check is essential and must happen before detaching or dropping.
        reason="Pickup is blocked."
        if hook.Run("PlayerCanPickupWeapon",ply,w)~=true or not eligible() or not IsValid(w) then return end
        reason="The item could not be transferred."
        if merge then
            if ply:GetWeapon(class)~=merge.weapon or merge.weapon.count~=merge.before or w.count~=merge.amount then return end
            w:PickupFunc(ply)
            merged=IsValid(merge.weapon) and merge.weapon.count==merge.before+merge.amount and (not IsValid(w) or w.count==0)
            accepted=merged
            if merged and IsValid(w) then w:Remove() end
            return
        end
        if ply:HasWeapon(class) or hg.weaponInv.CanInsert(ply,w)==false then return end
        if IsValid(snapshot.owner) and snapshot.owner~=ent then return end
        if snapshot.owner==ent and ent:IsPlayer() then
            ent:DropWeapon(w)
            if not IsValid(w) or IsValid(w:GetOwner()) then return end
        end
        if not eligible(true) or ply:HasWeapon(class) or hg.weaponInv.CanInsert(ply,w)==false then return end
        w:SetParent(NULL) w:SetPos(ent:GetPos()) w:SetAngles(ent:GetAngles())
        w:SetNoDraw(false) w:DrawShadow(true) w:RemoveSolidFlags(FSOLID_NOT_SOLID)
        w.DontEquipInstantly=(not w.NoHolster) and (w.weaponInvCategory~=1)
        ply:PickupWeapon(w)
        accepted=IsValid(w) and w:GetOwner()==ply and ply:GetWeapon(class)==w
    end,debug.traceback)
    -- A callback may throw after Source has already changed ownership.
    local cleanupOK,cleanupErr=xpcall(function()
    accepted=accepted or (IsValid(w) and w:IsWeapon() and w:GetOwner()==ply and ply:GetWeapon(class)==w)
    -- Native utility callbacks grant the inventory flag before cosmetic
    -- effects. Finish that grant if a cosmetic callback then throws.
    if utilityAttempt and ply.inventory==actorInventory and actorInventory.Weapons[class]==true then
        accepted=true
        if IsValid(w) then w:Remove() end
    end
    if merge and IsValid(merge.weapon) and merge.weapon.count==merge.before+merge.amount
        and (not IsValid(w) or w.count==0) then
        accepted=true
        if IsValid(w) then w:Remove() end
    end
    if accepted then
        if inventory.Weapons[class]==record then inventory.Weapons[class]=nil end
        if IsValid(w) then w.IsSpawned=false w.init=false end
    elseif IsValid(w) then
        if IsValid(w:GetOwner()) and w:GetOwner()~=ent then
            -- Another native callback acquired the actual item. Never steal
            -- it back or leave a serialized source that can recreate it.
            if inventory.Weapons[class]==record then inventory.Weapons[class]=nil end
        elseif created then w:Remove()
        elseif snapshot and sameSource() and (inventory.Weapons[class]==nil or inventory.Weapons[class]==record) then
            if snapshot.owner==ent and ent:IsPlayer() and not IsValid(w:GetOwner()) then
                local restored,restoreError=pcall(ent.PickupWeapon,ent,w)
                if not restored then ErrorNoHalt("[Inventory] Restore callback failed: "..tostring(restoreError).."\n") end
                if ent:GetActiveWeapon()==w and IsValid(snapshot.active) and snapshot.active:GetOwner()==ent then
                    ent:SetActiveWeapon(snapshot.active)
                end
            end
            if w:GetOwner()==snapshot.owner or (not IsValid(snapshot.owner) and not IsValid(w:GetOwner())) then
                w:SetParent(snapshot.parent) w:SetPos(snapshot.pos) w:SetAngles(snapshot.ang)
                w:SetNoDraw(snapshot.nodraw) w:DrawShadow(not snapshot.nodraw)
                w:RemoveSolidFlags(w:GetSolidFlags()) w:AddSolidFlags(snapshot.flags)
                w.IsSpawned=snapshot.spawned w.init=snapshot.init w.DontEquipInstantly=snapshot.equip
                if inventory.Weapons[class]==nil or inventory.Weapons[class]==record then inventory.Weapons[class]=record end
            end
        elseif not IsValid(w:GetOwner()) then
            -- A newer source inventory owns the slot now. Preserve this
            -- physical item as a loose drop instead of overwriting that slot
            -- or leaving an unlisted hidden child on a corpse.
            w:SetParent(NULL) w:SetNoDraw(false) w:DrawShadow(true)
            w:RemoveSolidFlags(FSOLID_NOT_SOLID)
            w.IsSpawned=true w.init=true
        end
    elseif isentity(record) and inventory.Weapons[class]==record then
        inventory.Weapons[class]=nil
    end
    end,debug.traceback)
    if w then hg.InventoryWeaponTransfers[w]=nil end
    tx.done=true I.Release(tx)
    if not ok then ErrorNoHalt("[Inventory] Transfer callback failed: "..tostring(err).."\n") end
    if not cleanupOK then ErrorNoHalt("[Inventory] Transfer cleanup failed: "..tostring(cleanupErr).."\n") end
    if accepted and IsValid(w) and not w.DontEquipInstantly then
        timer.Simple(0,function()
            if IsValid(ply) and ply:Alive() and (I.PolicyLives[ply] or 0)==actorLife and I.Available(ply)
                and IsValid(w) and w:GetOwner()==ply and ply:GetWeapon(class)==w then ply:SelectWeapon(class) end
        end)
    end
    return accepted==true,not accepted and reason or nil
end

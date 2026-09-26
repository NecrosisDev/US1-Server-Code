local blackList = {
    ["weapon_hands_sh"] = true,
    ["weapon_zombclaws"] = true
}

local META = getmetatable("PLAYER")
META.inventory = {
    Weapons = {},
    Ammo = {},
    Armor = {},
    Attachments = {}
}
META.armors = {}

function hg.CreateInv(ply)
    ply.inventory = {}
    local inv = ply.inventory
    inv.Weapons = {}
    for i, wep in ipairs(ply:GetWeapons()) do
        if blackList[wep:GetClass()] then continue end
        inv.Weapons[wep:GetClass()] = wep--wep.GetInfo and wep:GetInfo() or true
    end

    inv.Ammo = ply:GetAmmo()
    inv.Armor = {}
    inv.Attachments = {}
    ply:SetNetVar("Inventory", inv)
end

function hg.RenewInv(ply, isDead)
    ply.inventory = ply.inventory or {}
    local inv = ply.inventory
    inv.Weapons = inv.Weapons or {}

    local sling = inv.Weapons["hg_sling"] -- Вот бы все это автоматизировать
    local kastet = inv.Weapons["hg_brassknuckles"]
    local flashlight = inv.Weapons["hg_flashlight"]

    inv.Weapons = {}

    for i, wep in pairs(ply:GetWeapons()) do
        if blackList[wep:GetClass()] then continue end
        if not isDead then
            inv.Weapons[wep:GetClass()] = wep--wep.GetInfo and wep:GetInfo() or true
        else
            ply.nohook = true
            ply:DropWeapon(wep)

            wep:SetNoDraw(true)
            wep:DrawShadow(false)
            wep:AddSolidFlags(FSOLID_NOT_SOLID)

            local rag = ply:GetNWEntity("RagdollDeath")

            if IsValid(rag) then
                wep:SetPos(rag:GetPos()) -- Hidden inventory stays at its parent, not far underground.
                wep:SetParent(rag, 0)
            else
                wep:SetPos(ply:GetPos())
                wep:SetParent(ply, 0)
            end

            inv.Weapons[wep:GetClass()] = wep
        end
    end

    inv.Weapons["hg_sling"] = sling
    inv.Weapons["hg_brassknuckles"] = kastet
    inv.Weapons["hg_flashlight"] = flashlight
    inv.Ammo = ply:GetAmmo()
    inv.Armor = inv.Armor or {}
    inv.Attachments = inv.Attachments or {}
    ply:SetNetVar("Inventory", inv)
end

hook.Add("Player Spawn", "homigrad-inventory", function(ply)
    hg.CreateInv(ply)
    ply.armors = {}
    ply.armors_health = {}
    ply:SyncArmor()
end)

hook.Add("WeaponEquip", "homigrad-inventory", function(wep, ply)
    local inv = ply.inventory or {}
    if blackList[wep:GetClass()] then return end

    wep:SetNoDraw(false)

    inv.Weapons = inv.Weapons or {}
    inv.Weapons[wep:GetClass()] = wep
    
    if wep.sling then
        wep.sling = nil
        if not inv["Weapons"]["hg_sling"] then
            inv["Weapons"]["hg_sling"] = true
            ply:ChatPrint("You took the sling the weapon was attached to.")
        else
            local sling = ents.Create("hg_sling")
            sling:SetPos(ply:EyePos())
            sling:SetVelocity(ply:GetAimVector() * 5)
            sling:Spawn()
            ply:ChatPrint("You deattached the sling the weapon was connected to.")
        end
    end

    ply:SetNetVar("Inventory", inv)
end)

hook.Add("PlayerDroppedWeapon", "homigrad-inventory", function(ply, wep)
    local inv = ply.inventory or {}
    if ply:IsNPC() then return end
    if blackList[wep:GetClass()] then return end
    if not inv.Weapons or not inv.Weapons[wep:GetClass()] then return end
    if ply.nohook then ply.nohook = nil return end
    inv.Weapons[wep:GetClass()] = nil
    ply:SetNetVar("Inventory", inv)
end)

hook.Add("PlayerAmmoChanged", "homigrad-inventory", function(ply,ammoID,oldcount,newcount)
    if not ply.inventory then return end
    ply.inventory.Ammo = ply:GetAmmo()
    ply:SetNetVar("Inventory", ply.inventory)

    -- Reserve clearing/death is not acquisition; its nested callback only updates inventory.
    if game.GetAmmoName(ammoID) == "Grenade" and newcount > oldcount then

        local wep = ply:Give("weapon_hg_hl2nade_tpik")
        if not IsValid(wep) then return end -- Preserve reserve if acquisition fails.
        wep.DontEquipInstantly = true
        wep.count = newcount-oldcount
        ply:SetAmmo(0,ammoID)

        timer.Simple(0.1,function()
            if not IsValid(wep) then return end
            wep.DontEquipInstantly = nil
        end)
    end
end)

local vecZero = Vector(0, 0, 0)
hook.Add("PlayerDropWeapon", "homigrad-inventory", function(ply)
    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) or wep.NoDrop then return end
    local eyeAngles = ply:EyeAngles()
    eyeAngles.x = 0
    local ent = hg.GetCurrentCharacter(ply)
    local bon = ent:LookupBone("ValveBiped.Bip01_R_Hand")

    if wep.RemoveFake then wep:RemoveFake() end
    wep:SetCollisionGroup(COLLISION_GROUP_WORLD)
    ply:DropWeapon(wep, ply:EyePos(), vecZero)
    wep:SetPos(ply:EyePos())
    ply.inventory.Weapons[wep:GetClass()] = nil
    ply:SetNetVar("Inventory", ply.inventory)
    ply:SetActiveWeapon(NULL)

    timer.Simple(0.1,function()
        if not IsValid(wep) then return end
        if not IsValid(ply) then return end
        local ent = IsValid(ply:GetNWEntity("RagdollDeath")) and ply:GetNWEntity("RagdollDeath") or ply.FakeRagdoll
        if not IsValid(ent) then return end
        local bon = ent:LookupBone("ValveBiped.Bip01_R_Hand")
        local handpos,handang = ent:GetPos(),ent:GetAngles()
        if bon then
            local phys = ent:GetPhysicsObjectNum(ent:TranslateBoneToPhysBone(bon))
            if IsValid(phys) then
                handpos = phys:GetPos()
                handang = phys:GetAngles()
            end
        end

        local localpos,localang = LocalToWorld(wep.WorldPos and wep.WorldPos + Vector(3.5,0,0) or vector_origin,wep.WorldAng or angle_zero,handpos,handang)
        localang:RotateAroundAxis(localang:Forward(),180)
        wep:SetPos(localpos)
        wep:SetAngles(localang)
        wep:SetVelocity(vector_origin)
        wep:SetCollisionGroup(COLLISION_GROUP_WEAPON)

        local physbone = ent:TranslateBoneToPhysBone(bon)
        local physbonetorso = ent:TranslateBoneToPhysBone(ent:LookupBone("ValveBiped.Bip01_Spine2"))

        local cons = constraint.Weld(wep, ent, 0, physbone, 600, true, false)

        if math.random(1,10) <= 2 then
            timer.Simple(4, function()
                timer.Simple(0, function()
                    local cons2 = constraint.NoCollide(wep, ent, 0, 0)
                end)
                if IsValid(cons) then
                    cons:Remove()
                    cons = nil
                end
            end)
        end

        local enta = ply:Alive() and (ply.organism and !ply.organism.otrub) and ply or ent
        local inv = enta:GetNetVar("Inventory",{})
        if not inv["Weapons"] then return end
        if inv["Weapons"]["hg_sling"] and ishgweapon(wep) and not wep:IsPistolHoldType() then
            local rope = constraint.Rope(wep,ent,0,physbonetorso,vector_origin,vector_origin,10,5,0,0,"null",true,color_white)
            wep.sling = true
            ent.rope_attach = wep
            inv["Weapons"]["hg_sling"] = nil
            enta:SetNetVar("Inventory",inv)
        end
    end)
end)

hook.Add("PlayerLoadout", "giveHands", function(ply)
    ply:Give("weapon_hands_sh")
    return true
end)

hook.Add("DoPlayerDeath", "homigrad-inventory", function(ply)
    hook.Run("PlayerDropWeapon", ply)
end)

function hg.TransferItems(ply,ragdoll)
	if IsValid(ragdoll) then
		local inv = ply:GetNetVar("Inventory",{})
		--if inv["Weapons"] then
		--	for wep,tbl in pairs(inv["Weapons"]) do
		--		local weapon = weapons.Get(wep)
		--		if weapon and weapon.holsteredBone and not weapon.shouldntDrawHolstered then
		--			tbl[3] = true
		--		end
		--	end
		--end
		ragdoll.inventory = inv
		ragdoll:SetNetVar("Inventory",ragdoll.inventory)
		-- ragdoll:SetNetVar("zb_Scrappers_RaidMoney",ply:GetNetVar("zb_Scrappers_RaidMoney"))

		hg.CreateInv(ply)
		ply:SetNetVar("Inventory",{})
		ply.inventory = ply:GetNetVar("Inventory",{})

        hook.Run("ItemsTransfered",ply,ragdoll)

		ragdoll:SetNetVar("Armor",ply.armors)
		ragdoll.armors = ragdoll:GetNetVar("Armor",{})
		ragdoll:SetNetVar("HideArmorRender", ply:GetNetVar("HideArmorRender", false))
		
		ply:SetNetVar("Armor",{})
		ply.armors = ply:GetNetVar("Armor",{})
		
		hg.SyncWeapons()
	end
end

hook.Add("PostPlayerDeath", "homigrad-inventory", function(ply)
    local ragdoll = ply:GetNWEntity("RagdollDeath")
    hg.RenewInv(ply, true)
    hg.TransferItems(ply, ragdoll)
    ply:SetNetVar("Inventory", ply.inventory)
    ragdoll:SetNetVar("Inventory", ragdoll.inventory)

    --ply:StripWeapons() -- WTF
    ply:SetNetVar("Armor",{})
    ply:SetNetVar("Inventory",{})
    ply:RemoveAllAmmo()
end)

include("homigrad/sv_inventory_transfer.lua")
local functions = {
    ["Weapons"] = function(ply, ent, wep)
        return hg.TransferInventoryWeapon(ply,ent,wep)
    end,
    ["Ammo"] = function(ply, ent, ammo, amt)
        local amt2 = ent.inventory.Ammo[tonumber(ammo)]
        if not amt2 or amt != amt2 then return end

        ply:GiveAmmo(amt2, game.GetAmmoName(ammo), true)
        --ent.inventory.Ammo[tonumber(ammo)] = nil
        if ent:IsPlayer() then
            ent:SetAmmo(0, game.GetAmmoName(ammo))
        else
            ent.inventory.Ammo[tonumber(ammo)] = nil
        end
    end,
    ["Armor"] = function(ply, ent, placement, armor)
        if hg.armor[placement][armor].nodrop then return end
        if (not ent.armors[placement]) or (ent.armors[placement] ~= armor) or ply.armors[placement] then return end
        if !hg.AddArmor(ply, armor) then return end
        ent.armors[placement] = nil

        if placement == "face" and ent:GetNetVar("zableval_masku", false) and armor != "nightvision1" then
            ply:SetNetVar("zableval_masku", true)
            ent:SetNetVar("zableval_masku", false)
        end

        hook.Run("ItemTransfer",ply, ent, placement, armor)
    end,
    ["Attachments"] = function(ply, ent, att)
        att = tonumber(att)
        if not ent.inventory.Attachments[att] then return end
        ply.inventory.Attachments[#ply.inventory.Attachments + 1] = ent.inventory.Attachments[att]
        ent.inventory.Attachments[att] = nil
    end,
    -- ["Money"] = function(ply, ent)
    --     local money = ent:GetNetVar("zb_Scrappers_RaidMoney", 0)
    --     ply:SetNetVar("zb_Scrappers_RaidMoney", ply:GetNetVar("zb_Scrappers_RaidMoney", 0) + money)
    --     ent:SetNetVar("zb_Scrappers_RaidMoney", 0)
    -- end,
}

util.AddNetworkString("ply_take_item")
-- 2026-09-25 loot panel: every well-formed take request gets exactly one answer. Refusals used to be silent while
-- the client removed the tile anyway, so the item "came back" on re-open (reported as dupes and dropped pickups).
-- Malformed requests still get no answer. hg.LootTakeRejects counts refusal reasons; zc_loot_rejects prints them.
util.AddNetworkString("zc_loot_take_result")
hg.LootTakeRejects = hg.LootTakeRejects or {}
local function takeResult(ply, ent, tblIndex, thing, ok, reason, detail, seq)
    if not IsValid(ply) then return end
    if not ok then
        local key = detail and (reason .. " [" .. detail .. "]") or reason
        hg.LootTakeRejects[key] = (hg.LootTakeRejects[key] or 0) + 1
    end
    net.Start("zc_loot_take_result")
    net.WriteEntity(IsValid(ent) and ent or NULL)
    net.WriteString(tblIndex or "")
    net.WriteString(thing or "")
    net.WriteBool(ok == true)
    net.WriteString(reason or "")
    net.WriteUInt(seq or 0, 16)
    net.Send(ply)
end
-- Words for a ZCityInteractions.CanLoot refusal. Mirrors CanLoot's checks for the message only; CanLoot decides.
local function lootRefusal(p, target)
    local I = ZCityInteractions
    local o = p.organism
    if not p:Alive() or not o or o.otrub then return "You can't loot right now." end
    if isfunction(I.Cuffed) and I.Cuffed(p) then return "You can't loot while cuffed." end
    if isfunction(I.Available) and not I.Available(p) then return "You're busy with something else." end
    local left = not o.larmamputated and (o.larm or 0) < .99
    local right = not o.rarmamputated and (o.rarm or 0) < .99
    if not left and not right then return "Your arms are too hurt." end
    local actual = IsValid(target.FakeRagdoll) and target.FakeRagdoll or target
    if isfunction(I.Available) and (not I.Available(target) or not I.Available(actual)) then return "Someone else is handling that." end
    local viewer = IsValid(p.FakeRagdoll) and p.FakeRagdoll or p
    if viewer:GetPos():DistToSqr(actual:GetPos()) > 125 * 125 then return "Too far away." end
    local eye = hg and hg.eye and hg.eye(p) or p:EyePos()
    local tr = util.TraceLine({start = eye, endpos = actual:WorldSpaceCenter(), filter = {p, viewer}, mask = MASK_SOLID})
    if tr.Hit and tr.Entity ~= actual and tr.Entity ~= target then
        return "Something is in the way.", IsValid(tr.Entity) and tr.Entity:GetClass() or "world"
    end
    return "You can't loot that right now."
end
concommand.Add("zc_loot_rejects", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end
    local lines = {}
    for reason, n in pairs(hg.LootTakeRejects) do lines[#lines + 1] = string.format("%6d  %s", n, reason) end
    table.sort(lines, function(a, b) return a > b end)
    local out = "[loot] take refusals since load:\n" .. (#lines > 0 and table.concat(lines, "\n") or "  none") .. "\n"
    if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, out) else print(out) end
end)
net.Receive("ply_take_item", function(len, ply)
    if len>4096 or not IsValid(ply) or not ply:IsPlayer() then return end
    local tblIndex = net.ReadString()
    local thing = net.ReadString()
    local tbl = net.ReadTable()
    local ent = net.ReadEntity()
    local seq = net.ReadUInt(16) -- request id echoed in the reply (0 from clients without the new panel)
    local function refuse(reason, detail) takeResult(ply, ent, tblIndex, thing, false, reason, detail, seq) end

    if (ply.cooldown_takeitem or 0) > CurTime() then
        -- At most two cooldown answers per window; anything beyond that is spam and stays unanswered.
        if ply.loot_cd_window ~= ply.cooldown_takeitem then ply.loot_cd_window, ply.loot_cd_replies = ply.cooldown_takeitem, 0 end
        ply.loot_cd_replies = ply.loot_cd_replies + 1
        if ply.loot_cd_replies <= 2 then refuse("cooldown") end
        return
    end
    ply.cooldown_takeitem = CurTime() + 0.5

    if !IsValid(ent) or !IsValid(ply) then refuse("That's gone.") return end
    if ent:IsPlayer() and not IsValid(ent.FakeRagdoll) then refuse("They got back up.") return end
    if not ZCityInteractions or not ZCityInteractions.CanLoot(ply,ent) then
        if ZCityInteractions then refuse(lootRefusal(ply, ent)) else refuse("You can't loot that right now.") end
        return
    end
    if type(thing)~="string" or #thing>128 or type(tbl)~="table" then return end
    for key in pairs(tbl) do if key~=1 then return end end
    if not ent.inventory or not ply.inventory then refuse("That's gone.") return end
    if tblIndex=="Ammo" then
        local id=tonumber(thing)
        if not id or id~=math.floor(id) or not ent.inventory.Ammo then return end
        if type(tbl[1])~="number" or tbl[1]~=tbl[1] or tbl[1]<=0 or tbl[1]>100000 then return end
        if ent.inventory.Ammo[id]~=tbl[1] then refuse(ent.inventory.Ammo[id] and "The amount changed. Try again." or "Someone already took that.") return end
    elseif tblIndex=="Armor" then
        if type(tbl[1])~="string" or #tbl[1]>128 or not hg.armor[thing] or not hg.armor[thing][tbl[1]] then return end
        if not ent.armors or not ply.armors then refuse("That's gone.") return end
        if ent.armors[thing]~=tbl[1] then refuse("Someone already took that.") return end
        if hg.armor[thing][tbl[1]].nodrop then refuse("That can't be taken.") return end
        if ply.armors[thing] then refuse("You're already wearing armor there.") return end
    elseif tblIndex=="Weapons" then
        if next(tbl) then return end
        if not ent.inventory.Weapons or not ent.inventory.Weapons[thing] then refuse("Someone already took that.") return end
    elseif tblIndex=="Attachments" then
        local id=tonumber(thing)
        if next(tbl) or not id or id~=math.floor(id) or not ent.inventory.Attachments or not ply.inventory.Attachments then return end
        if not ent.inventory.Attachments[id] then refuse("Someone already took that.") return end
    else return end
    local func = functions[tblIndex]
    local ok, why = false, nil
    if func then
        local transferred,reason=func(ply, ent, thing, unpack(tbl))
        if tblIndex=="Weapons" then
            ok, why = transferred==true, reason
        elseif not IsValid(ent) then
            ok = false
        elseif tblIndex=="Ammo" then
            local id=tonumber(thing)
            if ent:IsPlayer() then ok = ent:GetAmmoCount(id)==0 else ok = ent.inventory.Ammo[id]==nil end
        elseif tblIndex=="Armor" then
            ok, why = ent.armors[thing]==nil, "You can't wear that."
        elseif tblIndex=="Attachments" then
            ok = ent.inventory.Attachments[tonumber(thing)]==nil
        end
    end
    if IsValid(ply) and IsValid(ent) then
        ply:SetNetVar("Inventory", ply.inventory)
        ent:SetNetVar("Inventory", ent.inventory)
        ply:SyncArmor()
        ent:SyncArmor()
    end
    if ok then takeResult(ply, ent, tblIndex, thing, true, nil, nil, seq) else refuse(why or "You can't take that right now.") end
end)
-- 2026-09-25 look-at prompt: clients learn which prop models are loot containers (hg.loot_boxes is server-only),
-- so an unopened crate still shows "Search". Sent on join, on request (rate limited) and once after a reload.
util.AddNetworkString("zc_loot_models")
local function sendLootModels(target)
    if not istable(hg.loot_boxes) then return end
    local list = {}
    for model in pairs(hg.loot_boxes) do
        if isstring(model) and #list < 4000 then list[#list + 1] = model end
    end
    net.Start("zc_loot_models")
    net.WriteUInt(#list, 12)
    for _, model in ipairs(list) do net.WriteString(model) end
    if target then net.Send(target) else net.Broadcast() end
end
net.Receive("zc_loot_models", function(len, ply)
    if not IsValid(ply) or (ply.zcLootModelsAt or 0) > CurTime() then return end
    ply.zcLootModelsAt = CurTime() + 10
    sendLootModels(ply)
end)
hook.Add("PlayerInitialSpawn", "ZCLoot.Models", function(ply)
    timer.Simple(5, function() if IsValid(ply) then sendLootModels(ply) end end)
end)
timer.Simple(1, function() sendLootModels() end)

util.AddNetworkString("should_open_inv")
local playerMeta = FindMetaTable("Player")
function playerMeta:OpenInventory(ent)
    hook.Run("ZB_InventoryOpened",self,ent)
    if not IsValid(ent) then return end
    if ent:IsPlayer() and not IsValid(ent.FakeRagdoll) then return end
    if ent:IsPlayer() then hg.RenewInv(ent) end
    if self:IsPlayer() then hg.RenewInv(self) end
    self.cooldown_takeitem = CurTime() + 0.5
    net.Start("should_open_inv")
    net.WriteEntity(ent)
    net.Send(self)
end

function playerMeta:GetLookTrace()
    if not IsValid(self) or not self:Alive() then return end
    local tr = {}
    local ent = IsValid(self.FakeRagdoll) and self.FakeRagdoll or self
    local att = ent:GetAttachment(ent:LookupAttachment("eyes"))
    if not att then return false end
    tr.start = att.Pos
    tr.endpos = att.Pos + self:EyeAngles():Forward() * 80
    tr.filter = ent
    return util.TraceLine(tr)
end

hook.Add("Player Think", "loot-fellows",function(ply)
    if not ply:Alive() then return end
    ply.keypressed = ply.keypressed or false
    --if not ply:GetLookTrace() then return end

    local use = IsValid(ply.FakeRagdoll) and (ply:KeyDown(IN_WALK) and ply:KeyDown(IN_SPEED) and not ply:KeyDown(IN_ATTACK) and not ply:KeyDown(IN_ATTACK2)) or (not IsValid(ply.FakeRagdoll) and (ply:KeyDown(IN_ATTACK2) and ply:KeyDown(IN_USE)))
    
    if use then
        local trace = hg.eyeTrace(ply, 60)
    
        if not trace then return end
        local ent = trace.Entity
        ent = IsValid(hg.RagdollOwner(ent)) and hg.RagdollOwner(ent) or ent
		local _ply, _ent, canloot = hook.Run("ZB_CanLootInventory", ply, ent, canloot)
		if canloot ~= nil and canloot == false then
			ply.keypressed = true
			return
		end
    
        hook.Run("ZB_InventoryChecked", ply, ent)
        
        if not IsValid(ent) or not ent:GetNetVar("Inventory") then return end
        
        if not ply.keypressed then ply:OpenInventory(ent) end
        
        ply.keypressed = true
    else
        ply.keypressed = false
    end
end)

--// Prop inventory example
--[[
	local pos = Entity(1):GetEyeTrace().HitPos
	local ent = ents.Create("prop_physics")
	ent:SetModel("models/props_interiors/Furniture_Desk01a.mdl")
	ent:SetPos(pos)
	ent:Spawn()
	ent.inventory = {}
	local wep = "weapon_ar15"
	local weapon = weapons.Get(wep)
	ent.inventory.Weapons = {[wep] = {30,hg.ClearAttachments(wep)}}
	hg.SetAttachment(ent.inventory.Weapons[wep][2],"supressor2",wep)
	ent:SetNetVar("Inventory",ent.inventory)
]]

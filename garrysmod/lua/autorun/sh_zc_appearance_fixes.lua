-- Appearance content fixes (owner 2026-09-25). Found by the HD-texture audit and confirmed on
-- US1's own file system (work/appearance-hd/README.md):
--  1. Face options whose material does not exist in any mount (e.g. Male 01 "Face 9", Female 04
--     and Female 05 "Face 6") rendered as the missing-texture checkerboard. Both realms drop every
--     facemap entry whose .vmt is missing, so the editor stops offering them and a saved pick falls
--     back to the model's own face.
--  2. Materials that reference a texture that does not exist get a working one (client only). Each
--     fix applies only while the reference is still broken, so a fixed content pack wins.
if SERVER then AddCSLuaFile() end

local removedTotal = 0 -- across passes (load tick + InitPostEntity), for the receipt

local function pruneFacemaps()
    local slots = hg and hg.Appearance and hg.Appearance.FacemapsSlots
    if not istable(slots) then return end
    for _, faces in pairs(slots) do
        if istable(faces) then
            for name, mat in pairs(faces) do
                if isstring(mat) and mat ~= "" and not file.Exists("materials/" .. mat .. ".vmt", "GAME") then
                    faces[name] = nil
                    removedTotal = removedTotal + 1
                end
            end
        end
    end
end

-- material -> { set = { param = texture }, undef = { param }, float = { param = value } }
local BLACKMESA_FACE = {
    -- VMTs point $phongexponenttexture at base_female/femaleface_exponent, which no pack ships.
    -- Use a fixed exponent instead; 9 is what the same pack gives Bill's head.
    undef = { "$phongexponenttexture" }, float = { ["$phongexponent"] = 9 }, check = "$phongexponenttexture",
}
local MATERIAL_FIXES = {
    -- "femle" typo in the pack; the intended female sheet ships with GMod (garrysmod_dir.vpk).
    ["models/humans/female/group01/warpoint_jacket_colorable"] = {
        set = { ["$phongexponenttexture"] = "models/humans/female/group01/players_sheet_phong" }, check = "$phongexponenttexture",
    },
    -- bill_head_normal is in no pack; HL2's flat normal keeps the material's phong working.
    ["models/humans/slav/bill/bill_head"] = { set = { ["$bumpmap"] = "dev/flat_normal" }, check = "$bumpmap" },
}
for _, n in ipairs({ "base_f_d", "base_f_02_d", "base_f_03_d", "base_f_04_d", "base_f_05_d", "base_f_06_d",
                     "base_f_07_d", "base_f_edith_d", "base_f_mia_d", "base_f_wendy_d" }) do
    MATERIAL_FIXES["models/humans/slav/blackmesa/base_female/" .. n] = BLACKMESA_FACE
end

local function fixMaterials()
    local fixed = 0
    for name, fix in pairs(MATERIAL_FIXES) do
        local mat = Material(name)
        local cur = mat and not mat:IsError() and mat:GetTexture(fix.check)
        if mat and not mat:IsError() and (not cur or cur:IsErrorTexture()) then
            for param, tex in pairs(fix.set or {}) do mat:SetTexture(param, tex) end
            for _, param in ipairs(fix.undef or {}) do mat:SetUndefined(param) end
            for param, v in pairs(fix.float or {}) do mat:SetFloat(param, v) end
            mat:Recompute()
            fixed = fixed + 1
        end
    end
    return fixed
end

local function run()
    pruneFacemaps()
    if SERVER then
        file.Write("zc_appearance_fixes_receipt.txt", os.date("!%Y-%m-%d %H:%M:%S") .. " v20260925.1 facemaps_removed="
            .. removedTotal .. "\n")
    else
        fixMaterials()
    end
end

hook.Add("InitPostEntity", "ZCAppearanceFixes", run)
timer.Simple(0, function() pruneFacemaps() end)

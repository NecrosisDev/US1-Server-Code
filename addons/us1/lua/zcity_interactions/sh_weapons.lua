local I=ZCityInteractions
I.WeaponProfiles={}
local function family(kind,names)
    for _,name in ipairs(names) do I.WeaponProfiles[name]={kind=kind} end
end
-- Semantic families, not hold types: native axes, furniture and wire also
-- inherit weapon_melee, and some axes use a pistol hold type.
family("knife",{
    "weapon_melee","weapon_sogknife","weapon_pocketknife","weapon_buck200knife","weapon_ssdagger",
    "weapon_eft_melee_a2607","weapon_eft_melee_a2607d","weapon_eft_melee_6x5",
    "weapon_eft_melee_fulcrum","weapon_eft_melee_cultist","weapon_eft_melee_m2"
})
family("wire",{"weapon_zc_fiberwire_standalone"})
family("hands",{"weapon_hands_sh"})
family("pistol",{
    "weapon_glock17","weapon_glock18c","weapon_glock26","weapon_glock22","weapon_tticglock",
    "weapon_makarov","weapon_makarovpistolpb","weapon_m9beretta","weapon_m9berettacommando",
    "weapon_px4beretta","weapon_hk_usp","weapon_m1911","weapon_fivsevn","weapon_fn45",
    "weapon_grach","weapon_minebeap220","weapon_mauserred9","weapon_conan357","weapon_grizzlymkv",
    "weapon_p22","weapon_mk23","weapon_pernachots","weapon_p38","weapon_cz75sp01","weapon_rugermk4",
    "weapon_deagle","weapon_p99","weapon_browninghp","weapon_rugermk3","weapon_tti2011",
    "weapon_p220","weapon_tokarev","weapon_flintlock","weapon_swmp9","weapon_cz75",
    "weapon_vp9hk","weapon_p320alligator","weapon_hkp7","weapon_pl15","weapon_apsss",
    "weapon_p250","weapon_m70zastavapist","weapon_ppk","weapon_zoraki","weapon_mp-80","weapon_osapb"
})
family("revolver",{
    "weapon_revolver2","weapon_revolver357","weapon_revolver412rex","weapon_python",
    "weapon_revolverswr8","weapon_revolversw686","weapon_revolvermodel29","weapon_revolversh12",
    "weapon_revolverequiem","weapon_magnumbfr","weapon_revolve50bmg"
})
-- These shapes need a different authored grip/contact profile. Keep an
-- explicit reason rather than treating the base class as authorization.
I.UnsupportedWeapons={
    weapon_eft_melee_akula="This push dagger needs a matching grip animation",
    weapon_hg_machete="This blade needs a larger-weapon animation",
    weapon_hg_spear_knife="This polearm needs a two-handed animation",
    wep_hmcd_mansion_knife="This weapon uses a different damage owner"
}
local PISTOL_CATEGORY_PROFILE={kind="pistol"}
function I.WeaponProfile(w)
    if not IsValid(w) then return end
    local profile=I.WeaponProfiles[w:GetClass()]
    if profile then return profile end
    -- The server's handgun SWEPs use this exact authored category. Class
    -- allowlists age immediately when a new pistol is added; the native gun
    -- interface below remains the safety check that excludes props, tools and
    -- melee weapons which merely borrow a pistol hold type.
    if w.Category=="Weapons - Pistols" then return PISTOL_CATEGORY_PROFILE end
end
function I.IsHandgun(w)
    local p=I.WeaponProfile(w)
    return p and (p.kind=="pistol" or p.kind=="revolver") and w.ishgweapon and w.GetTrace and w.PrimaryAttack
end
if CLIENT then return end
local function finite(value,fallback,limit)
    if type(value)~="number" or value~=value or value<0 or value==math.huge then return fallback end
    return math.min(value,limit)
end
function I.KnifeDamage(w)
    return finite(w.DamagePrimary,15,100)
end
function I.WithKnifeProfile(w,fn)
    -- Scope transient native strike fields through nested damage callbacks,
    -- then restore exactly what the weapon owner had before this contact.
    local pen,size,slash,once=w.Penetration,w.PenetrationSize,w.slash,w.attackedOnce
    w.Penetration=finite(w.PenetrationPrimary,8,100)
    w.PenetrationSize=finite(w.PenetrationSizePrimary,.75,10)
    w.slash=false w.attackedOnce=false
    local ok,err=xpcall(fn,debug.traceback)
    if IsValid(w) then
        w.Penetration=pen w.PenetrationSize=size w.slash=slash w.attackedOnce=once
    end
    if not ok then error(err,0) end
end

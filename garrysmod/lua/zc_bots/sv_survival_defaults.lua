-- Plain defaults table folded from Trauma's sh_survival_config.lua. The
-- Derma editor, net broadcast and superadmin-tunable schema are all cut for
-- Phase 1 -- this is just the numbers sv_survival.lua reads, in one place so
-- a later phase can wire an admin command back onto GetSurvivalConfig().

hg = hg or {}
hg.botdriver = hg.botdriver or {}

hg.botdriver.SurvivalDefaults = {
	allow_objective_under_danger = true,
	critical_survival_always_preempts = true,
	survival_preempts_soft = true,

	low_ammo_frac = 0.2,
	bleed_urgent = 15,
	blood_urgent = 3100,
	blood_critical = 2500,
	health_urgent_frac = 0.35,
	stamina_caution_frac = 0.25,
	pain_caution = 20,
	-- Task 4 (2026-09-22): pain high enough to reach for painkillers even with
	-- no bleeding/blood emergency (org.pain scale, see sv_survival.lua's
	-- weapon_painkillers header note). BEHAVIOR CHOICE: no authored reference
	-- value exists for "urgent" on this scale; picked well above pain_caution
	-- (a "slow down" reason) so pain alone only preempts to self-treat once it
	-- is clearly the dominant problem.
	pain_urgent = 50,
	-- Task 4 (2026-09-22): org.satiety (0-100 scale, sv_metabolism.lua) below
	-- this is worth spending a carried consumable on for the passive
	-- blood/health regen bonus -- see sv_survival.lua's NOURISHMENT header note.
	satiety_caution = 25,
	oxygen_caution = 15,

	hostile_near_range = 1200,
	ally_near_range = 900,
	threat_scan_interval = 0.35,
}

function hg.botdriver.GetSurvivalConfig()
	return hg.botdriver.SurvivalDefaults
end

-- GoobOS death panel body view (UI cohesion U1, 2026-09-26): a translucent playermodel with its organs inside, tinted
-- by the damage each hit of this life did, up to the timeline's scrub time.
if not CLIENT then return end
ZCGoobApps = ZCGoobApps or {}
ZCGoobApps.DeathBody = ZCGoobApps.DeathBody or {}

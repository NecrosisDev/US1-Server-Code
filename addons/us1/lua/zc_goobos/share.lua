-- GoobOS share sheet (UI cohesion U2, 2026-09-26): post a killcam clip or a round-replay moment to CityLeak, or copy
-- a chat link for it. ZCGoobApps.Share.Open(spec) is the one entry point (death panel, killcam, Replays, CityLeak).
if not CLIENT then return end
ZCGoobApps = ZCGoobApps or {}
ZCGoobApps.Share = ZCGoobApps.Share or {}

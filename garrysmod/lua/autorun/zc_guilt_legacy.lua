-- Pat's Revamped Punishment (workshop 3685034437), the three files the live server still took ONLY from the workshop item
-- (nativized 2026-09-24): the shared config/net strings, the legacy client menu + admin menu, and the ULX guiltadmin
-- module (lua/ulx/modules/sh/). Its server half has been native since 2026-09-16 (lua/autorun/server/
-- sv_pat_guilt_overhaul.lua == lua/zc_guilt_justice/legacy_server.lua, the Justice-delegating build). Everything is
-- idempotent (ZCITY_GUILT = ZCITY_GUILT or {}; hook ids reused), so this coexists with the workshop item until it is
-- dropped from the collection - after which nothing changes.
include("zc_guilt_legacy/sh_guilt.lua")
if CLIENT then include("zc_guilt_legacy/cl_guilt.lua") end

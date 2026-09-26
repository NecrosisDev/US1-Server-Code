-- ZChat media companion, version 20260922.1
AddCSLuaFile("zc_chat_media/client.lua")
-- Split out of client.lua: AddCSLuaFile silently drops a file over 64KB
-- LZMA-compressed, and the emoji PNGs do not compress.
AddCSLuaFile("zc_chat_media/emoji_extra.lua")
AddCSLuaFile("zc_chat_media/giphy_config.lua")
-- Pulled in here as well as by autorun, so a fresh copy of the report
-- handler loads on autorefresh rather than waiting for a map change.
include("autorun/server/sv_zc_chat_report.lua")

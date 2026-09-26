-- Z-City playtime loader (server). Tracking and the hourly ZPoint reward.
-- No client files: the numbers are networked with SetNWInt instead, so nothing here has to reach a
-- connected client to work (see the note in sv_playtime.lua about the scoreboard column).
include("zc_playtime/sv_playtime.lua")

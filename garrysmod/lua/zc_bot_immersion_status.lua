local D = hg and hg.botdriver
local out = { time = os.time(), map = game.GetMap(), mode = zb and (zb.CROUND_MAIN or zb.CROUND),
    humans = #player.GetHumans(), bots = {}, config = {}, hooks = {} }
for _, name in ipairs({"zc_bots_enable", "zc_bots_chatter", "zc_bots_fill", "zc_bots_name_tag"}) do
    local cv = GetConVar(name)
    out.config[name] = cv and cv:GetString() or "missing"
end
out.personalitySchema = D and D.personalitySchema
out.chatterEpoch = D and D.chatterRuntime and D.chatterRuntime.epoch
out.visualContact = D and D.lib and isfunction(D.lib.VisualContact) or false
out.reactions = isfunction(ZCChatReaction_Register)
out.bench = hg and hg.botfill and isfunction(hg.botfill.AssertBench) or false
for _, spec in ipairs({{"HomigradDamage", "zc_bots_chatter_hurt"}, {"PlayerDeath", "zc_bots_chatter_death"},
    {"PlayerDeath", "zc_bots_chatter_revenge"}, {"ZB_PreRoundStart", "zc_bots_chatter_reset"}}) do
    local fn = (hook.GetTable()[spec[1]] or {})[spec[2]]
    out.hooks[spec[2]] = isfunction(fn) and debug.getinfo(fn, "S").short_src or "missing"
end
for _, bot in ipairs(player.GetBots()) do
    if bot.zcBot then
        local brain = D and D.brains[bot]
        local p = brain and brain.personality
        out.bots[#out.bots + 1] = { name = bot:Nick(), alive = bot:Alive(), benched = bot.zcBotBenched or false,
            archetype = p and p.archetype, style = p and p.chatStyle }
    end
end
file.Write("zc_bot_immersion_status.json", util.TableToJSON(out, true))

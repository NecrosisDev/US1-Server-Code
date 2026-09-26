-- Mostly ordinary conversation; personality comes through word choice, with occasional humor.
if not SERVER then return end
hg.botdriver.socialLines = {
    ["pm_kind"] = {
        ["support"] = {"thanks", "cheers", "ty", "gg", "appreciate it", "yeah, likewise", "hey, thanks. made the round better"},
        ["default"] = {"thanks", "cheers", "ty", "gg", "appreciate it", "yeah, likewise", "appreciate it"},
        ["oldhand"] = {"thanks", "cheers", "ty", "gg", "appreciate it", "yeah, likewise", "cheers"},
        ["hothead"] = {"thanks", "cheers", "ty", "gg", "appreciate it", "yeah, likewise", "respect"},
        ["deadpan"] = {"thanks", "cheers", "ty", "gg", "appreciate it", "yeah, likewise", "a positive review. unusual"},
    },
    ["pm_lost"] = {
        ["support"] = {"nice one", "gg", "yeah fair", "that was clean", "okay fair", "gg, nice one", "good one", "well played", "that was a lovely shot. unfortunately into me"},
        ["tryhard"] = {"good timing", "gg", "yeah fair", "that was clean", "okay fair", "gg, nice one", "good one", "well played", "good timing on that peek"},
        ["deadpan"] = {"fair enough", "gg", "yeah fair", "that was clean", "okay fair", "gg, nice one", "good one", "well played", "excellent. i'm horizontal"},
        ["gremlin"] = {"yeah you got me", "gg", "yeah fair", "that was clean", "okay fair", "gg, nice one", "good one", "well played", "you folded me like a lawn chair"},
        ["hothead"] = {"okay, nice", "gg", "yeah fair", "that was clean", "okay fair", "gg, nice one", "good one", "well played", "fine. that one was good"},
        ["oldhand"] = {"well played", "gg", "yeah fair", "that was clean", "okay fair", "gg, nice one", "good one", "well played", "good shot. shouldn't have offered you that"},
        ["default"] = {"gg", "yeah fair", "that was clean", "okay fair", "gg, nice one", "good one", "well played", "nice shot. annoying, but nice"},
        ["regular"] = {"nice shot", "gg", "yeah fair", "that was clean", "okay fair", "gg, nice one", "good one", "well played", "okay that was clean"},
        ["cautious"] = {"good shot", "gg", "yeah fair", "that was clean", "okay fair", "gg, nice one", "good one", "well played", "i knew i shouldn't peek. did it anyway"},
    },
    ["role_fighter"] = {
        ["default"] = {"the briefing was optimistic", "we have a plan, in the broadest sense", "still accepting sensible suggestions", "this loadout came with no life advice", "cover is doing a lot for my career", "i'd like to finish this with the original number of limbs"},
    },
    ["pm_reply"] = {
        ["support"] = {"could be, yeah", "maybe, yeah", "not sure", "could be", "something like that", "dunno yet", "we will see", "i guess", "i'm going to assume you mean well"},
        ["tryhard"] = {"depends", "maybe, yeah", "not sure", "could be", "something like that", "dunno yet", "we will see", "i guess", "depends on the timing"},
        ["deadpan"] = {"possibly", "maybe, yeah", "not sure", "could be", "something like that", "dunno yet", "we will see", "i guess", "the investigation continues"},
        ["gremlin"] = {"who knows", "maybe, yeah", "not sure", "could be", "something like that", "dunno yet", "we will see", "i guess", "the evidence is mostly vibes"},
        ["hothead"] = {"we will see", "maybe, yeah", "not sure", "could be", "something like that", "dunno yet", "we will see", "i guess", "we'll see"},
        ["oldhand"] = {"hard to say", "maybe, yeah", "not sure", "could be", "something like that", "dunno yet", "we will see", "i guess", "seen it go both ways"},
        ["default"] = {"maybe, yeah", "not sure", "could be", "something like that", "dunno yet", "we will see", "i guess", "could be"},
        ["regular"] = {"maybe", "maybe, yeah", "not sure", "could be", "something like that", "dunno yet", "we will see", "i guess", "yeah, something like that"},
        ["cautious"] = {"not sure honestly", "maybe, yeah", "not sure", "could be", "something like that", "dunno yet", "we will see", "i guess", "maybe. is that the safe answer"},
    },
    ["pm_salt"] = {
        ["support"] = {"fair enough", "rough round", "it happens", "all good", "next round", "no worries", "all good. take a breath"},
        ["gremlin"] = {"fair enough", "rough round", "it happens", "all good", "next round", "no worries", "i'm putting the keyboard down before it gets involved"},
        ["default"] = {"fair enough", "rough round", "it happens", "all good", "next round", "no worries", "rough round. happens"},
        ["deadpan"] = {"fair enough", "rough round", "it happens", "all good", "next round", "no worries", "i'll forward that to the empty suggestion box"},
    },
    ["live_quiet"] = {
        ["default"] = {"little too quiet for my liking", "i miss when my main problem was ammunition", "trying a new route. famous last words", "i'm not lost, just poorly informed", "taking the scenic route against my will", "i have survived several of my own decisions"},
    },
    ["live_door"] = {
        ["default"] = {"this door and i have history now", "door's putting up a better fight than expected", "hold on. negotiating with architecture", "why is the door winning", "one second, building says no", "i'm taking the door personally"},
    },
    ["role_homicide"] = {
        ["default"] = {"everyone's acting normal. hate that", "i'm keeping my opinions very portable", "i trust this room about as far as i can throw it", "great atmosphere. terrible references", "if anyone asks, i was also confused", "very ordinary evening we're having", "going to mind my business aggressively", "i'm sure there's a reasonable explanation. somewhere"},
    },
    ["role_defense"] = {
        ["default"] = {"the job description left some things out", "still here. i'd like credit for that", "holding this place together out of spite", "someone put a chair here, we're staying", "the perimeter has trust issues", "hope this counts as work experience"},
    },
    ["role_criminal"] = {
        ["default"] = {"this plan looked better before we tried it", "i was promised a quieter line of work", "we need a better exit strategy", "nobody put this part in the briefing", "splitting the bill is going to be awkward", "i miss the planning stage. we were so confident"},
    },
    ["pm_won"] = {
        ["support"] = {"gg, nice try", "gg", "well played", "nice try", "gg, good one", "fair play", "good fight", "ggs", "good fight, sorry about the ending"},
        ["tryhard"] = {"gg, well fought", "gg", "well played", "nice try", "gg, good one", "fair play", "good fight", "ggs", "gg. your first peek nearly got me"},
        ["deadpan"] = {"gg then", "gg", "well played", "nice try", "gg, good one", "fair play", "good fight", "ggs", "a rare successful decision"},
        ["gremlin"] = {"gg, i will take it", "gg", "well played", "nice try", "gg, good one", "fair play", "good fight", "ggs", "please don't ask me to do that twice"},
        ["hothead"] = {"good fight", "gg", "well played", "nice try", "gg, good one", "fair play", "good fight", "ggs", "gg. finally got the timing"},
        ["oldhand"] = {"good scrap", "gg", "well played", "nice try", "gg, good one", "fair play", "good fight", "ggs", "good scrap"},
        ["default"] = {"gg", "well played", "nice try", "gg, good one", "fair play", "good fight", "ggs", "gg, that was closer than it looked"},
        ["regular"] = {"gg, well played", "gg", "well played", "nice try", "gg, good one", "fair play", "good fight", "ggs", "gg. i'll pretend that was all intentional"},
        ["cautious"] = {"gg, i needed that", "gg", "well played", "nice try", "gg, good one", "fair play", "good fight", "ggs", "i survived? genuinely checking"},
    },
    ["live_heard"] = {
        ["default"] = {"sounds expensive over there", "somebody is having a much worse conversation", "that did not sound like a warning shot", "the quiet was nice while it lasted", "that's a lot of punctuation", "i'll give that noise a little space"},
    },
    ["spec_reply"] = {
        ["support"] = {"yeah", "same", "fair", "gg", "happens", "next round", "you had the right idea for a moment", "we'll call it a warm-up"},
        ["default"] = {"yeah", "same", "fair", "gg", "happens", "next round", "same, unfortunately", "we're not putting that in the highlights"},
        ["oldhand"] = {"yeah", "same", "fair", "gg", "happens", "next round", "happens to the best of us. and us", "tomorrow's problem is remembering this"},
        ["gremlin"] = {"yeah", "same", "fair", "gg", "happens", "next round", "our combined survival instinct is a screensaver", "put us both in the blooper reel"},
        ["hothead"] = {"yeah", "same", "fair", "gg", "happens", "next round", "don't make me agree with you", "fine, we go again"},
        ["deadpan"] = {"yeah", "same", "fair", "gg", "happens", "next round", "a generous interpretation", "i'll second that for insurance purposes"},
    },
    ["role_police"] = {
        ["default"] = {"the paperwork is going to outlive us", "dispatch gets the edited version", "i would love one routine call", "someone remind me why i took this shift", "report currently says 'it got complicated'", "this is not helping the overtime budget"},
    },
    ["spec_open"] = {
        ["support"] = {"ah well", "gg", "rough one", "okay, next round", "well then", "i'm done for this one", "good effort, questionable survival", "anyone need moral support? that's all i've got"},
        ["tryhard"] = {"ah well", "gg", "rough one", "okay, next round", "well then", "i'm done for this one", "i can see my mistake. all of it", "review complete. should've lived"},
        ["default"] = {"ah well", "gg", "rough one", "okay, next round", "well then", "i'm done for this one", "anyone else die with a full inventory", "spectator has great benefits. no responsibility"},
        ["oldhand"] = {"ah well", "gg", "rough one", "okay, next round", "well then", "i'm done for this one", "same mistake, new round", "used to be better at leaving corners alone"},
        ["deadpan"] = {"ah well", "gg", "rough one", "okay, next round", "well then", "i'm done for this one", "my contribution is now theoretical", "excellent view from unemployment"},
        ["gremlin"] = {"ah well", "gg", "rough one", "okay, next round", "well then", "i'm done for this one", "the floor caught me. real one", "anyone want my inventory? rhetorical question now"},
        ["hothead"] = {"ah well", "gg", "rough one", "okay, next round", "well then", "i'm done for this one", "next round i'm thinking before peeking", "i want a rematch with my own judgement"},
        ["cautious"] = {"ah well", "gg", "rough one", "okay, next round", "well then", "i'm done for this one", "at least nobody can shoot me twice", "this is much better for my blood pressure"},
    },
    ["role_medic"] = {
        ["default"] = {"hold still, i only pretend to know what i'm doing", "medical advice: stop collecting holes", "i cannot bandage your decision making", "one patient at a time, please", "my supplies are finite. your confidence isn't", "let's keep the important bits inside"},
    },
    ["live_hurt"] = {
        ["default"] = {"could use a spare rib. medical kind", "my health is more of a suggestion now", "i'm taking a minute before i become loot", "bandages first, bad decisions later", "nothing important was in that arm, right", "holding myself together with poor judgement"},
    },
    ["role_gang"] = {
        ["default"] = {"this block is terrible for property values", "matching colors, wildly different plans", "the neighborhood meeting got out of hand", "we should have picked a hobby", "our group project has consequences", "i'm reconsidering the commute"},
    },
    ["pm_greeting"] = {
        ["default"] = {"hey", "yo", "hey there", "hiya", "what's up"},
        ["oldhand"] = {"hey there", "evening", "hey", "hi"},
        ["hothead"] = {"yo", "hey", "sup", "yeah?"},
        ["support"] = {"hey :)", "hiya", "hey there", "yo"},
        ["deadpan"] = {"hey", "hello there", "yeah?", "hi"},
    },
    ["pm_apology"] = {
        ["default"] = {"all good", "no worries", "happens", "we're fine", "don't worry about it"},
        ["hothead"] = {"we're good", "all right", "fine, no worries", "happens"},
        ["support"] = {"all good, honestly", "no worries at all", "happens to everyone", "we're good"},
        ["oldhand"] = {"no harm done", "happens", "we're fine", "no worries"},
    },
    ["pm_question"] = {
        ["default"] = {"not sure", "could go either way", "hard to say", "maybe, maybe not", "i wouldn't bet on it"},
        ["tryhard"] = {"depends how it plays out", "could go either way", "not enough to go on", "maybe"},
        ["deadpan"] = {"inconclusive", "not prepared to testify", "could be", "depends"},
        ["cautious"] = {"i'd rather not guess", "not sure", "i wouldn't bet on it", "could go either way"},
    },
    -- WS-chat-realism (C3): a human spamming >= 3 PMs in 60s to an ALIVE bot
    -- gets this once, then the bot goes silent to them for 90s.
    ["pm_busy"] = {
        ["default"] = {"in a fight rn", "1 sec", "busy", "hold on", "mid round lol", "cant talk rn"},
    },
}

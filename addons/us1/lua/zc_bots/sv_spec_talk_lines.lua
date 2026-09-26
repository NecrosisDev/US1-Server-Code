-- Script bank for sv_spec_talk.lua (spectator conversations). Data only.
--
-- Each script: id, weight, cast = { role = predicate }, optional = { role =
-- true } for roles that may go unfilled, turns = { { who = role, say = pool,
-- chance = optional skip chance, about = optional subject role, pause =
-- optional extra think time } }. A pool is a plain list or a table keyed by
-- temperament (any/chill/crude/polite/ragey/gloomy); see sv_spec_talk.lua
-- for placeholders.
--
-- Writing rules for this bank: sound like tired people in dead chat, not
-- like a script. Short lines. Mostly lower case (sv_chat_style.lua reshapes
-- per speaker anyway). No line may reveal anything a dead player could not
-- know. Game tips must be TRUE for this server -- every mechanic mentioned
-- in the "teach" section is cited to the file that implements it.

if not SERVER then return end

local T = hg.botdriver.specTalk
local P = T.pred

local S = {}

----------------------------------------------------------------------
-- Aim: roasting, excuses, the odd compliment
----------------------------------------------------------------------

S[#S + 1] = {
	id = "aim_whiff", weight = 4,
	cast = { a = P.any, b = P.whiffed, c = P.any }, optional = { c = true },
	turns = {
		{ who = "a", say = {
			any = { "{b} how did you miss that", "{b} what were you even shooting at", "{b} you had him bro",
				"{b} was spraying the ceiling", "i watched {b} miss an entire mag", "{b} hit everything except him" },
			crude = { "{b} your aim is fucking tragic", "{b} i watched you miss a whole mag lmao",
				"{b} bro shot the walls to death", "{b} you couldnt hit water if you fell out of a boat" },
			ragey = { "{b} HOW DID YOU MISS", "{b} he was RIGHT THERE", "{b} you had him and you let him walk" },
			polite = { "{b}, you were so close there.", "{b}, unlucky. You nearly had him.", "That was a tough fight, {b}." },
			gloomy = { "at least {b} missed with confidence", "{b} missed like i usually miss", "{b} aimed like me. condolences" },
		} },
		{ who = "b", say = {
			any = { "he was strafing", "my mouse slipped", "i hit him like 3 times", "lag", "shut up",
				"he had armor im telling you", "i was aiming for his legs", "sens was off" },
			crude = { "suck my dick i hit him", "fuck off my sens was off", "i hit that fucker twice",
				"shut the fuck up lmao" },
			ragey = { "I HIT HIM TWICE", "hitreg is broken i swear", "that was NOT a miss", "no way i missed all of that" },
			polite = { "I genuinely thought I hit him.", "Fair, that was not my best.", "My hands were shaking, honestly." },
			gloomy = { "yeah i know. i always do that", "thats just how i am", "i dont even know why i try" },
		} },
		{ who = "a", chance = .75, say = {
			any = { "sure you did", "keep telling yourself that", "lmao", "the ceiling is dead at least",
				"he had armor on his whole body apparently", "ok stormtrooper" },
			crude = { "yeah ok aimbot", "cope harder", "sure buddy lmao" },
			ragey = { "whatever", "unreal" },
			polite = { "It happens to everyone.", "Next round, then." },
		} },
		{ who = "c", chance = .55, say = {
			any = { "lol", "i saw it, it was bad", "he did miss tho", "it was pretty bad ngl", "i was spectating it was painful" },
			crude = { "it was fucking awful i watched it", "lmaooo" },
			polite = { "To be fair, he was moving a lot.", "Go easy on him." },
		} },
	},
}

S[#S + 1] = {
	id = "aim_fragger", weight = 3,
	cast = { a = P.any, b = P.fragger, c = P.any }, optional = { c = true },
	turns = {
		{ who = "a", say = {
			any = { "{b} was popping off that round", "{b} you were actually cracked", "{b} how many did you get",
				"ok {b} was locked in" },
			crude = { "{b} fucking demon", "{b} was going apeshit", "{b} was cheating i fucking swear" },
			ragey = { "{b} is walling. theres no way", "{b} stop sweating" },
			polite = { "{b}, great round honestly.", "Well played, {b}. That was impressive." },
			gloomy = { "{b} did more this round than i will all week" },
		} },
		{ who = "b", say = {
			any = { "lucky", "thanks lol", "i was locked in", "{kills} and then i died anyway", "they kept walking into me" },
			crude = { "im just built different", "they were ass tbh", "hell yeah" },
			ragey = { "and i STILL died", "didnt matter" },
			polite = { "Thanks! Mostly luck.", "Thank you. They kept peeking the same door." },
			gloomy = { "then i died anyway", "doesnt matter. dead now" },
		} },
		{ who = "c", chance = .5, say = {
			any = { "still died tho lol", "carry us next round then", "ok but who killed you", "the one round you dont bottom frag" },
			crude = { "and then got clapped lmao" },
		} },
	},
}

S[#S + 1] = {
	id = "aim_headshot", weight = 3,
	cast = { a = P.any, b = P.headshot },
	turns = {
		{ who = "a", say = {
			any = { "{b} got domed", "that headshot on {b} was clean", "{b} caught one right between the eyes",
				"{b} you got one tapped lol" },
			crude = { "{b} got his shit pushed in", "{b} got his head popped like a grape", "{b} ate that one with his face" },
			ragey = { "{b} how did you not see him", "{b} you walked right into it" },
			polite = { "{b}, that was a very clean shot on you.", "Unlucky, {b}." },
			gloomy = { "{b} went out quick at least", "at least it was painless {b}" },
		} },
		{ who = "b", say = {
			any = { "didnt even see him", "one tap wtf", "i was mid turn", "{killer} was just waiting there", "he prefired me" },
			crude = { "fuck {killer} honestly", "i didnt see shit", "{killer} is a camping bastard" },
			ragey = { "HEADSHOT THROUGH ALL THAT?", "{killer} is locked on i swear", "that hit my shoulder on my screen" },
			polite = { "It was a very good shot, to be fair.", "Credit to {killer}, honestly." },
			gloomy = { "didnt even hurt", "one of my better deaths", "yeah that's about right" },
		} },
		{ who = "a", chance = .6, say = {
			any = { "should have been crouching", "he was holding that door the whole time", "check your corners next time",
				"that door is always held" },
			crude = { "stop walking face first into doors dumbass" },
			polite = { "That doorway is always watched, I've learned that too." },
		} },
	},
}

S[#S + 1] = {
	id = "aim_longshot", weight = 2,
	cast = { a = P.any, b = P.longshot },
	turns = {
		{ who = "b", say = {
			any = { "where did that even come from", "i got shot from the other side of the map", "{killer} is sniping from spawn" },
			crude = { "who the fuck shot me from narnia", "{killer} is a sniping rat" },
			ragey = { "FROM WHERE", "that range is stupid" },
			polite = { "I have no idea where that came from.", "That was an absurd distance." },
			gloomy = { "didnt even see it coming. relatable" },
		} },
		{ who = "a", say = {
			any = { "{killer} was on the roof", "he was across the street", "you were crossing open ground bro",
				"thats what you get for running in the open" },
			crude = { "you ran across the open like a fucking deer" },
			polite = { "You were in the open for quite a while, to be fair." },
		} },
		{ who = "b", chance = .6, say = {
			any = { "ok noted", "i hate this map", "next time im hugging walls", "whatever" },
			ragey = { "i hate snipers so much" },
		} },
	},
}

----------------------------------------------------------------------
-- How you died: reloading, healing, falling, melee, speed
----------------------------------------------------------------------

S[#S + 1] = {
	id = "death_reloading", weight = 3,
	cast = { a = P.any, b = P.reloading, c = P.any }, optional = { c = true },
	turns = {
		{ who = "a", say = {
			any = { "{b} reloading in the open again", "bro reloaded with him right there", "{b} why were you reloading",
				"{b} died mid reload lmao" },
			crude = { "who the fuck reloads in the middle of the street {b}", "{b} reloaded like he had all day" },
			ragey = { "{b} WHY WOULD YOU RELOAD THERE" },
			polite = { "{b}, unlucky timing on that reload.", "That reload came at a bad moment, {b}." },
			gloomy = { "{b} died reloading. peak human behavior" },
		} },
		{ who = "b", say = {
			any = { "i had like 2 bullets", "i thought he was dead", "i was behind cover i swear", "it was empty ok" },
			crude = { "i had no fucking bullets what was i supposed to do", "fuck off it was empty" },
			ragey = { "IT WAS EMPTY", "i couldnt do anything else" },
			polite = { "I really had nothing left in it.", "I thought I had more time." },
			gloomy = { "i always do that", "yeah. classic" },
		} },
		{ who = "a", say = {
			any = { "pull your pistol if hes close", "swap to your sidearm next time", "get behind something first then reload",
				"back off and reload, dont stand there", "if hes that close just swap weapons" },
			crude = { "pull your pistol you dumbass", "swap to your sidearm like a normal person" },
			polite = { "Switching to a pistol is usually faster when they're close.", "Reload behind cover, it helps." },
		} },
		{ who = "c", chance = .4, say = {
			any = { "or kick him lol", "ive died like that so many times", "tactical reload moment" },
			crude = { "or just punch him idk" },
		} },
	},
}

S[#S + 1] = {
	id = "death_healing", weight = 2,
	cast = { a = P.any, b = P.healing },
	turns = {
		{ who = "a", say = {
			any = { "{b} died bandaging lmao", "{b} was patching up in the middle of the room", "{b} got shot mid bandage" },
			crude = { "{b} died wrapping his little booboo lmao", "{b} bandaging in the open like a dumbass" },
			polite = { "{b}, sorry, that was an awful time to get caught." },
			gloomy = { "{b} tried to heal. the game said no" },
		} },
		{ who = "b", say = {
			any = { "i was bleeding out", "i had no choice", "i thought i was safe", "i was losing so much blood" },
			crude = { "i was bleeding like a stuck pig", "i was gonna die anyway fuck it" },
			ragey = { "I WAS BLEEDING OUT WHAT DO YOU WANT" },
			polite = { "I was losing a lot of blood, to be fair.", "I thought I'd cleared the area." },
			gloomy = { "was gonna die either way" },
		} },
		{ who = "a", say = {
			any = { "heal behind a door at least", "shoot him first then heal", "go somewhere with one entrance to heal",
				"crouch in a corner and do it, you were in the open" },
			polite = { "Behind a closed door is safer for that." },
		} },
	},
}

S[#S + 1] = {
	id = "death_fell", weight = 2,
	cast = { a = P.any, b = P.fell, c = P.any }, optional = { c = true },
	turns = {
		{ who = "a", say = {
			any = { "did {b} just die to gravity", "{b} fell off something lmao", "{b} lost to the floor" },
			crude = { "{b} fucking yeeted himself off a ledge", "{b} got killed by the floor lmaooo" },
			polite = { "{b}, are you alright? That was quite a fall." },
			gloomy = { "{b} found the fastest way out. respect" },
		} },
		{ who = "b", say = {
			any = { "i thought i could make it", "it was like one floor", "fall damage is insane here", "my legs just gave up" },
			crude = { "fall damage in this game is fucking stupid" },
			ragey = { "IT WAS ONE FLOOR" },
			gloomy = { "i meant to do that" },
		} },
		{ who = "c", chance = .6, say = {
			any = { "you break your legs so easy here", "fall damage here is no joke", "you gotta crouch jump down stuff" },
		} },
	},
}

S[#S + 1] = {
	id = "death_selfkill", weight = 1,
	cast = { a = P.any, b = P.selfkill },
	turns = {
		{ who = "a", say = {
			any = { "{b} how did you kill yourself", "{b} died to nobody", "no one even shot {b}" },
			crude = { "{b} killed himself lmfao" },
		} },
		{ who = "b", say = {
			any = { "i dont want to talk about it", "no comment", "long story", "i panicked" },
			gloomy = { "honestly saved everyone the trouble" },
		} },
	},
}

S[#S + 1] = {
	id = "death_melee", weight = 2,
	cast = { a = P.any, b = P.melee },
	turns = {
		{ who = "a", say = {
			any = { "{b} got beat to death lol", "{b} got meleed", "{b} lost a knife fight" },
			crude = { "{b} got his ass beat", "{b} got bonked to death lmao" },
			polite = { "{b}, that looked painful." },
		} },
		{ who = "b", say = {
			any = { "he came out of nowhere", "i was holding a gun too", "i couldnt turn fast enough" },
			crude = { "fucker ran up on me" },
			ragey = { "I SHOT HIM FIRST" },
			gloomy = { "didnt even fight back. typical" },
		} },
		{ who = "a", chance = .5, say = {
			any = { "just kick them when they get close", "you gotta back up when theyre that close", "bash him with the gun" },
		} },
	},
}

S[#S + 1] = {
	id = "death_speedrun", weight = 3,
	cast = { a = P.any, b = P.shortLife, c = P.any }, optional = { c = true },
	turns = {
		{ who = "a", say = {
			any = { "{b} died in like {life} seconds", "new record {b}", "{b} barely left spawn", "{b} speedrunning death" },
			crude = { "{b} fucking speedran that", "{b} lasted {life} seconds lmao" },
			ragey = { "{b} you were alive for {life} SECONDS" },
			polite = { "{b}, that was a short one. Unlucky." },
			gloomy = { "{b} had the right idea" },
		} },
		{ who = "b", say = {
			any = { "spawn was cursed", "i didnt even get to move", "i walked out the door and died", "i blinked" },
			crude = { "i walked out and got fucking deleted" },
			ragey = { "i didnt even SEE anyone" },
			polite = { "I barely made it out the door." },
			gloomy = { "thats my usual", "honestly thats longer than normal for me" },
		} },
		{ who = "c", chance = .6, say = {
			any = { "same tbh", "we all died fast this round", "at least you didnt die first", "i died faster lol" },
		} },
	},
}

S[#S + 1] = {
	id = "death_survivor", weight = 2,
	cast = { a = P.any, b = P.longLife },
	turns = {
		{ who = "a", say = {
			any = { "{b} where were you all round", "{b} was hiding the whole time", "{b} where were you camping" },
			crude = { "{b} was camping in a closet the whole fucking round" },
			polite = { "{b}, you survived a long time there." },
		} },
		{ who = "b", say = {
			any = { "playing it safe", "i was holding a room", "its called survival", "someone had to live" },
			crude = { "its called not being a dumbass" },
			gloomy = { "didnt matter in the end" },
		} },
	},
}

----------------------------------------------------------------------
-- Grudges between the dead: who killed whom, teamkills
----------------------------------------------------------------------

S[#S + 1] = {
	id = "grudge_killed_each_other", weight = 4,
	cast = { a = P.any, b = P.victimOf("a"), c = P.any }, optional = { c = true },
	turns = {
		{ who = "b", say = {
			any = { "{a} really shot me", "{a} what was that", "thanks {a}", "{a} you camping bastard",
				"{a} of all people" },
			crude = { "{a} you fucking rat", "{a} eat shit for that one", "{a} you camping piece of shit" },
			ragey = { "{a} WHY", "{a} you coward", "{a} really waited behind that door huh" },
			polite = { "{a}, well played. That was a good angle.", "Nice shot earlier, {a}." },
			gloomy = { "{a} put me out of my misery. thanks", "at least it was {a}" },
		} },
		{ who = "a", say = {
			any = { "you were in my way", "you had it coming", "nothing personal", "you ran right at me", "its called holding an angle" },
			crude = { "get fucked lmao", "you walked into it dumbass", "skill issue" },
			ragey = { "you peeked ME", "what was i supposed to do" },
			polite = { "Sorry! You surprised me.", "Nothing personal, I promise." },
			gloomy = { "i died right after if it helps", "dont worry, karma got me" },
		} },
		{ who = "b", chance = .8, say = {
			any = { "ok camper", "i was literally about to leave", "i saw you first", "whatever", "rematch next round" },
			crude = { "ok rat", "fuck you next round then" },
			ragey = { "you got lucky", "i was lagging" },
			polite = { "Fair enough.", "I'll get you next time." },
		} },
		{ who = "a", chance = .5, say = {
			any = { "sure", "see you next round", "keep crying", "lol" },
			crude = { "cry more" },
			polite = { "Looking forward to it." },
		} },
		{ who = "c", chance = .45, say = {
			any = { "lmao drama", "just kiss already", "both of you died so who cares", "can you two get a room" },
			crude = { "both of yall are ass", "fight fight fight" },
			polite = { "You both died, so I'd call it even." },
		} },
	},
}

S[#S + 1] = {
	id = "grudge_teamkill", weight = 4,
	cast = { a = P.any, b = P.teamkilled, c = P.killerOf("b") }, optional = { c = true },
	turns = {
		{ who = "a", say = {
			any = { "{b} got teamkilled lol", "who killed {b}", "{b} got shot by his own team" },
			crude = { "{b} got fucking betrayed", "{b} got capped by his own guy lmao" },
			polite = { "{b}, sorry, that was friendly fire wasn't it." },
		} },
		{ who = "b", say = {
			any = { "by my own team", "{killer} shot me in the back", "{killer} cant tell colors apparently" },
			crude = { "{killer} fucking shot me", "{killer} is a traitor piece of shit" },
			ragey = { "BY MY OWN TEAM", "{killer} ARE YOU BLIND" },
			polite = { "{killer} shot me. I'm sure it was an accident.", "Friendly fire. It happens." },
			gloomy = { "even my team wants me dead" },
		} },
		{ who = "c", say = {
			any = { "you ran in front of me", "my bad", "you peeked my shot", "i thought you were one of them", "you moved" },
			crude = { "you ran right into my fucking bullets" },
			ragey = { "you walked INTO my shot" },
			polite = { "I'm really sorry, you stepped into my line.", "My fault, sorry." },
			gloomy = { "yeah that was me. sorry. i ruin things" },
		} },
		{ who = "b", chance = .7, say = {
			any = { "i was there first", "check your target", "watch your lane", "whatever" },
			crude = { "learn to fucking aim" },
			ragey = { "unbelievable" },
			polite = { "It's fine, don't worry about it." },
		} },
	},
}

----------------------------------------------------------------------
-- Personalities
----------------------------------------------------------------------

S[#S + 1] = {
	id = "persona_tidy", weight = 3,
	cast = { a = P.temper("crude", "chill", "ragey"), b = P.tidyWriter, c = P.any }, optional = { c = true },
	turns = {
		{ who = "a", say = {
			any = { "{b} why do you type like a teacher", "{b} uses full stops in game chat", "{b} types like hes writing an email",
				"why does {b} capitalize everything" },
			crude = { "{b} talks like a fucking butler", "{b} types like a serial killer with those periods" },
			ragey = { "{b} stop typing like my boss" },
		} },
		{ who = "b", say = {
			any = { "Some of us were raised properly.", "Punctuation is free.", "I just like reading what I wrote.",
				"It takes one extra second." },
		} },
		{ who = "a", say = {
			any = { "nerd", "ok grandma", "sir this is a video game", "lmao" },
			crude = { "fuckin nerd", "ok professor" },
		} },
		{ who = "c", chance = .5, say = {
			any = { "leave him alone hes the only normal one here", "tbh i respect it", "{b} is the only one here with a job" },
			crude = { "{b} probably irons his socks" },
			polite = { "I appreciate it, {b}." },
		} },
	},
}

S[#S + 1] = {
	id = "persona_ragey", weight = 3,
	cast = { a = P.temper("chill", "polite", "crude", "gloomy"), b = P.temper("ragey"), c = P.any }, optional = { c = true },
	turns = {
		{ who = "a", say = {
			any = { "{b} calm down its a game", "{b} is gonna break his keyboard", "who pissed in {b}s cereal", "{b} you ok bro",
				"{b} has been mad all night" },
			crude = { "{b} take a fucking breath lmao", "{b} is one death away from punching his monitor" },
			polite = { "{b}, it's only a game, you know.", "{b}, maybe take a short break?" },
			gloomy = { "{b} has more energy than me. even if its anger" },
		} },
		{ who = "b", say = {
			any = { "IM CALM", "im not mad", "shut up", "im fine", "i am completely calm", "i'm NOT yelling" },
		} },
		{ who = "a", say = {
			any = { "you typed that in caps", "sure buddy", "sounds calm", "lmao ok" },
			crude = { "yeah ok psycho" },
			polite = { "Of course. Sorry." },
		} },
		{ who = "c", chance = .5, say = {
			any = { "{b} has been mad since tuesday", "let him rage its entertaining", "{b} is always like this lol" },
			crude = { "{b} gets angrier than my dad" },
		} },
	},
}

S[#S + 1] = {
	id = "persona_gloomy", weight = 3,
	cast = { a = P.temper("chill", "polite", "crude"), b = P.temper("gloomy") },
	turns = {
		{ who = "a", say = {
			any = { "{b} you good bro", "{b} why are you always so down", "{b} sounds like he needs a hug", "{b} you sound tired man" },
			crude = { "{b} cheer up you sad fuck lol", "{b} who hurt you" },
			polite = { "{b}, you alright? You seem a bit down.", "{b}, you're doing better than you think." },
		} },
		{ who = "b", say = {
			any = { "im fine", "its just a game. like everything else", "nothing matters anyway", "im not good at anything so",
				"this is the most social ive been all week", "yeah. dont worry about it" },
		} },
		{ who = "a", say = {
			any = { "damn ok", "you got a kill earlier though", "its ok bro we all suck", "we should play together next round" },
			crude = { "bro we all suck its fine", "same tbh lmao" },
			polite = { "Well, I enjoy playing with you.", "Stick with me next round, we'll do alright." },
		} },
		{ who = "b", chance = .7, say = {
			any = { "thanks i guess", "ok", "maybe", "that's nice of you" },
		} },
	},
}

S[#S + 1] = {
	id = "persona_crude", weight = 3,
	cast = { a = P.temper("polite", "chill", "gloomy"), b = P.temper("crude"), c = P.any }, optional = { c = true },
	turns = {
		{ who = "a", say = {
			any = { "{b} say fuck one more time", "{b} there might be kids here", "{b} do you ever stop swearing" },
			polite = { "{b}, is the swearing really necessary?", "{b}, some of us are eating." },
			gloomy = { "{b} swears like it's his job" },
		} },
		{ who = "b", say = {
			any = { "fuck yes it is", "fuck", "its a fucking video game", "no fucking idea what youre talking about", "fuck off lmao" },
		} },
		{ who = "a", say = {
			any = { "unbelievable", "every single time", "incredible", "i asked for that" },
			polite = { "Right. Of course." },
		} },
		{ who = "c", chance = .5, say = {
			any = { "lmaooo", "{b} is a poet", "honestly respect it" },
			crude = { "fuckin based" },
		} },
	},
}

S[#S + 1] = {
	id = "persona_laggy", weight = 2,
	cast = { a = P.any, b = P.archetype("laggy"), c = P.any }, optional = { c = true },
	turns = {
		{ who = "a", say = {
			any = { "{b} your ping is insane", "{b} you were teleporting all round", "{b} is playing from the moon" },
			crude = { "{b} is playing on a fucking potato", "{b} fix your internet dude" },
			polite = { "{b}, your connection looked rough this round." },
		} },
		{ who = "b", say = {
			any = { "im on hotel wifi", "my router is dying", "someone is streaming in my house", "its not my fault",
				"i shot first on my screen" },
		} },
		{ who = "c", chance = .6, say = {
			any = { "lagswitch confirmed", "plug in an ethernet cable bro", "restart your router lol" },
			crude = { "lagswitching ass" },
		} },
	},
}

S[#S + 1] = {
	id = "persona_tryhard", weight = 2,
	cast = { a = P.temper("chill", "crude", "gloomy"), b = P.archetype("tryhard") },
	turns = {
		{ who = "a", say = {
			any = { "{b} is sweating so hard rn", "{b} takes this way too serious", "{b} plays like theres money on it" },
			crude = { "{b} sweaty ass", "{b} bro its a fucking casual server" },
		} },
		{ who = "b", say = {
			any = { "its called trying", "some of us like winning", "im just good", "you could try it sometime" },
			crude = { "cope" },
			polite = { "I just enjoy playing well." },
		} },
		{ who = "a", chance = .7, say = {
			any = { "you still died", "and yet here you are in spectator", "ok pro" },
		} },
	},
}

S[#S + 1] = {
	id = "persona_polite_vs_crude", weight = 2,
	cast = { a = P.temper("crude"), b = P.temper("polite") },
	turns = {
		{ who = "a", say = { "{b} why are you so nice all the time its creepy", "{b} you ever been mad in your life",
			"{b} say something mean i dare you" } },
		{ who = "b", say = { "I just don't see the point in being rude.", "I have been mad. Privately.", "No thank you." } },
		{ who = "a", say = { "fucking saint over here", "thats so weird man", "one day im gonna make you swear" } },
		{ who = "b", chance = .6, say = { "Good luck with that.", "We'll see.", "Heck." } },
	},
}

----------------------------------------------------------------------
-- Petty arguments
----------------------------------------------------------------------

S[#S + 1] = {
	id = "petty_shotguns", weight = 2,
	cast = { a = P.any, b = P.any, c = P.any }, optional = { c = true },
	turns = {
		{ who = "a", say = {
			any = { "shotguns are so broken in this game", "whoever balanced shotguns here needs help" },
			crude = { "shotguns in this game are fucking bullshit" },
			ragey = { "SHOTGUNS ARE BROKEN" },
		} },
		{ who = "b", say = {
			any = { "skill issue", "just dont get close to them", "theyre fine", "you just keep running into rooms" },
			crude = { "stop running at them then dumbass" },
			polite = { "They're only strong up close, to be fair." },
		} },
		{ who = "a", say = {
			any = { "easy for you to say", "you literally only use shotguns", "they one shot from across the room" },
			ragey = { "IT ONE SHOT ME FROM ACROSS THE ROOM" },
		} },
		{ who = "b", say = {
			any = { "because theyre good", "and?", "sounds like a you problem" },
			crude = { "and? cry about it" },
		} },
		{ who = "c", chance = .5, say = {
			any = { "rifles > everything", "pump ones take forever to reload tho", "the pump ones you have to hold r to load more than one shell",
				"kicking people is better than both" },
		} },
	},
}

S[#S + 1] = {
	id = "petty_killsteal", weight = 2,
	cast = { a = P.any, b = P.fragger, c = P.any }, optional = { c = true },
	turns = {
		{ who = "a", say = {
			any = { "{b} stole my kill", "{b} you took my kill earlier", "i had that guy one shot {b}" },
			crude = { "{b} you kill stealing little shit" },
			ragey = { "{b} THAT WAS MY KILL" },
		} },
		{ who = "b", say = {
			any = { "you werent gonna get it", "should have shot faster", "there are no kill steals only kill secures", "finders keepers" },
			crude = { "shoulda shot faster bitch" },
			polite = { "Sorry, I didn't know you were on him." },
		} },
		{ who = "a", say = {
			any = { "i had him", "unbelievable", "every time", "ok", "i did all the damage" },
			ragey = { "I DID ALL THE DAMAGE" },
		} },
		{ who = "c", chance = .5, say = { "kill stealing is a crime on this server", "you both died so", "lol", "it counts for nothing anyway" } },
	},
}

S[#S + 1] = {
	id = "petty_loot", weight = 2,
	cast = { a = P.any, b = P.any, c = P.any }, optional = { c = true },
	turns = {
		{ who = "a", say = {
			any = { "{b} took the gun i was going for", "{b} you stole my gun earlier", "{b} i was literally walking to that gun" },
			crude = { "{b} you snaked my fucking gun" },
		} },
		{ who = "b", say = {
			any = { "finders keepers", "walk faster", "it didnt have your name on it", "i needed it more" },
			crude = { "walk faster then" },
			polite = { "Oh, sorry. I didn't see you." },
			gloomy = { "didnt help me anyway" },
		} },
		{ who = "a", say = { "i was RIGHT there", "you saw me", "unbelievable", "whatever. dead now anyway" } },
		{ who = "c", chance = .45, say = { "just loot a body next time", "theres always stuff on bodies", "lmao", "you both died with it so" } },
	},
}

S[#S + 1] = {
	id = "petty_map", weight = 2,
	cast = { a = P.any, b = P.any, c = P.any }, optional = { c = true },
	turns = {
		{ who = "a", say = {
			any = { "who voted for this map", "this map is a maze", "i still get lost on this map" },
			crude = { "who the fuck picked this map", "this map is ass" },
			ragey = { "i HATE this map" },
			gloomy = { "i get lost on every map honestly" },
		} },
		{ who = "b", say = { "me", "its a good map", "learn the map then", "you say that every time", "its fine once you know it" } },
		{ who = "a", say = { "its all hallways", "every door is a death trap", "why would you vote for this", "ok" } },
		{ who = "c", chance = .5, say = { "vote a different one next time then", "the doors are the worst part", "at least its not the other one" } },
	},
}

S[#S + 1] = {
	id = "petty_first_death", weight = 2,
	cast = { a = P.any, b = P.any, c = P.any },
	turns = {
		{ who = "a", say = { "who died first this round", "ok who died first", "who was first in spectator" } },
		{ who = "b", say = { "{c} did", "not me", "{c} lol" } },
		{ who = "c", say = {
			any = { "i did not", "no i wasnt", "lies", "i was like third" },
			ragey = { "NO I WASNT" },
			gloomy = { "yeah it was me. its always me" },
			polite = { "I believe that was me, yes." },
		} },
		{ who = "b", chance = .7, say = { "you literally were", "i watched it happen", "sure", "the killfeed says otherwise" } },
	},
}

----------------------------------------------------------------------
-- Watching the living, and dead-chat small talk
----------------------------------------------------------------------

S[#S + 1] = {
	id = "watch_survivor", weight = 2,
	cast = { a = P.any, b = P.any },
	turns = {
		{ who = "a", say = { "whos still alive", "how many left", "who are you guys watching" } },
		{ who = "b", say = {
			any = { "watching {live}", "{live} is still up", "{live} is just crouching in a corner lol", "{live} has been hiding forever" },
			crude = { "{live} is camping like a little rat" },
		} },
		{ who = "a", say = { "is he good", "hope he wins", "hope he dies lol", "hes gonna die", "he better not bottle this" } },
		{ who = "b", chance = .7, say = { "hes ok", "no", "kinda", "he has like no health", "honestly yeah" } },
	},
}

S[#S + 1] = {
	id = "chat_hours", weight = 1,
	cast = { a = P.temper("gloomy", "chill"), b = P.any, c = P.any }, optional = { c = true },
	turns = {
		{ who = "a", say = { "i have like 400 hours in this and i still die first", "how do people get good at this",
			"i swear i get worse every week" } },
		{ who = "b", say = { "thats commitment", "same honestly", "you just gotta stop peeking everything", "play slower" } },
		{ who = "c", chance = .6, say = { "400 hours of dying", "at least youre consistent", "same bro" } },
	},
}

S[#S + 1] = {
	id = "chat_oldtimer", weight = 1,
	cast = { a = P.archetype("oldhand", "deadpan"), b = P.any },
	turns = {
		{ who = "a", say = { "this server used to be so different", "remember when rounds were slower", "people used to actually talk more" } },
		{ who = "b", say = { "different how", "ok grandpa", "when was this" } },
		{ who = "a", say = { "less shooting more talking", "people used to roleplay a bit", "you had to actually find a gun first" } },
		{ who = "b", chance = .6, say = { "sounds boring", "ok boomer", "i kinda miss that too", "sure grandpa" } },
	},
}

S[#S + 1] = {
	id = "chat_food", weight = 1,
	cast = { a = P.any, b = P.any, c = P.any }, optional = { c = true },
	turns = {
		{ who = "a", say = { "brb getting food while dead", "im so hungry", "what are you guys eating" } },
		{ who = "b", say = { "cereal", "nothing its 3am", "leftover pizza", "i had chips like an hour ago" } },
		{ who = "c", chance = .5, say = { "cereal at night is elite", "my character is hungrier than me lol", "same" } },
		{ who = "a", chance = .5, say = { "ok back", "nice", "valid" } },
	},
}

----------------------------------------------------------------------
-- Teaching: someone asks the obvious question, someone answers, somebody
-- else roasts the asker for not knowing. Every tip below is TRUE on US1;
-- the implementing file is named on each script.
----------------------------------------------------------------------

local REACT = {
	any = { "wait really", "oh", "since when", "huh", "ok that explains a lot", "no way", "i did not know that",
		"thats actually useful", "brb rebinding everything" },
	crude = { "well fuck me", "you gotta be shitting me", "holy shit thats useful", "fuck ok" },
	ragey = { "WHY DOESNT THE GAME TELL YOU THAT", "why is none of this explained anywhere", "cool. great. thanks game" },
	polite = { "Oh, thank you!", "That's really useful, thanks.", "Good to know, cheers." },
	gloomy = { "of course i didnt know that", "would have been nice to know 300 hours ago", "cool. another thing i was bad at" },
}

local ROAST = {
	any = { "{a} didnt know that lmao", "how many hours do you have {a}", "{a} is new confirmed", "imagine not knowing that",
		"{a} has been playing on hard mode this whole time", "lmao {a}" },
	crude = { "{a} youve been playing this shit blind", "{a} is actually clueless lmao", "bro {a} how" },
	ragey = { "{a} HOW did you not know", "{a} you have been here for months" },
	polite = { "Don't worry, {a}, I only learned that recently too.", "Nobody tells you these things, {a}." },
	gloomy = { "i didnt know that either tbh", "same {a}. dont feel bad" },
}

-- teach(id, ask, answer, opts): a asks, b answers, a reacts, c roasts.
-- opts.joke / opts.react override the shared pools; opts.after adds turns.
T.topicAnswers = {}

local function teach(id, ask, answer, opts)
	opts = opts or {}
	T.topicAnswers[id] = answer
	local turns = {
		{ who = "a", say = ask },
		{ who = "b", say = answer },
		{ who = "a", say = opts.react or REACT, chance = .8 },
		{ who = "c", say = opts.joke or ROAST, chance = .55 },
	}
	for _, t in ipairs(opts.after or {}) do turns[#turns + 1] = t end
	S[#S + 1] = {
		id = "teach_" .. id, weight = opts.weight or 1.2,
		cast = { a = opts.asker or P.any, b = opts.teacher or P.any, c = P.any }, optional = { c = true },
		turns = turns,
	}
end

-- Lean: IN_ALT1/IN_ALT2, "Lean left/right" in the Keybinds tab, unbound by
-- default (weapons/homigrad_base/sh_anim.lua, lua/autorun/client/zcity_keybind_patch.lua).
teach("lean",
	{ any = { "wait you can lean in this?", "how are people leaning", "how did he peek me without showing his body", "is there a lean key" },
		ragey = { "how is everyone leaning and i cant", "HOW IS HE LEANING" },
		polite = { "Is there a way to lean? I keep seeing people do it." } },
	{ any = { "esc menu, keybinds tab, lean left and lean right", "its in the keybinds tab, its not bound by default",
			"bind lean left and right in the esc keybinds, i use q and e", "+alt1 and +alt2, or just set it in keybinds" },
		crude = { "bro its in the fucking keybinds tab", "keybinds tab. lean. use your eyes" },
		polite = { "It's in the ESC menu under Keybinds, Lean left and Lean right. They're unbound by default." } },
	{ joke = { any = { "{a} has been peeking with his whole body this whole time", "{a} leans with his entire torso like a door",
		"imagine not leaning", "{a} walks out of cover like a hero" }, crude = { "{a} been peeking like a fucking bus" } } })

-- Kick: hg_kick, unbound; zcity_keybind_reset puts kick on G and ragdoll on F
-- (dynamic_anims_util/animations/legkick/sv_legkick.lua, zcity_keybind_patch.lua).
teach("kick",
	{ any = { "how do you kick people", "how did he kick that door open", "wait theres a kick?", "how are people kicking doors" },
		crude = { "how the fuck do you kick in this" } },
	{ any = { "theres a kick bind in keybinds, its not set by default", "type zcity_keybind_reset in console, kick ends up on G",
			"kick bind. kick a door a few times and it breaks", "bind kick, it knocks people over most of the time" },
		polite = { "There's a Kick bind in the Keybinds tab. zcity_keybind_reset in console puts it on G." } },
	{ joke = { any = { "{a} been knocking on doors politely this whole time", "{a} opens every door with his hands like a gentleman",
		"kicking is half the game {a}" }, crude = { "{a} never kicked a single door lmao" } },
	  after = { { who = "b", chance = .45, say = { "look straight down and kick to stomp", "look down when you kick, its a stomp",
		"kicks cost stamina though dont spam it" } } } })

-- Ragdoll: "fake" command / Ragdoll bind (fake/sv_input.lua).
teach("ragdoll",
	{ any = { "how do you ragdoll on purpose", "how do people flop over whenever they want", "whats the flop key" } },
	{ any = { "ragdoll bind in keybinds, or type fake in console", "fake in console. zcity_keybind_reset puts it on F",
			"its the fake command, press again to get up" } },
	{ joke = { any = { "the flop is essential {a}", "{a} discovering the best feature 400 hours in", "flopping is a lifestyle" } } })

-- Tube-fed shotguns / bolt rifles keep loading only while R is held
-- (weapon_remington870.lua reloadFunc); pump actions need R after each shot.
teach("shell_reload",
	{ any = { "why does my shotgun only load one shell", "the pump shotgun reload is so slow", "why do i only ever have one shell" },
		ragey = { "WHY DOES MY SHOTGUN ONLY LOAD ONE SHELL" } },
	{ any = { "hold R dont tap it", "you gotta hold reload, it keeps loading while you hold it", "keep R held down and it loads them all",
			"hold R bro, let go when you have enough" },
		crude = { "hold R dumbass" },
		polite = { "Hold the reload key instead of tapping it. It keeps loading shells while it's held." } },
	{ joke = { any = { "{a} fighting with one shell at a time lmao", "{a} been tapping R like morse code", "that explains your whole round {a}" } },
	  after = { { who = "c", chance = .35, say = { "and press R after every shot to pump it", "pump ones need R after each shot too" } } } })

-- Arterial bleeding: bandages cannot stop it, tourniquet (or medkit
-- tourniquet mode) can; neck tourniquet strangles (weapon_bandage_sh.lua,
-- weapon_tourniquet.lua, organism/tier_1/modules/sv_blood.lua).
teach("arterial",
	{ any = { "i bandaged and still bled out", "why didnt my bandage stop the bleeding", "i used 3 bandages and still died" },
		gloomy = { "bandaged myself and bled out anyway. figures" } },
	{ any = { "bandages dont stop arterial, you need a tourniquet", "that was arterial, bandages do nothing for it",
			"if its spurting you need a tourniquet, the medkit has a tourniquet mode too" },
		polite = { "That was probably an arterial bleed. Bandages can't stop those, you need a tourniquet." } },
	{ react = { any = { "whats arterial", "how do you tell", "the spurting one?" } },
	  joke = { any = { "dont put a tourniquet on a neck wound tho lol", "tourniquet on the neck is a strangle", "{a} just kept bandaging the fountain" } },
	  after = { { who = "b", chance = .5, say = { "its the one that pumps with your heartbeat", "the fast one that spurts", "yeah the spurting one" } } } })

-- Medkit: R cycles six modes (weapon_medkit_sh.lua).
teach("medkit_modes",
	{ any = { "does the medkit only bandage", "whats the point of the medkit over bandages", "the medkit is just a big bandage right" } },
	{ any = { "press R on it, it has like six modes", "R switches modes. bandage, painkiller, tourniquet, antidote, needle, all that",
			"R on the medkit bro, it does way more than bandage" },
		polite = { "Press R with it out. It cycles through bandage, painkiller, tranexamic acid, tourniquet, needle and antidote." } },
	{ joke = { any = { "{a} has been carrying a whole hospital and using the bandage", "{a} discovered the R key", "the medkit is a swiss army knife {a}" } } })

-- Painkillers on someone else only if they are down; ~15 s onset
-- (weapon_painkillers.lua, modules/sv_pain.lua).
teach("painkillers",
	{ any = { "i gave him painkillers and nothing happened", "do painkillers even work on other people", "painkillers didnt do anything" } },
	{ any = { "only works on someone else if theyre down", "they take like 15 seconds to kick in", "he has to be ragdolled for you to give him pills" } },
	{ joke = { any = { "dont eat the whole bottle yourself tho", "{a} trying to feed pills to a guy mid gunfight lol", "you get drugged if you take too many lol" } } })

-- Looting: hold RMB+E on a body/container (homigrad/sv_inventory.lua).
teach("loot",
	{ any = { "how do you get stuff off bodies", "can you loot bodies in this", "how did he get that guys gun and ammo" } },
	{ any = { "hold right click and E on them", "right click plus E on the body", "hold rmb and press E, you get their inventory" },
		polite = { "Hold right click and press E while looking at the body." } },
	{ joke = { any = { "{a} walked past like five bodies full of ammo", "{a} has been leaving free loot everywhere", "bodies are basically shops {a}" } } })

-- Ammo check: Alt+R (homigrad_base/sh_reload.lua).
teach("ammo_check",
	{ any = { "how do you know how many bullets you have", "is there an ammo counter", "how do you check your mag" } },
	{ any = { "hold alt and press R", "alt R checks the mag", "alt plus R, no ammo counter in this" } },
	{ joke = { any = { "{a} counts his shots out loud", "{a} reloads after every two shots just in case" } } })

-- Gun bash: hold E + LMB (homigrad_base/shared.lua).
teach("gun_bash",
	{ any = { "he just hit me with his gun??", "how do you melee with a gun", "i got pistol whipped how" } },
	{ any = { "hold E and click", "E plus left click is a bash", "hold use and shoot, it bashes instead" } },
	{ joke = { any = { "{a} got bonked by a rifle lol", "getting bashed is so embarrassing", "{a} lost to the stock of a gun" } } })

-- Hand gestures: Q (radial) > Do Gesture, RMB for the list (homigrad/cl_hud.lua).
teach("gestures",
	{ any = { "how do you flip people off", "how did he thumbs up me", "how do you do the point thing" },
		crude = { "how do i flip these fuckers off" } },
	{ any = { "Q, do gesture, right click it for the list", "hold Q, do gesture, right click", "radial menu, gestures, right click for the good ones" } },
	{ joke = { any = { "{a} learns the most important feature", "finally {a} can communicate", "{a} is gonna be unbearable now" },
		crude = { "{a} about to flip off the whole server" } } })

-- Voice lines: Q > Do Phrase, RMB for contexts (homigrad/sh_phrases.lua).
teach("phrases",
	{ any = { "how are people yelling voice lines", "how do you scream for help", "how did he do that voice line" } },
	{ any = { "Q wheel, do phrase, right click for the specific ones", "do phrase in the Q menu, right click it", "Q, phrase, right click, yell for help" } },
	{ joke = { any = { "{a} been screaming irl instead", "we dont need more yelling {a}" } } })

-- Give up: K while unconscious (addons/giveup_button); KO reaper after 90 s
-- (addons/ko_reaper).
teach("giveup",
	{ any = { "i was knocked out for like a minute just staring", "being unconscious is so boring", "is there a way to die faster when youre knocked out" },
		gloomy = { "i was unconscious for a minute. best part of my round" } },
	{ any = { "press K when youre unconscious", "K gives up when youre knocked out", "just hit K" } },
	{ joke = { any = { "or wait 90 seconds and the game does it for you", "{a} spectated the ceiling for a minute lol" } } })

-- Karma: <50 random seizures, forgive with F within 5 s of dying
-- (gamemode/libraries/guilt/sv_guilt.lua, cl_guilt.lua).
teach("karma",
	{ any = { "i keep randomly seizing what is this", "why does my guy keep having seizures", "why cant i stand up randomly" },
		ragey = { "WHY DO I KEEP HAVING SEIZURES" } },
	{ any = { "your karma is low, stop teamkilling", "thats low karma, under 50 you start seizing", "karma. you been shooting randoms?" },
		crude = { "thats karma dumbass. stop killing your team" } },
	{ joke = { any = { "{a} teamkiller confirmed", "we know what you did {a}", "{a} is a war criminal" } },
	  after = { { who = "b", chance = .5, say = { "it comes back slowly on its own", "people can forgive you with F when they die",
		"press F right after you die to forgive people btw" } } } })

-- Killcam: space steps through the hits (lua/zc_killcam/cl_life.lua).
teach("killcam",
	{ any = { "i have no idea how i died", "what even killed me", "where did that come from" } },
	{ any = { "watch the killcam, space goes through the hits", "killcam shows you, press space", "space in the killcam, it shows it from his eyes" } },
	{ joke = { any = { "{a} closes the killcam out of shame", "the killcam is a crime scene {a}" } } })

-- Spectating: LMB/RMB cycle, R camera mode, Alt toggles name tags
-- (gamemode/init.lua, lua/zc_observer/cl_observer.lua).
teach("spectate",
	{ any = { "how do you switch who youre watching", "how do you get free cam", "how do you see names while dead" } },
	{ any = { "left and right click, R changes the camera", "click to swap, R for free roam", "tap alt for name tags, clicks swap people" } },
	{ joke = { any = { "{a} has been watching the same guy all round", "{a} spectating a wall" } } })

-- Reinforcements: !reinforcements when most of the round is dead
-- (lua/autorun/server/sv_zc_reinforcement_vote.lua).
teach("reinforce",
	{ any = { "this round is taking forever", "can we do anything while dead", "im so bored in spectator" } },
	{ any = { "type !reinforcements if everyone is dead", "!reinforcements once most people are dead, we come back as a wave",
			"vote reinforcements, !reinforcements" } },
	{ joke = { any = { "{a} wants back in so he can die again", "we are the reinforcements lol" } } })

-- Combat roll: sprint, then crouch + direction (zcity_sprint_roll.lua).
teach("roll",
	{ any = { "how did he roll", "wait you can roll?", "how do people dodge roll" } },
	{ any = { "while sprinting tap crouch and a direction", "sprint then crouch plus A or D", "sprint and crouch, it costs stamina tho" } },
	{ joke = { any = { "{a} thought it was an animation glitch", "{a} about to roll everywhere now" } } })

-- Hold breath: steadies sway, needs 90 stamina (modules/sv_lungs.lua).
teach("hold_breath",
	{ any = { "my aim shakes so much with scopes", "how do you stop the sway", "the sniper sway is insane" } },
	{ any = { "bind hold breath, it steadies your aim", "hold breath bind in keybinds, needs stamina", "+hmcd_holdbreath. dont hold it too long" } },
	{ joke = { any = { "{a} been sniping on hard mode", "{a} breathes too loud irl too" } } })

-- Stamina: crouching still regenerates faster (modules/sv_stamina.lua).
teach("stamina",
	{ any = { "why am i so slow", "why is my guy out of breath all the time", "my stamina is always empty" } },
	{ any = { "stop sprinting everywhere", "crouch and stand still, it comes back faster", "you sprint and kick too much" } },
	{ joke = { any = { "{a} sprints to the bathroom", "{a} cardio is not great" } } })

-- Doors: Alt+E quiet, Shift+E fast (homigrad/sh_inventory.lua).
teach("doors",
	{ any = { "how do people open doors so quietly", "how did he slam that door open", "every door i open is so loud" } },
	{ any = { "alt E opens it slow and quiet", "shift E slams it open, alt E is quiet", "walk key plus E, it creaks it open" } },
	{ joke = { any = { "{a} announces himself at every door", "{a} opens doors like the fbi" } } })

-- Dislocations: Q > fix dislocation, far better if someone else does it
-- (organism/tier_1/sv_organism.lua).
teach("dislocation",
	{ any = { "my arm is dislocated what do i do", "how do you fix a dislocated leg", "i keep failing to fix my arm" } },
	{ any = { "Q wheel, fix dislocation. get someone else to do it though, way better chance",
			"have someone else fix it, doing it yourself almost never works", "crouch or lie down first, it helps a bit" } },
	{ joke = { any = { "{a} tried like 12 times on his own lmao", "{a} is his own worst doctor" } } })

-- Burning: roll while ragdolled with A/D (fake/sv_control.lua); urine puts
-- out fires (lua/autorun/server/zc_urine.lua).
teach("fire",
	{ any = { "i was on fire and just died", "how do you put yourself out", "is there anything you can do on fire" } },
	{ any = { "ragdoll and hold A or D to roll", "flop over and roll with A and D", "roll around while ragdolled" } },
	{ joke = { any = { "or get someone to piss on you", "pee works too, not even joking", "{a} just stood there on fire" },
		crude = { "or get someone to piss on you lmao", "piss on it. it actually works" } } })

-- Hurt grab: with hands, RMB a badly hurt standing player
-- (addons/hurt_grab); kick catch: RMB a ground kick with bare hands
-- (addons/kick_catch).
teach("hurt_grab",
	{ any = { "how did he just grab me", "i got grabbed and flopped how", "he caught my kick??" } },
	{ any = { "if youre bleeding a lot people can grab you with right click", "hands out and right click, works on hurt people",
			"you can catch kicks with your hands if you right click them" } },
	{ joke = { any = { "{a} got ragdolled like a doll", "{a} got manhandled" } } })

-- CPR: hold torso with RMB, hold LMB (weapon_hands_sh.lua).
teach("cpr",
	{ any = { "can you revive people", "is there cpr in this", "can you save someone whos down" } },
	{ any = { "grab their chest with right click and hold left click, cpr", "right click the torso, hold left click",
			"cpr is a thing, hold their chest and pump with left click" } },
	{ joke = { any = { "you break ribs sometimes lol", "{a} is gonna crack everyones ribs now" } } })

-- Body check: hands, RMB the head, press R -- temperature and wounds
-- (weapon_hands_sh.lua).
teach("body_check",
	{ any = { "how do you tell how long someone has been dead", "how do people know what killed a body", "how are people checking bodies" } },
	{ any = { "grab the head with your hands and press R", "right click the body with hands, then R, it tells you how warm it is",
			"hands, grab them, R. it says how cold they are and the wounds" } },
	{ joke = { any = { "{a} is a detective now", "csi {a}" } } })

-- Spit: zc_spit (addons/zc_spit).
teach("spit",
	{ any = { "did someone just spit on me", "how do you spit on people", "i got spat on lol" } },
	{ any = { "zc_spit in console, bind it", "bind zc_spit", "its zc_spit, everyone has it bound" } },
	{ joke = { any = { "we all have that bound", "{a} about to spit on everyone" }, crude = { "most important bind in the game honestly" } } })

-- A teacher who is half wrong gets corrected. Kick/ragdoll are unbound by
-- default; zcity_keybind_reset gives G/F (zcity_keybind_patch.lua).
S[#S + 1] = {
	id = "teach_corrected", weight = 1,
	cast = { a = P.any, b = P.any, c = P.any },
	turns = {
		{ who = "a", say = { "how do you kick", "whats the kick key", "whats the key to ragdoll" } },
		{ who = "b", say = { "its G", "G i think", "F? i think its F" } },
		{ who = "c", say = { "its not bound by default", "nothings bound by default, type zcity_keybind_reset", "only after zcity_keybind_reset, otherwise nothing" } },
		{ who = "b", say = { "oh i reset mine ages ago", "huh ok", "well its G for me" } },
		{ who = "a", chance = .6, say = REACT },
	},
}

-- Human questions in public/dead chat -> a teach topic (sv_chat_listen.lua
-- handleQuestion). Every group must match (plain substring); the first
-- topic that matches wins, so narrower topics come first. The second group
-- is usually the "how/why/didn't work" intent, so a help request ("anyone
-- got a medkit?") is not mistaken for a question about medkits.
T.questionTopics = {
	{ id = "body_check", all = { { "how long", "been dead", "dead for", "check bod", "checking bod" } } },
	{ id = "shell_reload", all = { { "shotgun", "shell", "pump" }, { "reload", "one shell", "load" } } },
	{ id = "arterial", all = { { "bandage", "bleed", "bled", "tourniquet", "arterial" }, { "still", "stop", "didnt", "didn't", "why", "how", "work" } } },
	{ id = "medkit_modes", all = { { "medkit" }, { "mode", "what does", "only", "how do", "how does" } } },
	{ id = "painkillers", all = { { "painkiller", "pills" }, { "work", "nothing", "didnt", "didn't", "how" } } },
	{ id = "lean", all = { { "lean" } } },
	{ id = "kick", all = { { "kick" }, { "how", "key", "button", "bind", "door" } } },
	{ id = "ragdoll", all = { { "ragdoll", "flop" }, { "how", "key", "button", "bind", "purpose" } } },
	{ id = "loot", all = { { "loot", "bodies", "body", "inventory" }, { "how", "can you", "can i" } } },
	{ id = "ammo_check", all = { { "ammo", "bullets", "mag" }, { "check", "counter", "how many", "left" } } },
	{ id = "gun_bash", all = { { "bash", "pistol whip", "with his gun", "melee with a gun" } } },
	{ id = "gestures", all = { { "gesture", "flip off", "flip people off", "thumbs up", "middle finger", "point at" } } },
	{ id = "phrases", all = { { "voice line", "voiceline", "phrase", "scream for help", "yell for help" } } },
	{ id = "giveup", all = { { "unconscious", "knocked out", "give up", "passed out" } } },
	{ id = "karma", all = { { "karma", "seizure", "seizing" } } },
	{ id = "killcam", all = { { "killcam", "kill cam", "how did i die", "what killed me" } } },
	{ id = "spectate", all = { { "spectat", "free cam", "freecam", "switch who", "name tags", "nametags" } } },
	{ id = "roll", all = { { "roll" }, { "how", "can you" } } },
	{ id = "hold_breath", all = { { "sway", "hold breath", "hold my breath", "shaky", "shaking" } } },
	{ id = "stamina", all = { { "stamina", "out of breath" } } },
	{ id = "doors", all = { { "door" }, { "quiet", "slam", "silent" } } },
	{ id = "dislocation", all = { { "dislocat" } } },
	{ id = "fire", all = { { "on fire", "put out", "extinguish", "burning" } } },
	{ id = "hurt_grab", all = { { "grabbed me", "grab me", "caught my kick", "catch kick", "catch a kick" } } },
	{ id = "cpr", all = { { "cpr", "revive" } } },
	{ id = "spit", all = { { "spit" } } },
	{ id = "reinforce", all = { { "reinforcement", "respawn", "come back" }, { "how", "can we", "is there", "any way" } } },
}

hg.botdriver.specTalkScripts = S

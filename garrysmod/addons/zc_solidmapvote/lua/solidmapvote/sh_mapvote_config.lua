SolidMapVote = SolidMapVote or {}
SolidMapVote["Config"] = SolidMapVote["Config"] or {}

-- Time in seconds until the mapvote is over from when it starts.
SolidMapVote["Config"]["Length"] = 25

-- The time in seconds that the vote will stay on the screen after the winning map has been chosen.
SolidMapVote["Config"]["Post Vote Length"] = 5

-- Map Button Size (1 = Tall, 2 = Square)
SolidMapVote["Config"]["Map Button Size"] = 2

-- Autostart Settings [I recommend leaving it like this]
SolidMapVote["Config"]["Enable Vote Autostart"] = false
SolidMapVote["Config"]["Vote Autostart Delay"] = 60 * 60 -- 60 Minutes
SolidMapVote["Config"]["Autostart Reminder"] = 3 * 60 -- 3 minutes
SolidMapVote["Config"]["Time Left Commands"] = {"!timeleft", "/timeleft", ".timeleft"}

-- Map eligibility is controlled by Map Blacklist and Allowed Prefixes at the end of this file.

-- Helper Colors 
local namecolor = {
    default = Color(255, 255, 255),
    superadmin = Color(200, 0, 0),
    admin      = Color(255, 165, 0),
    moderator  = Color(0, 170, 255),
    operator   = Color(0, 170, 255),
    helper     = Color(0, 200, 20),
    support    = Color(0, 200, 20),
    vip        = Color(255, 204, 0)
}

-- Avatar Border Color
SolidMapVote["Config"]["Avatar Border Color"] = function(ply)
    if ply:IsUserGroup("superadmin") then
        return HSVToColor(math.sin(2 * RealTime()) * 128 + 127, 1, 1)
    end
    local group = ply:GetUserGroup()

    if namecolor[group] then
        return namecolor[group]
    end
    return color_white
end

-- Vote Power
SolidMapVote["Config"]["Vote Power"] = function(ply)
	if ply:IsAdmin() then return 1 end 
	return 1
end

-- Fair Map Recycling
SolidMapVote["Config"]["Fair Map Recycling"] = true

-- Show Map Play Count
SolidMapVote["Config"]["Show Map Play Count"] = true

-- Manual Map Pool [I recommend setting it to true and making your own map pool]
SolidMapVote["Config"]["Manual Map Pool"] = false

-- Map Pool
SolidMapVote["Config"]["Map Pool"] = {
    "ttt_example_v1",
    "mu_example_v2",
    "gm_example_v3",
    "zs_etc",
}


-- Enable Voice/Chat
SolidMapVote["Config"]["Enable Voice"] = true
SolidMapVote["Config"]["Enable Chat"] = true

-- Force Vote Permission
SolidMapVote["Config"]["Force Vote Permission"] = function(ply) return ply:IsAdmin() end
SolidMapVote["Config"]["Force Vote Commands"] = {"forcertv", "!forcertv", "/forcertv", ".forcertv"}

-- RTV Settings
SolidMapVote["Config"]["RTV Percentage"] = 0.6
SolidMapVote["Config"]["RTV Delay"] = 60
SolidMapVote["Config"]["Enable UnVote"] = true
SolidMapVote["Config"]["Vote Commands"] = {"rtv", "!rtv", "/rtv", ".rtv"}

-- Nomination Settings
SolidMapVote["Config"]["Nomination Commands"] = {"nominate", "!nominate", "/nominate", ".nominate"}
SolidMapVote["Config"]["Allow Nominations"] = true
SolidMapVote["Config"]["Nomination Permissions"] = function(ply) return true end

-- Extend/Random Settings
SolidMapVote["Config"]["Enable Extend"] = true
SolidMapVote["Config"]["Extend Image"] = "https://i.imgur.com/zzBeMid.png"
SolidMapVote["Config"]["Enable Random"] = true
SolidMapVote["Config"]["Random Mode"] = 2
SolidMapVote["Config"]["Random Image"] = "https://i.imgur.com/oqeqWhl.png"

-- Missing Image
SolidMapVote["Config"]["Missing Image"] = ""
SolidMapVote["Config"]["Missing Image Size"] = { width = 1920, height = 1080 }

-- In this table you can add information for the map to make it more appealing on the mapvote. These are the configs i made over time you get to automatically use yay
-- Probably contains all maps you have on the server
SolidMapVote["Config"]["Specific Maps"] = {
    {
        filename = "xmas_nipperhouse",
        displayname = "Nipperhouse",
        image = "https://images.steamusercontent.com/ugc/702911555414894073/7591C07E628B94AC47A6A28E4ED9BB41ACC4F7E1/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 637,
        height = 358
    },
    {
        filename = "gm_everpine_mall",
        displayname = "Everpine Mall",
        image = "https://images.steamusercontent.com/ugc/19810950073279739/4F41E5B6AD43B40ABE556970E81DC1DE9847B4DC/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "gm_hetveer_popajoja",
        displayname = "Hetveer",
        image = "https://images.steamusercontent.com/ugc/2404445481966696859/D2088FD10E9FF65127864A3501873A3ECC7E3C64/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "gm_militia_big",
        displayname = "Militia",
        image = "https://images.steamusercontent.com/ugc/134374981574693361/719D17E1DC24EA80EF4FF0732A614957565F664E/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "gm_nuketown",
        displayname = "Nuketown",
        image = "https://images.steamusercontent.com/ugc/794240887422687297/ADECDB5411A54906897CDA798EC516084BED882C/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "gm_oxxo_redux",
        displayname = "OXXO Store)",
        image = "https://images.steamusercontent.com/ugc/15197703179410690339/464028E62BA2E8D7016B79A558DE4248DBCF47C9/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "gm_ridgemont",
        displayname = "Ridgemont",
        image = "https://images.steamusercontent.com/ugc/1662354326144070021/AC830FC2C3C9ED6526164416CA6BE85E0472EEF9/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 637,
        height = 358
    },
    {
        filename = "mu_museum",
        displayname = "The Museum",
        image = "https://images.steamusercontent.com/ugc/937195384592880106/320BA3C23D26ACC6D6800174F33D1B0EE9EB8062/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 637,
        height = 358
    },
    {
        filename = "mu_pharaoh",
        displayname = "Pharaoh",
        image = "https://images.steamusercontent.com/ugc/949593428637311070/7DBD5974DFD56FFC62F6375D58ECA45E0BAF3091/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "mu_springbreak",
        displayname = "Spring Break",
        image = "https://images.steamusercontent.com/ugc/92721123038072815/913CE97774439C12C1D4E44FEF057D318F3C800D/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 637,
        height = 358
    },
    {
        filename = "mu_winternight",
        displayname = "Winter Night",
        image = "https://images.steamusercontent.com/ugc/90474193447003565/A1F2650960C7F9D8F1D51F3678C9711E8DF06881/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "ph_islandhouse_night",
        displayname = "Island House",
        image = "https://images.steamusercontent.com/ugc/2033976129423924846/C886FDF45D78BA417D47DDF691D848DE326858E3/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 637,
        height = 358
    },
    {
        filename = "ttt_blackmesa_bahpu",
        displayname = "Black Mesa",
        image = "https://images.steamusercontent.com/ugc/2393187660789102554/418867A7B92FD6BDE1B2CBDE462C7CC60E973E82/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 637,
        height = 358
    },
    {
        filename = "ttt_csgobank",
        displayname = "Bank",
        image = "https://images.steamusercontent.com/ugc/780658650791512143/C9C4EAA21E44B505D8B31A4210F972F73428C506/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "ttt_greenbelt",
        displayname = "Greenbelt",
        image = "https://images.steamusercontent.com/ugc/2262559980386521391/7D9DB11C45729571D93642182EF0EBFC817AF472/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 637,
        height = 358
    },
    {
        filename = "ttt_gsf_gunsandgroceries_winter_b1",
        displayname = "Guns & Groceries",
        image = "https://images.steamusercontent.com/ugc/16316204670986143817/E12C8126C64F31498EE070AD69FB2A4F7794C3DC/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 637,
        height = 358
    },
    {
        filename = "ttt_mall",
        displayname = "The Mall",
        image = "https://images.steamusercontent.com/ugc/3280053338128279796/0378E5A48FF55730E7BCF5D915A9BB6375781227/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "ttt_manorhouse",
        displayname = "Manor House",
        image = "https://images.steamusercontent.com/ugc/31867982587187966/F78D129484574B655BE41C5BB0B7BBB536B55C4E/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 637,
        height = 358
    },
    {
        filename = "ttt_panorama",
        displayname = "Panorama",
        image = "https://images.steamusercontent.com/ugc/13895424572091927197/CC8DCD9871AF69058DFD389995797F705C96F3B1/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "ttt_poolparty_xmas",
        displayname = "Pool Party Christmas",
        image = "https://images.steamusercontent.com/ugc/14684703692125247691/F9F36EFD90D3B51C04936DC53607C99F410084E1/?imw=2048&imh=1152&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 2048,
        height = 1152
    },
    {
        filename = "ttt_shadowraid_v3",
        displayname = "Shadow Raid",
        image = "https://images.steamusercontent.com/ugc/778477486686664629/65559F01A49CF0BF604248EE17B0359294872C33/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "ttt_silence_v3",
        displayname = "Silence",
        image = "https://images.steamusercontent.com/ugc/379784372259838181/EBCA7705D20FAEE2789FA44259EEDD28A49F5D89/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "ttt_theship_v1",
        displayname = "The Ship",
        image = "https://images.steamusercontent.com/ugc/882977693157358161/0687B53450B7172EAC24E587850167CB2B332259/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 637,
        height = 358
    },
    {
        filename = "ttt_whitehousev3",
        displayname = "The White House",
        image = "https://images.steamusercontent.com/ugc/2441391184293227159/D6BBCA9BDF0CD6700A70574DFB4462B9E46C4B81/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "zs_drifting",
        displayname = "Drifting",
        image = "https://images.steamusercontent.com/ugc/2026096911684949585/8BA635AF188EC5245B7C8F44AC20C87553B621D1/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "zs_muhosransk_v3",
        displayname = "Muhosransk",
        image = "https://images.steamusercontent.com/ugc/270588452671698521/8EB7FCF62A4E333A9AA7E4D2A14C998D886F184C/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
{
    filename = "gm_mysterious_forest",
    displayname = "Mysterious Forest",
    image = "https://images.steamusercontent.com/ugc/782979273622978002/B3BEEDF2B1F6B80CFBF1A6EB6BD44F24CE11065D/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
    width = 637,
    height = 358
},
{
    filename = "gm_grenze_mall",
    displayname = "Grenze Mall",
    image = "https://images.steamusercontent.com/ugc/48736189777936854/3C0167A53F2B24EB6026D15C72C09B32F729E2C7/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
    width = 637,
    height = 358
},
{
    filename = "mu_calmtime_winter",
    displayname = "Calm Winter",
    image = "https://images.steamusercontent.com/ugc/1878592335951258548/D4693EC5B7DBA7B0593480F8A33BCF4042CA7860/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
    width = 268,
    height = 268
},
{
    filename = "contagion",
    displayname = "Contagion",
    image = "https://images.steamusercontent.com/ugc/400052635012945835/57B00BF491A08C52A8C6C419EEC2B557503CB482/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
    width = 637,
    height = 358
},
{
    filename = "ttt_coder",
    displayname = "Coder",
    image = "https://images.steamusercontent.com/ugc/351646386179912464/EED34229CDE9329C19C80162558E744016A0E6E1/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
    width = 268,
    height = 268
},
{
    filename = "ttt_krustykrab",
    displayname = "Krusty Krab",
    image = "https://images.steamusercontent.com/ugc/755968752079515788/40B65CDE62FD0A5BBF437B685ED11CAC71C173AC/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
    width = 637,
    height = 358
},
{
    filename = "zs_snowy_castle",
    displayname = "Snowy Castle",
    image = "https://images.steamusercontent.com/ugc/43106053935353407/475E9E33CEA8E91FD3DBDAC971BC92E4F025CA48/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
    width = 268,
    height = 268
},
{
    filename = "cs_dancing",
    displayname = "Dancing",
    image = "https://images.steamusercontent.com/ugc/14600813986822815175/FB47636B462C78D081A5F7098B028A17550B3FC4/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
    width = 268,
    height = 268
},
{
    filename = "cs_insertion2_dusk",
    displayname = "Insertion II",
    image = "https://images.steamusercontent.com/ugc/1707410012008903274/EAF20FB8A86FDA3AE76879BCDC9B319F84567CC5/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
    width = 268,
    height = 268
},
{
    filename = "cs_meridian",
    displayname = "Meridian",
    image = "https://images.steamusercontent.com/ugc/505827628521153513/2098F804BBEE2B9071011B0E0256F079BF80DA68/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
    width = 268,
    height = 268
},
{
    filename = "gm_brutalist_mcdonalds",
    displayname = "Brutalist McDonald's",
    image = "https://images.steamusercontent.com/ugc/2467488268105900201/86C7C6F9A2120C908478DB7C389623475B1956C1/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
    width = 268,
    height = 268
},
{
    filename = "mu_abandoned",
    displayname = "Abandoned",
    image = "https://images.steamusercontent.com/ugc/778307366400589606/290B871A8DEDD1251A9E973B77CF25A72338C3D7/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
    width = 637,
    height = 358
},
{
    filename = "de_dust2_xmas_fix",
    displayname = "Dust II Christmas",
    image = "https://images.steamusercontent.com/ugc/16994982089582617420/2B33A26EF1B36222A375775E484DFD4CE33B9D87/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
    width = 268,
    height = 268
},
{
    filename = "gm_daydreamestate",
    displayname = "Daydream Estate",
    image = "https://images.steamusercontent.com/ugc/14624259977925576868/D3B024BFCE278D3FFBDA636E1824C43FD9EE3186/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
    width = 637,
    height = 358
},
{
    filename = "ttt_solitude",
    displayname = "Solitude",
    image = "https://images.steamusercontent.com/ugc/14283944673464082295/174B97E9296ADB5746F951C71547147E5DB7F83B/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
    width = 637,
    height = 358
},
{
    filename = "gm_apartments",
    displayname = "Apartments",
    image = "https://images.steamusercontent.com/ugc/1477697066773221791/F924B7C272A828E3CAA7E41FEB3FA10F1E595478/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
    width = 268,
    height = 268
},
{
    filename = "gm_home_alone_1990",
    displayname = "Home Alone",
    image = "https://images.steamusercontent.com/ugc/14761659666563330437/C78BAB0AA0A88D0E1AC4C4B3C31355AA3708A033/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
    width = 637,
    height = 358
},
{
    filename = "zs_intercity_mall_v16",
    displayname = "Intercity Mall",
    image = "https://images.steamusercontent.com/ugc/16207663677117756333/8117DE24F728B2405564AD1DDE5FE941A07417F5/?imw=2048&imh=1152&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
    width = 2048,
    height = 1152
},

{
        filename = "hmcd_downtown",
        displayname = "Downtown", 
        image = "https://images.steamusercontent.com/ugc/12308211434830665957/2613327B58285692097A38FF125FCCB9C3919B14/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 637,
        height = 358
    },
    {
        filename = "hmcd_aircraft",
        displayname = "Floating Ship", 
        image = "https://images.steamusercontent.com/ugc/2523786576349586926/768C156E22C1B9B9E0D86E74649F3F067BC65226/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "hmcd_hristmass_map",
        displayname = "Christmas Homigrad",
        image = "https://images.steamusercontent.com/ugc/12968649023217585903/F1648DFED89824D3B6B444D07DE81BB26AA2BEF7/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 637,
        height = 358
    },
    {
        filename = "gm_secretcamp_hmcd",
        displayname = "Secret Camp", 
        image = "https://images.steamusercontent.com/ugc/18006821206638836066/1B8EE8DD7E94FFC26D4F1F37FB6D7E9A4E718188/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "gm_1950s_woolworths",
        displayname = "Woolworths",
        image = "https://images.steamusercontent.com/ugc/18219760960809834477/985119C3F309D0DA4D6283045EF23F29895C321E/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "gm_broadcasting_station_night",
        displayname = "Station Night",
        image = "https://images.steamusercontent.com/ugc/17203362106224614909/5153A4801B8056A9E69DC3A861DF42382C227D4B/?imw=2048&imh=1152&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 2048,
        height = 1152
    },
    {
        filename = "gm_funkis_night",
        displayname = "Funkis Night",
        image = "https://images.steamusercontent.com/ugc/14170673543400358/124DC75C851A4FE744526E25EC0D1916C8221D4B/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 637,
        height = 358
    },
    {
        filename = "gm_sosnovka2",
        displayname = "Sosnovka",
        image = "https://images.steamusercontent.com/ugc/5097543432676715890/92AF29A00F527C0225B6D4B854FAA293BAFE1BAF/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "gm_wawa",
        displayname = "Wawa",
        image = "https://images.steamusercontent.com/ugc/10783380683989782532/B20781F28B60A80D45D45DA02BA6139E8E5AB107/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "gm_zabroshka_winter",
        displayname = "Zabroshka Winter",
        image = "https://images.steamusercontent.com/ugc/1780630351475797637/9E4D0E436CA000A904DE34D89EBEF555689CBDA7/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "tdm_city18",
        displayname = "City 18",
        image = "https://images.steamusercontent.com/ugc/2527164217078965837/B38DB5B6DA32203F20A731E37FFEA14C1A255EEC/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "ttt_pizzeria",
        displayname = "Pizzeria",
        image = "https://images.steamusercontent.com/ugc/2453979000636858666/D9E15FD4AAF9B7762218E754845444560D61C86F/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 637,
        height = 358
    },
    {
        filename = "ttt_edinburgh",
        displayname = "Edinburgh",
        image = "https://images.steamusercontent.com/ugc/32195934287255402/DF252DE953C2FFAAAA9F16D03645F3109CBDA599/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "gm_office_but_osha_certified",
        displayname = "Office",
        image = "https://images.steamusercontent.com/ugc/5835050607314162136/C51374CDC3CBBFA143C93887B5E4561E608C9579/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "ttt_cs_mcdonalds",
        displayname = "McDonalds",
        image = "https://images.steamusercontent.com/ugc/12581775426211189469/AE9BB074DE2357F3016CBFE820EC37BDAA63D94D/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "ttt_ants",
        displayname = "Ants",
        image = "https://images.steamusercontent.com/ugc/1705160970211931544/1C8603A35CF7E1C0AB201DC9BEE2BB8C19A5D5B6/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "ttt_67thway_2022",
        displayname = "67th Way",
        image = "https://images.steamusercontent.com/ugc/1868445746588379171/99B8F9ADE56ACF83F2A1202E94D5B33AA85CFF83/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "ttt_amsterville_open",
        displayname = "Amsterville",
        image = "https://images.steamusercontent.com/ugc/2028364316137680198/05C5B9E1F6E75093EEAC61EC3D2232DFC2A279CB/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "mu_factory_winter",
        displayname = "Factory Winter",
        image = "https://images.steamusercontent.com/ugc/23178672178752800/61A13E2D4EC205392DD012645B2C03F1BB32757C/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 637,
        height = 358
    },
    {
        filename = "hmcd_alexandra",
        displayname = "Alexandra",
        image = "https://images.gamebanana.com/img/ss/mods/4e726fb0ef90e.jpg",
        width = 268,
        height = 268
    },
    {
        filename = "gm_voidtown",
        displayname = "Voidtown",
        image = "https://images.steamusercontent.com/ugc/11370003479100549407/636B804891DD5FF2350D0922E31D3427ED87A14C/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "gm_sad_csm",
        displayname = "Sad",
        image = "https://images.steamusercontent.com/ugc/2514781045786525117/9EEEF064BD22C36A88D8C2CC79A68A0DEC41A2AE/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 637,
        height = 358
    },
    {
        filename = "gm_gleb",
        displayname = "Gleb",
        image = "https://images.steamusercontent.com/ugc/1696156397363076866/9FA5CA22F9EB9738B37E65DE0580097706E2F13A/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "gm_dune_plaza",
        displayname = "Dune Plaza",
        image = "https://images.steamusercontent.com/ugc/14455607143929598166/4020C8634C318052F4E43EC2720793FA2939ACAE/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 637,
        height = 358
    },
{
        filename = "cs_apartments",
        displayname = "Apartments",
        image = "https://images.steamusercontent.com/ugc/803242059824595364/E0D738AF04333FE1F1BEC6061501B2594DF38F0B/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "cs_christalley",
        displayname = "Christ Alley",
        image = "https://images.steamusercontent.com/ugc/5086284433604859527/94840CE7961E3820A4EA01F9CBDEAB79C8A3310B/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "slash_lodge",
        displayname = "Lodge",
        image = "https://images.steamusercontent.com/ugc/865106845083684811/973CA14B9D206BDD36AB9BD2FDE3E81A51F7D3C3/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 637,
        height = 358
    },   
    {
        filename = "gm_construct",
        displayname = "",
        image = "",
        width = 637,
        height = 358
    },
    {
        filename = "gm_csgoinsertion",
        displayname = "Insertion",
        image = "https://images.steamusercontent.com/ugc/880881498629507142/8FA94504495835D989CBEBB974B4008A36CF6A92/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "gm_deschool",
        displayname = "New school",
        image = "https://images.steamusercontent.com/ugc/2453969772029767436/0AC2DE6CAAEF65590FC863D3ABACA231A32B85B5/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 637,
        height = 358
    },
    {
        filename = "gm_flatgrass",
        displayname = "",
        image = "",
        width = 637,
        height = 358
    },
    {
        filename = "gm_monolith10",
        displayname = "Monolith",
        image = "https://images.steamusercontent.com/ugc/1741224593393550286/5811F78C78ECBDEF41B5C9E85E01D9ADA64CA1DB/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "gm_stage_6_old",
        displayname = "Stage 6",
        image = "https://images.steamusercontent.com/ugc/2527164217048896920/A8D66F6B58AC2BB792D57FD1795DAA6769E24474/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 637,
        height = 358
    },
    {
        filename = "gm_trainride_v1_day",
        displayname = "",
        image = "",
        width = 637,
        height = 358
    },
    {
        filename = "hmcd_bloodring",
        displayname = "",
        image = "",
        width = 637,
        height = 358
    },
    {
        filename = "hmcd_examen",
        displayname = "Examen",
        image = "https://images.steamusercontent.com/ugc/17521375459090714681/E4E55E7615ED2E55B2C2604E986BA47716BAA8BC/?imw=2048&imh=1152&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 2048,
        height = 1152
    },
    {
        filename = "hmcd_metropolis_extended",
        displayname = "Metropolis",
        image = "https://images.steamusercontent.com/ugc/29944196396129719/D037FF02E5A874093654C0A43DFF2009FE9C88C5/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 637,
        height = 358
    },
    {
        filename = "mu_smallotown_v2_13",
        displayname = "Small Town Day",
        image = "https://i.imgur.com/gYI8nD0.jpeg",
        width = 1920,
        height = 1080
    },
    {
        filename = "mu_smallotown_v2_13_night",
        displayname = "Small town Night",
        image = "https://images.steamusercontent.com/ugc/2471991866894665268/E0386560E0ACE770E6C7A0D966B96FCBAB0993E9/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 637,
        height = 358
    },
    {
        filename = "mu_smallotown_v2_hl2",
        displayname = "",
        image = "",
        width = 637,
        height = 358
    },
    {
        filename = "mu_smallotown_waste_v2_13",
        displayname = "Smallotown Waste",
        image = "https://images.steamusercontent.com/ugc/17616805716960919189/BF5FCA49087A8D4975FD63A022E29A1CF53E4012/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 637,
        height = 358
    },
    {
        filename = "rp_countryestatev1",
        displayname = "Country Estate",
        image = "https://steamuserimages-a.akamaihd.net/ugc/7416500506119185/67BC73D45952044DD291FD385FFA7EC638A1CF61/",
        width = 268,
        height = 268
    },
    {
        filename = "rp_hometown1999_d",
        displayname = "Hometown",
        image = "https://images.steamusercontent.com/ugc/939260234999456398/976296AB4FC6954FC9E547BACB1A5984D6F2CBAC/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 637,
        height = 358
    },
    {
        filename = "ttt_casino_b2",
        displayname = "",
        image = "",
        width = 637,
        height = 358
    },
    {
        filename = "ttt_crossroads",
        displayname = "",
        image = "",
        width = 637,
        height = 358
    },
    {
        filename = "ttt_dworzecglowny",
        displayname = "Dworzecglowny",
        image = "https://images.steamusercontent.com/ugc/15304899760191004/5D71E542E8627245AD512C72DB9B6BB90393DB22/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 637,
        height = 358
    },
        {
		filename = "zs_winter_solstice_v2",
		displayname = "Winter Solstice",
		image = "https://images.steamusercontent.com/ugc/775114553532395019/5FD0F16CD756C57462E33CF3C492F7CAF5C79D44/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 637,
		height = 358
	},

        {
		filename = "zs_christmas_factory_v1",
		displayname = "Christmas Factory",
		image = "https://images.steamusercontent.com/ugc/1972044745358674694/BA7C098FB6571BDEDB0AF9D503AD7DC24424103C/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 637,
		height = 358
	},

        {
		filename = "ttt_gsf_grippyfactory",
		displayname = "Grippy Factory",
		image = "https://images.steamusercontent.com/ugc/17071035839441057875/9AC8B5589C7E7FCF13D859C8210569F94CD2A90F/?imw=5000&imh=5000&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=false",
		width = 5000,
		height = 5000
	},

        {
		filename = "de_nighttown",
		displayname = "Night Town",
		image = "https://images.steamusercontent.com/ugc/16216167036899142938/903701FE244877090ADAF8B7D01E9534BEBFC0FD/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 637,
		height = 358
	},

        {
		filename = "ttt_blackfactory",
		displayname = "Black Factory",
		image = "https://images.steamusercontent.com/ugc/1634233932261093171/3FEBA937F513404EF63C4349EFB091C5428A8FC9/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 268,
		height = 268
	},

        {
		filename = "gm_bbicotka_snow_hmcd",
		displayname = "Bbicotka Christmas",
		image = "https://images.steamusercontent.com/ugc/10793773218923862/A38402121BF0249425993B44511565DA26CF86E9/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 268,
		height = 268
	},

        {
		filename = "dm_christmas_in_the_suburbs",
		displayname = "Christmas Suburbs",
		image = "https://images.steamusercontent.com/ugc/542945375824635764/8BEAAD8BF2A13A104ECF5EBBA2D892C9D0ECCA7F/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 268,
		height = 268
	},

        {
		filename = "gm_snowyisolation_v3",
		displayname = "Snowy Isolation",
		image = "https://images.steamusercontent.com/ugc/13046857339542305/02C3133046621AB9A1FB69D0F0EA47D5DEA6FF95/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 637,
		height = 358
	},

        {
		filename = "ttt_skatepark",
		displayname = "Skatepark",
		image = "https://images.steamusercontent.com/ugc/1862812087886176901/E69B7A80504A2D69DB01705AA0535F60DA19BD04/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 268,
		height = 268
	},

        {
		filename = "ttt_warhawk_g2",
		displayname = "Warhawk",
		image = "https://images.steamusercontent.com/ugc/16428815146951663/DD88B6512A8377795D2DF9B8C5382E3893B69C7C/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 268,
		height = 268
	},

        {
		filename = "ttt_richland_remix_v1",
		displayname = "Richland",
		image = "https://images.steamusercontent.com/ugc/1627446869062039512/A4D39ADC6CEA9461F62138E93EC3DACA0D7D0C7E/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 268,
		height = 268
	},

        {
		filename = "freeway_thicc_v3",
		displayname = "Freeway",
		image = "https://images.steamusercontent.com/ugc/2451740164185127624/79BA8D5F474E08BF8E8236F8D0545DAD038FF72B/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 268,
		height = 268
	},

        {
		filename = "ttt_christmastown",
		displayname = "Christmas Town",
		image = "https://images.steamusercontent.com/ugc/2050867552730917333/12FBA353C73132998BCF14BCD0083CDAF2FBBC51/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 637,
		height = 358
	},

        {
		filename = "abandonment",
		displayname = "Abandonment",
		image = "https://images.steamusercontent.com/ugc/1657853809658072136/5C406ECE73CA322DE6CFD1ADD6A00F8B672ACC18/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 268,
		height = 268
	},
	{
		filename = "gm_baik_stalingrad",
		displayname = "[TDM] Stalingrad",
		image = "https://images.steamusercontent.com/ugc/427070261335385812/F308F3E439A305FA4F35350D8C70D470966D9501/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 637,
		height = 358
	},
	{
		filename = "gm_bbicotka_hmcd",
		displayname = "Bbicotka",
		image = "https://images.steamusercontent.com/ugc/1848170935364477114/4F2ED51C7E9FC390FA14F32D3B12BB138F639080/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 268,
		height = 268
	},
	{
		filename = "gm_frame",
		displayname = "Frame",
		image = "https://images.steamusercontent.com/ugc/1860548820891328629/531EA795A2FB189E0D3696A6D38853D068A9C7B7/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 268,
		height = 268
	},
	{
		filename = "gm_retreat",
		displayname = "Antarctica Bunker",
		image = "https://images.steamusercontent.com/ugc/1771572251306060523/8214DD6D97CD86CFCE619777376EB75A604EA66A/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 268,
		height = 268
	},
	{
		filename = "gm_wick",
		displayname = "Wick's House",
		image = "https://images.steamusercontent.com/ugc/779616049760594011/AD6F95FC3B8F158090095FED977E9EBAFEDFC82E/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 637,
		height = 358
	},
	{
		filename = "gm_ww1_jlps",
		displayname = "Trenches",
		image = "https://images.steamusercontent.com/ugc/170414660099197384/44864BD985A58C9E5482A27C46E19CF5EACB58E8/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 268,
		height = 268
	},
	{
		filename = "cs_market_2_gc",
		displayname = "Market",
		image = "https://images.steamusercontent.com/ugc/952961283025567834/71619377EA1A609EFDA85B3CAB9C85A3E768FE5F/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 268,
		height = 268
	},
	{
		filename = "cs_siege_csgo",
		displayname = "Siege",
		image = "https://images.steamusercontent.com/ugc/803242059820385418/0014A053FA0C43512752AE133088B744719859F7/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 637,
		height = 358
	},
	{
		filename = "de_beroth_beta",
		displayname = "Beroth",
		image = "https://images.steamusercontent.com/ugc/1797521926876255963/418618748194BC76D7326559B5CF88C2D6CC09E3/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 268,
		height = 268
	},
	{
		filename = "de_shanty_v3_fix",
		displayname = "Shanty",
		image = "https://images.steamusercontent.com/ugc/574564421354292808/362BAD9B363CFFEA33F2CFA6B1CB03235673A779/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 268,
		height = 268
	},
	{
		filename = "dm_backwash",
		displayname = "Backwash",
		image = "https://images.steamusercontent.com/ugc/541902544720841510/B52BFD28C157933931BEA663A28F5B28C720F1BF/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 637,
		height = 358
	},
	{
		filename = "dm_stad",
		displayname = "Stad",
		image = "https://images.steamusercontent.com/ugc/540775541813485684/0C7E6873D1AF0127AD91FCA0758AA13EA40CE8E9/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 637,
		height = 358
	},
	{
		filename = "lv1_storage",
		displayname = "Storage",
		image = "https://images.steamusercontent.com/ugc/2487761350986897910/48D263B16B293FEA6472BDA723E301014D71BEBF/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 268,
		height = 268
	},

	{
		filename = "mu_aughts_v1",
		displayname = "Aughts",
		image = "https://images.steamusercontent.com/ugc/7423600155094026/B10B762D7E4F6607EA3442F3A8207DADE4B4B13A/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 268,
		height = 268
	},

	{
		filename = "ins_samawah_day",
		displayname = "Samawah",
		image = "https://images.steamusercontent.com/ugc/14590243576575914812/3D3E9662BA95BBF7AAE75BF0B72E4599089F4D43/?imw=1024&imh=576&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 1024,
		height = 576
	},

	{
		filename = "ttt_hellcrane",
		displayname = "Hellcrane",
		image = "https://images.steamusercontent.com/ugc/1968664484671963415/57BA436639E47738DB5EDA0166807D014480994D/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 637,
		height = 358
	},

	{
		filename = "gm_ruraltown",
		displayname = "Rural Town",
		image = "https://images.steamusercontent.com/ugc/952961148025624668/E7FD3F1D209FBC7FB1030FB34F721BEF6E0EF443/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 637,
		height = 358
	},

	{
		filename = "gm_building_v2_war",
		displayname = "Building War",
		image = "https://images.steamusercontent.com/ugc/32195849048916194/895E2DEDD0259309FA12797BC22BEE14586C9315/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 637,
		height = 358
	},

	{
		filename = "gm_bridge_conflict",
		displayname = "Bridge Conflict",
		image = "https://images.steamusercontent.com/ugc/28805470179213662/EB762141103DFABE7E6201A62B875434FE899353/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 637,
		height = 358
	},

	{
		filename = "rp_almaden",
		displayname = "Almaden",
		image = "https://images.steamusercontent.com/ugc/870746586764085215/71E0C0C34980435D11E023960D087A2419C0DDF6/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 637,
		height = 358
	},

	{
		filename = "ttt_libertycity",
		displayname = "Liberty City",
		image = "https://images.steamusercontent.com/ugc/2247920665249635045/9452454D4D0EBC03C0BD3F6F92168285E60DED2D/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 637,
		height = 358
	},

	{
		filename = "ttt_fernwood",
		displayname = "Fernwood",
		image = "https://images.steamusercontent.com/ugc/11849208252616526998/73F5B9B3BC2E370C830C3D726EBD0D402FA0E14A/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 637,
		height = 358
	},

	{
		filename = "gm_russian_winter_village",
		displayname = "Winter Village",
		image = "https://images.steamusercontent.com/ugc/31059346045463997/BCC55E2EEDEF4180BBB4E1E430F5DD3DAA970662/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 268,
		height = 268
	},

	{
		filename = "ttt_clueless_rv",
		displayname = "Clueless",
		image = "https://images.steamusercontent.com/ugc/1476571419109224664/5FEEACC6E078272330C29BD204AB71AF02C2E0C7/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 637,
		height = 358
	},

	{
		filename = "ttt_5c_plaza",
		displayname = "Plaza",
		image = "https://images.steamusercontent.com/ugc/2303092842269230909/1E244E726268854D7535993B995D49B23DCAD725/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 268,
		height = 268
	},

	{
		filename = "ttt_grovestreet_los",
		displayname = "Grove Street",
		image = "https://images.steamusercontent.com/ugc/155775665897264707/BF569B7EF55909304C4A25E0197B2E6D1B316014/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 637,
		height = 358
	},
	{
		filename = "gm_prison_xmas",
		displayname = "Prison Christmas",
		image = "https://images.steamusercontent.com/ugc/12995951468685456644/E13B3355326D7E776E55FC67EE84B254C73D7C88/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 637,
		height = 358
	},

	{
		filename = "ttt_backyard_v2",
		displayname = "Backyard",
		image = "https://images.steamusercontent.com/ugc/1862812087885375985/67B2EC061B120C8EB107F330CECF386C45DC2D7E/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 637,
		height = 358
	},

	{
		filename = "zs_lighthouse_revived_v1b",
		displayname = "Lighthouse",
		image = "https://images.steamusercontent.com/ugc/2000198497748738599/13E586A590423B5584F59BF9E0D7A9CCECA8853E/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 637,
		height = 358
	},

	{
		filename = "ttt_groverhaus_remastered_a3b",
		displayname = "Groverhaus",
		image = "https://images.steamusercontent.com/ugc/31069315495498129/30949B54BE5F4080590748A55BC10312E99C968B/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 637,
		height = 358
	},

	{
		filename = "ttt_lifetheroof_b2_fix2017",
		displayname = "Lifetheroof",
		image = "https://images.steamusercontent.com/ugc/447331389953883375/62BBB0AD722407AA69417E47FB3A8ECDAE28A472/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 637,
		height = 358
	},

	{
		filename = "gm_building_v2",
		displayname = "Building",
		image = "https://images.steamusercontent.com/ugc/32195215392191746/DD2033A1D797F6F1C1FB32F4A7C5493D8C61E7B3/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 637,
		height = 358
	},

	{
		filename = "ttt_district",
		displayname = "District",
		image = "https://images.steamusercontent.com/ugc/1866183490248546457/B3A25EE51543B3F045E6FD8F49CCD5C915DCA359/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 637,
		height = 358
	},

	{
		filename = "ttt_diescraper",
		displayname = "Diescraper",
		image = "https://images.steamusercontent.com/ugc/44573776974951198/778F67FB3832787CD679C8B58622BA34EB593B63/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 637,
		height = 358
	},

	{
		filename = "ttt_crossroads",
		displayname = "Roblox",
		image = "https://images.steamusercontent.com/ugc/15305629792705154/10160CBDAD2197598C3BD286F143D3B25D8E4E46/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 637,
		height = 358
	},

	{
		filename = "gm_trainride_v1",
		displayname = "Train Ride",
		image = "https://images.steamusercontent.com/ugc/1832406284767477778/8BEBDCE6B096555EF686F7A8E39D7BBFB3D82E53/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 637,
		height = 358
	},

	{
		filename = "gm_1950s_town",
		displayname = "1950s Town",
		image = "https://images.steamusercontent.com/ugc/35243779586131688/A94CD90F3F138CBAA808C39E468FB713240E5D69/",
		width = 637,
		height = 358
	},
	{
		filename = "gm_abandoned_factory",
		displayname = "Abandoned Factory",
		image = "https://i.imgur.com/qa3zbOn.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "zs_adrift_v4",
		displayname = "Adrift",
		image = "https://i.imgur.com/D1UWlcz.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "ttt_airbus_b3",
		displayname = "Airbus",
		image = "https://images.steamusercontent.com/ugc/451793768183537756/784FC8768B2BE0BD677731494CFF957D54C89150/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 268,
		height = 268
	},
	{
		filename = "ttt_amsterville_open",
		displayname = "Amsterville",
		image = "https://i.imgur.com/i64MVDT.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "gm_apartments_v2",
		displayname = "Apartments",
		image = "https://i.imgur.com/KPBfKDx.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "gm_apartments_hl2",
		displayname = "Apartments HL2",
		image = "",
		width = 1920,
		height = 1080
	},
	{
		filename = "gm_assault_sandbox",
		displayname = "Assault",
		image = "https://i.imgur.com/l9uncGb.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "dm_autoroute",
		displayname = "Autoroute",
		image = "https://steamuserimages-a.akamaihd.net/ugc/793110765021454093/855DFAE97ADDB925D55988661DE777D77A996EA9/",
		width = 637,
		height = 358
	},
	{
		filename = "ttt_bank_change",
		displayname = "Bank",
		image = "https://i.imgur.com/aGJXyWJ.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "gm_bbicotka_remastered",
		displayname = "BBicotka Remastered",
		image = "",
		width = 1920,
		height = 1080
	},
	{
		filename = "gm_bbicotka_snow_v1",
		displayname = "BBicotka Snow V1",
		image = "https://steamuserimages-a.akamaihd.net/ugc/5064892335390812278/B8403E1709929D16D3189E97FB5EDE7C1DFE9F64/",
		width = 268,
		height = 268
	},
	{
		filename = "gm_lilys_bedroom",
		displayname = "Bedroom",
		image = "https://i.imgur.com/n8XfLIa.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "gm_chimney",
		displayname = "Chimney",
		image = "https://images.steamusercontent.com/ugc/2482130582399742959/D806FC369AFC22003B0C7FEFBB9EAAB6E3C0EFC1/",
		width = 268,
		height = 268
	},
	{
		filename = "cs_christ_borough",
		displayname = "Christ Borough",
		image = "https://images.steamusercontent.com/ugc/2281698841354777339/714AB654C1E4C9AD52029085CD824D2B909D4784/",
		width = 268,
		height = 268
	},
	{
		filename = "dm_christmas_in_the_suburbs",
		displayname = "Christmas in the Suburbs",
		image = "https://steamuserimages-a.akamaihd.net/ugc/542945375824635764/8BEAAD8BF2A13A104ECF5EBBA2D892C9D0ECCA7F/",
		width = 268,
		height = 268
	},
	{
		filename = "tdm_city18",
		displayname = "City 18",
		image = "https://i.imgur.com/FAFS23T.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "dm_underpass",
		displayname = "City 17 Underpass",
		image = "https://i.imgur.com/oFzdbq3.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "dm_overwatch",
		displayname = "City 17's Streets",
		image = "https://i.imgur.com/PzfgnHc.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "zs_cliffside_night",
		displayname = "Cliffside Night",
		image = "https://steamuserimages-a.akamaihd.net/ugc/1833536468832305787/6368A7A9FD91546DB2569F4D0E2E014E303A1D84/",
		width = 268,
		height = 268
	},
	{
		filename = "ttt_clue_2022",
		displayname = "Clue",
		image = "https://images.steamusercontent.com/ugc/1848170393446499953/D13723BB0F5F4A6182AFD57098EAC87A0E66B57E/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 268,
		height = 268
	},
	{
		filename = "ttt_clue_xmas",
		displayname = "Clue Christmas",
		image = "https://steamuserimages-a.akamaihd.net/ugc/1862800643585569110/A8EDA6E5B93E1FEE7BF7AB6B1D4251EE8A818AA4/",
		width = 637,
		height = 358
	},
	{
		filename = "gm_kleinercomcenter",
		displayname = "Community Center",
		image = "https://i.imgur.com/NfqaleF.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "gm_church",
		displayname = "Country Church",
		image = "https://i.imgur.com/AjtJ3NW.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "ttt_cs_rio",
		displayname = "Rio",
		image = "https://images.steamusercontent.com/ugc/544132148621718525/0473F6A2A5D611D85C49F44B81DFA1646AC79C85/",
		width = 268,
		height = 268
	},
	{
		filename = "ttt_denizen",
		displayname = "Denizen",
		image = "https://images.steamusercontent.com/ugc/2467484540067634826/04701BE4E1302CBBA3D2EDB397A6383BD4DEFCAF/",
		width = 268,
		height = 268
	},
	{
		filename = "cs_drugbust_winter",
		displayname = "Drugbust Winter",
		image = "https://images.steamusercontent.com/ugc/2006946920142316635/11DDD4E2D8633F8C61E5E094E3EA14EA27EF31F2/",
		width = 268,
		height = 268
	},
	{
		filename = "de_dust2",
		displayname = "Dust II",
		image = "https://i.imgur.com/09vBwAA.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "gm_eliden_hmcd",
		displayname = "Eliden",
		image = "https://images.steamusercontent.com/ugc/1870709225849737923/FB608035E31262C7BC4B6E89719DF5954A9DDD87/",
		width = 268,
		height = 268
	},
	{
		filename = "zavod",
		displayname = "EFT Factory",
		image = "https://i.imgur.com/0o19pTl.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "ttt_fastfood_xmas",
		displayname = "Fastfood Christmas",
		image = "https://images.steamusercontent.com/ugc/16001098103064042436/171DDD2754F561DA01127AC12FEC870B7E8467E1/?imw=1024&imh=576&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 1024,
		height = 576
	},

	{
		filename = "ttt_fastfood_a6",
		displayname = "Fastfood",
		image = "https://i.imgur.com/AZmGWhd.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "hmcd_aircraft",
		displayname = "Floating Ship",
		image = "https://i.imgur.com/j9Ahytp.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "freeway_thicc_v3",
		displayname = "Freeway",
		image = "https://i.imgur.com/w9wUmsm.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "gm_freeway_spacetunnel",
		displayname = "Freeway (Space Tunnel)",
		image = "", -- Needs image URL
		width = 1920,
		height = 1080
	},
	{
		filename = "ttt_gas_station",
		displayname = "Gas Station",
		image = "https://images.steamusercontent.com/ugc/1862812795116674409/19B860A87DE46E5E527542885F98AC624E0B50F7/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 637,
		height = 358
	},
	{
		filename = "ttt_grovestreet_a13",
		displayname = "Grove Street",
		image = "https://i.imgur.com/1w3FxcH.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "gm_heavengarden",
		displayname = "Heaven Garden",
		image = "https://steamuserimages-a.akamaihd.net/ugc/25430472004536836/FF3B0BBF097B5B8F20E087A6CC624AE4DEE87974/",
		width = 637,
		height = 358
	},
	{
		filename = "gm_hram",
		displayname = "Hram",
		image = "https://images.steamusercontent.com/ugc/1848169665937012788/5912BEF1B6C35DE016C268EACB16657C779B0B13/",
		width = 268,
		height = 268
	},
	{
		filename = "cs_insertion2_dusk",
		displayname = "Insertion",
		image = "https://i.imgur.com/KJAthSW.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "zs_last_mansion_v3",
		displayname = "Last Mansion",
		image = "https://steamuserimages-a.akamaihd.net/ugc/46502257633427922/0E6DAE34CA47274A0C978DBFC774F4C48A87A83F/",
		width = 268,
		height = 268
	},
	{
		filename = "ttt_lifetheroof",
		displayname = "Life the Roof",
		image = "https://steamuserimages-a.akamaihd.net/ugc/447331671887795106/C3E3FEFC0891E25424F7D4427AE18A4EACE57564/",
		width = 268,
		height = 268
	},
	{
		filename = "ttt_lifetheroof_xmas",
		displayname = "Lifetheroof Christmas",
		image = "https://images.steamusercontent.com/ugc/12109780947427792597/54B3D342A6E4A870F8A254B124D55D623E43F467/?imw=5000&imh=5000&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=false",
		width = 268,
		height = 268
	},
	{
		filename = "ttt_ile_v4",
		displayname = "Lighthouse",
		image = "https://i.imgur.com/pcBZ56Z.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "gm_liminal_hotel",
		displayname = "Liminal Hotel",
		image = "https://i.imgur.com/olQX174.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "rp_lone_pine",
		displayname = "Lone Pine",
		image = "https://steamuserimages-a.akamaihd.net/ugc/4038373796000342/852FFB3961728F5340421BFB2F33878FA0D40F21/",
		width = 268,
		height = 268
	},
	{
		filename = "gm_mafiamansion",
		displayname = "Mafia Mansion",
		image = "https://steamuserimages-a.akamaihd.net/ugc/25432209487088929/922EB68A9C30B192417C9131AA166D6B5542F268/",
		width = 637,
		height = 358
	},
	{
		filename = "ttt_minecraft_b5",
		displayname = "Minecraft B5",
		image = "https://i.imgur.com/u2pFlcs.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "ttt_minecraftcity_v4",
		displayname = "Minecraft City",
		image = "https://i.imgur.com/LGlZOMT.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "ttt_mc_island_2013",
		displayname = "Minecraft Island",
		image = "https://i.imgur.com/FBkaQTn.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "gm_grant_street",
		displayname = "Neon Tokyo",
		image = "https://i.imgur.com/3VUaVT5.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "sm_manhattanmegamallnightv1",
		displayname = "Mega Mall",
		image = "https://i.imgur.com/JDbC6hu.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "dm_lockdown",
		displayname = "Nova Prospekt Lockdown",
		image = "https://i.imgur.com/iykF5Ji.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "cs_office_night",
		displayname = "Office Night",
		image = "https://images.steamusercontent.com/ugc/34104000781391674/A3812A3BB8D22614C33D925872C939403AA73622/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 637,
		height = 358
	},
	{
		filename = "cs_office-unlimited",
		displayname = "Office Unlimited",
		image = "https://i.imgur.com/S2T3jQ8.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "gm_building",
		displayname = "Office Building",
		image = "https://i.imgur.com/DIgrELg.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "gm_paradise_resort",
		displayname = "Paradise Resort",
		image = "https://i.imgur.com/KkqgNll.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "mu_powerhermit",
		displayname = "Power Hermit",
		image = "https://images.steamusercontent.com/ugc/703985853899817204/7664C9E0912978F352997C6C1FB08EDCB7BA5368/",
		width = 268,
		height = 268
	},
	{
		filename = "dm_resistance",
		displayname = "Resistance HQ",
		image = "https://i.imgur.com/ZPXmjle.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "ttt_rooftops_2016_v1",
		displayname = "Rooftops",
		image = "https://images.steamusercontent.com/ugc/574565056145859159/06E58BDE9EF0C629D8D82BA4BD6827291173245E/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 268,
		height = 268
	},
	{
		filename = "gm_deschool",
		displayname = "School Remastered",
		image = "https://i.imgur.com/JoPG7Wm.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "de_school2",
		displayname = "School Old",
		image = "https://steamuserimages-a.akamaihd.net/ugc/477771277038257194/1B32EA910F16BFEAC17E80F174FC7FE9F920657E/",
		width = 637,
		height = 358
	},
	{
		filename = "ph_scotch",
		displayname = "Scotch",
		image = "https://i.imgur.com/pWp9Az4.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "gm_sentimental98v1",
		displayname = "Sentimental",
		image = "https://steamuserimages-a.akamaihd.net/ugc/2429215188817953961/D7F0DCDE2F8BF4846BA2E8671D797C7790F17C6F/",
		width = 268,
		height = 268
	},
	{
		filename = "mu_smallotown_v2_snow",
		displayname = "Small Town Christmas",
		image = "https://i.imgur.com/xquWM5T.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "dm_steamlab",
		displayname = "Steam HQ",
		image = "https://i.imgur.com/2nuVKJr.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "ttt_sw_cantina_v1",
		displayname = "SW Cantina V1",
		image = "https://steamuserimages-a.akamaihd.net/ugc/922544719528325865/D63B0082A09788075DF8DC03C9AF528FF1D90AC5/",
		width = 268,
		height = 268
	},
	{
		filename = "gm_terminal_v1a",
		displayname = "Terminal",
		image = "https://i.imgur.com/3DZBDGS.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "ttt_terrortown",
		displayname = "Terror Town",
		image = "https://images.steamusercontent.com/ugc/702857494015515228/2293B11359399CAA10386DCB71CB9989683C29F8/",
		width = 268,
		height = 268
	},
	{
		filename = "ttt_terrortrain_2020_b5",
		displayname = "Terror Train",
		image = "https://i.imgur.com/HJNGC9p.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "dm_transit",
		displayname = "Transit",
		image = "https://images.steamusercontent.com/ugc/853851618304705190/39134FCC5718407012F1FD7D973D4769B7704594/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
		width = 637,
		height = 358
	},
	{
		filename = "gm_wick",
		displayname = "Wick's House",
		image = "https://i.imgur.com/qPwmEke.jpeg",
		width = 1920,
		height = 1080
	},
	{
		filename = "ttt_winterplant_v4",
		displayname = "Winter Power Plant",
		image = "", -- Needs image URL
		width = 1920,
		height = 1080
	},
	{
		filename = "gm_ww1_jlps",
		displayname = "WW1 JLPS",
		image = "https://steamuserimages-a.akamaihd.net/ugc/170414660099197384/44864BD985A58C9E5482A27C46E19CF5EACB58E8/",
		width = 268,
		height = 268
	},
    {
        filename = "de_survivor",
        displayname = "Survivor",
        image = "https://images.steamusercontent.com/ugc/1701780512559542039/615A625DF8A6A239BEE8FA138512A3BA81D5C95E/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "gm_broadcasting_station",
        displayname = "Broadcasting Station",
        image = "https://images.steamusercontent.com/ugc/32192049026217129/C8E76D593FA7EC49586D75E4F14DD071AAAF5F78/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "gm_funkis",
        displayname = "Funkis",
        image = "https://images.steamusercontent.com/ugc/14170847377989121/6304577EFB7EF559F0A9464378975E1FE119CFED/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 637,
        height = 358
    },
    {
        filename = "gm_oilrig",
        displayname = "Oilrig",
        image = "https://images.steamusercontent.com/ugc/17284798545478651403/B4B430C36343F7BEF314186664D8D2F21A5DDE01/?imw=268&imh=268&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 268,
        height = 268
    },
    {
        filename = "gm_stage_6",
        displayname = "Stage 6",
        image = "https://images.steamusercontent.com/ugc/2527164217048896920/A8D66F6B58AC2BB792D57FD1795DAA6769E24474/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 637,
        height = 358
    },
    {
        filename = "gm_sosnovka2_night",
        displayname = "Sosnovka Night",
        image = "https://images.steamusercontent.com/ugc/5097543432676798407/13FD2F29AA8F8763E4FAAC7230B90EB9F1AF587A/?imw=637&imh=358&ima=fit&impolicy=Letterbox&imcolor=%23000000&letterbox=true",
        width = 637,
        height = 358
    },
}
-- Copied from MAIN RTV on 2026-09-12; enforced for every map source.
SolidMapVote.Config["Map Blacklist"] = {
    ["gm_blighthouse_pr_night"] = true,
    ["gm_construct"] = true, ["gm_flatgrass"] = true, ["gm_altarskforest"] = true, ["gm_renostruct_v2"] = true,
    ["gm_renostruct_v2_night"] = true, ["gm_city_of_silence"] = true, ["ttt_hogwarts"] = true,
    ["gm_fork_better"] = true, ["gm_gmarket"] = true,
    ["zs_abandonedmall_2025_v5a"] = true,
    ["zs_abandonedmall_2025_v6"] = true,
    ["gm_c17_ivaylo"] = true, ["gm_c17_ivayloZ_csm"] = true,
}
SolidMapVote.Config["Allowed Prefixes"] = {
    ["ttt"] = true, ["hmcd"] = true, ["mu"] = true, ["ze"] = false,
    ["zs"] = true, ["tdm"] = true, ["zb"] = false, ["zbattle"] = false,
    ["gm"] = true, ["ph"] = true, ["cs"] = true, ["de"] = true
}
SolidMapVote.Config["Map Limit"] = 6
SolidMapVote.Config["Rounds Per Vote"] = 16

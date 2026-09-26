-- Read-only probe for "player cannot be turned into a crawler".
--
-- hg.ZCityGore_AmputateTorso (Gore V2 EnsureFakeAndSplit) refuses for two
-- different reasons, and the context menu reports them differently:
--
--   A. stale state - ply:GetNWBool("ZCityTorsoSevered") or organism.torsoamputated
--      is still true from an earlier life. MakeCrawler short-circuits before the
--      native call and says "already has native torso amputation".
--      Gore V2 clears the PLAYER flag on PlayerSpawn only, never clears
--      organism.torsoamputated, and never clears the flag it set on the RAGDOLL.
--
--   B. unsupported skeleton - BuildSplitRagdolls needs
--      ValveBiped.Bip01_Spine2 with a physics object on the live body. A
--      non-ValveBiped playermodel returns nil and MakeCrawler says
--      "native_torso_rejected".
--
-- Both look like "immune" in game. This changes nothing; it only reports.
-- zc_crawler_diag  -> console table + data/zc_crawler_diag/report.txt

if not SERVER then return end

local VERSION = "20260922.1"
if ZCCrawlerDiag and ZCCrawlerDiag.Version == VERSION then return end

ZCCrawlerDiag = ZCCrawlerDiag or {}
local D = ZCCrawlerDiag
D.Version = VERSION

local function boneOK(ent, name)
    if not IsValid(ent) then return "no_ent" end
    local bone = ent:LookupBone(name)
    if bone == nil or bone < 0 then return "missing" end
    local id = ent:TranslateBoneToPhysBone(bone)
    if id == nil or id < 0 then return "no_physbone" end
    if not IsValid(ent:GetPhysicsObjectNum(id)) then return "no_phys" end
    return "ok"
end

function D.Inspect(ply)
    local org = type(ply.organism) == "table" and ply.organism or nil
    local rag = ply.FakeRagdoll
    local body = hg and hg.GetCurrentCharacter and hg.GetCurrentCharacter(ply) or nil

    local row = {
        nick = ply:Nick(),
        steamid = ply:SteamID64(),
        alive = ply:Alive(),
        model = ply:GetModel() or "?",
        plyFlag = ply:GetNWBool("ZCityTorsoSevered", false),
        ragValid = IsValid(rag),
        ragFlag = IsValid(rag) and rag:GetNWBool("ZCityTorsoSevered", false) or false,
        torsoamputated = org and org.torsoamputated or false,
        lleg = org and org.llegamputated or false,
        rleg = org and org.rlegamputated or false,
        pending = ply.__zcGoreTorsoPending and true or false,
        blastQueued = ply.__zcGoreBlastQueued and true or false,
        lowerTorso = IsValid(ply.__zcGoreLowerTorso),
        spine2 = boneOK(body, "ValveBiped.Bip01_Spine2"),
        pelvis = boneOK(body, "ValveBiped.Bip01_Pelvis"),
        isCrawler = ZCMakeCrawler and ZCMakeCrawler.IsCrawler and ZCMakeCrawler.IsCrawler(ply) or false
    }

    -- The verdict MakeCrawler would reach right now, without calling anything.
    if not row.alive then
        row.verdict = "dead"
    elseif row.plyFlag or row.torsoamputated then
        row.verdict = "A_stale_state_reports_already"
    elseif row.pending then
        row.verdict = "native_transition_pending"
    elseif row.spine2 ~= "ok" then
        row.verdict = "B_skeleton_" .. row.spine2
    else
        row.verdict = "would_apply"
    end

    return row
end

function D.Report()
    local rows = {}
    for _, ply in ipairs(player.GetHumans()) do
        rows[#rows + 1] = D.Inspect(ply)
    end
    return rows
end

concommand.Add("zc_crawler_diag", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end

    local rows = D.Report()
    local lines = {"[zc_crawler_diag] " .. VERSION .. " " .. os.date("!%Y-%m-%dT%H:%M:%SZ")}

    for _, r in ipairs(rows) do
        lines[#lines + 1] = string.format(
            "%-20s %s alive=%s verdict=%-32s plyFlag=%s ragFlag=%s(valid=%s) torsoamp=%s legs=%s/%s pending=%s lower=%s spine2=%s pelvis=%s isCrawler=%s model=%s",
            string.sub(r.nick, 1, 20), r.steamid, tostring(r.alive), r.verdict,
            tostring(r.plyFlag), tostring(r.ragFlag), tostring(r.ragValid),
            tostring(r.torsoamputated), tostring(r.lleg), tostring(r.rleg),
            tostring(r.pending), tostring(r.lowerTorso),
            r.spine2, r.pelvis, tostring(r.isCrawler), r.model)
    end

    if #rows == 0 then lines[#lines + 1] = "(no human players)" end

    local text = table.concat(lines, "\n")
    file.CreateDir("zc_crawler_diag")
    -- Bounded: an admin re-running this must not grow a file forever.
    local previous = file.Read("zc_crawler_diag/report.txt", "DATA") or ""
    if #previous > 60000 then previous = string.sub(previous, -30000) end
    file.Write("zc_crawler_diag/report.txt", previous .. text .. "\n\n")

    if IsValid(ply) then
        for _, line in ipairs(lines) do ply:PrintMessage(HUD_PRINTCONSOLE, line) end
    else
        print(text)
    end
end)

print("[zc_crawler_diag] Loaded " .. VERSION)

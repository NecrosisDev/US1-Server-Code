-- Private zombie HUD; never sends original allegiance or another player's role.
local old=ZC_POSTMORTEM_CLIENT
if old and old.Restore then old.Restore() end
local C={generation=-1,active=false}
ZC_POSTMORTEM_CLIENT=C
surface.CreateFont("ZC_Postmortem",{font="Tahoma",size=20,weight=700,antialias=true})
local function Active()
    local p=LocalPlayer()
    return C.active and IsValid(p) and p:Alive() and p.PlayerClassName=="headcrabzombie"
        and zb and zb.modes and type(CurrentRound)=="function" and zb.ROUND_STATE==1
        and zb.ROUND_START==C.stamp and CurrentRound()==zb.modes.hmcd and CurrentRound().Type==C.variant
end
function C.Restore()
    if C.mode and C.mode.HUDPaint==C.wrapper then C.mode.HUDPaint=C.original end
    C.mode,C.original,C.wrapper=nil,nil,nil
end
net.Receive("zc_postmortem",function()
    local gen,active,variant,stamp=net.ReadUInt(32),net.ReadBool(),net.ReadString(),net.ReadFloat()
    if gen<C.generation or (gen==C.generation and C.retired and active) then return end
    if gen>C.generation then C.retired=false end
    -- Waiting/rising snapshots are false; they must not retire an event before its first activation.
    if not active and C.active and gen==C.generation then C.retired=true end
    C.generation,C.active,C.variant,C.stamp=gen,active,variant,stamp
    if not active then C.Restore() end
end)
hook.Add("Think","zc_postmortem",function()
    if not Active() then C.Restore(); return end
    local p,mode=LocalPlayer(),CurrentRound()
    p.isTraitor,p.MainTraitor,p.isGunner,p.SubRole=false,false,false,nil
    if mode.HUDPaint~=C.wrapper then
        C.Restore()
        if type(mode.HUDPaint)~="function" then return end
        C.mode,C.original=mode,mode.HUDPaint
        local original=mode.HUDPaint
        C.wrapper=function(self,...) if not Active() then return original(self,...) end end
        mode.HUDPaint=C.wrapper
    end
end)
hook.Add("HUDPaint","zc_postmortem",function()
    if not Active() then return end
    draw.SimpleText("Postmortem: Zombie","ZC_Postmortem",ScrW()/2,ScrH()*0.78,Color(190,65,55),TEXT_ALIGN_CENTER)
    draw.SimpleText("Hunt the living. This is your last life.","ZC_Postmortem",ScrW()/2,ScrH()*0.78+26,color_white,TEXT_ALIGN_CENTER)
end)

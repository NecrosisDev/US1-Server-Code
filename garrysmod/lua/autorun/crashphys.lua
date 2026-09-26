if SERVER then
    util.AddNetworkString("PhysgunDispatchCrashScreen")
    function PhysgunDispatchCrashScreen(server_id, inst)
        print("[Physgun] Dispatching crash screen")

        -- you can add your own code here, be careful as there is no recovery or error handling.
        -- try not to interact with the engine too much.

        net.Start("PhysgunDispatchCrashScreen")
        net.WriteString(server_id)
        net.WriteString(inst)
        net.Broadcast()
    end
    return
end

RunConsoleCommand("sv_timeout", "9999")
RunConsoleCommand("cl_timeout", "9999")

local function DrawCrashScreen(state)
    draw.NoTexture()
    surface.SetDrawColor(0, 0, 0, 253)
    surface.DrawRect(0, 0, ScrW(), ScrH())
    local text = "Physgun.com CrashHandler"
    local font = "Trebuchet18"
    draw.SimpleText(text, font, ScrW() - 5, 5, Color(255, 255, 255, 255), TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
    font = "DermaLarge"
    text = "Oh No! The server has crashed!\nDon't Worry, the server is already restarting.\nYou will be reconnected shortly.\n" .. state
    local w, h = surface.GetTextSize(text)
    draw.DrawText(text, font, ScrW() / 2, ScrH() / 2 - h, Color(255, 255, 255, 255), TEXT_ALIGN_CENTER)
end

net.Receive("PhysgunDispatchCrashScreen", function()
    local server_id = net.ReadString()
    local inst = net.ReadString()

    print("The server has crashed - Loading Crash Screen")

    local PC_STATE = "..."
    local function RunCheck()
        http.Fetch("https://api.physgun.com/api/crash/" .. server_id .. "?instance=" .. inst, function(body)
            local data = util.JSONToTable(body)
            if data and data.success then
                PC_STATE = data[0] and data[0].state or "..."
                if data[0] and data[0].retry then
                    RunConsoleCommand("retry")
                end
            else
                PC_STATE = "..."
            end
        end, function() end)
    end

    RunConsoleCommand("sv_timeout", "9999")
    RunConsoleCommand("cl_timeout", "9999")

    local lastTime
    hook.Add("HUDPaint", "PaintPhysgunCrashScreen", function()
        if not lastTime then
            lastTime = os.time()
        end

        if os.time() - lastTime > 10 then
            RunCheck()
            lastTime = os.time()
        end

        DrawCrashScreen(PC_STATE)
    end)
end)

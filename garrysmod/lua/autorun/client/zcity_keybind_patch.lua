--========================================================--

-- zcity_keybind_patch.lua

-- V012 (Русский / English)

--========================================================--



if SERVER then return end



local PATCH_NAME = "ZCity_Keybind_V012"



--========================================================--

-- Файлы сохранения

--========================================================--



local SAVE_FILE = "zcity_keybinds.txt"

local CONFIG_FILE = "zcity_config.txt"



--========================================================--

-- Языки

--========================================================--



local LANGUAGES = {

    ["ru"] = "Русский",

    ["en"] = "English"

}



local CURRENT_LANG = "ru"



--========================================================--

-- Текст на русском и английском

--========================================================--



local TEXTS = {

    -- Окно помощи

    help_title = {

        ru = "Помощь по привязке клавиш",

        en = "Keybind Help"

    },

    help_header = {

        ru = [[

Своя привязка означает клавишу, которую вы назначили в консоли с помощью команды "bind".

Вы можете отменить привязку клавиши командой "unbind".

Введите в консоли "key_listboundkeys", чтобы увидеть все ваши привязки через команду "bind" (и настройки Gmod).



Общие подсказки по клавишам:

Клавиша [Alt] + Клавиша [E]: свернуть шею со спины

Клавиша [Alt] + Клавиша [R]: маскировка под одежду трупа

Клавиша [E] + Клавиша [ЛКМ]: бить с приклада оружием

Клавиша [ПКМ] + Клавиша [E]: обыск предметов

В рэгдолле + Клавиша [E]: управлять головой

В рэгдолле + Клавиша [Shift]: захват левой рукой

В рэгдолле + Клавиша [Alt]: захват правой рукой

]],

        en = [[

Custom bind means the key you assigned in the console using the "bind" command.

You can unbind a key using the "unbind" command.

Type "key_listboundkeys" in the console to see all your binds from the "bind" command (and Gmod settings).



General key hints:

Key [Alt] + Key [E]: Snap neck from behind

Key [Alt] + Key [R]: Disguise as corpse clothing

Key [E] + Key [LMB]: Melee with weapon butt

Key [RMB] + Key [E]: Loot items

In ragdoll + Key [E]: Control head

In ragdoll + Key [Shift]: Left hand grab

In ragdoll + Key [Alt]: Right hand grab

]]

    },

    links_header = {

        ru = "Связанные ссылки",

        en = "Related Links"

    },

    

    -- Основное меню

    tab_title = {

        ru = "Привязка клавиш",

        en = "Keybinds"

    },

    gameplay_header = {

        ru = "Игровой процесс",

        en = "Gameplay"

    },

    

    -- Кнопки

    btn_help = {

        ru = "Помощь",

        en = "Help"

    },

    btn_clear = {

        ru = "Очистить",

        en = "Clear"

    },

    btn_language = {

        ru = "Язык",

        en = "Language"

    },

    

    -- Метки

    native_bind = {

        ru = "Своя привязка",

        en = "Custom bind"

    },

    

    -- Консольные сообщения

    msg_reload = {

        ru = "Конфигурация перезагружена",

        en = "Configuration reloaded"

    },

    msg_reset = {

        ru = "Восстановлены стандартные клавиши",

        en = "Default keys restored"

    },

    msg_lang_changed = {

        ru = "Язык изменён на: ",

        en = "Language changed to: "

    },

    tab_added = {

        ru = "Вкладка добавлена",

        en = "Tab added"

    },

    loaded = {

        ru = "Загружен (Русский/English)",

        en = "Loaded (Russian/English)"

    },

    

    -- Названия действий

    bind_kick = {

        ru = "Пинок",

        en = "Kick"

    },

    bind_fake = {

        ru = "Рэгдолл",

        en = "Ragdoll"

    },

    bind_laser = {

        ru = "Вкл/Выкл лазерное крепление оружия",

        en = "Toggle weapon laser"

    },

    bind_leanleft = {

        ru = "Наклон влево",

        en = "Lean left"

    },

    bind_leanright = {

        ru = "Наклон вправо",

        en = "Lean right"

    },

    bind_breath = {

        ru = "Задержать дыхание",

        en = "Hold breath"

    },

    bind_look = {

        ru = "Осмотреться",

        en = "Look around"

    },

    bind_zoom = {

        ru = "Приблизить камеру",

        en = "Zoom camera"

    }

}



--========================================================--

-- Функция получения текста

--========================================================--



local function GetText(key, ...)

    local text = TEXTS[key]

    if not text then return "[" .. key .. "]" end

    

    local str = text[CURRENT_LANG] or text["en"] or text["ru"] or ""

    

    if select("#", ...) > 0 then

        return string.format(str, ...)

    end

    return str

end



--========================================================--

-- Сохранение и загрузка языка

--========================================================--



local function SaveLanguage()

    file.Write(CONFIG_FILE, CURRENT_LANG)

end



local function LoadLanguage()

    if file.Exists(CONFIG_FILE, "DATA") then

        local saved = file.Read(CONFIG_FILE, "DATA")

        if saved and LANGUAGES[saved] then

            CURRENT_LANG = saved

        end

    end

end



--========================================================--

-- Определения привязок

--========================================================--



local Binds = {

    {

        command = "hg_kick",

        key = KEY_NONE,

        hold = false

    },

    {

        command = "fake",

        key = KEY_NONE,

        hold = false

    },

    {

        command = "hmcd_togglelaser",

        key = KEY_NONE,

        hold = false

    },

    {

        command = "+alt1",

        key = KEY_NONE,

        hold = true

    },

    {

        command = "+alt2",

        key = KEY_NONE,

        hold = true

    },

    {

        command = "+hmcd_holdbreath",

        key = KEY_NONE,

        hold = true

    },

    {

        command = "+altlook",

        key = KEY_NONE,

        hold = true

    },

    {

        command = "+hg_zoom",

        key = KEY_NONE,

        hold = true

    }

}



-- Получение названия привязки

local function GetBindTitle(command)

    local titles = {

        hg_kick = "bind_kick",

        fake = "bind_fake",

        hmcd_togglelaser = "bind_laser",

        ["+alt1"] = "bind_leanleft",

        ["+alt2"] = "bind_leanright",

        ["+hmcd_holdbreath"] = "bind_breath",

        ["+altlook"] = "bind_look",

        ["+hg_zoom"] = "bind_zoom"

    }

    return GetText(titles[command] or command)

end



--========================================================--

-- Сохранение и загрузка привязок

--========================================================--



local function SaveKeyBinds()

    local data = {}

    for _, bind in ipairs(Binds) do

        data[bind.command] = bind.key

    end

    file.Write(SAVE_FILE, util.TableToJSON(data, true))

end



local function LoadKeyBinds()

    if not file.Exists(SAVE_FILE, "DATA") then

        SaveKeyBinds()

        return

    end

    local content = file.Read(SAVE_FILE, "DATA")

    if not content then return end

    local data = util.JSONToTable(content)

    if not data then return end

    for _, bind in ipairs(Binds) do

        local savedKey = data[bind.command]

        if savedKey then

            bind.key = tonumber(savedKey) or bind.key

        end

    end

end



LoadKeyBinds()

LoadLanguage()



--========================================================--

-- Вспомогательные функции

--========================================================--



local function GetNativeBind(command)

    local native = input.LookupBinding(command)

    if not native then return nil end

    return string.upper(native)

end



--========================================================--

-- Выполнение команд

--========================================================--



local ZoomDown = false



hook.Add("PlayerButtonDown", PATCH_NAME .. "_Down", function(ply, button)

    if ply ~= LocalPlayer() then return end

    if gui.IsGameUIVisible() then return end

    local focus = vgui.GetKeyboardFocus()

    if IsValid(focus) then return end

    

    for _, bind in ipairs(Binds) do

        if bind.key == KEY_NONE then continue end

        if button ~= bind.key then continue end

        

        if bind.hold then

            if not ZoomDown then

                ZoomDown = true

                RunConsoleCommand(bind.command)

            end

        else

            RunConsoleCommand(bind.command)

        end

        return

    end

end)



hook.Add("PlayerButtonUp", PATCH_NAME .. "_Up", function(ply, button)

    if ply ~= LocalPlayer() then return end

    

    for _, bind in ipairs(Binds) do

        if not bind.hold then continue end

        if bind.key == KEY_NONE then continue end

        if button ~= bind.key then continue end

        

        if ZoomDown then

            ZoomDown = false

            local cmd = bind.command

            if string.StartWith(cmd, "+") then

                RunConsoleCommand("-" .. string.sub(cmd, 2))

            end

        end

    end

end)



--========================================================--

-- Смена языка (ОПРЕДЕЛЯЕМ РАНЬШЕ)

--========================================================--



local function RefreshAllUI()

    if IsValid(ZCityKeybindHelpFrame) then

        ZCityKeybindHelpFrame:Remove()

    end

    

    local menu = MainMenu

    if IsValid(menu) and menu.ZCityKeybindPage and IsValid(menu.ZCityKeybindPage) then

        -- Функция DrawKeyBindings будет определена позже, но вызовется только когда меню уже открыто

        if DrawKeyBindings then

            DrawKeyBindings(menu.ZCityKeybindPage)

        end

    end

end



local function SetLanguage(lang)

    if not LANGUAGES[lang] then return false end

    

    CURRENT_LANG = lang

    SaveLanguage()

    

    chat.AddText(Color(0, 255, 0), GetText("msg_lang_changed"), LANGUAGES[lang])

    

    RefreshAllUI()

    return true

end



--========================================================--

-- Окно помощи

--========================================================--



local HELP_LINKS = {

    {

        name_ru = "Ссылка на аддон ENG/RU",

        name_en = "Addon Link ENG/RU",

        url = "https://steamcommunity.com/sharedfiles/filedetails/?id=3737887777"

    },

    {

        name_ru = "Ссылка на оригинал CN",

        name_en = "Original Link CN",

        url = "https://steamcommunity.com/sharedfiles/filedetails/?id=3736711821"

    },

    {

        name_ru = "Автор",

        name_en = "Author",

        url = "https://steamcommunity.com/profiles/76561198211540476/"

    },

    {

        name_ru = "Другой автор",

        name_en = "Other Author",

        url = "https://steamcommunity.com/id/illnk1/"

    }

}



local function OpenHelpWindow()

    if IsValid(ZCityKeybindHelpFrame) then

        ZCityKeybindHelpFrame:Remove()

    end

    

    local frame = vgui.Create("DFrame")

    frame:SetSize(700, 500)

    frame:Center()

    frame:SetTitle(GetText("help_title"))

    frame:MakePopup()

    ZCityKeybindHelpFrame = frame

    

    local left = vgui.Create("DPanel", frame)

    left:Dock(FILL)

    left:DockMargin(5, 5, 5, 5)

    left.Paint = function(self, w, h)

        surface.SetDrawColor(35, 35, 35, 255)

        surface.DrawRect(0, 0, w, h)

    end

    

    local text = vgui.Create("RichText", left)

    text:Dock(TOP)

    text:SetTall(250)

    function text:PerformLayout()

        self:SetFontInternal("DermaDefault")

        self:SetFGColor(Color(255, 255, 255))

    end

    function text:Paint(w, h)

        surface.SetDrawColor(25, 25, 25, 255)

        surface.DrawRect(0, 0, w, h)

        self:DrawTextEntryText(color_white, color_white, color_white)

    end

    text:SetVerticalScrollbarEnabled(true)

    text:InsertColorChange(255, 255, 255, 255)

    text:AppendText(GetText("help_header"))

    

    local header = vgui.Create("DLabel", left)

    header:Dock(TOP)

    header:DockMargin(5, 10, 5, 10)

    header:SetText(GetText("links_header"))

    header:SetFont("DermaLarge")

    header:SizeToContents()

    

    for _, linkData in ipairs(HELP_LINKS) do

        local btn = vgui.Create("DButton", left)

        btn:Dock(TOP)

        btn:DockMargin(5, 0, 5, 5)

        btn:SetTall(30)

        

        local linkName = (CURRENT_LANG == "ru") and linkData.name_ru or linkData.name_en

        btn:SetText(linkName)

        

        btn.DoClick = function()

            gui.OpenURL(linkData.url)

        end

    end

end



--========================================================--

-- Строка привязки

--========================================================--



local function CreateBindRow(parent, bind)

    local row = vgui.Create("DPanel", parent)

    row:Dock(TOP)

    row:DockMargin(10, 5, 10, 0)

    row:SetTall(72)

    

    row.Paint = function(self, w, h)

        surface.SetDrawColor(40, 40, 40, 220)

        surface.DrawRect(0, 0, w, h)

        draw.SimpleText(GetBindTitle(bind.command), "DermaDefaultBold", 10, 10, color_white)

        draw.SimpleText(bind.command, "DermaDefault", 10, 28, Color(180, 180, 180))

        

        local nativeBind = GetNativeBind(bind.command)

        if nativeBind then

            draw.SimpleText(GetText("native_bind") .. ": " .. nativeBind, "DermaDefault", 10, 46, Color(180, 180, 180))

        end

    end

    

    local binder = vgui.Create("DBinder", row)

    local oldPaint = binder.Paint

    binder.Paint = function(self, w, h)

        if oldPaint then oldPaint(self, w, h) end

        surface.SetDrawColor(180, 0, 0, 255)

        surface.DrawOutlinedRect(0, 0, w, h)

    end

    binder:Dock(RIGHT)

    binder:DockMargin(0, 8, 10, 8)

    binder:SetWide(150)

    binder:SetValue(bind.key)

    

    function binder:OnChange(key)

        if not key then return end

        bind.key = key

        SaveKeyBinds()

    end

    

    local clear = vgui.Create("DButton", row)

    clear:Dock(RIGHT)

    clear:DockMargin(0, 8, 5, 8)

    clear:SetWide(60)

    clear:SetText(GetText("btn_clear"))

    

    local clearOldPaint = clear.Paint

    clear.Paint = function(self, w, h)

        if clearOldPaint then clearOldPaint(self, w, h) end

        surface.SetDrawColor(180, 0, 0, 255)

        surface.DrawOutlinedRect(0, 0, w, h)

    end

    

    clear.DoClick = function()

        bind.key = KEY_NONE

        SaveKeyBinds()

        binder:SetValue(KEY_NONE)

    end

end



--========================================================--

-- Отображение привязок клавиш

--========================================================--



local function DrawKeyBindings(parent)

    parent:Clear()

    

    local scroll = vgui.Create("DScrollPanel", parent)

    scroll:Dock(FILL)

    local canvas = scroll:GetCanvas()

    

    local header = vgui.Create("DPanel", canvas)

    header:Dock(TOP)

    header:DockMargin(10, 10, 10, 10)

    header:SetTall(40)

    header.Paint = function(self, w, h)

        surface.SetDrawColor(60, 60, 60, 220)

        surface.DrawRect(0, 0, w, h)

        draw.SimpleText(GetText("gameplay_header"), "DermaDefaultBold", 15, h / 2, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

    end

    

    -- Кнопка помощи

    local helpBtn = vgui.Create("DButton", header)

    helpBtn:Dock(RIGHT)

    helpBtn:DockMargin(0, 5, 5, 5)

    helpBtn:SetWide(80)

    helpBtn:SetText(GetText("btn_help"))

    helpBtn.DoClick = function()

        OpenHelpWindow()

    end

    

    -- Кнопка выбора языка

    local langBtn = vgui.Create("DButton", header)

    langBtn:Dock(RIGHT)

    langBtn:DockMargin(0, 5, 5, 5)

    langBtn:SetWide(100)

    langBtn:SetText(GetText("btn_language") .. ": " .. LANGUAGES[CURRENT_LANG])

    

    local langMenuCreated = false

    langBtn.DoClick = function()

        if langMenuCreated then return end

        local menu = DermaMenu()

        

        for code, name in pairs(LANGUAGES) do

            menu:AddOption(name, function()

                SetLanguage(code)

                langBtn:SetText(GetText("btn_language") .. ": " .. LANGUAGES[CURRENT_LANG])

                langMenuCreated = false

            end)

        end

        

        menu:Open()

        langMenuCreated = true

        menu.OnRemove = function() langMenuCreated = false end

    end

    

    for _, bind in ipairs(Binds) do

        CreateBindRow(canvas, bind)

    end

end



--========================================================--

-- Патч меню

--========================================================--



local function AddKeybindTab(menu)

    if not IsValid(menu) then return end

    if menu.ZCityKeybindAdded then return end

    

    menu.ZCityKeybindAdded = true

    

    menu:AddSelect(menu.lDock, GetText("tab_title"), {

        Func = function(luaMenu, page)

            if ZCGoobApps then
                ZCGoobApps.State.settings = ZCGoobApps.State.settings or {query=""}
                ZCGoobApps.State.settings.tab = "Keybinds"
                if ZCGoobApps.Launch("settings") then luaMenu:Close(); return end
            end
            menu.ZCityKeybindPage = page

            DrawKeyBindings(page)

        end

    })

    

    print("[ZCity Keybind Patch] " .. GetText("tab_added"))

end



--========================================================--

-- Запуск

--========================================================--



hook.Add("Think", PATCH_NAME .. "_MenuWatcher", function()

    local menu = MainMenu

    if not IsValid(menu) then return end

    AddKeybindTab(menu)

end)



hook.Add("ShutDown", PATCH_NAME .. "_Shutdown", function()

    SaveKeyBinds()

end)



--========================================================--

-- Консольные команды

--========================================================--



concommand.Add("zcity_keybind_reload", function()

    LoadKeyBinds()

    chat.AddText(Color(0, 255, 0), GetText("msg_reload"))

end)



concommand.Add("zcity_keybind_reset", function()

    local defaults = {

        hg_kick = KEY_G,

        fake = KEY_F,

        ["+hg_zoom"] = KEY_LALT

    }

    for _, bind in ipairs(Binds) do

        local key = defaults[bind.command]

        if key then bind.key = key end

    end

    SaveKeyBinds()

    chat.AddText(Color(255, 200, 0), GetText("msg_reset"))

end)



concommand.Add("zcity_keybind_lang", function(_, lang)

    if lang and LANGUAGES[lang] then

        SetLanguage(lang)

    else

        print("Доступные языки / Available languages: ru, en")

    end

end)



concommand.Add("zcity_keybind_dump", function()

    print("========== ZCity Привязки клавиш ==========")

    for _, bind in ipairs(Binds) do

        print(GetBindTitle(bind.command), bind.command, bind.key)

    end

    print("Current language: " .. CURRENT_LANG)

    print("============================================")

end)



print("[ZCity Keybind Patch] V012 " .. GetText("loaded"))
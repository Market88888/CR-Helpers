script_name("PC Stats")
script_description("Statistika personazha | Arizona PC | by Marco_Santiago (PC port)")
script_author("Marco_Santiago")

-- ФИКС: script_version() и SCRIPT_VER раньше были ДВУМЯ разными строками
-- ("1.8.8" и "1.8.9") — расходились между собой при каждом обновлении,
-- если забывали поправить обе. Теперь SCRIPT_VER объявлена один раз,
-- выше, и именно она передаётся в script_version() — единая точка
-- правды для версии скрипта.
-- ============================================================
--  ВЕРСИЯ СКРИПТА (меняй здесь — одна точка правды)
--  SCRIPT_VER  = то, что стоит у тебя сейчас
--  Сравнение с GitHub: version.txt в репо maincrafter48-prog/Sats
--  Если там версия НОВЕЕ SCRIPT_VER → доступно обновление
-- ============================================================
local SCRIPT_VER = "1.8.2"
script_version(SCRIPT_VER)

-- интервал автопроверки обновлений (минуты). 1 или 5 — на выбор
local PCS_UPDATE_AUTO_MINUTES = 5

-- имя чат-команды, зарегистрированной сейчас (для перерегистрации при смене)
local _registeredMenuCmd = nil

-- ФИКС "attempt to index global 'St'": таблица St создавалась ниже по
-- файлу (ближе к OnFrame), а saveCfg() определена выше и обращалась к
-- St как к глобальной переменной (которая всегда nil) — падало при
-- каждом вызове saveCfg из onTaxPaymentSuccess и т.п. Объявляем local
-- заранее, а саму таблицу заполняем на прежнем месте ниже по файлу.
local St

pcall(require, 'lib.moonloader')
local _encoding = require('encoding')
if _encoding then _encoding.default = 'CP1251' end
local _u8_raw = _encoding and _encoding.UTF8 or function(s) return s end
local u8 = setmetatable({}, {
    __call  = function(_, s)
        if s == nil then return '' end
        if type(s) ~= 'string' then s = tostring(s) end
        local ok, result = pcall(_u8_raw, s)
        return ok and result or s
    end,
    __index = _u8_raw,
})

-- валюта, которая раньше называлась в игре "Евро", теперь называется
-- "Акции Arizona (AARP)" — единая точка правды для текста метки, чтобы
-- не расползалось по всему файлу разными вариантами написания
local CUR_AARP_SHORT = u8"\xc0\xea\xf6\xe8\xe8\x20\x41\x41\x52\x52\x50"

local function safeRequire(name)
    local ok, lib = pcall(require, name)
    if not ok then return nil end
    return lib
end

-- PCS_GUARD BEGIN
-- ============================================================
--  ЗАЩИТА СТЕКА IMGUI (PCS_GUARD)
-- ------------------------------------------------------------
-- Любой дисбаланс Begin/End, BeginChild/EndChild, BeginPopup/EndPopup,
-- PushStyleColor/PopStyleColor, PushStyleVar/PopStyleVar в ImGui —
-- это assert в нативном коде, то есть вылет игры без единой строки
-- в moonloader.log (pcall такое не ловит). Ниже — прокси поверх
-- mimgui ТОЛЬКО для этого скрипта (общий mimgui-объект других
-- скриптов не трогаем), который:
--   * считает открытые окна/дочерние/popup/tooltip и стили;
--   * не даёт закрыть то, чего не открывали (лишний End/Pop → no-op);
--   * при End/EndChild/EndPopup сначала закрывает то, что осталось
--     открытым выше (после ошибки внутри pcall);
--   * PCS_GUARD.unwind(snap) в конце кадра/блока чинит любую утечку;
--   * пишет в moonloader.log строки (print), где утечка возникла.
-- Всё завёрнуто в ОДНУ глобальную таблицу: локальных переменных
-- в файле и так почти 200 (лимит LuaJIT).
-- ============================================================
PCS_GUARD = (function()
    local G = { c = 0, v = 0, w = 0, wk = {}, cl = {}, vl = {}, wl = {},
                trace = false, leaks = 0, lastPrint = 0, lastErr = nil, lastErrT = 0 }
    local real
    local CLOSE = { W = 'End', C = 'EndChild', P = 'EndPopup', T = 'EndTooltip' }

    local function ln()
        if not G.trace then return 0 end
        local i = debug.getinfo(3, 'l')
        return (i and i.currentline) or 0
    end

    local function lineList(t, a, b)
        local out, seen = {}, {}
        for i = a, b do
            local l = t[i]
            if l and l > 0 and not seen[l] then seen[l] = true; out[#out + 1] = l end
        end
        return table.concat(out, ',', 1, math.min(#out, 8))
    end

    local function report(where, s, dc, dv, dw)
        G.leaks = G.leaks + 1
        G.trace = true -- со следующего кадра запоминаем строки вызовов
        local t = os.clock()
        if G.leaks > 8 and t - G.lastPrint < 30 then return end
        G.lastPrint = t
        print(string.format(
            '[PC Stats][guard] ImGui stack leak repaired (%s): colors=%d vars=%d windows=%d | lines: color[%s] var[%s] window[%s] | total=%d',
            where, dc, dv, dw,
            lineList(G.cl, s.c + 1, G.c), lineList(G.vl, s.v + 1, G.v), lineList(G.wl, s.w + 1, G.w), G.leaks))
    end

    -- ── контрольные точки на диск (переживают нативный вылет) ──
    -- PCS_GUARD.traceOpen(path) вызывается при открытии меню; дальше
    -- PCS_GUARD.mark("...") пишет строку в КОЛЬЦО из 30 строк файла и сразу
    -- делает flush. После вылета в файле остаются последние 30 событий;
    -- самое позднее — строка с наибольшим номером в начале строки.
    G.NS, G.SL, G.tn = 30, 80, 0
    function G.traceOpen(path)
        G.tn = 0
        if G.tf then pcall(G.tf.close, G.tf); G.tf = nil end
        local f = io.open(path, 'wb')
        if f then
            local blank = string.rep(' ', G.SL - 1) .. '\n'
            for _ = 1, G.NS do f:write(blank) end
            f:flush()
            G.tf = f
        end
    end
    function G.mark(text)
        local f = G.tf
        if not f then return end
        local n = G.tn + 1
        G.tn = n
        local line = string.format('%06d %.2f %s', n, os.clock(), tostring(text)):sub(1, G.SL - 1)
        line = line .. string.rep(' ', G.SL - 1 - #line) .. '\n'
        f:seek('set', ((n - 1) % G.NS) * G.SL)
        f:write(line)
        f:flush()
    end

    -- ImGui.Text* принимает printf-формат. Строка из данных сервера с одиночным '%'
    -- ("Защита 5%", "Шанс 12%") — это "неполная спецификация формата": CRT вызывает
    -- invalid-parameter handler и процесс умирает без единой строки в логе.
    -- Если аргументов формата нет — экранируем % → %% (текст на экране не меняется).
    local function esc(str)
        if type(str) ~= 'string' or not str:find('%', 1, true) then return str end
        G.escN = (G.escN or 0) + 1
        if G.escN <= 6 then
            local a = str:sub(1, 60):gsub('[^\32-\126]', '?')
            print('[PC Stats][guard] lone % in ImGui text escaped (would crash ImGui printf): ' .. a)
            G.mark('escaped % in text: ' .. a)
        end
        return (str:gsub('%%', '%%%%'))
    end

    function G.snap() return { c = G.c, v = G.v, w = G.w } end

    function G.unwind(s, where)
        if not s or not real then return end
        local dc, dv, dw = G.c - s.c, G.v - s.v, G.w - s.w
        if dc <= 0 and dv <= 0 and dw <= 0 then return end
        report(where or '?', s, math.max(dc, 0), math.max(dv, 0), math.max(dw, 0))
        while G.w > s.w do
            local k = G.wk[G.w]
            G.wk[G.w] = nil
            G.w = G.w - 1
            pcall(real[CLOSE[k]])
        end
        if dc > 0 then pcall(real.PopStyleColor, dc); G.c = s.c end
        if dv > 0 then pcall(real.PopStyleVar, dv);   G.v = s.v end
    end

    -- выполнить fn под pcall, после чего ВСЕГДА привести стек ImGui к
    -- состоянию "до вызова"; возвращает ok, err как pcall
    function G.call(fn, ...)
        local s = G.snap()
        local ok, err = pcall(fn, ...)
        G.unwind(s, 'call')
        if not ok then
            local e = tostring(err)
            local t = os.clock()
            if e ~= G.lastErr or t - G.lastErrT > 10 then
                G.lastErr, G.lastErrT = e, t
                print('[PC Stats][guard] error inside protected block: ' .. e)
            end
        end
        return ok, err
    end

    -- то же, но ошибка пробрасывается дальше (для внешнего pcall кадра)
    function G.callr(fn, ...)
        local ok, err = G.call(fn, ...)
        if not ok then error(err, 0) end
    end

    function G.wrap(r)
        if not r then return r end
        real = r
        local P = setmetatable({}, { __index = r })

        P.PushStyleColor = function(...)
            r.PushStyleColor(...)
            local n = G.c + 1
            G.c = n
            if G.trace then G.cl[n] = ln() end
        end
        P.PopStyleColor = function(n)
            n = n or 1
            if n > G.c then n = G.c end
            if n <= 0 then return end
            r.PopStyleColor(n)
            G.c = G.c - n
        end
        P.PushStyleVar = function(...)
            r.PushStyleVar(...)
            local n = G.v + 1
            G.v = n
            if G.trace then G.vl[n] = ln() end
        end
        P.PopStyleVar = function(n)
            n = n or 1
            if n > G.v then n = G.v end
            if n <= 0 then return end
            r.PopStyleVar(n)
            G.v = G.v - n
        end

        local function opener(kind, fname, always)
            P[fname] = function(...)
                local res = r[fname](...)
                if always or res then
                    local n = G.w + 1
                    G.w = n
                    G.wk[n] = kind
                    if G.trace then G.wl[n] = ln() end
                end
                return res
            end
        end
        opener('W', 'Begin', true)
        opener('C', 'BeginChild', true)
        opener('P', 'BeginPopup', false)
        opener('T', 'BeginTooltip', true)

        local function closer(kind, fname)
            P[fname] = function(...)
                local i = G.w
                while i > 0 and G.wk[i] ~= kind do i = i - 1 end
                if i == 0 then return end -- такого окна мы не открывали — закрывать нечего
                if G.w > i then
                    G.leaks = G.leaks + 1
                    G.trace = true
                    while G.w > i do -- закрываем то, что осталось открытым выше
                        local k = G.wk[G.w]
                        G.wk[G.w] = nil
                        G.w = G.w - 1
                        pcall(r[CLOSE[k]])
                    end
                end
                G.wk[i] = nil
                G.w = i - 1
                return r[fname](...)
            end
        end
        closer('W', 'End')
        closer('C', 'EndChild')
        closer('P', 'EndPopup')
        closer('T', 'EndTooltip')

        -- текстовые функции с printf-форматом: fmt — первый аргумент
        for _, fname in ipairs({ 'Text', 'TextWrapped', 'TextDisabled', 'BulletText', 'SetTooltip' }) do
            P[fname] = function(fmt, ...)
                if select('#', ...) == 0 then fmt = esc(fmt) end
                return r[fname](fmt, ...)
            end
        end
        -- fmt — второй аргумент
        for _, fname in ipairs({ 'TextColored', 'LabelText' }) do
            P[fname] = function(a, fmt, ...)
                if select('#', ...) == 0 then fmt = esc(fmt) end
                return r[fname](a, fmt, ...)
            end
        end
        return P
    end

    return G
end)()
-- PCS_GUARD END

local sampev = safeRequire("lib.samp.events")
local imgui  = PCS_GUARD.wrap(safeRequire("mimgui"))
local inicfg = safeRequire("inicfg")
local ffi    = safeRequire("ffi")


-- ============================================================
--  САМООБНОВЛЕНИЕ (проверка версии + автозагрузка с GitHub)
-- ------------------------------------------------------------
-- Источник тот же, что и у остальных скриптов линейки (см.
-- MarketLauncher): репозиторий Market88888/CR-Helpers, файл
-- PCStats.lua. Порядок опроса источников идентичен —
-- GitHub Releases (tag_name) → tags API → raw-файл из веток
-- main/master, берём первый, что отдал корректный script_version().
--
-- Всё завёрнуто в ОДНУ глобальную таблицу PCS_UPDATE (а не в
-- десяток отдельных local'ов) по двум причинам:
--   1) файл и так близок к лимиту Lua/LuaJIT в 200 локальных
--      переменных на функцию (весь файл — это одна "функция чанка"),
--      а глобальная переменная слот локальной переменной не занимает;
--   2) поле такой таблицы (PCS_UPDATE.state, PCS_UPDATE.check и т.д.)
--      можно читать из ЛЮБОГО места файла — в т.ч. из вкладки
--      "О скрипте" (см. drawAboutInner), которая объявлена намного
--      ниже по файлу и не видела бы обычные local-переменные отсюда.
--
-- Команда в чате: /pcsupdate — проверить; /pcsupdate install —
-- скачать актуальную версию и перезаписать этим файлом себя же,
-- затем попытаться горячо перезагрузиться через script:reload()
-- (тот же метод, что уже использует кнопка "Перезагрузить скрипт").
-- То же самое доступно кнопками во вкладке "О скрипте" → "Обновления".
-- ============================================================
PCS_UPDATE = (function()
    local M = {}

    M.cfg = {
        github_user = 'maincrafter48-prog',
        github_repo = 'Sats',
        file        = 'PCStats.lua',
        version_file = 'version.txt',
    }
    -- проверка вручную: /pcsupdate, установка: /pcsupdate install
    M.cfg.autoCheck = true
    M.cfg.api_release = ('https://api.github.com/repos/%s/%s/releases/latest'):format(M.cfg.github_user, M.cfg.github_repo)
    M.cfg.api_tags    = ('https://api.github.com/repos/%s/%s/tags'):format(M.cfg.github_user, M.cfg.github_repo)
    M.cfg.raw_main    = ('https://raw.githubusercontent.com/%s/%s/main/%s'):format(M.cfg.github_user, M.cfg.github_repo, M.cfg.file)
    M.cfg.raw_master  = ('https://raw.githubusercontent.com/%s/%s/master/%s'):format(M.cfg.github_user, M.cfg.github_repo, M.cfg.file)
    M.cfg.raw_ver     = ('https://raw.githubusercontent.com/%s/%s/main/%s'):format(M.cfg.github_user, M.cfg.github_repo, M.cfg.version_file)
    M.cfg.release_dl  = ('https://github.com/%s/%s/releases/latest/download/%s'):format(M.cfg.github_user, M.cfg.github_repo, M.cfg.file)

    M.effil = safeRequire('effil')

    M.state = {
        checking   = false,
        installing = false,
        ver_remote = nil,
        available  = false,
        last_check = 0,
        last_error = nil,
        dlProg     = 0,   -- 0..100 прогресс скачивания
        dlStatus   = "",  -- текст статуса (скачивание / запись / готово)
    }

    local function normVer(v)
        if not v or v == '' then return nil end
        return tostring(v):gsub('^[vV]', '')
    end

    local function verLt(a, b)
        local function parts(s)
            local t = {}
            for p in (s or '0'):gmatch('%d+') do t[#t + 1] = tonumber(p) end
            return t
        end
        local pa, pb = parts(a), parts(b)
        for i = 1, math.max(#pa, #pb) do
            local ai, bi = pa[i] or 0, pb[i] or 0
            if ai < bi then return true end
            if ai > bi then return false end
        end
        return false
    end

    local function verFromBody(body)
        if not body or body == '' then return nil end
        return normVer(body:match('script_version%s*%(%s*["\']([^"\']+)["\']')
            or body:match('SCRIPT_VER%s*=%s*["\']([^"\']+)["\']'))
    end

    local function parseRelease(body)
        return normVer(body and body:match('"tag_name"%s*:%s*"([^"]+)"'))
    end

    local function parseFirstTag(body)
        return normVer(body and body:match('"name"%s*:%s*"([^"]+)"'))
    end

    local function isValidBody(body)
        if type(body) ~= 'string' or #body < 500 then return false end
        local headPart = body:sub(1, 400)
        if headPart:find('<!DOCTYPE html', 1, true) or headPart:find('<html', 1, true) then return false end
        if body:find('Not Found', 1, true) and #body < 400 then return false end
        return body:find('script_name%s*%(') ~= nil
    end

    local function writeAtomic(path, content)
        local tmp = path .. '.tmp'
        local f = io.open(tmp, 'wb')
        if not f then return false end
        f:write(content)
        f:close()
        os.remove(path)
        local renamed = false
        pcall(function() renamed = os.rename(tmp, path) end)
        if renamed then return true end
        local rf = io.open(tmp, 'rb')
        local wf = io.open(path, 'wb')
        if not rf or not wf then
            if rf then rf:close() end
            if wf then wf:close() end
            pcall(os.remove, tmp)
            return false
        end
        wf:write(rf:read('*a'))
        rf:close(); wf:close()
        pcall(os.remove, tmp)
        return true
    end

    -- HTTP GET без обязательного effil: requests / downloadUrlToFile / urlmon
    local function httpGetBody(url)
        url = tostring(url or "")
        if url == "" then return nil, "empty url" end
        -- 1) requests (синхронно — вызывать из lua_thread)
        local okR, requests = pcall(require, "requests")
        if okR and requests then
            local ok, response
            if requests.get then
                ok, response = pcall(requests.get, url, {
                    headers = { ["User-Agent"] = "PCStats-AutoUpdate/1.0" },
                    timeout = 20,
                })
            elseif requests.request then
                ok, response = pcall(requests.request, "GET", url, {
                    headers = { ["User-Agent"] = "PCStats-AutoUpdate/1.0" },
                    timeout = 20,
                })
            end
            if ok and response then
                local code = tonumber(response.status_code or response.status) or 0
                local body = response.text or response.content or ""
                if code == 200 and type(body) == "string" and #body > 0 then
                    return body, nil
                end
            end
        end
        -- 2) downloadUrlToFile (MoonLoader)
        if type(downloadUrlToFile) == "function" then
            local tmp = getWorkingDirectory and (getWorkingDirectory() .. "/PCStats_http.tmp") or "moonloader/PCStats_http.tmp"
            pcall(os.remove, tmp)
            pcall(downloadUrlToFile, url, tmp, function() end)
            local waited = 0
            while waited < 15000 do
                wait(300); waited = waited + 300
                local f = io.open(tmp, "rb")
                if f then
                    local body = f:read("*a"); f:close()
                    if body and #body > 2 then
                        pcall(os.remove, tmp)
                        return body, nil
                    end
                end
            end
            pcall(os.remove, tmp)
        end
        -- 3) urlmon (Windows)
        if ffi then
            pcall(function()
                ffi.cdef[[ int URLDownloadToFileA(void* p, const char* u, const char* f, unsigned long, void*); ]]
            end)
            local urlmon
            pcall(function() urlmon = ffi.load("urlmon") end)
            if urlmon and urlmon.URLDownloadToFileA then
                local tmp = getWorkingDirectory and (getWorkingDirectory() .. "/PCStats_http.tmp") or "moonloader/PCStats_http.tmp"
                pcall(os.remove, tmp)
                local hr = urlmon.URLDownloadToFileA(nil, url, tmp, 0, nil)
                if hr == 0 then
                    local f = io.open(tmp, "rb")
                    if f then
                        local body = f:read("*a"); f:close()
                        pcall(os.remove, tmp)
                        if body and #body > 2 then return body, nil end
                    end
                end
            end
        end
        return nil, "no downloader"
    end

    -- совместимость: если есть effil — старый путь; иначе nil (check/install используют httpGetBody)
    local function httpFetch(url)
        if not M.effil then return nil end
        return M.effil.thread(function(target)
            local req = require('requests')
            local ok, response = pcall(req.request, 'GET', target, {
                headers = { ['User-Agent'] = 'PCStats-AutoUpdate/1.0' },
                timeout = 20,
            })
            if not ok or not response then
                return false, { status_code = 0, text = '', error = tostring(response or 'connect error') }
            end
            return true, { status_code = tonumber(response.status_code) or 0, text = response.text or '', error = nil }
        end)(url)
    end

    -- Идёт через уже переопределённый ниже sampAddChatMessage (см.
    -- секцию "ФИКС КАРАКУЛЬ") — сообщение сразу дублируется тостом.
    -- Определяется через pcall(sampAddChatMessage, ...), поэтому
    -- безопасно вызывать даже до того, как SAMP доступен.
    local function notify(text, color)
        pcall(sampAddChatMessage, (color or '{66ccff}') .. '[PC Stats] ' .. text, -1)
    end
    M.notify = notify

    -- Проверка версии на GitHub. silent=true — тихая фоновая проверка
    -- (например, при старте скрипта): сообщение в чат появится, только
    -- если реально нашлось обновление; ошибки и "версия актуальна" в
    -- этом режиме не выводятся, чтобы не спамить при каждом заходе.
    function M.check(silent)
        if M.state.checking or M.state.installing then return end
        M.state.checking = true
        M.state.last_error = nil
        if not silent then
            notify("\xcf\xf0\xee\xe2\xe5\xf0\xea\xe0\x20\xee\xe1\xed\xee\xe2\xeb\xe5\xed\xe8\xe9\x2e\x2e\x2e")
        end

        lua_thread.create(function()
            local remote_ver = nil
            -- 1) version.txt (самый быстрый и надёжный)
            local sources = {
                M.cfg.raw_ver,
                M.cfg.raw_main,
                M.cfg.raw_master,
            }
            for _, url in ipairs(sources) do
                local body, err = httpGetBody(url)
                if body and #body > 0 then
                    if url == M.cfg.raw_ver or url:find("version%.txt") then
                        local line = body:match("([^\r\n]+)") or body
                        line = line:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^[vV]", "")
                        if line:match("^%d+%.%d+") then
                            remote_ver = normVer(line)
                        end
                    else
                        remote_ver = verFromBody(body)
                    end
                    if remote_ver then break end
                end
            end
            -- 2) GitHub API через effil (если есть)
            if not remote_ver and M.effil then
                for _, item in ipairs({
                    { url = M.cfg.api_release, mode = 'release' },
                    { url = M.cfg.api_tags, mode = 'tags' },
                }) do
                    local okT, thr = pcall(httpFetch, item.url)
                    if okT and thr then
                        for _ = 1, 100 do
                            wait(100)
                            local st, er = thr:status()
                            if st == 'completed' then
                                local ok, response = thr:get()
                                if ok and response and tonumber(response.status_code) == 200 then
                                    if item.mode == 'release' then
                                        remote_ver = parseRelease(response.text)
                                    else
                                        remote_ver = parseFirstTag(response.text)
                                    end
                                end
                                break
                            end
                            if not st or st == 'failed' or st == 'canceled' or er then break end
                        end
                    end
                    if remote_ver then break end
                end
            end

            M.state.checking = false
            M.state.last_check = os.time()
            if remote_ver then
                M.state.ver_remote = remote_ver
                M.state.available = verLt(SCRIPT_VER, remote_ver)
                M.state.last_error = nil
                if not silent then
                    if M.state.available then
                        notify("\xe4\xee\xf1\xf2\xf3\xef\xed\xee\x20\xee\xe1\xed\xee\xe2\xeb\xe5\xed\xe8\xe5\x20v" .. remote_ver, "{FFD700}")
                    else
                        notify("\xf3\xf1\xf2\xe0\xed\xee\xe2\xeb\xe5\xed\xe0\x20\xe0\xea\xf2\xf3\xe0\xeb\xfc\xed\xe0\xff\x20\xe2\xe5\xf0\xf1\xe8\xff\x20v" .. SCRIPT_VER, "{00FF88}")
                    end
                end
            else
                M.state.last_error = 'check failed'
                if not silent then
                    notify("\xcd\xe5\x20\xf3\xe4\xe0\xeb\xee\xf1\xfc\x20\xef\xf0\xee\xe2\xe5\xf0\xe8\xf2\xfc\x20\xe2\xe5\xf0\xf1\xe8\xfe\x20\xed\xe0\x20\x47\x69\x74\x48\x75\x62", "{FF6666}")
                end
            end
        end)
    end

    -- Скачивает актуальный файл с GitHub и перезаписывает им СЕБЯ
    -- САМОГО на диске (тот же путь, что вернёт thisScript().path),
    -- затем пробует горячую перезагрузку через штатный script:reload()
    -- — если в этой сборке MoonLoader его нет, откатывается на
    -- unload() с сообщением в чат, и игроку нужно запустить скрипт
    -- заново вручную (папка moonloader / F4)
    function M.install()
        if M.state.installing then
            notify("\xd3\xe6\xe5\x20\xe8\xe4\xb8\xf2\x20\xf3\xf1\xf2\xe0\xed\xee\xe2\xea\xe0\x20\xee\xe1\xed\xee\xe2\xeb\xe5\xed\xe8\xff", "{FFAA00}")
            return
        end
        local selfPath = nil
        pcall(function()
            if thisScript and thisScript() then selfPath = thisScript().path end
        end)
        if not selfPath or selfPath == "" then
            notify("\xcd\xe5\x20\xf3\xe4\xe0\xeb\xee\xf1\xfc\x20\xee\xef\xf0\xe5\xe4\xe5\xeb\xe8\xf2\xfc\x20\xef\xf3\xf2\xfc\x20\xea\x20\xf1\xe2\xee\xe5\xec\xf3\x20\xf4\xe0\xe9\xeb\xf3", "{FF6666}")
            return
        end
        M.state.installing = true
        M.state.dlProg = 0
        M.state.dlStatus = "\xef\xee\xe4\xe3\xee\xf2\xee\xe2\xea\xe0..."
        notify("\xcd\xe0\xf7\xe8\xed\xe0\xfe\x20\xf1\xea\xe0\xf7\xe8\xe2\xe0\xed\xe8\xe5\x20\xee\xe1\xed\xee\xe2\xeb\xe5\xed\xe8\xff\x2e\x2e\x2e")

        lua_thread.create(function()
            local urls = {
                M.cfg.raw_main,
                M.cfg.raw_master,
                M.cfg.release_dl,
            }
            local body = nil
            local nUrl = #urls
            for i, url in ipairs(urls) do
                -- прогресс 5%..70% по этапам зеркал
                M.state.dlProg = math.floor(5 + (i - 1) * (60 / nUrl))
                M.state.dlStatus = "\xf1\xea\xe0\xf7\xe8\xe2\xe0\xed\xe8\xe5\x20" .. tostring(M.state.dlProg) .. "%"
                wait(50)
                local b, err = httpGetBody(url)
                if b and isValidBody(b) then
                    body = b
                    M.state.dlProg = 75
                    M.state.dlStatus = "\xf1\xea\xe0\xf7\xe0\xed\xee\x20" .. tostring(#b) .. " \xe1\xe0\xe9\xf2"
                    break
                end
                M.state.dlProg = math.floor(5 + i * (60 / nUrl))
            end
            if not body then
                M.state.installing = false
                M.state.dlProg = 0
                M.state.dlStatus = ""
                M.state.last_error = "download failed"
                notify("\xcd\xe5\x20\xf3\xe4\xe0\xeb\xee\xf1\xfc\x20\xf1\xea\xe0\xf7\xe0\xf2\xfc\x20\xee\xe1\xed\xee\xe2\xeb\xe5\xed\xe8\xe5\x20\xf1\x20GitHub", "{FF6666}")
                return
            end
            local newVer = verFromBody(body)
            M.state.dlProg = 82
            M.state.dlStatus = "\xf0\xe5\xe7\xe5\xf0\xe2\xed\xe0\xff\x20\xea\xee\xef\xe8\xff..."
            wait(50)
            pcall(function()
                local old = io.open(selfPath, "rb")
                if old then
                    local data = old:read("*a"); old:close()
                    local bak = io.open(selfPath .. ".bak", "wb")
                    if bak then bak:write(data); bak:close() end
                end
            end)
            M.state.dlProg = 90
            M.state.dlStatus = "\xe7\xe0\xef\xe8\xf1\xfc\x20\xf4\xe0\xe9\xeb\xe0..."
            wait(50)
            if not writeAtomic(selfPath, body) then
                M.state.installing = false
                M.state.dlProg = 0
                M.state.dlStatus = ""
                notify("\xcd\xe5\x20\xf3\xe4\xe0\xeb\xee\xf1\xfc\x20\xe7\xe0\xef\xe8\xf1\xe0\xf2\xfc\x20\xf4\xe0\xe9\xeb\x20\xf1\xea\xf0\xe8\xef\xf2\xe0", "{FF6666}")
                return
            end
            M.state.dlProg = 100
            M.state.dlStatus = "\xe3\xee\xf2\xee\xe2\xee"
            M.state.installing = false
            M.state.available = false
            M.state.ver_remote = newVer or M.state.ver_remote
            notify("\xce\xe1\xed\xee\xe2\xeb\xe5\xed\xee\x20\xe4\xee\x20v" .. tostring(newVer or "?") ..
                "\x2e\x20\xcf\xe5\xf0\xe5\xe7\xe0\xe3\xf0\xf3\xe7\xea\xe0\x2e\x2e\x2e", "{00FF88}")
            wait(600)
            local ok, scr = pcall(thisScript)
            if ok and scr then
                if scr.reload then
                    pcall(function() scr:reload() end)
                else
                    notify("\xcf\xe5\xf0\xe5\xe7\xe0\xef\xf3\xf1\xf2\xe8\xf2\xe5\x20\xf1\xea\xf0\xe8\xef\xf2\x20\xe2\xf0\xf3\xf7\xed\xf3\xfe\x20\x28F10\x20/\x20moonloader\x29", "{FFAA00}")
                end
            end
        end)
    end


    return M
end)()

-- Тонкие обёртки-глобалы для команды чата /pcsupdate (см. main())
function pcsCheckForUpdate(silent) PCS_UPDATE.check(silent) end
function pcsInstallUpdate() PCS_UPDATE.install() end

-- ============================================================
--  ФИКС "КАРАКУЛЬ" В ЧАТЕ ВМЕСТО ЭМОДЗИ
-- ------------------------------------------------------------
-- родной чат SA-MP рисует текст как однобайтовую CP1251-кодировку —
-- он не умеет отображать многобайтовые UTF-8 символы (эмодзи, ⚠️, ✅
-- и т.п.), а в коде скрипта такие символы вставлены прямо как сырые
-- UTF-8-байты рядом с CP1251-текстом. В результате движок чата читает
-- каждый байт эмодзи как отдельный CP1251-символ — отсюда и "каракули".
-- Решение: подменяем sampAddChatMessage один раз при старте скрипта на
-- обёртку, которая перед отправкой вырезает из строки все корректные
-- 3- и 4-байтовые UTF-8-последовательности (это и есть эмодзи/значки),
-- не трогая однобайтовый CP1251-текст. Правится это в одном месте —
-- переделывать каждое сообщение по отдельности не нужно ──
local function stripUtf8Symbols(s)
    if type(s) ~= "string" then return s end
    local out, i, len = {}, 1, #s
    while i <= len do
        local b = string.byte(s, i)
        local seqLen = 0
        if b >= 0xF0 and b <= 0xF4 then
            seqLen = 4
        elseif b >= 0xE0 and b <= 0xEF then
            seqLen = 3
        end
        if seqLen > 0 and i + seqLen - 1 <= len then
            local valid = true
            for k = 1, seqLen - 1 do
                local cb = string.byte(s, i + k)
                if not cb or cb < 0x80 or cb > 0xBF then valid = false; break end
            end
            if valid then
                i = i + seqLen -- целиком вырезаем UTF-8 эмодзи/значок
            else
                out[#out + 1] = string.char(b); i = i + 1
            end
        else
            out[#out + 1] = string.char(b); i = i + 1
        end
    end
    return table.concat(out)
end

-- ФИКС (п.15): раньше здесь была только обёртка для CP1251/эмодзи, а
-- вторая обёртка (для тостов) была объявлена отдельно, намного позже
-- по файлу — итоговый вызов шёл через wrapper2 → wrapper1 → orig.
-- Теперь это ОДНА функция, объединяющая обе задачи. Также:
--   - table.unpack может быть nil в некоторых сборках LuaJIT/MoonLoader
--     (правильно: local unpack = table.unpack or unpack);
--   - _pcsStripColorTags раньше резал только "{RRGGBB}", теперь ещё и
--     "{RRGGBBAA}".
if type(sampAddChatMessage) == "function" then
    local _origAddChatMessage = sampAddChatMessage
    local _unpack = table.unpack or unpack

    -- убираем цветовые теги — тосту цвет не нужен, нужен только сам текст
    local function _pcsStripColorTags(s)
        s = tostring(s or "")
        s = s:gsub("{%x%x%x%x%x%x%x%x}", "") -- {RRGGBBAA}
        s = s:gsub("{%x%x%x%x%x%x}", "")     -- {RRGGBB}
        return s
    end
    -- строки-разделители скрипта (сплошные линии из символов рамки) несут
    -- ноль информации сами по себе — тост для одной такой линии не нужен
    local function _pcsIsDecorativeOnly(s)
        local stripped = s:gsub("[\226][\148\149][\128-\191]", "")
        stripped = stripped:gsub("[%s%-=_]+", "")
        return stripped == ""
    end
    -- по первому цветовому тегу сообщения примерно угадываем тип тоста
    local _pcsColorToToastType = {
        ["FF6666"] = "error",   ["FF4444"] = "error",
        ["00FF88"] = "success", ["25AAFF"] = "info", ["00AAFF"] = "info",
        ["FFD700"] = "warning",
    }
    local function _pcsGuessToastType(s)
        local hex = tostring(s or ""):match("^{(%x%x%x%x%x%x)}")
        return (hex and _pcsColorToToastType[hex:upper()]) or "info"
    end

    sampAddChatMessage = function(text, color)
        local rawText = text
        if type(text) == "string" then
            text = stripUtf8Symbols(text)
            -- applyCustomChatColor определяется ниже по файлу (после того,
            -- как загружен cfg) — на момент реального вызова (отправка
            -- сообщения в чат) она уже точно объявлена как глобальная
            if type(applyCustomChatColor) == "function" then
                local okC, colored = pcall(applyCustomChatColor, text)
                if okC and colored then text = colored end
            end
        end
        local ret = { pcall(_origAddChatMessage, text, color) }
        -- тост — отдельно; pcs_notify определяется позже по файлу
        pcall(function()
            if type(pcs_notify) ~= "function" then return end
            local clean = _pcsStripColorTags(rawText)
            if type(clean) == "string" and clean:match("%S") and not _pcsIsDecorativeOnly(clean) then
                -- ФИКС "в тосте вопросики вместо текста": rawText — это сырые
                -- CP1251-байты (как их ожидает сам sampAddChatMessage), а
                -- imgui/mimgui, которым рисуются тосты, ждут UTF-8. Без
                -- конвертации через u8() каждый кириллический байт превращался
                -- в невалидную UTF-8-последовательность и рисовался как "?".
                -- Сначала убираем возможные UTF-8 emoji-байты (та же функция,
                -- что и для обычного чата чуть выше) — иначе они попадут в
                -- u8() вместе с CP1251 и превратятся в мусор — и только потом
                -- конвертируем в UTF-8 для показа.
                pcs_notify(u8(stripUtf8Symbols(clean)), _pcsGuessToastType(rawText))
            end
        end)
        return _unpack(ret, 2)
    end
end

-- ŠµŃ�Š»Šø inicfg Š½Šµ Š·Š°Š³Ń€Ń�Š·ŠøŠ»Ń�Ń¸ ā€” Š·Š°Š³Š»Ń�Ń�ŠŗŠ° Ń‡Ń‚Š¾Š±Ń‹ Š½Šµ ŠŗŃ€Š°Ń�Š½Ń�Ń‚Ń�
if not inicfg then
    inicfg = {
        load = function() return nil end,
        save = function() end,
    }
end

if not imgui then
    function main()
        repeat wait(0) until isSampAvailable()
        wait(2000)
        sampAddChatMessage("{FF4444}[Stats] \xe2\x9a\xa0\xef\xb8\x8f ERROR: mimgui not found!", -1)
    end
    return
end
if not sampev then
    function main()
        repeat wait(0) until isSampAvailable()
        wait(2000)
        sampAddChatMessage("{FF4444}[Stats] \xe2\x9a\xa0\xef\xb8\x8f ERROR: lib.samp.events not found!", -1)
    end
    return
end

-- ============================================================
--  WINAPI ЧЕРЕЗ FFI (без os.execute!)
-- ------------------------------------------------------------
-- os.execute() на Windows для GUI-процесса (каким является
-- SA-MP/GTA:SA) под капотом дёргает C-функцию system(), а она
-- всегда порождает видимое окно cmd.exe (даже для простых команд
-- вроде mkdir), потому что у процесса нет своей консоли — Windows
-- создаёт новую. Это окно перехватывает фокус и может свернуть
-- игру в полноэкранном режиме, из-за чего игра выглядит "вылетевшей".
-- Поэтому папку конфига создаём через WinAPI CreateDirectoryA, а
-- ссылки открываем через ShellExecuteA — оба варианта работают
-- без создания какого-либо окна консоли ──
local _winApiOk = false
if ffi then
    _winApiOk = pcall(function()
        ffi.cdef[[
            int CreateDirectoryA(const char *lpPathName, void *lpSecurityAttributes);
            void *ShellExecuteA(void *hwnd, const char *lpOperation, const char *lpFile,
                                 const char *lpParameters, const char *lpDirectory, int nShowCmd);
        ]]
    end)
end
local _shell32 = nil
if _winApiOk then
    local okLib, lib = pcall(ffi.load, "shell32")
    if okLib then _shell32 = lib end
end

-- создаёт папку через WinAPI (без консоли); возвращает true при успехе
-- вызова (папка создана или уже существовала — CreateDirectoryA в обоих
-- случаях не бросает исключение, просто выставляет код ошибки, который
-- нам тут не важен)
local function winCreateDir(path)
    if not _winApiOk then return false end
    local ok = pcall(function() ffi.C.CreateDirectoryA(path, nil) end)
    return ok
end

-- открывает ссылку через WinAPI (без консоли)
local function winOpenUrl(url)
    if not _shell32 then return false end
    local ok = pcall(function() _shell32.ShellExecuteA(nil, "open", url, nil, nil, 1) end)
    return ok
end



-- ============================================================
local CFG_DIR      = "moonloader/config/PCStats"
local CFG_FILE     = CFG_DIR .. "/settings.ini"
-- старое расположение конфига (плоский файл без папки, версии до 1.1.2) —
-- нужно для миграции: если новый файл ещё не существует, но существует
-- старый, подхватываем настройки из него и сразу пересохраняем в новую
-- папку, чтобы обновление скрипта не сбросило игроку его настройки
local CFG_FILE_OLD = "moonloader/config/PCStats.ini"

-- создаёт папку конфига, если её ещё нет; если она уже есть — ничего не
-- делает и не пересоздаёт. Раньше это делалось через os.execute('mkdir'),
-- что на Windows каждый раз на мгновение открывало окно cmd.exe (см.
-- комментарий у WinAPI-обёрток выше) — из-за того, что saveCfg() (а
-- значит и ensureCfgDir()) вызывается очень часто, буквально при любом
-- изменении настроек, это окно постоянно мелькало и могло сворачивать
-- игру в полноэкранном режиме. Теперь используем CreateDirectoryA без
-- всякой консоли; на всякий случай (если ffi недоступен) оставлен
-- запасной вариант через os.execute ──
local function ensureCfgDir()
    -- ФИКС (п.25): saveCfg() (а с ней и ensureCfgDir) дёргается из
    -- слайдеров настроек при движении — десятки раз в секунду. Кэшируем
    -- успех первого вызова, чтобы не дёргать CreateDirectoryA/mkdir
    -- на каждое сохранение.
    if St._cfgDirOk then return end
    if not winCreateDir(CFG_DIR:gsub("/", "\\")) then
        pcall(os.execute, 'mkdir "' .. CFG_DIR:gsub("/", "\\") .. '" 2>nul')
    end
    St._cfgDirOk = true
end

-- ФИКС (п.24): читаем не весь файл лога построчно через :lines(), а
-- только "хвост" — открываем в бинарном режиме и сразу seek'аем к нужному
-- месту с конца. При накоплении нескольких тысяч строк построчное чтение
-- всего файла на каждой загрузке скрипта могло давать заметный фриз.
local function readLogTail(path, maxLines, avgLineLen)
    local f = io.open(path, "rb")
    if not f then return {} end
    local size = f:seek("end")
    local wantBytes = maxLines * (avgLineLen or 64)
    local seekPos = math.max(0, size - wantBytes)
    f:seek("set", seekPos)
    local chunk = f:read("*a") or ""
    f:close()
    local lines = {}
    local first = true
    for line in (chunk .. "\n"):gmatch("(.-)\n") do
        if first and seekPos > 0 then
            first = false -- первая строка после произвольного seek может быть обрезана посередине
        elseif line ~= "" then
            lines[#lines+1] = line
        end
    end
    return lines
end

-- ============================================================
--  ШРИФТ ИКОНОК ВКЛАДОК (FontAwesome 6 Free Solid, обрезанный)
-- ------------------------------------------------------------
-- ниже — обрезанный (только 5 нужных глифов: user/hand-fist/
-- sack-dollar/gear/circle-info, взяты с fontawesome.com/v6/search)
-- вариант fa-solid-900.ttf в base64, ~2.3 КБ вместо ~420 КБ полного
-- шрифта. mimgui умеет грузить шрифт только из файла или из ffi-
-- буфера в памяти, а не прямо из Lua-строки, поэтому декодируем
-- base64 в бинарные байты и один раз сохраняем как .ttf-файл рядом
-- с настройками (moonloader/config/PCStats/) — при следующих запусках
-- скрипт видит, что файл уже есть, и просто переиспользует его ──
local ICON_FONT_FILE = CFG_DIR .. "/pcstats-icons.ttf"
local ICON_FONT_B64 = table.concat({
    "AAEAAAAKAIAAAwAgT1MvMlFQWnEAAA3IAAAAYGNtYXDIPbtOAAAOKAAAAHRnbHlmX7YriQAAAKwAAAxQaGVhZCe8GNUAAA04AAAA",
    "NmhoZWEETAI2AAANpAAAACRobXR4FgEAWQAADXAAAAA0bG9jYRJWFX8AAA0cAAAAHG1heHAAJAGRAAAM/AAAACBuYW1lHX04eQAA",
    "DpwAAAGYcG9zdDw87asAABA0AAAAuAAFAAD/wAGAAcAABgANABQAGwA1AAA3Nwc3JzERFzMjMycxBzcXJxcRMQc3IzMjFzE3JTY3",
    "MTE2NyExFhcWFxExBgcGByExJicmJxFAWlpaWiezs7NaWYBZWVlZM7Ozs1la/uYBDQ4UASAUDg0BAQ0OFP7gFA4NATqGhoaG/vQ6",
    "hobAhoaGAQyGwIaGEBQODQEBDQ4U/mAUDg0BAQ0OFAGgAAAC//P/4ABNAaAAFQAiAAATNCcxMSYjIgcGFRExFBcWMzI3NjURAzY3",
    "NicmJwYHBhcWF0AJCQ4OCQkJCQ4OCQkgFwwKCgwXFwwKCgwXAYAOCQkJCQ7/AA4JCQkJDgEA/mABExQUEwEBExQUEwEAAAIAAP/e",
    "AcABoQBqAHMAABMWFzExFgcHMTMxNzE2NzYXFhcWBwcxMzEyFxYVFAcGIyMxBzEzMTIXFhUUBwYjIzEHMQYHBicmJyY3NzEjMQcx",
    "BgcGJyYnJjc3MSMxIicmNTQ3NjMzMTcxIzEiJyY1NDc2MzMxNzE2NzYXFwc3BzMxNzEjtQ4HBwEKXwsDCgsNDgcHAgk6DgkJCQkO",
    "RRU6DgkJCQkORQsDCgsNDgcHAglfCwMKCw0OBwcCCToOCQkJCQ5FFToOCQkJCQ5FCwMKCw0GFRUVXxVfAaADCgsNO0UOBwcBAwoL",
    "DTsJCQ4OCQmACQkODgkJRQ4HBwEDCgsNO0UOBwgCAwoLDTsJCQ4OCQmACQkODgkJRQ4HBwGggICAgAAAAQAK/8ABNAHAAH4AABMy",
    "FzExFhUVMTIzMDEWMRcxFhcWBwYHBicnMSYHBgcGFxYXFhcXMTIxFhcWFxYXFgcGBwYHBgcVMRQHBiMiJyY1NTEwIzAxIzExMSYn",
    "JicmJyY3Njc2FxYXFhcWNzY3NicmJyYnJzExMTAxJicmJyYnJjc2NzY3Njc1MTQ3NjOgDgkJAgMBMA0HCAIDCwoOLzAeHAEDBAIL",
    "GDEDARYXGBQWDgwGBhESGRQYCQkODgkJAQETGRoVDAUEBQYMCw0RFRUQMRsZAgIDAwoZMQMWGBgUFg0NBwUTExkUFwkJDgHACQkO",
    "JAEIAwsKDg0HBwIIBw0MEA8FBgcPDAEFCAgMDhobIB0TEwoIAyEOCQkJCQ4jAwcHCQYMDA0MBAUFBwYGAwYLCxIQBQYHDwsBBggH",
    "DQ4aGyAcExMKCAMjDgkJAAACAAD/wAHAAcAAGgAwAAA3MjcxMTY3NjU0JyYnJiMiBwYHBhUUFxYXFjMHBgcxMQYHFBcWMyExMjc2",
    "NSYnJicj4CMdHRIRERIdHSMjHR0SERESHR0jLkszMgIJCA0BhA0ICQIyM0tcwBERHh4iIh4eERERER4eIiIeHhERMAIyM0sNCAkJ",
    "CA1LMzICAAIAEP/QAfABwAAVAEwAAAE0JzExJiMiBwYVFTEUFxYzMjc2NTUHNjcxMTYnJicmBwYHBhUWFxYXFhc2NzY3Njc0JyYn",
    "JgcGBwYXFhcWFxYVBgcGByYnJic0NzY3ASAJCQ4OCQkJCQ4OCQmQCgEBCAkNDQopFxcBICA2NkNDNjYgIAEXGCgKDQ0JCAEBCh4R",
    "EQIyMUtLMjECEREdAaAOCQkJCQ7gDgkJCQkO4FkJDQ0KCwEBCCIvMDhDNjYgIAEBICA2NkM4MC8iCAEBCgsNDQkYIyMpSzEyAgIy",
    "MUspIyMYAAACAAz/wAH0AcAAYABtAAABFgcHMRYVFAcXMRYHBgcHMQYHBicnMQYHBzEGBwYjIicmJycxJicHMQYnJicnMSYnJjc3",
    "MSY1NDcnMSY3Njc3MTY3NhcXMTY3NzE2NzYzMhcWFxcxFhc3MTYXFhcXMRYXBzY3NicmJwYHBhcWFwHwBAosAgIsCgQHCQUKDAoO",
    "OBQYDAQPFBYWFQ4EDBgUOA4KDQkFCQcECiwCAiwKBAcJBQkNCg44FBgMBA8UFhYVDgQMGBQ4DgoNCgQJB/AtGBYWGC0tGBYWGC0B",
    "GQ4KKAwNDQwoCg4SEQgQDwsEEhAJOg4DBAQDDjoJEBIECw8QCBERDwonDQ0NDCgKDhIRCBAPCwQSEAo5DgMEBAMOOQoQEgQLDxAI",
    "ERKpAScoKCcBAScoKCcBAAIAEP/ZAfABpwA8AH8AADc2NzYzMhcXMSMxIgcGFRQXFjMzMTAxMDExMTI3NjU1MTQnJiMiBwYVFTEn",
    "MSYnJgcGBwYHBhcWFxY3NjcHBgcGBxQHFBUVMRQXFjMyNzY1NTEXMTExFhcWNzY3Njc2JyYnJgcGBwYHBiMiJzExJzEzMTI3NjU0",
    "JyYjIzEiIwYjaQwaMUBAMREiDgkJCQkOcA4JCQkJDg4JCRIsOTk5OSwlEAQFBgwNDAsFQggGBgIBCQkODgkJEiw5OTk5LCUQBAUG",
    "DA0MCwUMGjFAQDERIg4JCQkJDnACAgMC9SIaLy8RCQkODgkJCQkOcA4JCQkJDiMRLA8ODg8sJS4NDAsFBAUGDFYDBgYIAQIDAnAO",
    "CQkJCQ4jESwPDg4PLCUuDQwLBQQFBgwiGi8vEQkJDg4JCQEAAwAA/8ACAAHAABoAOABLAAAFNjcxMTY3NjU0JyYnJicGBwYHBhUU",
    "FxYXFhcnMyMzNTEjMSYnNjczMRYXFTEzMRYXBgcjMSYnNjc3MhcxMRYVFAcGIyInJjU0NzYzAQBGOjokIiIkOjpGRjo6JCIiJDo6",
    "RigYGBgYFgICFjAWAggWAgIWUBYCAhYoDgkJCQkODgkJCQkOQAEhIjw9Q0M9PCIhAQEhIjw9Q0M9PCIhAbBAAhYWAgIWWAIWFgIC",
    "FhYC0AkJDg4JCQkJDg4JCQABABD/2QHnAacARgAAEzMjMzIXFhUUBwYjIzEiJyY1NTE0NzYzMhcWFRUxNzE2NzYXFhcWFxYHBgcG",
    "BwYnJicmNTQ3NjMyFxYzMjc2NTQnJiMiBwd+MjIyDgkJCQkOgA4JCQkJDg4JCRIsOTk5OSwsDw4ODywsOTk5OSwKCgkNDQoxQEAx",
    "Ly8xQEAxEQEgCQkODgkJCQkOgA4JCQkJDjMRLA8ODg8sLDk5OTksLA8ODg8sCQ0NCgkJLy8xQEAxLy8RAAIAAP/AAcABwAAhADIA",
    "ABMHNwcjMSIHBhUUFxYzITEyNzY1NCcmIyMxJzEmJyMxBgcFISEhEzEWFxYzMzEyNzY3E4cHBwdgDgkJCQkOAYAOCQkJCQ5gBwkU",
    "eBQJARn+gAGA/oAVAg0OE/YTDg0CFQGuDg4OCQkODgkJCQkODgkJDhEBARFu/q0TDQ0NDRMBUwAABQAg/8ABoAHAABAAIAA2AEwA",
    "kAAAEzIXMTEWFRUxIzE1MTQ3NjMHNDcxMTYzMhcWFRUxIzE1MzQ3MTE2MzIXFhUVMRQHBiMiJyY1NRc0NzExNjMyFxYVFTEUBwYj",
    "IicmNTUHNRU1FjMyNxYXFjMyNxUxFAcGBxUxFAcGIyMxIicmNTUxJicnMSYnNTE2NzY3MzEyFxYVFAcGIyMxBgcWFzMxNjc2N8AO",
    "CQlACQkOgAkJDg4JCUDACQkODgkJCQkODgkJYAkJDg4JCQkJDg4JCWAOEhQQBhEQFRIOEREeCQkOoA4JCRoVCyUBARISG1gRCwwM",
    "CxE4DwEBDzgfFBQBAcAJCQ5wcA4JCUAOCQkJCQ5QUA4JCQkJDmAOCQkJCQ5gQA4JCQkJDkAOCQkJCQ5AWAEBAQkLEwwMCQkoISEW",
    "YA4JCQkJDk4MFQsmNRsbEhIBDAsREQsMAQ8PAQEUFB8AAAMAAP/AAgABwAAQADgAhgAAASMzIycxJjc2NzMxFhcWBwcHMyMzFhcw",
    "MRYXFhcWFwYHBgchMSYnJic2NzY3NjcwMTExMTE2NzY3FyYnBgcVMQYHBgcWFxYXFzEWFxYHFAcGIyYnJicmBwYXFhcxMTExFhcV",
    "MRYXNjc1MTY3NjcmJyYnMTE1MSYnJjcmNzYzMhcWNzYnJic1AUCAgIAvBQQECsQKBAQFL4CAgIAGBx4qKSAgAgEbGyn+wCkbGwEC",
    "ICApKh4CAwQEVAISEgIMChgCAxYSEQITCQcBBggNEBMEBBIHBBEDAwwQAhISAgwLFwIDFhITEwoGAQEHCQ0OERIGAxEKCwFgRwkI",
    "BwEBBwgJRyAEBBIiIzc4UikbGwEBGxspUjg3IyISAQICA1gSAgISDgIHDB8eCwoEAQUFBQQHAwUBCAEBBBASCAEBBQMPEgICEg4C",
    "Bw0gHgsLBAEFBQQDBQQFBQMREgcCAg4AAAEAAAANAY8AFQAAAAAAAQAAAAEAAQAAAAAAAAAAAAAAAABRAIgBGQG/AgUCdgMQA7AE",
    "FwR4BMEFcQYoAAEAAAMFAwBWlOtdXw889QALAgAAAAAA4Y1qrAAAAADhjWqs//P/tQKLAcsAAAAIAAIAAAAAAAABgAAAAED/8wHA",
    "AAABQAAKAcAAAAIAABACAAAMAgAAEAIAAAACAAAQAcAAAAHAACACAAAAAAEAAAHL/7UAAAKA//P/8wKLAAEAAAAAAAAAAAAAAAAA",
    "AAANAAQCAwOEAAUAAAFMAWYAAABHAUwBZgAAAPUAGQCEAAACAAkDAAAAAAAAAAAAABAAAAAAAAAAAAAAAEFXU00AgPAH+B0By/+1",
    "AAABywBLAAAAAQAAAAABQQGvAAAAIAAAAAAAAgAAAAMAAAAUAAMAAQAAABQABABgAAAAFAAQAAMABPAH8BHwE/Ah8Frw4vH49t74",
    "Hf//AADwB/AR8BPwIfBa8OLx+Pbe+B3//w/9D/QP8w/mD64PJw4SCS0H7wABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAHAFoAAwAB",
    "BAkAAAA0AAAAAwABBAkAAQAyADQAAwABBAkAAgAKAGYAAwABBAkAAwA+AHAAAwABBAkABAAyADQAAwABBAkABQBkAK4AAwABBAkA",
    "BgAsARIAQwBvAHAAeQByAGkAZwBoAHQAIAAoAGMAKQAgAEYAbwBuAHQAIABBAHcAZQBzAG8AbQBlAEYAbwBuAHQAIABBAHcAZQBz",
    "AG8AbQBlACAANgAgAEYAcgBlAGUAIABTAG8AbABpAGQAUwBvAGwAaQBkAEYAbwBuAHQAIABBAHcAZQBzAG8AbQBlACAANgAgAEYA",
    "cgBlAGUAIABTAG8AbABpAGQALQA2AC4ANQAuADEAVgBlAHIAcwBpAG8AbgAgADcANwAzAC4AMAAxADEANwAxADgANwA1ACAAKABG",
    "AG8AbgB0ACAAQQB3AGUAcwBvAG0AZQAgAHYAZQByAHMAaQBvAG4AOgAgADYALgA1AC4AMQApAEYAbwBuAHQAQQB3AGUAcwBvAG0A",
    "ZQA2AEYAcgBlAGUALQBTAG8AbABpAGQAAgAAAAAAAP/bABkAAAAAAAAAAAAAAAAAAAAAAAAAAAANAAABAgEDAQQBBQEGAQcBCAEJ",
    "AQoBCwEMAQ0LZXhjbGFtYXRpb24HaGFzaHRhZwtkb2xsYXItc2lnbgR1c2VyCXBvd2VyLW9mZgRnZWFyDWFycm93cy1yb3RhdGUL",
    "Y2lyY2xlLWluZm8RYXJyb3ctcm90YXRlLWxlZnQFdHJhc2gJaGFuZC1maXN0C3NhY2stZG9sbGFy",
})

-- UTF-8 байты нужных иконок (кодовые точки Private Use Area
-- FontAwesome: f007/f6de/f81d/f013/f05a) — считаются напрямую в UTF-8,
-- БЕЗ u8(), потому что u8() конвертирует из CP1251, а это не кириллица
local ICON_USER = "\239\128\135" -- fa-user        -- vkladka "Personazh"
local ICON_FIST = "\239\155\158" -- fa-hand-fist   -- vkladka "Boy"
local ICON_SACK = "\239\160\157" -- fa-sack-dollar -- vkladka "Finansy"
local ICON_GEAR = "\239\128\147" -- fa-gear        -- vkladka "Nastroyki"
local ICON_INFO = "\239\129\154" -- fa-circle-info -- vkladka "O skripte"
-- ── добавленные по просьбе иконки для кнопок "О скрипте" и панели
-- настроек (тот же шрифт-подмножество, догружены доп. глифы) ──
local ICON_POWER = "\239\128\145" -- fa-power-off       -- "Выключить"
local ICON_TRASH = "\239\135\184" -- fa-trash           -- "Удалить"
local ICON_UNDO  = "\239\131\162" -- fa-arrow-rotate-left -- "Сброс данных"
local ICON_SYNC  = "\239\128\161" -- fa-arrows-rotate   -- "Перезагрузить"

-- простой чистый Lua base64-декодер (без внешних зависимостей —
-- на скрипт с mimgui нельзя рассчитывать, что будет доступна bit32/bit)
local function b64decode(data)
    local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    local rev = {}
    for i = 1, #b64chars do rev[b64chars:sub(i,i)] = i - 1 end
    data = data:gsub('[^%w%+%/%=]', '')
    local out = {}
    local i = 1
    local n = #data
    while i <= n do
        local c1 = rev[data:sub(i,i)]
        local c2 = rev[data:sub(i+1,i+1)]
        local c3 = data:sub(i+2,i+2)
        local c4 = data:sub(i+3,i+3)
        local v3 = rev[c3]
        local v4 = rev[c4]
        if not c1 or not c2 then break end
        local n1 = c1 * 4 + math.floor(c2 / 16)
        out[#out+1] = string.char(n1)
        if c3 ~= '' and c3 ~= '=' and v3 then
            local n2 = (c2 % 16) * 16 + math.floor(v3 / 4)
            out[#out+1] = string.char(n2)
            if c4 ~= '' and c4 ~= '=' and v4 then
                local n3 = (v3 % 4) * 64 + v4
                out[#out+1] = string.char(n3)
            end
        end
        i = i + 4
    end
    return table.concat(out)
end

-- распаковывает шрифт иконок на диск, если его там ещё нет (или файл
-- повреждён/пустой) — вызывается один раз из imgui.OnInitialize ниже
local function ensureIconFontFile()
    local f = io.open(ICON_FONT_FILE, "rb")
    if f then
        local sz = f:seek("end")
        f:close()
        if sz and sz > 0 then return true end
    end
    ensureCfgDir()
    local raw = b64decode(ICON_FONT_B64)
    if not raw or #raw == 0 then return false end
    local out, ferr = io.open(ICON_FONT_FILE, "wb")
    if not out then return false end
    out:write(raw)
    out:close()
    return true
end

-- подключаем шрифт иконок в режиме MergeMode поверх обычного шрифта —
-- после этого ICON_USER/ICON_FIST/ICON_SACK/ICON_GEAR/ICON_INFO можно
-- вставлять прямо в любой imgui-текст как обычные символы
imgui.OnInitialize(function()
    pcall(ensureIconFontFile)
    pcall(function()
        -- как в рабочей PCStats 11: MergeMode поверх дефолтного шрифта
        local io = imgui.GetIO()
        local fonts = io.Fonts
        local baseSize = 13.0
        pcall(function()
            if fonts.ConfigData and fonts.ConfigData.Size and fonts.ConfigData.Size > 0
                and fonts.ConfigData.Data then
                local defaultFontCfg = fonts.ConfigData.Data[0]
                if defaultFontCfg and defaultFontCfg.SizePixels then
                    baseSize = defaultFontCfg.SizePixels
                end
            end
        end)
        local config = imgui.ImFontConfig()
        config.MergeMode  = true
        config.PixelSnapH = true
        -- держим диапазон глобально (ImGui хранит указатель)
        PCS_ICON_RANGES = imgui.new.ImWchar[3](0xf000, 0xf8ff, 0)
        fonts:AddFontFromFileTTF(ICON_FONT_FILE, baseSize, config, PCS_ICON_RANGES)
        -- пересобираем атлас, если API доступен
        pcall(function()
            if fonts.Build then fonts:Build() end
        end)
        pcall(function()
            if imgui.InvalidateDeviceObjects then imgui.InvalidateDeviceObjects() end
            if imgui.CreateDeviceObjects then imgui.CreateDeviceObjects() end
        end)
    end)
end)

local cfg = {
    theme        = 1,
    autoRefresh  = true,
    autoInterval = 30,
    winWPct      = 0.0,
    winHPct      = 0.0,
    -- ŠŗŠ°Ń�Ń‚Š¾Š¼Š½Ń‹Šµ Ń†Š²ŠµŃ‚Š° Š°ŠŗŃ†ŠµŠ½Ń‚Š° (R,G,B 0..1)
    custR = -1, custG = -1, custB = -1,
    -- ŠŗŠ°Ń�Ń‚Š¾Š¼Š½Ń‹Š¹ Ń†Š²ŠµŃ‚ Ń„Š¾Š½Š° Ń�Ń‚Ń€Š¾Šŗ (R,G,B 0..1, -1 = Š°Š²Ń‚Š¾ Š¾Ń‚ Š°ŠŗŃ†ŠµŠ½Ń‚Š°)
    rowBgR  = -1, rowBgG = -1, rowBgB = -1,
    -- цвет текста (imgui.Col.Text, глобально), -1 = авто (белый из темы)
    textR = -1, textG = -1, textB = -1,
    -- фон самого окна скрипта (imgui.Col.WindowBg), -1 = авто (чёрный)
    winBgR = -1, winBgG = -1, winBgB = -1,
    -- цвет обводки окна/карточек (imgui.Col.Border), -1 = авто (от акцента)
    outlineR = -1, outlineG = -1, outlineB = -1,
    -- толщина обводки окна (px, до масштаба интерфейса), диапазон 1..6
    borderThickness = 1.2,
    -- "переливающаяся" (радужная, анимированная) обводка окна — если true,
    -- перекрывает cfg.outlineR/G/B бегущим по кругу HSV-цветом
    rainbowBorder = false,
    uiLightMode = false,
    -- false = старый единый ряд вкладок сверху (по умолчанию, как было
    -- раньше), true = новое боковое меню слева — по просьбе вкладки
    -- остаются НЕ слева, старый верхний ряд остаётся вариантом по умолчанию
    sidebarLayout = false,
    -- true = боковое меню свёрнуто (показывает только иконки без подписей)
    sidebarCollapsed = false,
    -- кастомный цвет текста сообщений скрипта в чате, -1 = авто (стандартные
    -- цвета {00FF88}/{00AAFF}/{FFD700}/{7289DA}, см. applyCustomChatColor)
    chatR = -1, chatG = -1, chatB = -1,
    -- смысловые цвета (успех / предупреждение / ошибка), -1 = дефолт
    successR = -1, successG = -1, successB = -1,
    warnR = -1, warnG = -1, warnB = -1,
    errorR = -1, errorG = -1, errorB = -1,

    -- Š¼Š°Ń�Ń�Ń‚Š°Š± Ń�Ń€ŠøŃ„Ń‚Š° (0.7 .. 2.0, default 1.0)
    fontSize = 1.25,
    -- ŠŗŃ�Ń€Ń�Ń‹ Š¾Š±Š¼ŠµŠ½Š° Š²Š°Š»Ń�Ń‚ Š² SA$ Š·Š° 1 ŠµŠ´. (Š´Š»Ń¸ Š²ŠŗŠ»Š°Š´ŠŗŠø "Š’Ń�ŠµŠ³Š¾")
    rateAZ  = 35000.0,
    rateBTC = 0.0,
    rateEUR = 0.0,
    rateVC  = 0.0,
    -- отдельно курс "продажа" VC$ с экрана "Криптовалюта" (заполняется
    -- автоматически из parsePhoneRatesText вместе с обычным rateVC,
    -- редактируется вручную так же, как остальные курсы) ──
    rateVCSell = 0.0,
    -- ASC ne chitaetsya avtomaticheski iz staty servera, kolichestvo vvoditsya vruchnuyu
    ascAmount = 0.0,
    rateASC   = 0.0,
    -- imya servera Arizona RP dlya avtoobnovleniya kursov s arz-wiki.com (sm. fetchArzWikiRates)
    vcServerName = "Tucson",
    -- opredelyat' server avtomaticheski (po hostname/IP tekushchego SAMP-servera),
    -- a ne vvodit' vruchnuyu
    vcAutoDetectServer = true,
    -- pryatat rodnoe okno /stats servera poka skript schitivaet dannye (chtoby ne migalo)
    hideNativeStats = true,
    -- vkladka "Finansy": dvuhkolonochnyy rezhim (nalichnye/bank/depozit/scheta slева, valyuty справа)
    financeTwoCol = true,
    -- serializovannye kastomnye cveta otdelnyh tekstov/cifr (id=r,g,b;id=r,g,b;...)
    customColorsStr = "",
    -- vkladka "Finansy": kakie kategorii uchityvat v obschem itoge "Vsego virtov"
    incCash = true, incBank = true, incDep = true, incAcc = true,
    incAZ = true, incBTC = true, incEUR = true, incVC = true, incASC = true,
    -- globalnyy cvet cifr/znacheniy (perekryvaet avtocvet, no ne perekryvaet individualnyy klik-cvet)
    globalNumColorOn = false,
    globalNumR = -1, globalNumG = -1, globalNumB = -1,
    -- komanda otkrytiya telefona v igre (kursy valyut teper chitayutsya iz nego, bez CEF)
    phoneOpenCmd  = "/phone",
    -- komanda otkrytiya glavnogo menyu skripta (bez slesha, po umolchaniyu "sw")
    menuOpenCmd = "sw",
    -- goryachaya klavisha otkrytiya menyu (VK-kod); po umolchaniyu F9 (120),
    -- chtoby hotkey rabotal "iz korobki" bez ruchnoy nastroyki — 0 tolko
    -- esli igrok sam ochistil naznachenie (sm. clampNum-fix v loadCfg nizhe)
    menuHotkeyVK = 120,
    -- nomer poslednej otkrytoy vkladki (1..5), chtoby posle perezahoda/
    -- obnovleniya skripta menyu otkryvalos na toy zhe vkladke, na kotoroy
    -- igrok byl v proshlyy raz
    lastTab = 1,

    -- ── Оплата налогов (вкладка "Налоги") ──
    taxAutoEnabled        = false, -- автооплата по таймеру вкл/выкл
    taxAutoIntervalHours  = 1,     -- через сколько часов повторять автооплату
    taxLastPayTime        = 0,     -- os.time() последней успешной оплаты (своей)
    taxLastPayAmount      = 0.0,   -- сумма последней оплаты (если удалось распознать из чата)
    taxPayOnLogin         = false, -- при входе в игру подождать 1-2 минуты и автоматически оплатить налоги
}

-- kastomnye cveta konkretnyh tekstovyh elementov (klikom po tekstu/cifram),
-- id -> {r,g,b}; zapolnyaetsya iz cfg.customColorsStr pri zagruzke
local customColors = {}

local function serializeCustomColors()
    local parts = {}
    for id, c in pairs(customColors) do
        table.insert(parts, id.."="..string.format("%.3f,%.3f,%.3f", c[1], c[2], c[3]))
    end
    return table.concat(parts, ";")
end

local function deserializeCustomColors(s)
    customColors = {}
    if not s or s == "" then return end
    for id, rgb in tostring(s):gmatch("([^=;]+)=([^;]+)") do
        local rr,gg,bb = rgb:match("([%d%.]+),([%d%.]+),([%d%.]+)")
        if rr then customColors[id] = {tonumber(rr), tonumber(gg), tonumber(bb)} end
    end
end

local saveCfgLater = false -- true, если настройки подхватились из старого файла и их надо пересохранить в новом месте
local _restoredMenuCmd = false -- true, если menuOpenCmd подхватился из сохранённых настроек (не дефолт) — используется для уведомления в чат при спавне

-- ── защита от битых/экстремальных значений в settings.ini: раньше
-- inicfg.load() был сломан (см. фикс сигнатуры выше) и всегда тихо
-- падал, поэтому сохранённые значения фактически никогда не
-- подставлялись обратно — любой мусор в файле был безвреден. Теперь,
-- когда загрузка реально работает, старый/повреждённый/отредактированный
-- вручную settings.ini мог бы напрямую попасть в нативный рендер
-- (например SetWindowFontScale с огромным fontSize) и уронить игру.
-- clampNum подстраховывает такие поля числовым диапазоном ──
local function clampNum(v, lo, hi, dflt)
    v = tonumber(v)
    if not v or v ~= v then return dflt end -- v~=v ловит NaN
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- ── надёжное чтение булевых полей настроек ──
-- ФИКС: настоящий inicfg.lua (используемый MoonLoader'ом) при ЧТЕНИИ
-- .ini САМ автоматически превращает строки "true"/"false" в настоящие
-- Lua-булевы значения (см. его ini_value(): сначала проверяет
-- lower()=='true'/'false' и только потом tonumber). Из-за этого
-- сравнение "m.поле == \"true\"" всегда даёт false (Lua: boolean ~=
-- string, никогда не равны), а "m.поле ~= \"false\"" — наоборот всегда
-- true — то есть тумблер, сохранённый как false, после перезапуска
-- скрипта тихо возвращался к своему умолчанию. toBool() понимает ОБА
-- варианта — и настоящий boolean от inicfg, и "сырую" строку (на
-- случай другой версии/реализации inicfg) — поэтому корректно работает
-- независимо от того, что именно вернула конкретная сборка inicfg ──
local function toBool(v, dflt)
    if type(v) == "boolean" then return v end
    if v == "true" then return true end
    if v == "false" then return false end
    return dflt
end

-- ── имя клавиши по VK-коду для отображения назначенной горячей
-- клавиши открытия меню (см. "Настройки" и onKeyDown ниже) ──
local VK_NAMES = {
    [8]="Backspace", [9]="Tab", [19]="Pause", [20]="CapsLock", [27]="Esc",
    [32]="Space", [33]="PageUp", [34]="PageDown", [35]="End", [36]="Home",
    [37]="Left", [38]="Up", [39]="Right", [40]="Down",
    [45]="Insert", [46]="Delete",
    [91]="Win", [93]="Menu",
    [144]="NumLock", [145]="ScrollLock",
    [160]="LShift", [161]="RShift", [162]="LCtrl", [163]="RCtrl", [164]="LAlt", [165]="RAlt",
    [186]=";", [187]="=", [188]=",", [189]="-", [190]=".", [191]="/",
    [192]="`", [219]="[", [220]="\\", [221]="]", [222]="'",
}
for i = 1, 12 do VK_NAMES[111 + i] = "F" .. i end
for i = 0, 9 do VK_NAMES[96 + i] = "Num" .. i end

local function vkName(code)
    code = tonumber(code)
    if not code or code == 0 then
        return u8"\xed\xe5\x20\xed\xe0\xe7\xed\xe0\xf7\xe5\xed\xe0"
    end
    if VK_NAMES[code] then return u8(VK_NAMES[code]) end
    if (code >= 48 and code <= 57) or (code >= 65 and code <= 90) then
        return string.char(code)
    end
    return "VK" .. code
end

local function applyCfgData(m)
    cfg.theme        = clampNum(m.theme, 1, 6, 1)
    cfg.autoRefresh  = toBool(m.autoRefresh, true)
    cfg.autoInterval = clampNum(m.autoInterval, 5, 3600, 30)
    cfg.winWPct      = clampNum(m.winWPct, 0.0, 1.0, 0.0)
    cfg.winHPct      = clampNum(m.winHPct, 0.0, 1.0, 0.0)
    cfg.custR        = clampNum(m.custR, -1, 1, -1)
    cfg.custG        = clampNum(m.custG, -1, 1, -1)
    cfg.custB        = clampNum(m.custB, -1, 1, -1)
    cfg.rowBgR        = clampNum(m.rowBgR, -1, 1, -1)
    cfg.rowBgG        = clampNum(m.rowBgG, -1, 1, -1)
    cfg.rowBgB        = clampNum(m.rowBgB, -1, 1, -1)
    cfg.textR         = clampNum(m.textR, -1, 1, -1)
    cfg.textG         = clampNum(m.textG, -1, 1, -1)
    cfg.textB         = clampNum(m.textB, -1, 1, -1)
    -- фон меню: читаем из ini (пикер в "Цвета интерфейса")
    cfg.winBgR        = clampNum(m.winBgR, -1, 1, -1)
    cfg.winBgG        = clampNum(m.winBgG, -1, 1, -1)
    cfg.winBgB        = clampNum(m.winBgB, -1, 1, -1)
    cfg.outlineR      = clampNum(m.outlineR, -1, 1, -1)
    cfg.outlineG      = clampNum(m.outlineG, -1, 1, -1)
    cfg.outlineB      = clampNum(m.outlineB, -1, 1, -1)
    cfg.borderThickness = clampNum(m.borderThickness, 0.5, 6.0, 1.2)
    cfg.rainbowBorder   = toBool(m.rainbowBorder, false)
    -- тумблер "чёрный/белый скрипт" (по просьбе, взамен убранного ручного
    -- пикера фона) — false = тёмный фон (по умолчанию), true = светлый
    cfg.uiLightMode     = toBool(m.uiLightMode, false)
    cfg.sidebarLayout    = toBool(m.sidebarLayout, false)
    cfg.sidebarCollapsed = toBool(m.sidebarCollapsed, false)
    cfg.chatR         = clampNum(m.chatR, -1, 1, -1)
    cfg.chatG         = clampNum(m.chatG, -1, 1, -1)
    cfg.chatB         = clampNum(m.chatB, -1, 1, -1)
    cfg.successR = clampNum(m.successR, -1, 1, -1); cfg.successG = clampNum(m.successG, -1, 1, -1); cfg.successB = clampNum(m.successB, -1, 1, -1)
    cfg.warnR = clampNum(m.warnR, -1, 1, -1); cfg.warnG = clampNum(m.warnG, -1, 1, -1); cfg.warnB = clampNum(m.warnB, -1, 1, -1)
    cfg.errorR = clampNum(m.errorR, -1, 1, -1); cfg.errorG = clampNum(m.errorG, -1, 1, -1); cfg.errorB = clampNum(m.errorB, -1, 1, -1)
    cfg.fontSize      = clampNum(m.fontSize, 0.7, 2.0, 1.25)
    cfg.rateAZ        = clampNum(m.rateAZ, 0, 100000000, 35000.0)
    cfg.rateBTC       = clampNum(m.rateBTC, 0, 1e12, 0.0)
    cfg.rateEUR       = clampNum(m.rateEUR, 0, 1e9, 0.0)
    cfg.rateVC        = clampNum(m.rateVC, 0, 1e9, 0.0)
    cfg.rateVCSell    = clampNum(m.rateVCSell, 0, 1e9, 0.0)
    cfg.ascAmount     = clampNum(m.ascAmount, 0, 1e12, 0.0)
    cfg.rateASC       = clampNum(m.rateASC, 0, 1e9, 0.0)
    cfg.vcServerName  = (m.vcServerName and m.vcServerName ~= "") and m.vcServerName or "Tucson"
    cfg.vcAutoDetectServer = toBool(m.vcAutoDetectServer, true)
    -- тумблер убран из интерфейса — родное окно /stats теперь скрывается всегда
    cfg.hideNativeStats = true
    cfg.financeTwoCol   = toBool(m.financeTwoCol, true)
    -- ── тумблеры категорий "Всего вирты": по умолчанию ВСЕ включены ──
    cfg.incCash = toBool(m.incCash, true)
    cfg.incBank = toBool(m.incBank, true)
    cfg.incDep  = toBool(m.incDep,  true)
    cfg.incAcc  = toBool(m.incAcc,  true)
    cfg.incAZ   = toBool(m.incAZ,   true)
    cfg.incBTC  = toBool(m.incBTC,  true)
    cfg.incEUR  = toBool(m.incEUR,  true)
    cfg.incVC   = toBool(m.incVC,   true)
    cfg.incASC  = toBool(m.incASC,  true)
    cfg.globalNumColorOn = toBool(m.globalNumColorOn, false)
    cfg.globalNumR = clampNum(m.globalNumR, -1, 1, -1)
    cfg.globalNumG = clampNum(m.globalNumG, -1, 1, -1)
    cfg.globalNumB = clampNum(m.globalNumB, -1, 1, -1)
    cfg.customColorsStr = m.customColorsStr or ""
    deserializeCustomColors(cfg.customColorsStr)
    cfg.phoneOpenCmd  = (m.phoneOpenCmd and m.phoneOpenCmd ~= "") and m.phoneOpenCmd or "/phone"
    cfg.menuOpenCmd   = (m.menuOpenCmd and m.menuOpenCmd ~= "") and m.menuOpenCmd or "sw"
    if cfg.menuOpenCmd ~= "sw" then _restoredMenuCmd = true end
    -- ФИКС "хотей не работает из коробки": раньше при первом запуске
    -- (файла настроек ещё нет / поле отсутствует) горячая клавиша
    -- оставалась 0 (не назначена), и её приходилось назначать вручную
    -- в "Настройках". Теперь если m.menuHotkeyVK вообще отсутствует в
    -- сохранённом файле (первый запуск/старый файл до этой версии) —
    -- подставляется дефолт F9 (120). Если поле в файле ЕСТЬ (даже "0",
    -- т.е. игрок сам снял назначение через "Снять") — уважаем этот выбор ──
    cfg.menuHotkeyVK = clampNum(m.menuHotkeyVK, 0, 255, (m.menuHotkeyVK == nil) and 120 or 0)
    local lt = tonumber(m.lastTab)
    cfg.lastTab = (lt and lt >= 1 and lt <= 8) and math.floor(lt) or 1
    -- ── Оплата налогов ──
    cfg.taxAutoEnabled        = toBool(m.taxAutoEnabled, false)
    -- ФИКС (по просьбе): раньше интервал автооплаты налогов был ограничен
    -- сутками (макс. 24ч) — теперь потолок поднят до 120ч (5 суток), чтобы
    -- можно было выставить кулдаун "раз в несколько дней", а не только "раз
    -- в сутки максимум"
    cfg.taxAutoIntervalHours  = clampNum(m.taxAutoIntervalHours, 1, 120, 1)
    cfg.taxLastPayTime        = clampNum(m.taxLastPayTime, 0, 99999999999, 0)
    cfg.taxLastPayAmount      = clampNum(m.taxLastPayAmount, 0, 1e15, 0.0)
    cfg.taxPayOnLogin         = toBool(m.taxPayOnLogin, false)

    -- ── учёт дохода PayDay (зарплата/депозит/аксы/AZ из чата) ──
    cfg.incomeTrackEnabled = toBool(m.incomeTrackEnabled, true)
    cfg.incomeAllTimeMoney = clampNum(m.incomeAllTimeMoney, 0, 1e18, 0.0)
    cfg.incomeAllTimeAZ    = clampNum(m.incomeAllTimeAZ,    0, 1e18, 0.0)
end

local function loadCfg()
    -- 1) пробуем новое расположение (папка moonloader/config/PCStats/)
    local ok, data = pcall(function() return inicfg.load(nil, CFG_FILE) end)
    if ok and data and data.main then
        applyCfgData(data.main)
    else
        -- 2) новой папки/файла ещё нет — пробуем старое плоское
        -- расположение (версии скрипта до 1.1.2). Если там что-то есть —
        -- подхватываем эти настройки и сразу пересохраняем в новую папку,
        -- чтобы при следующем запуске уже читать из неё
        local okOld, dataOld = pcall(function() return inicfg.load(nil, CFG_FILE_OLD) end)
        if okOld and dataOld and dataOld.main then
            applyCfgData(dataOld.main)
            saveCfgLater = true
        end
    end
end

local function saveCfg()
    -- п.12: помечаем, что настройки менялись в течение ТЕКУЩЕЙ открытой
    -- сессии меню — используется требованием закрытия с подтверждением
    -- (см. requestCloseMenu/drawCloseConfirmPopup ниже). Пока меню
    -- закрыто (например, автосохранение курсов валют в фоне) — не
    -- считается изменением "в настройках", подтверждение не нужно.
    if St.winOpen then St._settingsTouchedThisSession = true end
    cfg.customColorsStr = serializeCustomColors()
    ensureCfgDir() -- на случай, если папки ещё нет (первый запуск / миграция со старой версии) — если уже есть, ничего не делает
    pcall(function()
        inicfg.save({main={
            theme        = tostring(cfg.theme),
            autoRefresh  = tostring(cfg.autoRefresh),
            autoInterval = tostring(cfg.autoInterval),
            winWPct      = tostring(cfg.winWPct),
            winHPct      = tostring(cfg.winHPct),
            custR        = tostring(cfg.custR),
            custG        = tostring(cfg.custG),
            custB        = tostring(cfg.custB),
            rowBgR        = tostring(cfg.rowBgR),
            rowBgG        = tostring(cfg.rowBgG),
            rowBgB        = tostring(cfg.rowBgB),
            textR         = tostring(cfg.textR),
            textG         = tostring(cfg.textG),
            textB         = tostring(cfg.textB),
            winBgR        = tostring(cfg.winBgR),
            winBgG        = tostring(cfg.winBgG),
            winBgB        = tostring(cfg.winBgB),
            outlineR      = tostring(cfg.outlineR),
            outlineG      = tostring(cfg.outlineG),
            outlineB      = tostring(cfg.outlineB),
            borderThickness = tostring(cfg.borderThickness),
            rainbowBorder   = tostring(cfg.rainbowBorder),
            uiLightMode     = tostring(cfg.uiLightMode),
            sidebarLayout    = tostring(cfg.sidebarLayout),
            sidebarCollapsed = tostring(cfg.sidebarCollapsed),
            chatR         = tostring(cfg.chatR),
            chatG         = tostring(cfg.chatG),
            chatB         = tostring(cfg.chatB),
            successR = tostring(cfg.successR or -1), successG = tostring(cfg.successG or -1), successB = tostring(cfg.successB or -1),
            warnR = tostring(cfg.warnR or -1), warnG = tostring(cfg.warnG or -1), warnB = tostring(cfg.warnB or -1),
            errorR = tostring(cfg.errorR or -1), errorG = tostring(cfg.errorG or -1), errorB = tostring(cfg.errorB or -1),
            fontSize      = tostring(cfg.fontSize),
            rateAZ        = tostring(cfg.rateAZ),
            rateBTC       = tostring(cfg.rateBTC),
            rateEUR       = tostring(cfg.rateEUR),
            rateVC        = tostring(cfg.rateVC),
            rateVCSell    = tostring(cfg.rateVCSell),
            ascAmount     = tostring(cfg.ascAmount),
            rateASC       = tostring(cfg.rateASC),
            vcServerName  = tostring(cfg.vcServerName or "Tucson"),
            vcAutoDetectServer = tostring(cfg.vcAutoDetectServer),
            hideNativeStats = tostring(cfg.hideNativeStats),
            financeTwoCol   = tostring(cfg.financeTwoCol),
            incCash = tostring(cfg.incCash), incBank = tostring(cfg.incBank),
            incDep  = tostring(cfg.incDep),  incAcc  = tostring(cfg.incAcc),
            incAZ   = tostring(cfg.incAZ),   incBTC  = tostring(cfg.incBTC),
            incEUR  = tostring(cfg.incEUR),  incVC   = tostring(cfg.incVC),
            incASC  = tostring(cfg.incASC),
            globalNumColorOn = tostring(cfg.globalNumColorOn),
            globalNumR = tostring(cfg.globalNumR),
            globalNumG = tostring(cfg.globalNumG),
            globalNumB = tostring(cfg.globalNumB),
            lastTab       = tostring(cfg.lastTab or 1),
            phoneOpenCmd  = tostring(cfg.phoneOpenCmd or "/phone"),
            menuOpenCmd   = tostring(cfg.menuOpenCmd or "sw"),
            menuHotkeyVK  = tostring(cfg.menuHotkeyVK or 0),
            customColorsStr = cfg.customColorsStr,
            taxAutoEnabled        = tostring(cfg.taxAutoEnabled),
            taxAutoIntervalHours  = tostring(cfg.taxAutoIntervalHours),
            taxLastPayTime        = tostring(cfg.taxLastPayTime),
            taxLastPayAmount      = tostring(cfg.taxLastPayAmount),
            taxPayOnLogin         = tostring(cfg.taxPayOnLogin),
            incomeTrackEnabled = tostring(cfg.incomeTrackEnabled),
            incomeAllTimeMoney = tostring(cfg.incomeAllTimeMoney),
            incomeAllTimeAZ    = tostring(cfg.incomeAllTimeAZ),
        }}, CFG_FILE)
    end)
end

-- ============================================================
--  Š¢Š•Š�Š«
-- ============================================================
local THEMES = {
    {name="Night",  bg={0.00,0.00,0.00}, acc={0.43,0.71,1.0},  tile={0.00,0.00,0.00}, txt={1.0, 1.0, 1.0}},
    {name="Forest", bg={0.00,0.00,0.00}, acc={0.30,0.85,0.45}, tile={0.00,0.00,0.00}, txt={1.0, 1.0, 1.0}},
    {name="Sunset", bg={0.00,0.00,0.00}, acc={1.0, 0.55,0.20}, tile={0.00,0.00,0.00}, txt={1.0, 1.0, 1.0}},
    {name="Purple", bg={0.00,0.00,0.00}, acc={0.75,0.45,1.0},  tile={0.00,0.00,0.00}, txt={1.0, 1.0, 1.0}},
    {name="Gold",   bg={0.00,0.00,0.00}, acc={1.0, 0.80,0.25}, tile={0.00,0.00,0.00}, txt={1.0, 1.0, 1.0}},
    {name="Blood",  bg={0.00,0.00,0.00}, acc={1.0, 0.25,0.25}, tile={0.00,0.00,0.00}, txt={1.0, 1.0, 1.0}},
}
local function getTheme() return THEMES[cfg.theme] or THEMES[1] end

-- Š�Š¾Š»Ń�Ń‡ŠøŃ‚Ń� Š°ŠŗŃ†ŠµŠ½Ń‚Š½Ń‹Š¹ Ń†Š²ŠµŃ‚ (ŠŗŠ°Ń�Ń‚Š¾Š¼Š½Ń‹Š¹ ŠøŠ»Šø ŠøŠ· Ń‚ŠµŠ¼Ń‹)
local function getAcc()
    if cfg.custR >= 0 then return cfg.custR, cfg.custG, cfg.custB end
    local t = getTheme(); local a = t.acc
    return a[1], a[2], a[3]
end

-- ============================================================
--  Š¦Š’Š•Š¢Š�
-- ============================================================
local function iv4(r,g,b,a) return imgui.ImVec4(r,g,b,a or 1.0) end

-- ── HSV → RGB (для "переливающейся" радужной обводки окна) ──
local function hsv2rgb(h, s, v)
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    i = i % 6
    if     i == 0 then return v, t, p
    elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v
    else                return v, p, q end
end

-- ── кастомный цвет текста сообщений скрипта в чате (см. Настройки → "Цвет
-- текста в чате" / cfg.chatR/G/B). Все сообщения скрипта отправляются с
-- ведущим SAMP-тегом вида "{RRGGBB}[Stats]/[MSW] ..." — здесь этот тег
-- подменяется на выбранный игроком цвет. Красные теги ошибок/предупреждений
-- (FF4444/FF6666/FFAA00) сознательно НЕ трогаем, чтобы ошибка всегда
-- оставалась заметной, даже если выбран, например, зелёный или синий ──
local _CHAT_COLOR_PROTECTED_HEX = { ["FF4444"]=true, ["FF6666"]=true, ["FFAA00"]=true }
function applyCustomChatColor(text)
    if type(text) ~= "string" then return text end
    if not cfg.chatR or cfg.chatR < 0 then return text end
    local hex, rest = text:match("^{(%x%x%x%x%x%x)}(.*)$")
    if not hex or _CHAT_COLOR_PROTECTED_HEX[hex:upper()] then return text end
    local rr = math.floor(math.max(0, math.min(1, cfg.chatR)) * 255 + 0.5)
    local gg = math.floor(math.max(0, math.min(1, cfg.chatG)) * 255 + 0.5)
    local bb = math.floor(math.max(0, math.min(1, cfg.chatB)) * 255 + 0.5)
    return string.format("{%02X%02X%02X}%s", rr, gg, bb, rest)
end

local function thAcc()   local r,g,b=getAcc(); return iv4(r,g,b,1.0) end
local function thTxt()
    if cfg.textR >= 0 then return iv4(cfg.textR, cfg.textG, cfg.textB, 1.0) end
    if cfg.uiLightMode then return iv4(0.07, 0.07, 0.10, 1.0) end
    local t=getTheme(); return iv4(t.txt[1],t.txt[2],t.txt[3],1.0)
end
-- ФИКС (по просьбе): все "тусклые"/акцентные текстовые цвета теперь
-- реагируют на тумблер "чёрный/белый скрипт" (cfg.uiLightMode) — в
-- светлом режиме исходные светло-серые/пастельные тона почти не видны
-- на белом фоне, поэтому берём более тёмные и насыщенные варианты
local function thDim()
    if cfg.uiLightMode then return iv4(0.28, 0.30, 0.36, 1.0) end
    return iv4(0.85,0.87,0.95,1.0)
end
local function thSep()
    local r,g,b=getAcc()
    if cfg.uiLightMode then return iv4(0.40,0.42,0.48,0.85) end
    return iv4(r*0.30,g*0.30,b*0.30,0.7)
end
local function thGreen()
    if cfg.successR and cfg.successR >= 0 then return iv4(cfg.successR, cfg.successG, cfg.successB, 1.0) end
    if cfg.uiLightMode then return iv4(0.05, 0.55, 0.22, 1.0) end
    return iv4(0.25,0.92,0.48,1.0)
end
local function thGold()
    if cfg.warnR and cfg.warnR >= 0 then return iv4(cfg.warnR, cfg.warnG, cfg.warnB, 1.0) end
    if cfg.uiLightMode then return iv4(0.70, 0.50, 0.0, 1.0) end
    return iv4(1.0, 0.82,0.20,1.0)
end
local function thRed()
    if cfg.errorR and cfg.errorR >= 0 then return iv4(cfg.errorR, cfg.errorG, cfg.errorB, 1.0) end
    if cfg.uiLightMode then return iv4(0.78, 0.12, 0.12, 1.0) end
    return iv4(1.0, 0.30,0.30,1.0)
end
local function thAccBright()
    local r,g,b=getAcc()
    return iv4(math.min(1,r*1.15),math.min(1,g*1.15),math.min(1,b*1.15))
end

-- Š�Š¾Š»Ń�Ń‡ŠøŃ‚Ń� Ń†Š²ŠµŃ‚ Ń„Š¾Š½Š° Ń�Ń‚Ń€Š¾Šŗ dataRow (R,G,B)
local function getRowBgColor()
    if cfg.rowBgR >= 0 then
        return cfg.rowBgR, cfg.rowBgG, cfg.rowBgB
    end
    local r,g,b = getAcc()
    return r, g, b
end
-- ============================================================
--  AUTO UI SCALE (masshtabirovanie pod razreshenie ekrana)
-- ============================================================
 St = {}  -- consolidated frame-state table (keeps OnFrame's upvalue count under LuaJIT's 60 limit); local объявлен раньше по файлу, см. фикс выше
St.UI_SCALE      = 1.0   -- pereschityvaetsya kazhdyi kadr po DisplaySize
 St.UI_SCALE_MIN  = 0.88
 St.UI_SCALE_MAX  = 1.65
 St._lastSw, St._lastSh = 0, 0  -- poslednie izvestnye razmery ekrana (detekt smeny razresheniya)

local function S(n)
    return math.floor(n * St.UI_SCALE + 0.5)
end
local function Sf(n)
    return n * St.UI_SCALE
end
-- kak S(), no dopolnitelno uchityvaet polzovatelskiy razmer shrifta (cfg.fontSize),
-- nuzhen dlya blokov s zharestko zadannymi otstupami mezhdu strokami teksta
-- (vkladka "O skripte"), gde pri uvelichenii shrifta stroki nachinali nalezat
-- drug na druga i obrezalis ramkoy kartochki
local function SFtext(n)
    local fs = (cfg.fontSize and cfg.fontSize > 0) and cfg.fontSize or 1.25
    return math.floor(n * St.UI_SCALE * fs + 0.5)
end

-- ============================================================
--  ВСПЛЫВАЮЩИЕ УВЕДОМЛЕНИЯ (TOAST) — по образцу модуля
--  NotificationToastSystem из Market Helper, адаптировано под
--  cfg/S()/Sf()/iv4() этого скрипта (без иконочного шрифта fa —
--  в PCStats свой урезанный набор глифов без warning/error/eye/star)
-- ============================================================
do
    local function pcs_safe_call(fn, ...)
        if type(fn) ~= "function" then return nil end
        local ok, a, b = pcall(fn, ...)
        if ok then return a, b end
        return nil
    end

    local function pcs_pack_color(r, g, b, a)
        a = a == nil and 1 or a
        if imgui.ColorConvertFloat4ToU32 then
            local ok, packed = pcall(imgui.ColorConvertFloat4ToU32, iv4(r, g, b, a))
            if ok and packed then return packed end
        end
        local function tob(v) return math.floor((v<0 and 0 or (v>1 and 1 or v))*255+0.5) end
        local rr,gg,bb,aa = tob(r),tob(g),tob(b),tob(a)
        return (aa*0x1000000)+(bb*0x10000)+(gg*0x100)+rr
    end

    local PCS_TOAST_DEFAULTS = {
        toastEnabled       = true,
        toastWidth         = 320,
        toastPaddingX      = 14,
        toastPaddingY      = 10,
        toastAccentWidth   = 4,
        toastCornerRadius  = 8,
        toastSpacing       = 8,
        toastMarginX       = 18,
        toastMarginY       = 34,
        toastDuration      = 6.0,
        toastAnimSpeed     = 10.0,
        toastMaxVisible    = 5,
        toastPosH          = "right",   -- left | right
        toastPosV          = "bottom",  -- top | bottom
        toastBgR = 0.08, toastBgG = 0.08, toastBgB = 0.10, toastBgA = 0.90,
        toastTextR = 0.94, toastTextG = 0.94, toastTextB = 0.96,
        toastBorderEnabled = false,
        toastBorderR = 1.0, toastBorderG = 1.0, toastBorderB = 1.0, toastBorderA = 0.25,
        toastBorderSize = 1.0,
        toastFontScale = 1.0,
        -- ── новые пере-настраиваемые уведомления (вкладка "Уведомления") ──
        notifyWelcomeEnabled       = true,  -- сообщение при входе с командой открытия меню
        notifyPaydayReminderEnabled = true, -- "до PayDay осталось 5 минут"
        notifyCryptoUpdateEnabled  = true,  -- уведомление при автообновлении курса валют
        cryptoAutoRefreshEnabled   = false, -- сам автообновление курса по таймеру (выкл. по умолч. — доп. трафик)
        cryptoAutoRefreshMinutes   = 60,
    }
    for k, v in pairs(PCS_TOAST_DEFAULTS) do
        if cfg[k] == nil then cfg[k] = v end
    end

    local PCS_NOTIF_TYPES = {
        info    = { color = {0.25, 0.55, 0.95}, label = u8"\xc8\xed\xf4\xee\xf0\xec\xe0\xf6\xe8\xff", glyph = "i" },
        success = { color = {0.22, 0.78, 0.40}, label = u8"\xd3\xf1\xef\xe5\xf5", glyph = "OK" },
        warning = { color = {0.95, 0.66, 0.15}, label = u8"\xc2\xed\xe8\xec\xe0\xed\xe8\xe5", glyph = "!" },
        error   = { color = {0.92, 0.26, 0.26}, label = u8"\xce\xf8\xe8\xe1\xea\xe0", glyph = "X" },
        payday  = { color = {0.98, 0.78, 0.20}, label = "PayDay", glyph = "$" },
    }

    -- ── глобальная копия цветов уведомлений (только r,g,b), нужна ВНЕ
    -- этого do-блока — по просьбе используется для раскраски кнопок
    -- "Тест" во вкладке "Уведомления" под реальный цвет каждого типа
    -- (см. drawNotificationsSection ниже по файлу) ──
    PCS_NOTIF_COLORS = {}
    for k, v in pairs(PCS_NOTIF_TYPES) do
        PCS_NOTIF_COLORS[k] = { v.color[1], v.color[2], v.color[3] }
    end

    local PCS_STATE = { APPEARING='appearing', SHOWING='showing', DISAPPEARING='disappearing', DEAD='dead' }

    local function pcs_clamp01(v) if v<0 then return 0 elseif v>1 then return 1 else return v end end
    local function pcs_lerp(a,b,t) return a+(b-a)*t end
    local function pcs_lerp_dt(cur, tgt, speed, dt)
        local t = 1 - math.exp(-speed*math.max(dt,0))
        return pcs_lerp(cur, tgt, pcs_clamp01(t))
    end

    -- ── ручной перенос текста по словам (нужен, чтобы рисовать тосты
    -- напрямую через draw-list, без окна imgui — см. фикс "МЕШАЕТ ИГРАТЬ"
    -- у _draw_toast ниже: imgui.TextWrapped работает только внутри
    -- Begin()/End(), а окно как раз то, от чего мы уходим). Меряем на
    -- масштабе 1 (CalcTextSize всегда меряет текущим шрифтом со scale=1),
    -- max_w_at_scale1 уже должен быть поделён на fscale вызывающей стороной ──
    local function pcs_wrap_lines(text, max_w_at_scale1)
        text = tostring(text or "")
        local lines = {}
        for para in (text.."\n"):gmatch("([^\n]*)\n") do
            if para == "" then
                lines[#lines+1] = ""
            else
                local cur = nil
                for word in para:gmatch("%S+") do
                    local trial = cur and (cur.." "..word) or word
                    local sz = pcs_safe_call(imgui.CalcTextSize, trial)
                    local w = (sz and sz.x) or (#trial*7)
                    if cur and max_w_at_scale1 and w > max_w_at_scale1 then
                        lines[#lines+1] = cur
                        cur = word
                    else
                        cur = trial
                    end
                end
                lines[#lines+1] = cur or ""
            end
        end
        if #lines == 0 then lines[1] = "" end
        return lines
    end

    local PcsNotification = {}
    PcsNotification.__index = PcsNotification
    local _pcs_id_seq = 0
    local function pcs_next_id() _pcs_id_seq = _pcs_id_seq + 1; return _pcs_id_seq end

    function PcsNotification.new(text, ntype, duration, mcfg)
        local self = setmetatable({}, PcsNotification)
        self.id       = pcs_next_id()
        self.text     = tostring(text or "")
        self.ntype    = PCS_NOTIF_TYPES[ntype] and ntype or "info"
        self.duration = tonumber(duration) or mcfg.duration
        self.cfg      = mcfg
        self.state    = PCS_STATE.APPEARING
        self.timer    = 0
        self.alpha    = 0
        self.y        = 0
        self.target_y = 0
        self.offset   = 0
        self.height   = nil
        self.spawned  = false
        -- ФИКС "УВЕДОМЛЕНИЕ НЕ ПРОПАДАЕТ": общий возраст тоста, копится
        -- независимо от того, в каком он состоянии (appearing/showing/
        -- disappearing) — аварийный предохранитель ниже, в :update(),
        -- принудительно снимает тост с экрана, если он почему-либо завис
        -- (например, время игры "заморозилось" в момент показа диалога,
        -- или другая правка когда-нибудь снова сломает переход между
        -- состояниями) — тост гарантированно не висит вечно
        self.totalAge = 0
        return self
    end

    function PcsNotification:calc_height()
        if self.height then return self.height end
        local mcfg = self.cfg
        local fscale = mcfg.font_scale or 1.0
        local def = PCS_NOTIF_TYPES[self.ntype]
        -- ФИКС: считаем высоту ТЕМ ЖЕ способом (chip-отступ + ручной
        -- pcs_wrap_lines), которым тост реально рисуется в _draw_toast —
        -- иначе расчётная и настоящая высота расходятся, и уведомление
        -- либо обрезается, либо оставляет пустое место снизу.
        local chipSz = math.max(24, mcfg.padding_y*2 + 8)
        local textMaxW = mcfg.width - (8 + chipSz + 10) - mcfg.padding_x
        local lsz = pcs_safe_call(imgui.CalcTextSize, "Ag")
        local lineHBase = (lsz and lsz.y) or 16
        local n_lines = 0
        if def then n_lines = n_lines + #pcs_wrap_lines(def.label, textMaxW / fscale) end
        n_lines = n_lines + #pcs_wrap_lines(self.text, textMaxW / fscale)
        local content_h = n_lines * lineHBase * fscale + 2 * fscale
        self.height = math.max(mcfg.padding_y*2 + content_h + 4, chipSz + 16)
        return self.height
    end

    function PcsNotification:dismiss()
        if self.state ~= PCS_STATE.DISAPPEARING and self.state ~= PCS_STATE.DEAD then
            self.state = PCS_STATE.DISAPPEARING; self.timer = 0
        end
    end
    function PcsNotification:is_dead() return self.state == PCS_STATE.DEAD end

    function PcsNotification:update(dt, target_y, off_screen_y)
        self.target_y = target_y
        local mcfg = self.cfg
        self.totalAge = self.totalAge + (tonumber(dt) or 0)
        -- аварийный предохранитель: тост живёт не дольше duration+10 сек
        -- НИ ПРИ КАКИХ обстоятельствах, даже если анимация/состояние
        -- где-то застряло — гарантированно исчезает сам
        if self.totalAge > (self.duration + 10) then
            self.state = PCS_STATE.DEAD
            return
        end
        if self.state == PCS_STATE.APPEARING then
            if not self.spawned then self.y = off_screen_y; self.spawned = true end
            self.y     = pcs_lerp_dt(self.y, self.target_y, mcfg.anim_speed, dt)
            self.alpha = pcs_lerp_dt(self.alpha, 1, mcfg.anim_speed, dt)
            if math.abs(self.y-self.target_y) < 0.75 and self.alpha > 0.97 then
                self.state = PCS_STATE.SHOWING; self.timer = 0
            end
        elseif self.state == PCS_STATE.SHOWING then
            self.y     = pcs_lerp_dt(self.y, self.target_y, mcfg.anim_speed, dt)
            self.alpha = pcs_lerp_dt(self.alpha, 1, mcfg.anim_speed, dt)
            self.timer = self.timer + dt
            if self.timer >= self.duration then self:dismiss() end
        elseif self.state == PCS_STATE.DISAPPEARING then
            self.y     = pcs_lerp_dt(self.y, off_screen_y, mcfg.anim_speed, dt)
            self.alpha = pcs_lerp_dt(self.alpha, 0, mcfg.anim_speed, dt)
            self.timer = self.timer + dt
            if self.alpha < 0.02 or self.timer > 2.5 then self.state = PCS_STATE.DEAD end
        end
    end

    local PcsNotifyManager = {}
    PcsNotifyManager.config = {
        width=320, padding_x=14, padding_y=10, accent_width=4, corner_radius=8,
        spacing=8, margin_x=18, margin_y=34, duration=6.0, anim_speed=10.0,
        max_visible=5, position="bottom_right",
        bg_color={0.08,0.08,0.10,0.90}, text_color={0.94,0.94,0.96,1.0},
        border_enabled=false, border_color={1,1,1,0.25}, border_size=1.0,
        font_scale=1.0,
    }
    PcsNotifyManager.active  = {}
    PcsNotifyManager.pending = {}
    PcsNotifyManager.enabled = true
    PcsNotifyManager._registered = false

    function PcsNotifyManager.configure(opts)
        if type(opts) ~= "table" then return PcsNotifyManager end
        for k,v in pairs(opts) do PcsNotifyManager.config[k] = v end
        return PcsNotifyManager
    end
    function PcsNotifyManager.set_enabled(flag) PcsNotifyManager.enabled = flag and true or false end

    function PcsNotifyManager.add(text, ntype, duration)
        if not text or text == "" then return nil end
        local notif = PcsNotification.new(text, ntype, duration, PcsNotifyManager.config)
        if #PcsNotifyManager.active < PcsNotifyManager.config.max_visible then
            table.insert(PcsNotifyManager.active, notif)
        else
            table.insert(PcsNotifyManager.pending, notif)
        end
        PcsNotifyManager._ensure_registered()
        return notif.id
    end
    function PcsNotifyManager.clear() PcsNotifyManager.active={}; PcsNotifyManager.pending={} end

    function PcsNotifyManager:_layout_params(sw, sh)
        local mcfg = self.config
        local pos = mcfg.position or "bottom_right"
        local x
        if pos:find("right") then x = sw - mcfg.margin_x - mcfg.width
        elseif pos:find("left") then x = mcfg.margin_x
        else x = (sw - mcfg.width)/2 end
        if x < 0 then x = 0 end
        if x + mcfg.width > sw then x = sw - mcfg.width end
        local mgy = mcfg.margin_y
        if mgy < 28 then mgy = 28 end
        if pos:find("^top") then
            return x, mgy, false
        else
            return x, sh - mgy, true
        end
    end

    function PcsNotifyManager:_update(dt)
        local mcfg = self.config
        while #self.active < mcfg.max_visible and #self.pending > 0 do
            table.insert(self.active, table.remove(self.pending, 1))
        end
        if #self.active == 0 then return end
        local io = imgui.GetIO()
        local sw, sh = io.DisplaySize.x, io.DisplaySize.y
        local anchor_x, anchor_y, grows_up = self:_layout_params(sw, sh)
        local off_screen_y = grows_up and (sh+40) or -40
        local acc = 0
        for i = #self.active, 1, -1 do
            local n = self.active[i]
            n:calc_height()
            n.offset = acc
            acc = acc + n.height + mcfg.spacing
            local target_y
            if grows_up then target_y = anchor_y - n.height - n.offset
            else target_y = anchor_y + n.offset end
            n:update(dt, target_y, grows_up and off_screen_y or (off_screen_y - n.height))
        end
        self._anchor_x = anchor_x
        for i = #self.active, 1, -1 do
            if self.active[i]:is_dead() then table.remove(self.active, i) end
        end
    end

    local function pcs_toast_flags()
        local f = 0
        local W = imgui.WindowFlags
        -- ФИКС "МЕШАЕТ ИГРАТЬ" (доп. страховка для запасного пути ниже —
        -- основной фикс теперь через GetForegroundDrawList, см.
        -- _draw_toast): перечисляем ВСЕ известные варианты названия флага
        -- "не перехватывать мышь/клавиатуру" сразу, потому что в разных
        -- сборках mimgui он может называться по-разному (NoInputs как
        -- готовая комбинация, либо только атомарные NoMouseInputs/
        -- NoNavInputs/NoNavFocus) — если конкретное имя в этой сборке не
        -- существует, `W[name]` просто nil и молча пропускается, так что
        -- лишние строки безопасны.
        for _, name in ipairs({"NoTitleBar","NoResize","NoMove","NoScrollbar",
                "NoScrollWithMouse","NoCollapse","NoSavedSettings",
                "NoFocusOnAppearing","NoNav","NoBackground",
                "NoInputs","NoMouseInputs","NoNavInputs","NoNavFocus"}) do
            if W and W[name] then f = f + W[name] end
        end
        return f
    end
    local PCS_TOAST_FLAGS = pcs_toast_flags()

    -- ФИКС КРАША: раньше Begin()/PushStyleColor(Border) вызывались напрямую,
    -- а часть содержимого окна (GetWindowDrawList/GetWindowPos/AddRectFilled/
    -- PushStyleColor(Text) и т.д.) — тоже напрямую, без pcall. Если там
    -- вылетала ошибка (в этой сборке mimgui какой-то из вызовов иногда
    -- отсутствует/иначе себя ведёт), imgui.End() и парный PopStyleColor()
    -- после него просто не выполнялись — Begin/PushStyleColor оставались
    -- "разомкнутыми", и на СЛЕДУЮЩЕМ кадре это ломало весь imgui и крашило
    -- игру. Это тот же класс бага, что уже чинили в главном окне (там есть
    -- pcall-обёртка с принудительным End(), см. ниже по файлу) — но у
    -- тостов такой обёртки не было, а их OnFrame ничем не защищён. Теперь
    -- всё содержимое обёрнуто в pcall, Begin/End и Push/PopStyleColor
    -- гарантированно парные при любом исходе, а тост, вызвавший ошибку,
    -- помечается мёртвым (а не пытается перерисоваться и упасть повторно
    -- на каждом следующем кадре).
    function PcsNotifyManager:_draw_toast(n)
        local mcfg = self.config
        local def  = PCS_NOTIF_TYPES[n.ntype]
        local a    = pcs_clamp01(n.alpha)
        if a <= 0.01 then return end

        local pmin = imgui.ImVec2(self._anchor_x, n.y)
        local pmax = imgui.ImVec2(pmin.x + mcfg.width, pmin.y + n.height)

        -- ФИКС "МЕШКА ДЛЯ УПРАВЛЕНИЯ ВСЁ РАВНО ВКЛЮЧЕНА" (по-настоящему,
        -- в корне): раньше тост рисовался через imgui.Begin()/End() —
        -- обычное окно imgui. Такое окно ФИЗИЧЕСКИ перехватывает мышь в
        -- своей прямоугольной области — это встроенное поведение imgui,
        -- и никакая комбинация флагов (в т.ч. предыдущая попытка добавить
        -- "NoInputs") не гарантированно его убирает во ВСЕХ сборках
        -- mimgui: если конкретное имя флага в данной сборке не определено,
        -- `W[name]` — nil, и добавление флага молча ничего не делает —
        -- именно поэтому окно продолжало "включать мышку" даже с виду
        -- исправленным кодом.
        --
        -- Настоящий фикс: тост больше вообще НЕ создаёт окно imgui.
        -- Рисуем прямо на GetForegroundDrawList() — это просто линии/текст
        -- поверх игры (как HUD), у которых в принципе нет ни клавиатурного,
        -- ни мышиного захвата, потому что это не окно, а просто пиксели.
        local dl = pcs_safe_call(imgui.GetForegroundDrawList)
            or pcs_safe_call(imgui.GetOverlayDrawList)
            or pcs_safe_call(imgui.GetBackgroundDrawList)
        if dl then
            pcs_safe_call(function()
                local fscale = mcfg.font_scale or 1.0
                local c = def.color

                -- ФИКС (по просьбе "покрасивее"): мягкое цветное свечение под
                -- плашкой вместо плоской чёрной тени — несколько слоёв
                -- увеличивающегося прямоугольника с падающей прозрачностью,
                -- подсвеченных цветом типа уведомления (несколько дешёвых
                -- AddRectFilled вместо настоящего блюра, которого в mimgui нет)
                for gi = 2, 1, -1 do
                    local gpad = gi * 2
                    pcs_safe_call(dl.AddRectFilled, dl,
                        imgui.ImVec2(pmin.x - gpad, pmin.y - gpad),
                        imgui.ImVec2(pmax.x + gpad, pmax.y + gpad),
                        pcs_pack_color(c[1], c[2], c[3], 0.05*a),
                        mcfg.corner_radius + gpad)
                end
                -- обычная тёмная тень поверх свечения — для глубины/контраста
                -- ФИКС (по просьбе "тёмная полоса сверху слишком толстая"):
                -- смещение тени уменьшено (было +3/+5) — на короткой в одну
                -- строку плашке эта тень визуально читалась как отдельная
                -- толстая чёрная полоса над/под самим уведомлением
                pcs_safe_call(dl.AddRectFilled, dl,
                    imgui.ImVec2(pmin.x+2, pmin.y+3), imgui.ImVec2(pmax.x+2, pmax.y+3),
                    pcs_pack_color(0, 0, 0, 0.35*a), mcfg.corner_radius)

                local bg = mcfg.bg_color
                dl:AddRectFilled(pmin, pmax, pcs_pack_color(bg[1],bg[2],bg[3],bg[4]*a), mcfg.corner_radius)

                -- ФИКС (по просьбе "покрасивее"): тонкая цветная полоска-
                -- хайлайт по верхнему краю плашки (эффект лёгкого "глянца")
                pcs_safe_call(dl.AddRectFilledMultiColor, dl,
                    imgui.ImVec2(pmin.x + mcfg.corner_radius, pmin.y),
                    imgui.ImVec2(pmax.x - mcfg.corner_radius, pmin.y + 2),
                    pcs_pack_color(c[1], c[2], c[3], 0.55*a),
                    pcs_pack_color(c[1], c[2], c[3], 0.55*a),
                    pcs_pack_color(c[1], c[2], c[3], 0.0),
                    pcs_pack_color(c[1], c[2], c[3], 0.0))

                if cfg.rainbowBorder and (mcfg.border_size or 0) > 0 then
                    local hue = (os.clock() % 4.0) / 4.0
                    local hr, hg, hb = hsv2rgb(hue, 0.75, 1.0)
                    pcs_safe_call(dl.AddRect, dl, pmin, pmax,
                        pcs_pack_color(hr, hg, hb, a),
                        mcfg.corner_radius, 0, mcfg.border_size)
                end

                -- иконка-чип слева — теперь настоящий кружок (AddCircleFilled)
                -- вместо скруглённого квадрата, по просьбе "покрасивее"
                local chipSz = math.max(24, mcfg.padding_y*2 + 8)
                local chipMin = imgui.ImVec2(pmin.x+8, pmin.y+8)
                local chipMax = imgui.ImVec2(chipMin.x+chipSz, chipMin.y+chipSz)
                local chipCx, chipCy = chipMin.x + chipSz/2, chipMin.y + chipSz/2
                local chipR = chipSz/2
                pcs_safe_call(dl.AddCircleFilled, dl,
                    imgui.ImVec2(chipCx, chipCy), chipR,
                    pcs_pack_color(c[1],c[2],c[3],0.22*a), 24)
                pcs_safe_call(dl.AddCircle, dl,
                    imgui.ImVec2(chipCx, chipCy), chipR,
                    pcs_pack_color(c[1],c[2],c[3],0.85*a), 24, 1.4)
                local glyph = def.glyph or "i"
                local gsz = pcs_safe_call(imgui.CalcTextSize, glyph)
                local gw, gh = (gsz and gsz.x) or 6, (gsz and gsz.y) or 13
                dl:AddText(imgui.ImVec2(chipMin.x + (chipSz-gw)*0.5, chipMin.y + (chipSz-gh)*0.5),
                    pcs_pack_color(c[1],c[2],c[3],a), glyph)

                -- ФИКС "текст в уведомлениях слишком мелкий / слайдер
                -- масштаба ничего не меняет": этот путь отрисовки рисует
                -- прямо на GetForegroundDrawList(), который не привязан ни
                -- к какому окну — поэтому dl:AddText(pos, col, text) (без
                -- явного шрифта/размера) всегда брал БАЗОВЫЙ размер шрифта
                -- движка, а cfg.toastFontScale только влиял на перенос строк
                -- (см. "textMaxW / fscale" ниже), но не на реальный размер
                -- глифов. Теперь размер явно передаётся в AddText через
                -- перегрузку (font, font_size, pos, col, text), поэтому
                -- ползунок "Масштаб шрифта" в Настройках реально работает.
                local _toastFont = pcs_safe_call(imgui.GetFont)
                local _toastFontSize = (pcs_safe_call(imgui.GetFontSize) or 13) * fscale
                local function _toastAddText(pos, col, text)
                    if _toastFont then
                        local ok = pcall(dl.AddText, dl, _toastFont, _toastFontSize, pos, col, text)
                        if ok then return end
                    end
                    dl:AddText(pos, col, text) -- запасной вариант (без масштаба)
                end

                -- текст переносим вручную (imgui.TextWrapped недоступен
                -- без окна) — см. pcs_wrap_lines выше
                local textX    = pmin.x + 8 + chipSz + 10
                local textMaxW = mcfg.width - (8 + chipSz + 10) - mcfg.padding_x
                local lsz      = pcs_safe_call(imgui.CalcTextSize, "Ag")
                local lineHBase = (lsz and lsz.y) or 16
                local y = pmin.y + mcfg.padding_y

                for _, line in ipairs(pcs_wrap_lines(def.label, textMaxW / fscale)) do
                    _toastAddText(imgui.ImVec2(textX, y), pcs_pack_color(c[1],c[2],c[3],a), line)
                    y = y + lineHBase * fscale
                end
                y = y + 2 * fscale
                local tc = mcfg.text_color
                for _, line in ipairs(pcs_wrap_lines(n.text, textMaxW / fscale)) do
                    _toastAddText(imgui.ImVec2(textX, y), pcs_pack_color(tc[1],tc[2],tc[3],(tc[4] or 1)*a), line)
                    y = y + lineHBase * fscale
                end

                -- тонкая полоска-таймер снизу — сколько осталось до
                -- автозакрытия (по отдельной просьбе про "другой дизайн")
                if n.state == PCS_STATE.SHOWING and n.duration and n.duration > 0 then
                    local frac = 1 - pcs_clamp01(n.timer / n.duration)
                    if frac > 0.01 then
                        local by0 = pmax.y - 3
                        dl:AddRectFilled(imgui.ImVec2(pmin.x+6, by0), imgui.ImVec2(pmax.x-6, by0+2),
                            pcs_pack_color(1,1,1,0.10*a), 1)
                        dl:AddRectFilled(imgui.ImVec2(pmin.x+6, by0),
                            imgui.ImVec2(pmin.x+6 + (pmax.x-pmin.x-12)*frac, by0+2),
                            pcs_pack_color(c[1],c[2],c[3],0.85*a), 1)
                    end
                end
            end)
            return
        end

        -- ФИКС (по просьбе "уведомления совсем без мешка/окна-ловушки
        -- мыши"): раньше здесь был запасной вариант через imgui.Begin()/
        -- End() — обычное окно, а любое окно imgui физически перехватывает
        -- мышь в своей области (тот самый "мешок"), даже с флагами вроде
        -- NoInputs, если конкретная сборка mimgui их не поддерживает.
        -- Теперь никакого окна для тостов больше нет вообще — если ни
        -- один из способов получить draw list без окна (Foreground/
        -- Overlay/Background — см. попытки чуть выше) не сработал, тост
        -- этого кадра просто не рисуется (пропускаем кадр), но НИКОГДА не
        -- создаём кликабельное окно поверх игры.
    end

    function PcsNotifyManager:_render()
        if not self.enabled then return end
        pcall(function()
            -- ФИКС "нет тоста, пока меню скрипта закрыто": раньше здесь при
            -- закрытом St.winOpen вся очередь тостов принудительно стиралась
            -- каждый кадр — а именно вход в игру и обновление курса валют
            -- почти всегда происходят как раз при ЗАКРЫТОМ меню, поэтому эти
            -- тосты гарантированно не успевали отрисоваться ни разу. Тосты
            -- рисуются НЕ поверх окна меню, а отдельным слоем (см.
            -- imgui.OnFrame ниже — кадр активен только пока есть тосты, не
            -- завязан на winOpen), так что зависимости от открытого меню тут
            -- вообще не требуется — только сброс захвата мыши/клавиатуры
            -- после отрисовки, чтобы курсор игры не залипал.
            local dt = pcs_safe_call(function() return imgui.GetIO().DeltaTime end) or 0
            self:_update(dt)
            if #self.active > 0 then
                for _, n in ipairs(self.active) do self:_draw_toast(n) end
            end
            pcall(function()
                local io = imgui.GetIO()
                if io then
                    io.WantCaptureMouse = false
                    io.WantCaptureKeyboard = false
                end
            end)
        end)
    end

    function PcsNotifyManager._ensure_registered()
        if PcsNotifyManager._registered then return end
        PcsNotifyManager._registered = true
        -- ФИКС КУРСОРА: раньше условие было enabled=true почти всегда,
        -- и mimgui держал мышку ВКЛЮЧЁННОЙ даже при закрытом меню и без
        -- тостов. Кадр активен ТОЛЬКО пока на экране есть тосты.
        imgui.OnFrame(
            function()
                if not PcsNotifyManager.enabled then return false end
                local a = PcsNotifyManager.active
                local p = PcsNotifyManager.pending
                if a and #a > 0 then return true end
                if p and #p > 0 then return true end
                return false
            end,
            function()
                local ok, err = PCS_GUARD.call(function() PcsNotifyManager:_render() end)
                if not ok then pcall(function() PcsNotifyManager.clear() end) end
            end
        )
    end
    PcsNotifyManager._ensure_registered()

    -- применяет cfg.toast* к менеджеру (вызывается при старте и при
    -- любом изменении настроек во вкладке "Настройки")
    function pcs_apply_toast_settings()
        PcsNotifyManager.configure({
            width         = Sf(cfg.toastWidth or 320),
            padding_x     = Sf(cfg.toastPaddingX or 14),
            padding_y     = Sf(cfg.toastPaddingY or 10),
            accent_width  = Sf(cfg.toastAccentWidth or 4),
            corner_radius = Sf(cfg.toastCornerRadius or 8),
            spacing       = Sf(cfg.toastSpacing or 8),
            margin_x      = Sf(cfg.toastMarginX or 18),
            margin_y      = Sf(cfg.toastMarginY or 34),
            duration      = cfg.toastDuration or 6.0,
            anim_speed    = cfg.toastAnimSpeed or 10.0,
            max_visible   = cfg.toastMaxVisible or 5,
            position      = (cfg.toastPosV or "bottom").."_"..(cfg.toastPosH or "right"),
            bg_color      = {cfg.toastBgR or 0.08, cfg.toastBgG or 0.08, cfg.toastBgB or 0.10, cfg.toastBgA or 0.90},
            text_color    = {cfg.toastTextR or 0.94, cfg.toastTextG or 0.94, cfg.toastTextB or 0.96, 1.0},
            border_enabled= cfg.toastBorderEnabled == true,
            border_color  = {cfg.toastBorderR or 1.0, cfg.toastBorderG or 1.0, cfg.toastBorderB or 1.0, cfg.toastBorderA or 0.25},
            border_size   = cfg.toastBorderSize or 1.0,
            font_scale    = cfg.toastFontScale or 1.0,
        })
        PcsNotifyManager.set_enabled(cfg.toastEnabled ~= false)
    end
    pcs_apply_toast_settings()

    -- Публичная точка входа для всего остального скрипта:
    -- pcs_notify("текст в UTF-8", "info"/"success"/"warning"/"error"/"payday", длительность_сек)
    function pcs_notify(text, ntype, duration)
        if cfg.toastEnabled == false then return end
        -- пока меню ни разу не открывали в сессии — тосты скрыты
        if not St._toastSessionActive then return end
        -- ФИКС "нет тоста, пока меню закрыто": раньше тут ещё была проверка
        -- St.winOpen, которая обнуляла ЛЮБОЙ тост, показанный при закрытом
        -- меню (вход в игру, курс валют) — тосты рисуются отдельным слоем
        -- (см. PcsNotifyManager:_render), поэтому меню для их показа
        -- открывать не нужно, проверка была лишней.
        return PcsNotifyManager.add(text, ntype, duration)
    end

    -- Публичная точка входа: мгновенно убрать с экрана ВСЕ текущие
    -- уведомления (используется при закрытии главного меню, см.
    -- forceCloseMenuNow ниже по файлу) — глобальная функция (без local),
    -- т.к. PcsNotifyManager недоступен за пределами этого do..end блока
    function pcs_notify_clear()
        PcsNotifyManager.clear()
    end

    -- тестовая функция для кнопок "Тест" в настройках
    function pcs_toast_test(kind)
        local samples = {
            info    = u8"\xcf\xf0\xe8\xec\xe5\xf0\x20\xe8\xed\xf4\xee\xf0\xec\xe0\xf6\xe8\xee\xed\xed\xee\xe3\xee\x20\xf3\xe2\xe5\xe4\xee\xec\xeb\xe5\xed\xe8\xff\x2e",
            success = u8"\xce\xef\xe5\xf0\xe0\xf6\xe8\xff\x20\xef\xf0\xee\xf8\xeb\xe0\x20\xf3\xf1\xef\xe5\xf8\xed\xee\x2e",
            warning = u8"\xc2\xed\xe8\xec\xe0\xed\xe8\xe5\x3a\x20\xef\xf0\xee\xe2\xe5\xf0\xfc\xf2\xe5\x20\xed\xe0\xf1\xf2\xf0\xee\xe9\xea\xe8\x2e",
            error   = u8"\xcf\xf0\xe8\xec\xe5\xf0\x20\xee\xf8\xe8\xe1\xea\xe8\x20\x97\x20\xf7\xf2\xee\x2d\xf2\xee\x20\xef\xee\xf8\xeb\xee\x20\xed\xe5\x20\xf2\xe0\xea\x2e",
            payday  = "PayDay: +100 000",
        }
        if not samples[kind] then kind = "info" end
        pcs_notify(samples[kind], kind, cfg.toastDuration)
    end

    PCS_Notify = PcsNotifyManager
end

-- ============================================================
--  ФИКС (по просьбе): всплывающие уведомления ДЛЯ ВСЕГО ТЕКСТА,
--  который скрипт когда-либо пишет в чат
-- ============================================================
-- Вместо того, чтобы вручную добавлять pcs_notify(...) рядом с каждым из
-- десятков разбросанных по файлу вызовов sampAddChatMessage, оборачиваем
-- саму функцию ОДИН раз здесь: любой будущий и уже существующий вызов
-- sampAddChatMessage теперь автоматически дублируется тостом. Оригинал
-- всегда вызывается первым и в любом случае (даже если что-то в тосте
-- сломается) — это гарантирует, что обычный чат продолжает работать
-- как раньше, даже если появится ошибка в этой обёртке.
-- ФИКС (п.15): вторая обёртка sampAddChatMessage (тосты) объединена с
-- первой в начале файла — см. комментарий там. Здесь она больше не нужна.

-- ============================================================
--  Š�Š˛Š�Š¢Š˛ŠÆŠ¯Š�Š•
-- ============================================================
 St.winOpen        = false
 St.activeTab      = 1
 St.waitingStats   = false
local captureStarted = false
local TD_DELAY       = 0.8
local REQ_TIMEOUT    = 7.0
local lastReqTime    = 0.0
local lastTdTime     = 0.0
local tdCollector    = {}
local tdCollectorSize = 0
 St.statsData      = nil
 St.statusMsg      = ""
local lastAutoTime   = 0.0
local finalizing     = false
_sw_win_init         = nil
-- время (os.time()) момента, когда персонаж заспавнился в этой игровой
-- сессии — используется для таймера "В игре" на вкладке "Персонаж"
_sessionStartTime    = nil

-- форматирует секунды в "Чч Мм" / "Мм Сс" — для таймера сессии на вкладке
-- "Персонаж" (сколько времени персонаж в игре с момента спавна)
local function fmtSessionDuration(sec)
    sec = math.max(0, math.floor(tonumber(sec) or 0))
    local hh = math.floor(sec / 3600)
    local mm = math.floor((sec % 3600) / 60)
    local ss = sec % 60
    if hh > 0 then
        return string.format(u8"%d\xf7\x20%02d\xec", hh, mm)
    elseif mm > 0 then
        return string.format(u8"%d\xec\x20%02d\xf1", mm, ss)
    else
        return string.format(u8"%d\xf1", ss)
    end
end
 St.accPopupOpen   = false
 St._resetCharScroll = false
 St._resetSettScroll = false

-- Š±Ń�Ń„ŠµŃ€Ń‹ Š´Š»Ń¸ Ń€Ń�Ń‡Š½Š¾Š³Š¾ Š²Š²Š¾Š´Š° RGB Š² Š½Š°Ń�Ń‚Ń€Š¾Š¹ŠŗŠ°Ń…
 St.custRbuf = imgui.new.float(1.0)
 St.custGbuf = imgui.new.float(0.5)
 St.custBbuf = imgui.new.float(0.2)

-- Š±Ń�Ń„ŠµŃ€Ń‹ Ń†Š²ŠµŃ‚Š° Ń„Š¾Š½Š° Ń�Ń‚Ń€Š¾Šŗ (R,G,B)
 St.rowBgRbuf = imgui.new.float(0.43)
 St.rowBgGbuf = imgui.new.float(0.71)
 St.rowBgBbuf = imgui.new.float(1.0)

-- буферы цвета текста (imgui.Col.Text)
 St.textRbuf = imgui.new.float(1.0)
 St.textGbuf = imgui.new.float(1.0)
 St.textBbuf = imgui.new.float(1.0)

-- буферы фона окна скрипта (imgui.Col.WindowBg)
 St.winBgRbuf = imgui.new.float(0.0)
 St.winBgGbuf = imgui.new.float(0.0)
 St.winBgBbuf = imgui.new.float(0.0)

-- буферы цвета обводки (imgui.Col.Border)
 St.outlineRbuf = imgui.new.float(0.5)
 St.outlineGbuf = imgui.new.float(0.5)
 St.outlineBbuf = imgui.new.float(0.5)

-- цвет текста сообщений скрипта в чате (по умолчанию — стандартный
-- зелёный {00FF88}, т.е. (0, 1.0, 0.53))
 St.chatRbuf = imgui.new.float(0.0)
 St.chatGbuf = imgui.new.float(1.0)
 St.chatBbuf = imgui.new.float(0.53)

-- буфер для поля ввода команды открытия меню (вкладка "Настройки")
St.menuCmdBuf = imgui.new("char[16]", "sw")

-- ============================================================
--  Š£Š¢Š�Š›Š�Š¢Š«
-- ============================================================
-- Š�ŠµŃ�ŠøŃ€Ń�ŠµŠ¼ socket Š¾Š´ŠøŠ½ Ń€Š°Š· ŠæŃ€Šø Ń�Ń‚Š°Ń€Ń‚Šµ, Š½Šµ Š²Ń‹Š·Ń‹Š²Š°ŠµŠ¼ require ŠŗŠ°Š¶Š´Ń‹Š¹ Ń‚ŠøŠŗ
local _socket_gettime = nil
do
    local ok, sock = pcall(require, "socket")
    if ok and sock and sock.gettime then
        _socket_gettime = sock.gettime
    end
end
local function getTime()
    if _socket_gettime then return _socket_gettime() end
    return os.clock()
end
local function now() return getTime() end
local function trim(s) return (tostring(s or "")):match("^%s*(.-)%s*$") end

local function stripColor(s)
    if not s then return "" end
    s = tostring(s)
    s = s:gsub("{%x%x%x%x%x%x}", "")
    s = s:gsub("{%x%x%x%x%x%x%x%x}", "")
    s = s:gsub("{#[%x%d]+}", "")
    s = s:gsub("%[%x%x%x%x%x%x%]", "") -- цветовые коды в квадратных скобках (формат диалогов телефона)
    s = s:gsub("~[rgbypwsh]~", "")
    s = s:gsub("~n~", "\n")
    return s
end

local function stripBrackets(s)
    s = trim(s or "")
    if s:match("^%b[]$") then s=s:sub(2,-2) end
    return s
end

local function vOrDash(v)
    v = trim(stripBrackets(v or ""))
    return v ~= "" and v or "-"
end

local function hasVal(v)
    return trim(stripBrackets(v or "")) ~= ""
end

local function fmtDots(s)
    -- s Ń�Š¶Šµ Š´Š¾Š»Š¶Š½Š° Ń�Š¾Š´ŠµŃ€Š¶Š°Ń‚Ń� Ń‚Š¾Š»Ń�ŠŗŠ¾ Ń†ŠøŃ„Ń€Ń‹
    s = tostring(s or ""):gsub("%D","")
    if s=="" then return "0" end
    if #s<4 then return s end
    -- Š Š°Š·Š±ŠøŠ²Š°ŠµŠ¼ Ń�ŠæŃ€Š°Š²Š° Š³Ń€Ń�ŠæŠæŠ°Š¼Šø ŠæŠ¾ 3:
    -- reverse -> Š²Ń�Ń‚Š°Š²ŠøŃ‚Ń� Ń‚Š¾Ń‡ŠŗŃ� Š�Š˛Š�Š›Š• ŠŗŠ°Š¶Š´Ń‹Ń… 3 Ń†ŠøŃ„Ń€ -> reverse -> Ń�Š±Ń€Š°Ń‚Ń� Š½Š°Ń‡Š°Š»Ń�Š½Ń�Ńˇ Ń‚Š¾Ń‡ŠŗŃ� ŠµŃ�Š»Šø ŠµŃ�Ń‚Ń�
    local rev = s:reverse()
    local out = rev:gsub("(%d%d%d)", "%1.")
    -- Ń�Š±ŠøŃ€Š°ŠµŠ¼ Ń‚Š¾Ń‡ŠŗŃ� Š² ŠŗŠ¾Š½Ń†Šµ (Š¾Š½Š° Ń�Ń‚Š°Š»Š° Š±Ń‹ Š² Š½Š°Ń‡Š°Š»Šµ ŠæŠ¾Ń�Š»Šµ reverse)
    if out:sub(-1)=="." then out = out:sub(1,-2) end
    local result = out:reverse()
    -- Ń�Š±ŠøŃ€Š°ŠµŠ¼ Ń‚Š¾Ń‡ŠŗŃ� Š² Š½Š°Ń‡Š°Š»Šµ ŠµŃ�Š»Šø Š²Š´Ń€Ń�Š³ Š¾Ń�Ń‚Š°Š»Š°Ń�Ń�
    if result:sub(1,1)=="." then result = result:sub(2) end
    return result
end

local function fmtMoney(v)
    if v == nil then return "-" end
    local s = trim(stripBrackets(tostring(v)))
    if s=="" or s=="-" then return "-" end
    local neg = s:match("^%-")
    -- Š•Ń�Š»Šø Ń�Ń‚Ń€Š¾ŠŗŠ° Ń�Š¾Š´ŠµŃ€Š¶ŠøŃ‚ 'e' ŠøŠ»Šø 'E' ā€” Ń¨Ń‚Š¾ Š½Š°Ń�Ń‡Š½Š°Ń¸ Š½Š¾Ń‚Š°Ń†ŠøŃ¸, ŠŗŠ¾Š½Š²ŠµŃ€Ń‚ŠøŃ€Ń�ŠµŠ¼ Ń‡ŠµŃ€ŠµŠ· tonumber
    if s:find("[eE]") then
        local n = tonumber(s)
        if n then s = string.format("%.0f", math.abs(n))
        else s = "0" end
    else
        -- Š£Š±ŠøŃ€Š°ŠµŠ¼ Š²Ń�Ń‘ Š½ŠµŃ†ŠøŃ„Ń€Š¾Š²Š¾Šµ (Ń‚Š¾Ń‡ŠŗŠø, ŠæŃ€Š¾Š±ŠµŠ»Ń‹, Š·Š½Š°ŠŗŠø ā€” Ń€Š°Š·Š´ŠµŠ»ŠøŃ‚ŠµŠ»Šø Ń�Š¶Šµ Ń�Ń‚Š¾Ń¸Ń‚ ŠøŠ»Šø Š½ŠµŃ‚)
        s = s:gsub("%D","")
    end
    if s=="" or s=="0" then return "$0" end
    return (neg and "-$" or "$") .. fmtDots(s)
end

-- Vytaskivaet chislo (s drobnoy chastyu) iz stroki staty (dlya konvertacii valyut)
-- ponimaet sokrascheniya tipa "54kkk"/"54\xea\xea\xea"/"1.5m"/"2kk" (k/\xea=tys., kk/\xea\xea/m=mln, kkk/\xea\xea\xea/b=mlrd)
local function toNum(v)
    if v == nil then return 0 end
    local s = trim(stripBrackets(tostring(v)))
    if s == "" then return 0 end
    local neg = s:match("^%-") ~= nil
    s = s:gsub(",", ".")
    local numPart, suf = s:match("^([%d%.]+)%s*([%a\xe0-\xff]*)$")
    if numPart and suf and suf ~= "" then
        local lsuf = suf:lower()
        local mult = nil
        if lsuf:find("^kkk") or lsuf:find("^\xea\xea\xea") or lsuf == "b" then
            mult = 1e9
        elseif lsuf:find("^kk") or lsuf:find("^\xea\xea") or lsuf == "m" then
            mult = 1e6
        elseif lsuf:find("^k") or lsuf:find("^\xea") then
            mult = 1e3
        end
        if mult then
            local n2 = tonumber(numPart)
            if n2 then
                if neg then n2 = -n2 end
                return n2 * mult
            end
        end
    end
    s = s:gsub("[^%d%.]", "")
    -- ГЛАВНОЕ ИСПРАВЛЕНИЕ: раньше при нескольких точках последняя группа
    -- из 3 цифр ошибочно принималась за дробную часть и "съедалась" —
    -- из-за этого суммы вида 45.000.000.000 показывались как 45.000.000.
    -- Теперь: если последний сегмент после точки состоит РОВНО из 3 цифр
    -- (типичный признак разделителя тысяч) — все точки считаются
    -- разделителями тысяч. Иначе последняя точка — это десятичный разделитель
    -- (например "103.78" AZ или "572.53" VC$), а более ранние точки (если
    -- есть) — разделители тысяч.
    if s:find("%.") then
        local segs = {}
        for part in (s.."."):gmatch("([^%.]*)%.") do segs[#segs+1] = part end
        local lastSeg = segs[#segs]
        if lastSeg and #lastSeg == 3 and #segs >= 2 then
            s = table.concat(segs)
        else
            local intSegs = {}
            for i=1,#segs-1 do intSegs[#intSegs+1] = segs[i] end
            s = table.concat(intSegs) .. "." .. (lastSeg or "")
        end
    end
    local n = tonumber(s) or 0
    if neg then n = -n end
    return n
end

local function fmtInt(n)
    n = tonumber(n) or 0
    local neg = n < 0
    local s = fmtDots(string.format("%.0f", math.abs(n)))
    return (neg and "-" or "") .. s
end

-- Š¡Ń�Š¼Š¼Š° Š²Š°Š»Ń�Ń‚Ń‹: Ń†ŠµŠ»Š¾Šµ ŠµŃ�Š»Šø Š±ŠµŠ· Š´Ń€Š¾Š±Š½Š¾Š¹ Ń‡Š°Ń�Ń‚Šø, ŠøŠ½Š°Ń‡Šµ 2 Š·Š½Š°ŠŗŠ° ŠæŠ¾Ń�Š»Šµ Š·Š°ŠæŃ¸Ń‚Š¾Š¹
local function fmtAmt(n)
    n = tonumber(n) or 0
    if math.abs(n - math.floor(n+0.5)) < 0.001 then
        return fmtInt(math.floor(n+0.5))
    else
        return string.format("%.2f", n)
    end
end

local function looksTexture(t)
    if t == nil then return true end
    local s = tostring(t)
    return s == "" or s == " " or s == "null"
        or s:find("LD_", 1, true) or s:find("ld_", 1, true)
        or s:find(".txd", 1, true) or s:find(".saa", 1, true)
        or s:find("preview", 1, true)
end

local function isStatsPiece(t)
    local s = stripColor(t or "")
    return s:find("\xce\xf1\xed\xee\xe2\xed\xe0\xff \xf1\xf2\xe0\xf2\xe8\xf1\xf2\xe8\xea\xe0",1,true)
        or s:find("\xcd\xee\xec\xe5\xf0 \xe0\xea\xea\xe0\xf3\xed\xf2\xe0",1,true)
        or s:find("\xc8\xec\xff:",1,true)
        or s:find("\xcf\xee\xeb:",1,true)
        or s:find("\xc7\xe4\xee\xf0\xee\xe2\xfc\xe5:",1,true)
        or s:find("\xd3\xf0\xee\xe2\xe5\xed\xfc:",1,true)
        or s:find("\xd0\xe0\xe1\xee\xf2\xe0:",1,true)
        or s:find("AZ%-Coins",1,true)
        or s:find("\xc7\xe0\xf9\xe8\xf2\xe0:",1,true)
        or s:find("\xd3\xe4\xe0\xf7\xe0:",1,true)
end

-- ============================================================
--  Š�Š�Š Š�Š•Š 
-- ============================================================
local function parseStats(raw)
    local p = {
        accountNumber="",authDate="",accountState="",
        x3Payday="",x4Payday="",
        name="",gender="",health="",level="",respect="",
        cashSas="",cashVcs="",euro="",btc="",azCoins="",
        phone="",bank="",moneyDay="",bankCard="",
        acc={},
        job="",org="",position="",status="",citizenship="",family="",
        wanted="",lawfulness="",warnings="",addiction="",
        protection="",regen="",damage="",luck="",
        maxHp="",maxArmor="",stunChance="",bleedChance="",
        dodgeChance="",reflectDamage="",blockDamage="",
        fireRate="",recoil="",fruitStun="",
        hotel="",hotelRoom="",trailer="",
        firstLine="",
        extra={}
    }
    -- -- "status na servere" (popap na vkladke Finansy) -- eto NE nazvanie
    -- servera, a bukvalno pervaya nepustaya stroka, kotoruyu prislal /stats
    -- (na bolshinstve serverov Arizona RP eto stroka vida "dd.mm.gggg chch:mm" --
    -- vremya poslednego zahoda)
    do
        local firstCl = ""
        for line in (raw.."\n"):gmatch("([^\n]*)\n") do
            local cl0 = trim(stripColor(line))
            if cl0 ~= "" and cl0 ~= u8"\xce\xf1\xed\xee\xe2\xed\xe0\xff \xf1\xf2\xe0\xf2\xe8\xf1\xf2\xe8\xea\xe0" then
                firstCl = cl0
                break
            end
        end
        p.firstLine = firstCl
    end
    for line in (raw.."\n"):gmatch("([^\n]*)\n") do
        local cl = trim(stripColor(line))
        if cl and cl ~= "" then
            local k,v = cl:match("^(.-):%s*(.+)$")
            if k and v then
                k=trim(k); v=trim(v)
                local ai = k:match("^\xd1\xee\xf1\xf2\xee\xff\xed\xe8\xe5 \xeb\xe8\xf7\xed\xee\xe3\xee \xf1\xf7\xe5\xf2[\xe0\xb8]%s*\xb9%s*(%d+)$")
                if ai then p.acc[tonumber(ai)] = v
                elseif cl:find("PayDay",1,true) or cl:find("PAYDAY",1,true) then
                    local s2 = cl:lower():gsub("[\xd7\xd5\xf5]","x"):gsub("%s","")
                    if s2:find("x4") or s2:find("4x") then p.x4Payday=v
                    elseif s2:find("x3") or s2:find("3x") then p.x3Payday=v end
                elseif k:find("\xcd\xee\xec\xe5\xf0 \xe0\xea\xea\xe0\xf3\xed\xf2\xe0",1,true) then p.accountNumber=v
                elseif k:find("\xc0\xe2\xf2\xee\xf0\xe8\xe7\xe0\xf6\xe8\xff",1,true) then p.authDate=v
                elseif k:find("\xd2\xe5\xea\xf3\xf9\xe5\xe5 \xf1\xee\xf1\xf2\xee\xff\xed\xe8\xe5",1,true) then p.accountState=v
                elseif k=="\xc8\xec\xff" then p.name=v
                elseif k=="\xcf\xee\xeb" then p.gender=v
                elseif k=="\xc7\xe4\xee\xf0\xee\xe2\xfc\xe5" then p.health=v
                elseif k=="\xd3\xf0\xee\xe2\xe5\xed\xfc" then p.level=v
                elseif k=="\xd3\xe2\xe0\xe6\xe5\xed\xe8\xe5" then p.respect=v
                elseif k:find("\xcd\xe0\xeb\xe8\xf7\xed\xfb\xe5 \xe4\xe5\xed\xfc\xe3\xe8 %(SA%$%)") then p.cashSas=v
                elseif k:find("\xcd\xe0\xeb\xe8\xf7\xed\xfb\xe5 \xe4\xe5\xed\xfc\xe3\xe8 %(VC%$%)") then p.cashVcs=v
                -- Акции Arizona (AARP) — валюта, которая раньше называлась
                -- "Евро"; проверяем и старое, и новое написание, а также
                -- "AARP"/"Arizona" отдельно на случай, если сервер присылает
                -- урезанную подпись без слова "Акции" (раньше матчилось
                -- только "Акции", из-за чего при другой формулировке строка
                -- целиком пролетала мимо и валюта не показывалась)
                elseif k=="\xc5\xe2\xf0\xee"
                    or k:find("\xc0\xea\xf6\xe8\xe8",1,true)
                    or k:find("AAR+P")
                    or k:lower():find("aar+p")
                    or (k:find("Arizona",1,true) and not k:find("Coin",1,true))
                    or (k:lower():find("arizona",1,true) and not k:lower():find("coin",1,true)) then p.euro=v
                elseif k=="BTC" then p.btc=v
                elseif k:find("AZ",1,true) and k:find("oin",1,true) then p.azCoins=v
                elseif k=="\xcd\xee\xec\xe5\xf0 \xf2\xe5\xeb\xe5\xf4\xee\xed\xe0" then p.phone=v
                elseif k=="\xc4\xe5\xed\xfc\xe3\xe8 \xe2 \xe1\xe0\xed\xea\xe5" then p.bank=v
                elseif k:find("\xc4\xe5\xed\xfc\xe3\xe8 \xed\xe0 \xe4\xe5\xef\xee\xe7\xe8\xf2",1,true) then p.moneyDay=v
                elseif k=="\xc1\xe0\xed\xea\xee\xe2\xf1\xea\xe0\xff \xea\xe0\xf0\xf2\xe0" then p.bankCard=v
                elseif k=="\xd0\xe0\xe1\xee\xf2\xe0" then p.job=v
                elseif k=="\xce\xf0\xe3\xe0\xed\xe8\xe7\xe0\xf6\xe8\xff" then p.org=v
                elseif k=="\xc4\xee\xeb\xe6\xed\xee\xf1\xf2\xfc" then p.position=v
                elseif k=="\xd1\xf2\xe0\xf2\xf3\xf1" then p.status=v
                elseif k=="\xc3\xf0\xe0\xe6\xe4\xe0\xed\xf1\xf2\xe2\xee" then p.citizenship=v
                elseif k=="\xd1\xe5\xec\xfc\xff" then p.family=v
                elseif k=="\xd3\xf0\xee\xe2\xe5\xed\xfc \xf0\xee\xe7\xfb\xf1\xea\xe0" then p.wanted=v
                elseif k=="\xc7\xe0\xea\xee\xed\xee\xef\xee\xf1\xeb\xf3\xf8\xed\xee\xf1\xf2\xfc" then p.lawfulness=v
                elseif k=="\xcf\xf0\xe5\xe4\xf3\xef\xf0\xe5\xe6\xe4\xe5\xed\xe8\xff" then p.warnings=v
                elseif k:find("\xc7\xe0\xe2\xe8\xf1\xe8\xec\xee\xf1\xf2\xfc",1,true) then p.addiction=v
                elseif k=="\xc7\xe0\xf9\xe8\xf2\xe0" then p.protection=v
                elseif k=="\xd0\xe5\xe3\xe5\xed\xe5\xf0\xe0\xf6\xe8\xff" then p.regen=v
                elseif k=="\xd3\xf0\xee\xed" then p.damage=v
                elseif k=="\xd3\xe4\xe0\xf7\xe0" then p.luck=v
                elseif k=="\xcc\xe0\xea\xf1. HP" then p.maxHp=v
                elseif k:find("\xcc\xe0\xea\xf1.",1,true) and k:find("\xf0\xee\xed",1,true) then p.maxArmor=v
                elseif k=="\xd8\xe0\xed\xf1 \xee\xe3\xeb\xf3\xf8\xe5\xed\xe8\xff" then p.stunChance=v
                elseif k:find("\xd8\xe0\xed\xf1 \xee\xef",1,true) then p.bleedChance=v
                elseif k:find("\xd8\xe0\xed\xf1 \xe8\xe7\xe1\xe5\xe6",1,true) then p.dodgeChance=v
                elseif k=="\xce\xf2\xf0\xe0\xe6\xe5\xed\xe8\xe5 \xf3\xf0\xee\xed\xe0" then p.reflectDamage=v
                elseif k=="\xc1\xeb\xee\xea\xe8\xf0\xee\xe2\xea\xe0 \xf3\xf0\xee\xed\xe0" then p.blockDamage=v
                elseif k=="\xd1\xea\xee\xf0\xee\xf1\xf2\xf0\xe5\xeb\xfc\xed\xee\xf1\xf2\xfc" then p.fireRate=v
                elseif k=="\xce\xf2\xea\xe0\xf2" then p.recoil=v
                elseif k:find("\xcf\xeb\xee\xe4",1,true) then p.fruitStun=v
                elseif k=="\xce\xf2\xe5\xeb\xfc" then p.hotel=v
                elseif k:find("\xca\xee\xec\xed\xe0\xf2\xe0",1,true) then p.hotelRoom=v
                elseif k=="\xd2\xf0\xe5\xe9\xeb\xe5\xf0" then p.trailer=v
                else table.insert(p.extra,{k,v}) end
            end
        end
    end
    local total=0; local found=false
    for i=1,6 do
        local v=p.acc[i]
        if v and trim(v)~="" then
            local n=tonumber((v:gsub("%D","")))
            if n then total=total+n; found=true end
        end
    end
    p.totalAcc = found and fmtMoney(string.format("%.0f", total)) or ""

    -- ── страховочный запасной поиск AARP: если строка почему-то не
    -- разбилась по "ключ: значение" в цикле выше (другой разделитель,
    -- двойное двоеточие и т.п.), ищем "AARP" прямо по сырому тексту,
    -- без привязки к формату "ключ:значение" ──
    if p.euro=="" then
        for line in (raw.."\n"):gmatch("([^\n]*)\n") do
            local cl = trim(stripColor(line))
            if cl ~= "" and cl:lower():find("aar+p") then
                local num = cl:match("([%d][%d%s.,]*)%s*$") or cl:match("([%d][%d%s.,]*)")
                if num then p.euro = trim(num) end
                break
            end
        end
    end
    return p
end

-- ============================================================
--  Š�Š¢Š�Š›Š¬
-- ============================================================
-- Š�Ń€ŠøŠ¼ŠµŠ½Ń¸ŠµŠ¼ Ń�Ń‚ŠøŠ»Ń� Š³Š»Š¾Š±Š°Š»Ń�Š½Š¾ Ń‡ŠµŃ€ŠµŠ· GetStyle() ā€” ŠŗŠ°Šŗ MarketHelper, Š±ŠµŠ· Push/Pop Ń�Š¾Š²Ń�ŠµŠ¼
local function applyStyle()
    local s   = imgui.GetStyle()
    local r,g,b = getAcc()
    local t   = getTheme()
    local C   = s.Colors
    -- ── фон окна меню: по просьбе подключён простой пикер "Фон меню"
    -- (см. вкладку "Настройки" → "Оформление меню"), тот же принцип,
    -- что и у пикеров цвета всплывающих уведомлений — cfg.winBgR/G/B
    -- >= 0 задаёт свой цвет, -1 = стандартный чёрный/светлый по теме ──
    if cfg.winBgR and cfg.winBgR >= 0 then
        C[imgui.Col.WindowBg] = iv4(cfg.winBgR, cfg.winBgG, cfg.winBgB, 1.0)
        C[imgui.Col.ChildBg]  = iv4(cfg.winBgR, cfg.winBgG, cfg.winBgB, 0.55)
    elseif cfg.uiLightMode then
        C[imgui.Col.WindowBg] = iv4(0.95, 0.95, 0.97, 1.0)
        C[imgui.Col.ChildBg]  = iv4(1.00, 1.00, 1.00, 0.55)
    else
        C[imgui.Col.WindowBg] = iv4(0.00, 0.00, 0.00, 1.0)
        C[imgui.Col.ChildBg]  = iv4(0.00, 0.00, 0.00, 0.55)
    end
    C[imgui.Col.TitleBg]              = iv4(r*0.08, g*0.08, b*0.08, 1.0)
    C[imgui.Col.TitleBgActive]        = iv4(r*0.14, g*0.14, b*0.14, 1.0)
    if cfg.uiLightMode then
        C[imgui.Col.Button]        = iv4(math.min(1,r*0.35+0.55), math.min(1,g*0.35+0.55), math.min(1,b*0.35+0.55), 1.0)
        C[imgui.Col.ButtonHovered] = iv4(math.min(1,r*0.55+0.40), math.min(1,g*0.55+0.40), math.min(1,b*0.55+0.40), 1.0)
        C[imgui.Col.ButtonActive]  = iv4(r, g, b, 1.0)
    else
        C[imgui.Col.Button]               = iv4(r*0.10, g*0.10, b*0.10, 1.0)
        C[imgui.Col.ButtonHovered]        = iv4(r*0.45, g*0.45, b*0.45, 1.0)
        C[imgui.Col.ButtonActive]         = iv4(r*0.70, g*0.70, b*0.70, 1.0)
    end
    C[imgui.Col.ScrollbarBg]          = iv4(0, 0, 0, 0.15)
    C[imgui.Col.ScrollbarGrab]        = iv4(r*0.45, g*0.45, b*0.45, 0.70)
    C[imgui.Col.ScrollbarGrabHovered] = iv4(r*0.65, g*0.65, b*0.65, 0.85)
    C[imgui.Col.ScrollbarGrabActive]  = iv4(r,      g,      b,      1.0)
    C[imgui.Col.Separator]            = thSep()
    C[imgui.Col.Header]               = iv4(r*0.15, g*0.15, b*0.15, 1.0)
    C[imgui.Col.HeaderHovered]        = iv4(r*0.28, g*0.28, b*0.28, 1.0)
    -- обводка окна/карточек — либо от акцента (по умолчанию), либо
    -- кастомный цвет игрока (cfg.outlineR/G/B), выбранный в Настройках,
    -- либо "переливающийся" (радужный, анимированный по кругу HSV) —
    -- если включён cfg.rainbowBorder, он перекрывает обычный цвет
    if cfg.rainbowBorder then
        local hue = (os.clock() % 4.0) / 4.0
        local hr, hg, hb = hsv2rgb(hue, 0.75, 1.0)
        C[imgui.Col.Border] = iv4(hr, hg, hb, 0.95)
    elseif cfg.outlineR >= 0 then
        C[imgui.Col.Border] = iv4(cfg.outlineR, cfg.outlineG, cfg.outlineB, 0.90)
    elseif cfg.uiLightMode then
        -- ФИКС (по просьбе): в светлом режиме обводка по умолчанию
        -- серо-чёрная, а не акцентная — на белом фоне так лучше видно
        C[imgui.Col.Border] = iv4(0.30, 0.32, 0.38, 0.95)
    else
        C[imgui.Col.Border] = iv4(r*0.45, g*0.45, b*0.45, 0.90)
    end
    -- цвет текста — либо белый из темы (по умолчанию), либо кастомный
    -- цвет игрока (cfg.textR/G/B), выбранный в Настройках
    if cfg.textR >= 0 then
        C[imgui.Col.Text] = iv4(cfg.textR, cfg.textG, cfg.textB, 1.0)
    elseif cfg.uiLightMode then
        C[imgui.Col.Text] = iv4(0.07, 0.07, 0.10, 1.0)
    else
        C[imgui.Col.Text] = iv4(t.txt[1], t.txt[2], t.txt[3], 1.0)
    end
    s.WindowRounding   = Sf(16.0)
    s.ChildRounding    = Sf(10.0)
    s.FrameRounding    = Sf(12.0)
    s.GrabRounding     = Sf(12.0)
    s.GrabMinSize      = Sf(14.0)
    s.ScrollbarSize    = Sf(10.0)
    s.ItemSpacing      = imgui.ImVec2(S(6), S(5))
    s.WindowPadding    = imgui.ImVec2(S(12), S(10))
    s.FramePadding     = imgui.ImVec2(S(8), S(6))
    -- толщина рамки окна (не масштабируем ниже 1px, иначе пропадает);
    -- базовое значение теперь настраивается (cfg.borderThickness, 0.5..6)
    s.WindowBorderSize = math.max(1.0, Sf(cfg.borderThickness or 1.2))
    s.ChildBorderSize  = 0.0
end

-- ============================================================
--  UI Š�Š˛Š�Š�Š˛Š¯Š•Š¯Š¢Š«
-- ============================================================

-- Š—Š°Š³Š¾Š»Š¾Š²Š¾Šŗ Ń�ŠµŠŗŃ†ŠøŠø Ń� Š»ŠµŠ²Š¾Š¹ ŠæŠ¾Š»Š¾Ń�Š¾Š¹
local function secTitle(title)
    imgui.Spacing()
    local r,g,b = getAcc()
    local dl    = imgui.GetWindowDrawList()
    local p     = imgui.GetCursorScreenPos()
    local avail = imgui.GetContentRegionAvail().x
    local h     = S(30)
    -- Ń„Š¾Š½: Š¼ŠøŠ½ŠøŠ¼Ń�Š¼ 0.10 Ń¸Ń€ŠŗŠ¾Ń�Ń‚Šø Ń‡Ń‚Š¾Š±Ń‹ Š±Ń‹Š» Š²ŠøŠ´ŠµŠ½ Š½Š° Ń‡Ń‘Ń€Š½Š¾Š¼
    local br = math.max(r*0.22, 0.10)
    local bg2 = math.max(g*0.22, 0.10)
    local bb  = math.max(b*0.22, 0.10)
    dl:AddRectFilled(
        imgui.ImVec2(p.x,       p.y),
        imgui.ImVec2(p.x+avail, p.y+h),
        imgui.ColorConvertFloat4ToU32(iv4(br,bg2,bb,0.97)), 5)
    -- Ń€Š°Š¼ŠŗŠ° Ń�ŠµŠŗŃ†ŠøŠø
    dl:AddRect(
        imgui.ImVec2(p.x,       p.y),
        imgui.ImVec2(p.x+avail, p.y+h),
        imgui.ColorConvertFloat4ToU32(iv4(r*0.60,g*0.60,b*0.60,0.55)), 5, 0, 0.8)
    dl:AddRectFilled(
        imgui.ImVec2(p.x,   p.y+2),
        imgui.ImVec2(p.x+S(3), p.y+h-2),
        imgui.ColorConvertFloat4ToU32(iv4(r,g,b,1.0)), 2)
    dl:AddRectFilled(
        imgui.ImVec2(p.x+S(3),  p.y+2),
        imgui.ImVec2(p.x+S(18), p.y+h-2),
        imgui.ColorConvertFloat4ToU32(iv4(r*0.55,g*0.55,b*0.55,0.45)), 0)
    imgui.SetCursorPosY(imgui.GetCursorPosY()+4)
    imgui.SetCursorPosX(imgui.GetCursorPosX()+S(10))
    imgui.TextColored(thAccBright(), title)
    imgui.SetCursorPosY(imgui.GetCursorPosY()+2)
end

-- ā–ŗ Š�Ń€Š°Ń�ŠøŠ²Š°Ń¸ ŠŗŠ°Ń€Ń‚Š¾Ń‡ŠŗŠ°-Š¾Š±Ń‘Ń€Ń‚ŠŗŠ° (Ń�ŠŗŃ€ŠøŠ½Ń�Š¾Ń‚ 3 ā€” Š²Ń�Šµ Š±Š»Š¾ŠŗŠø Ń� Ń€Š°Š¼ŠŗŠ¾Š¹)
local function infoCard(id, cardH, drawFn)
    cardH = SFtext(cardH)
    local r,g,b = getAcc()
    local rr,rg,rb = getRowBgColor()
    local dl = imgui.GetWindowDrawList()
    local p  = imgui.GetCursorScreenPos()
    local aw = imgui.GetContentRegionAvail().x
    -- Ń„Š¾Š½ ŠŗŠ°Ń€Ń‚Š¾Ń‡ŠŗŠø: ŠŗŠ°Ń�Ń‚Š¾Š¼Š½Ń‹Š¹ Ń†Š²ŠµŃ‚ Ń„Š¾Š½Š° Ń�Ń‚Ń€Š¾Šŗ
    local bgR = math.max(rr*0.15, 0.08)
    local bgG = math.max(rg*0.15, 0.08)
    local bgB = math.max(rb*0.15, 0.08)
    dl:AddRectFilled(
        imgui.ImVec2(p.x,    p.y),
        imgui.ImVec2(p.x+aw, p.y+cardH),
        imgui.ColorConvertFloat4ToU32(iv4(bgR,bgG,bgB,0.97)), 10)
    -- Ń€Š°Š¼ŠŗŠ° Ń� Š°ŠŗŃ†ŠµŠ½Ń‚Š½Ń‹Š¼ Ń†Š²ŠµŃ‚Š¾Š¼
    dl:AddRect(
        imgui.ImVec2(p.x,    p.y),
        imgui.ImVec2(p.x+aw, p.y+cardH),
        imgui.ColorConvertFloat4ToU32(iv4(r*0.60,g*0.60,b*0.60,0.90)), 10, 0, 1.5)
    -- Š²ŠµŃ€Ń…Š½Ń¸Ń¸ Š°ŠŗŃ†ŠµŠ½Ń‚Š½Š°Ń¸ ŠæŠ¾Š»Š¾Ń�ŠŗŠ°
    dl:AddRectFilled(
        imgui.ImVec2(p.x+12,    p.y),
        imgui.ImVec2(p.x+aw-12, p.y+2),
        imgui.ColorConvertFloat4ToU32(iv4(r,g,b,0.95)), 2)
    imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
    imgui.BeginChild(id, imgui.ImVec2(aw - 2, cardH), false,
        imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
        -- ФИКС (п.12): drawFn — колбэк, переданный извне, может упасть;
        -- оборачиваем ТОЛЬКО его, а не весь BeginChild/EndChild
        local okFn, errFn = PCS_GUARD.call(drawFn, aw, cardH)
    imgui.EndChild()
    imgui.PopStyleColor()
    imgui.Spacing()
    if not okFn then
        pcall(sampAddChatMessage, "{FF6666}[PC Stats] " ..
            "\xee\xf8\xe8\xe1\xea\xe0\x20\xea\xe0\xf0\xf2\xee\xf7\xea\xe8: " .. tostring(errFn), -1)
    end
end

local _rowIndex = 0

-- ============================================================
--  Š�Š›Š�Š� ŠŸŠž ŠŸŠ ŠžŠ˜Š—Š’ŠžŠ›Š¬ŠĄŠ˜ (klik po tekstu/cifram -> smena cveta)
-- ============================================================
local _colorPopupBufs = {}

-- vozvraschaet kastomnyy cvet elementa (esli zadan) libo peredannyy po umolchaniyu
local function getElemColor(id, colorDefault)
    local c = customColors[id]
    if c then
        local a = (colorDefault and colorDefault.w) or 1.0
        return iv4(c[1], c[2], c[3], a)
    end
    return colorDefault
end

-- delaet posledniy narisovannyy Text/TextColored "klikabelnym": klik levoy knopkoy
-- otkryvaet vseplyvayuschee menu s polzunkami R/G/B dlya smeny cveta imenno etogo
-- teksta ili cifr. cveta sohranyayutsya v cfg i primenyayutsya pri sleduyushchih zapuskah.
local _colorPickerVec = {}

local function recolorOnClick(id)
    if imgui.IsItemClicked and imgui.IsItemClicked() then
        imgui.OpenPopup(id)
    end
    if imgui.IsItemHovered and imgui.IsItemHovered() then
        pcall(function()
            imgui.BeginTooltip()
            imgui.TextColored(iv4(0.75,0.80,0.90,1.0),
                u8"\xed\xe0\xe6\xec\xe8\xf2\xe5, \xf7\xf2\xee\xe1\xfb \xf1\xec\xe5\xed\xe8\xf2\xfc \xf6\xe2\xe5\xf2")
            imgui.EndTooltip()
        end)
    end
    pcall(imgui.SetNextWindowSize, imgui.ImVec2(S(300), 0), imgui.Cond and imgui.Cond.Appearing or 0)

    -- ФИКС (п.10): BeginPopup/содержимое/EndPopup под pcall (внутри —
    -- color picker, может упасть в некоторых сборках mimgui), EndPopup
    -- гарантирован через beganPopup
    local beganPopup = false
    local ok, err = pcall(function()
    if imgui.BeginPopup(id) then
        beganPopup = true
        local buf = _colorPopupBufs[id]
        if not buf then
            local c = customColors[id]
            buf = { imgui.new.float(c and c[1] or 1.0),
                    imgui.new.float(c and c[2] or 1.0),
                    imgui.new.float(c and c[3] or 1.0) }
            _colorPopupBufs[id] = buf
        end
        imgui.TextColored(thDim(), u8"\xd6\xe2\xe5\xf2 \xfd\xf2\xee\xe3\xee \xf2\xe5\xea\xf1\xf2\xe0/\xf6\xe8\xf4\xf0\xfb:")
        imgui.Spacing()

        local changed = false

        -- пробуем полноценный визуальный пикер (квадрат насыщенности + вертикальная
        -- полоса тона + hex-поле), как в стандартном ImGui color picker
        local okPicker = pcall(function()
            local vec = _colorPickerVec[id]
            if not vec then
                vec = imgui.new("float[3]", {buf[1][0], buf[2][0], buf[3][0]})
                _colorPickerVec[id] = vec
            end
            imgui.PushItemWidth(S(220))
            local flags = 0
            pcall(function() flags = imgui.ColorEditFlags.PickerHueBar + imgui.ColorEditFlags.DisplayHex end)
            if imgui.ColorPicker3("##cp"..id, vec, flags) then
                buf[1][0], buf[2][0], buf[3][0] = vec[0], vec[1], vec[2]
                changed = true
            end
            imgui.PopItemWidth()
        end)

        if not okPicker then
            -- запасной вариант (обычные ползунки), если ColorPicker3 недоступен в этой сборке mimgui
            imgui.PushItemWidth(150)
            if imgui.SliderFloat("R##rc"..id, buf[1], 0.0, 1.0) then changed = true end
            if imgui.SliderFloat("G##rc"..id, buf[2], 0.0, 1.0) then changed = true end
            if imgui.SliderFloat("B##rc"..id, buf[3], 0.0, 1.0) then changed = true end
            imgui.PopItemWidth()
        end

        if changed then
            customColors[id] = {buf[1][0], buf[2][0], buf[3][0]}
            saveCfg()
        end

        imgui.Spacing()
        local awPop  = imgui.GetContentRegionAvail().x
        local halfWP = (awPop - 8) * 0.5
        imgui.PushStyleColor(imgui.Col.Button,        iv4(0.35,0.06,0.06,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(0.55,0.10,0.10,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(0.75,0.16,0.16,1.0))
        if imgui.Button(u8"\xd1\xe1\xf0\xee\xf1 \xf6\xe2\xe5\xf2\xe0##rcreset", imgui.ImVec2(halfWP, S(28))) then
            customColors[id] = nil
            _colorPopupBufs[id] = nil
            _colorPickerVec[id] = nil
            saveCfg()
            imgui.CloseCurrentPopup()
        end
        imgui.PopStyleColor(3)
        imgui.SameLine(0, 8)
        do
            local pr,pg,pb = getAcc()
            imgui.PushStyleColor(imgui.Col.Button,        iv4(pr*0.22,pg*0.22,pb*0.22,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(pr*0.40,pg*0.40,pb*0.40,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(pr*0.58,pg*0.58,pb*0.58,1.0))
            if imgui.Button(u8"\xc7\xe0\xea\xf0\xfb\xf2\xfc##rcclose", imgui.ImVec2(halfWP, S(28))) then
                imgui.CloseCurrentPopup()
            end
            imgui.PopStyleColor(3)
        end
    end
    end) -- конец pcall

    if beganPopup then pcall(imgui.EndPopup) end
    if not ok then
        pcall(imgui.CloseCurrentPopup)
        pcall(sampAddChatMessage, "{FF6666}[PC Stats] " ..
            "\xee\xf8\xe8\xe1\xea\xe0\x20\xef\xee\xef\xe0\xef\xe0\x20\xe2\xfb\xe1\xee\xf0\xe0\x20\xf6\xe2\xe5\xf2\xe0: " .. tostring(err), -1)
    end
end

-- Edinaya risovka kнopok-obraztsov stilya (aktsent sverhu / fon strok snizu),
-- ispolzuetsya i dlya "gotovyh tem", i dlya "kombo-presetov" v odnom popupe,
-- chtoby vse presety vyglyadeli odinakovo.
local function drawStyleSwatchButton(uid, label, aR,aG,aB, bR,bG,bB, btnW, bH_c, isAct, tooltipText)
    local dl_cb = imgui.GetWindowDrawList()
    local p_cb  = imgui.GetCursorScreenPos()
    local halfH = bH_c * 0.5
    local bgAlpha = isAct and 0.85 or 0.45
    local rnd = 10
    -- FIX: раньше заливка была с острыми углами (0), а рамка поверх — со
    -- скруглёнными (8) => углы "рвались". Теперь заливка тоже скруглена
    -- с нужной стороны (верх/низ), флаги — через pcall на случай, если
    -- в этой сборке mimgui нет ImDrawFlags (тогда просто без углового флага)
    local flagsTop, flagsBot
    pcall(function() flagsTop = imgui.ImDrawFlags.RoundCornersTop end)
    pcall(function() flagsBot = imgui.ImDrawFlags.RoundCornersBottom end)
    if flagsTop then
        dl_cb:AddRectFilled(
            imgui.ImVec2(p_cb.x,           p_cb.y),
            imgui.ImVec2(p_cb.x+btnW,      p_cb.y+halfH),
            imgui.ColorConvertFloat4ToU32(iv4(aR*0.55,aG*0.55,aB*0.55,bgAlpha)), rnd, flagsTop)
    else
        dl_cb:AddRectFilled(
            imgui.ImVec2(p_cb.x,           p_cb.y),
            imgui.ImVec2(p_cb.x+btnW,      p_cb.y+halfH),
            imgui.ColorConvertFloat4ToU32(iv4(aR*0.55,aG*0.55,aB*0.55,bgAlpha)), 0)
    end
    if flagsBot then
        dl_cb:AddRectFilled(
            imgui.ImVec2(p_cb.x,           p_cb.y+halfH),
            imgui.ImVec2(p_cb.x+btnW,      p_cb.y+bH_c),
            imgui.ColorConvertFloat4ToU32(iv4(bR*0.55,bG*0.55,bB*0.55,bgAlpha)), rnd, flagsBot)
    else
        dl_cb:AddRectFilled(
            imgui.ImVec2(p_cb.x,           p_cb.y+halfH),
            imgui.ImVec2(p_cb.x+btnW,      p_cb.y+bH_c),
            imgui.ColorConvertFloat4ToU32(iv4(bR*0.55,bG*0.55,bB*0.55,bgAlpha)), 0)
    end
    local borderCol = isAct and iv4(aR,aG,aB,1.0) or iv4(aR*0.65,aG*0.65,aB*0.65,0.70)
    dl_cb:AddRect(
        imgui.ImVec2(p_cb.x,       p_cb.y),
        imgui.ImVec2(p_cb.x+btnW,  p_cb.y+bH_c),
        imgui.ColorConvertFloat4ToU32(borderCol), rnd, 0, isAct and 2.0 or 1.0)
    dl_cb:AddLine(
        imgui.ImVec2(p_cb.x+4,      p_cb.y+halfH),
        imgui.ImVec2(p_cb.x+btnW-4, p_cb.y+halfH),
        imgui.ColorConvertFloat4ToU32(iv4(1,1,1,0.12)), 1)
    imgui.PushStyleColor(imgui.Col.Button,        iv4(0,0,0,0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(aR*0.20,aG*0.20,aB*0.20,0.50))
    imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(aR*0.40,aG*0.40,aB*0.40,0.80))
    local clicked = imgui.Button(label.."##"..uid, imgui.ImVec2(btnW, bH_c))
    if imgui.IsItemHovered() and tooltipText then
        imgui.BeginTooltip()
        imgui.Text(tooltipText)
        imgui.EndTooltip()
    end
    imgui.PopStyleColor(3)
    return clicked
end

-- esli v Nastroykah vklyuchen globalnyy cvet cifr -- primenyaet ego poverh
-- avto/temnovogo cveta (no individualnyy klik-cvet konkretnogo elementa,
-- zadavaemyy cherez getElemColor, vse ravno v prioritete -- sm. dataRow/metricTile)
local function applyGlobalNumColor(col)
    if cfg.globalNumColorOn and cfg.globalNumR >= 0 then
        local a = (col and col.w) or 1.0
        return iv4(cfg.globalNumR, cfg.globalNumG, cfg.globalNumB, a)
    end
    return col
end

local function dataRow(label, value, valColor)
    if not hasVal(value) then return end
    local r,g,b = getAcc()
    local rr,rg,rb = getRowBgColor()
    local dl    = imgui.GetWindowDrawList()
    local p     = imgui.GetCursorScreenPos()
    local avail = imgui.GetContentRegionAvail().x
    local h     = S(36)
    _rowIndex = _rowIndex + 1
    -- Ń„Š¾Š½ Ń�Ń‚Ń€Š¾ŠŗŠø: ŠøŃ�ŠæŠ¾Š»Ń�Š·Ń�ŠµŠ¼ ŠŗŠ°Ń�Ń‚Š¾Š¼Š½Ń‹Š¹ Ń†Š²ŠµŃ‚ Ń„Š¾Š½Š° (rowBg) Ń� Ń‡ŠµŃ€ŠµŠ´Š¾Š²Š°Š½ŠøŠµŠ¼ Ń¸Ń€ŠŗŠ¾Ń�Ń‚Šø
    local shade = (_rowIndex % 2 == 0) and 0.13 or 0.07
    local minV  = (_rowIndex % 2 == 0) and 0.10 or 0.05
    local bgR = math.max(rr*shade, minV)
    local bgG = math.max(rg*shade, minV)
    local bgB = math.max(rb*shade, minV)
    dl:AddRectFilled(
        imgui.ImVec2(p.x,       p.y),
        imgui.ImVec2(p.x+avail, p.y+h),
        imgui.ColorConvertFloat4ToU32(iv4(bgR,bgG,bgB,0.98)), 5)
    -- Ń‚Š¾Š½ŠŗŠ°Ń¸ Ń€Š°Š¼ŠŗŠ° Ń�Ń‚Ń€Š¾ŠŗŠø Š¾Ń‚ Š°ŠŗŃ†ŠµŠ½Ń‚Š°
    dl:AddRect(
        imgui.ImVec2(p.x,       p.y),
        imgui.ImVec2(p.x+avail, p.y+h),
        imgui.ColorConvertFloat4ToU32(iv4(r*0.45,g*0.45,b*0.45,0.40)), 5, 0, 0.7)
    dl:AddRectFilled(
        imgui.ImVec2(p.x,   p.y+3),
        imgui.ImVec2(p.x+2, p.y+h-3),
        imgui.ColorConvertFloat4ToU32(iv4(r,g,b,0.85)), 1)
    -- Ń¸Ń€ŠŗŠ¾Ń�Ń‚Ń� Ń„Š¾Š½Š° Ń�Ń‚Ń€Š¾ŠŗŠø ā€” ŠµŃ�Š»Šø Ń�Š²ŠµŃ‚Š»Ń‹Š¹ Ń„Š¾Š½, Š´ŠµŠ»Š°ŠµŠ¼ Ń‚ŠµŠŗŃ�Ń‚ Ń‚Ń‘Š¼Š½Ń‹Š¼
    local bgBright = bgR*0.299 + bgG*0.587 + bgB*0.114
    local labelCol = bgBright > 0.35 and iv4(0.05,0.05,0.08,1.0) or iv4(0.95,0.95,0.98,1.0)
    -- Š´Š»Ń¸ valColor Ń‚Š¾Š¶Šµ ŠæŃ€Š¾Š²ŠµŃ€Ń¸ŠµŠ¼: ŠµŃ�Š»Šø Š½Šµ Š·Š°Š´Š°Š½ Ń¸Š²Š½Š¾ ā€” Š°Š²Ń‚Š¾
    local autoValCol
    if not valColor then
        autoValCol = bgBright > 0.35 and iv4(0.05,0.05,0.10,1.0) or thTxt()
    else
        autoValCol = valColor
    end
    autoValCol = applyGlobalNumColor(autoValCol)
    local lblId = "lbl_"..label
    local valId = "val_"..label
    labelCol   = getElemColor(lblId, labelCol)
    autoValCol = getElemColor(valId, autoValCol)
    imgui.SetCursorPosY(imgui.GetCursorPosY()+S(6))
    imgui.SetCursorPosX(imgui.GetCursorPosX()+S(10))
    imgui.TextColored(labelCol, label)
    recolorOnClick(lblId)
    local valStr  = u8(tostring(vOrDash(value) or '-'))
    local labelW  = imgui.CalcTextSize(label).x
    local valW    = imgui.CalcTextSize(valStr).x
    -- avtoumenshenie shrifta znacheniya, esli ono ne pomeshchaetsya v stroku
    -- (posle ispravleniya toNum summy mogut byt ochen bolshimi -- millirdy/trilliony)
    local baseScale = St.UI_SCALE * (cfg.fontSize > 0 and cfg.fontSize or 1.25)
    local rightPad = S(12)
    local maxValW = avail - labelW - S(24) - rightPad
    local shrink = 1.0
    if valW > maxValW and maxValW > S(10) and valW > 0 then
        shrink = maxValW / valW
        if shrink < 0.55 then shrink = 0.55 end
    end
    if shrink < 0.999 then
        pcall(imgui.SetWindowFontScale, baseScale * shrink)
        valW = valW * shrink
    end
    imgui.SameLine(avail - valW - rightPad)
    imgui.SetCursorPosY(imgui.GetCursorPosY())
    imgui.TextColored(autoValCol, valStr)
    recolorOnClick(valId)
    if shrink < 0.999 then
        pcall(imgui.SetWindowFontScale, baseScale)
    end
    imgui.SetCursorPosY(imgui.GetCursorPosY()+2)
end

 St._metricTileIdx = 0
local function metricTile(label, value, col, w, onClickFn)
    St._metricTileIdx = St._metricTileIdx + 1
    local h  = S(56)
    local r,g,b = getAcc()
    local rr,rg,rb = getRowBgColor()
    local dl = imgui.GetWindowDrawList()
    local p  = imgui.GetCursorScreenPos()
    -- Ń„Š¾Š½ Ń‚Š°Š¹Š»Š°
    local bgR = math.max(rr*0.18, 0.09)
    local bgG = math.max(rg*0.18, 0.09)
    local bgB = math.max(rb*0.18, 0.09)
    dl:AddRectFilled(
        imgui.ImVec2(p.x,   p.y),
        imgui.ImVec2(p.x+w, p.y+h),
        imgui.ColorConvertFloat4ToU32(iv4(bgR,bgG,bgB,0.97)), 10)
    -- Ń€Š°Š¼ŠŗŠ°
    dl:AddRect(
        imgui.ImVec2(p.x,   p.y),
        imgui.ImVec2(p.x+w, p.y+h),
        imgui.ColorConvertFloat4ToU32(iv4(
            math.max(r*0.65,0.22), math.max(g*0.65,0.22), math.max(b*0.65,0.22), 0.85)),
        10, 0, 1.5)
    -- Š»ŠµŠ²Š°Ń¸ Š°ŠŗŃ†ŠµŠ½Ń‚Š½Š°Ń¸ ŠæŠ¾Š»Š¾Ń�Š°
    local ac = col or thAcc()
    dl:AddRectFilled(
        imgui.ImVec2(p.x,   p.y+6),
        imgui.ImVec2(p.x+3, p.y+h-6),
        imgui.ColorConvertFloat4ToU32(iv4(ac.x,ac.y,ac.z,1.0)), 2)

    imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
    imgui.BeginChild("##mt"..tostring(St._metricTileIdx), imgui.ImVec2(w, h), false,
        imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)

        -- Š�Š½Š¾ŠæŠŗŠ° Ń�ŠæŃ€Š°Š²Š° (ŠµŃ�Š»Šø ŠµŃ�Ń‚Ń�) ā€” Ń€ŠøŃ�Ń�ŠµŠ¼ ŠæŠµŃ€Š²Š¾Š¹ Ń‡Ń‚Š¾Š±Ń‹ Š·Š½Š°Ń‚Ń� ŠµŃ‘ Ń�ŠøŃ€ŠøŠ½Ń�
        local btnW = onClickFn and S(44) or 0
        local btnH = S(32)
        if onClickFn then
            imgui.SetCursorPos(imgui.ImVec2(w - btnW - S(6), (h - btnH)*0.5))
            imgui.PushStyleColor(imgui.Col.Button,        iv4(r*0.25,g*0.25,b*0.25,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(r*0.65,g*0.65,b*0.65,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(r,      g,      b,      1.0))
            do local _sv=0
            if pcall(imgui.PushStyleVar,imgui.StyleVar.FrameRounding,Sf(7.0)) then _sv=_sv+1 end
            -- Ń�ŠøŠ¼Š²Š¾Š» "ŠæŠ¾Š´ŠµŠ»ŠøŃ‚Ń�Ń�Ń¸/ŠŗŠ¾ŠæŠøŃ€Š¾Š²Š°Ń‚Ń�": Ń�Ń‚Ń€ŠµŠ»ŠŗŠ° Š²Š²ŠµŃ€Ń…
            if imgui.Button(">>##cp"..tostring(St._metricTileIdx),
                            imgui.ImVec2(btnW, btnH)) then
                pcall(onClickFn)
            end
            if _sv>0 then pcall(imgui.PopStyleVar,_sv) end end
            imgui.PopStyleColor(3)
        end

        imgui.SetCursorPos(imgui.ImVec2(S(10), S(7)))
        imgui.TextColored(thDim(), label)

        -- Š—Š½Š°Ń‡ŠµŠ½ŠøŠµ (Ń�Š½ŠøŠ·Ń� Ń�Š»ŠµŠ²Š°, ŠŗŃ€Ń�ŠæŠ½ŠµŠµ)
        local valStr = u8(value~="" and value or "-")
        local mtId = "mt_"..label
        imgui.SetCursorPos(imgui.ImVec2(S(10), S(28)))
        imgui.TextColored(getElemColor(mtId, applyGlobalNumColor(col or thTxt())), valStr)
        recolorOnClick(mtId)

    imgui.EndChild()
    imgui.PopStyleColor()
end

 St._chipIdx = 0
 St.chipSide = false
local function chip(label, value)
    if not hasVal(value) then return end
    St._chipIdx = St._chipIdx + 1
    local avail = imgui.GetContentRegionAvail().x
    local w  = (avail - S(6)) * 0.5
    local h  = S(54)
    local r,g,b = getAcc()
    local rr,rg,rb = getRowBgColor()
    local dl = imgui.GetWindowDrawList()
    local doRender = function(side)
        local p = imgui.GetCursorScreenPos()
        -- Ń„Š¾Š½ chip: ŠŗŠ°Ń�Ń‚Š¾Š¼Š½Ń‹Š¹ Ń†Š²ŠµŃ‚ Ń„Š¾Š½Š° Ń�Ń‚Ń€Š¾Šŗ
        local bgR = math.max(rr*0.14, 0.08)
        local bgG = math.max(rg*0.14, 0.08)
        local bgB = math.max(rb*0.14, 0.08)
        dl:AddRectFilled(
            imgui.ImVec2(p.x,   p.y),
            imgui.ImVec2(p.x+w, p.y+h),
            imgui.ColorConvertFloat4ToU32(iv4(bgR,bgG,bgB,0.97)), 8)
        -- Ń€Š°Š¼ŠŗŠ° Š¾Ń‚ Š°ŠŗŃ†ŠµŠ½Ń‚Š°
        local brR = math.max(r*0.55, 0.20)
        local brG = math.max(g*0.55, 0.20)
        local brB = math.max(b*0.55, 0.20)
        dl:AddRect(
            imgui.ImVec2(p.x,   p.y),
            imgui.ImVec2(p.x+w, p.y+h),
            imgui.ColorConvertFloat4ToU32(iv4(brR,brG,brB,0.80)), 8, 0, 1)
        dl:AddRectFilled(
            imgui.ImVec2(p.x+8,   p.y+h-2),
            imgui.ImVec2(p.x+w-8, p.y+h),
            imgui.ColorConvertFloat4ToU32(iv4(r,g,b,0.70)), 2)
        imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
        local cid = "##chip"..tostring(St._chipIdx)..(side and "R" or "L")
        imgui.BeginChild(cid, imgui.ImVec2(w,h), false)
            imgui.SetCursorPos(imgui.ImVec2(S(8),S(6)))
            imgui.TextColored(thDim(), label)
            imgui.SetCursorPos(imgui.ImVec2(S(8),S(26)))
            imgui.TextColored(thAcc(), u8(vOrDash(value)))
        imgui.EndChild()
        imgui.PopStyleColor()
    end
    if St.chipSide then
        imgui.SameLine(0,S(6))
        doRender(true)
        imgui.Spacing()
        St.chipSide = false
    else
        St.chipSide = true
        doRender(false)
    end
end

local function tabButton(label, active, w, r,g,b, hParam)
    local ar,ag,ab = getAcc()
    local br = r or ar; local bg2 = g or ag; local bb = b or ab
    local dl = imgui.GetWindowDrawList()
    local p  = imgui.GetCursorScreenPos()
    local h  = hParam or S(38)
    if active then
        imgui.PushStyleColor(imgui.Col.Button,        iv4(br*0.22,bg2*0.22,bb*0.22,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(br*0.38,bg2*0.38,bb*0.38,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(br*0.55,bg2*0.55,bb*0.55,1.0))
    else
        imgui.PushStyleColor(imgui.Col.Button,        iv4(br*0.07,bg2*0.07,bb*0.07,0.85))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(br*0.18,bg2*0.18,bb*0.18,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(br*0.30,bg2*0.30,bb*0.30,1.0))
    end
    local clicked = imgui.Button(label, imgui.ImVec2(w or 0, h))
    imgui.PopStyleColor(3)
    if active then
        dl:AddRectFilled(
            imgui.ImVec2(p.x+S(4),         p.y+h-3),
            imgui.ImVec2(p.x+(w or 0)-S(4), p.y+h),
            imgui.ColorConvertFloat4ToU32(iv4(br,bg2,bb,0.95)), 2)
    end
    return clicked
end

-- ============================================================
--  Š‘ŠžŠšŠžŠ’ĄžŠ• Š�Š•Š�Ąž: Ń€Š°Š·Š´ŠµŠ»Ń‹ Š¸ Š²ĐºĐ»Đ°Đ´ĐºĐ¸ Đ²Đ½ŃƒŃ‚Ń€Đ¸ ĐºĐ°Đ¶Đ´ĐžĐ³Đž Ń€Đ°Đ·Đ´ĐµĐ»Đ°
-- ------------------------------------------------------------
-- левая вертикальная полоска (4 раздела): Персонаж / Налоги / Настройки /
-- О скрипте. Раздел "Персонаж" содержит 3 внутренние вкладки
-- (Персонаж/Бой/Финансы — как было раньше). Раздел "Налоги" теперь
-- упрощён: только оплата (без логов/напоминаний, вкладка "Логи чата"
-- убрана полностью). St.activeTab по-прежнему хранит "реальный" номер
-- вкладки — вся остальная логика в файле, завязанная на St.activeTab, не
-- переписывается.
local SECTION_DEFS = {
    { label = ICON_USER.." "..u8"\xcf\xe5\xf0\xf1\xee\xed\xe0\xe6",    icon=ICON_USER, name=u8"\xcf\xe5\xf0\xf1\xee\xed\xe0\xe6",    r=0.43,g=0.71,b=1.0,
      tabs = {
        { tab=1, label = ICON_USER.." "..u8"\xcf\xe5\xf0\xf1\xee\xed\xe0\xe6" },
        { tab=2, label = ICON_FIST.." "..u8"\xc1\xee\xe9" },
        { tab=3, label = ICON_SACK.." "..u8"\xd4\xe8\xed\xe0\xed\xf1\xfb" },
      } },
    { label = ICON_SACK.." "..u8"\xcd\xe0\xeb\xee\xe3\xe8",             icon=ICON_SACK, name=u8"\xcd\xe0\xeb\xee\xe3\xe8",             r=1.0,g=0.65,b=0.15,
      tabs = {
        { tab=6, label = u8"\xcd\xe0\xeb\xee\xe3\xe8" },
      } },
    { label = ICON_GEAR.." "..u8"\xcd\xe0\xf1\xf2\xf0\xee\xe9\xea\xe8", icon=ICON_GEAR, name=u8"\xcd\xe0\xf1\xf2\xf0\xee\xe9\xea\xe8", r=0.75,g=0.75,b=0.80,
      -- по просьбе "Уведомления" больше не отдельная под-вкладка —
      -- перенесены внутрь "Настроек" целиком (см. drawNotificationsSection)
      tabs = {
        { tab=4, label = ICON_GEAR.." "..u8"\xcd\xe0\xf1\xf2\xf0\xee\xe9\xea\xe8" },
      } },
    { label = ICON_INFO.." "..u8"\xce \xf1\xea\xf0.",                   icon=ICON_INFO, name=u8"\xce\x20\xf1\xea\xf0\xe8\xef\xf2\xe5",     r=0.75,g=0.45,b=1.0,
      tabs = { { tab=5 } } },
}

-- ── все 8 вкладок одним плоским списком — используется в "старом" (без
-- бокового меню) режиме отображения, см. cfg.sidebarLayout ──
local function flattenTabs()
    local out = {}
    for _, sec in ipairs(SECTION_DEFS) do
        for _, td in ipairs(sec.tabs) do
            table.insert(out, { tab = td.tab, label = td.label or sec.label, r = sec.r, g = sec.g, b = sec.b })
        end
    end
    return out
end

local function sectionOfTab(t)
    for si, sec in ipairs(SECTION_DEFS) do
        for _, td in ipairs(sec.tabs) do
            if td.tab == t then return si end
        end
    end
    return 1
end

-- ── тултип с обводкой текста (для свёрнутого бокового меню — иконки
-- без подписи; при наведении всплывает крупная подпись с тёмной
-- обводкой по контуру для читаемости поверх любого фона) ──
local function outlinedTooltip(text, r, g, b)
    imgui.BeginTooltip()
    imgui.SetWindowFontScale(St.UI_SCALE * (cfg.fontSize > 0 and cfg.fontSize or 1.25) * 1.15)
    local dlT = imgui.GetWindowDrawList()
    local pT  = imgui.GetCursorScreenPos()
    local colOutline = imgui.ColorConvertFloat4ToU32(iv4(0,0,0,0.9))
    local colText    = imgui.ColorConvertFloat4ToU32(iv4(r or 1, g or 1, b or 1, 1.0))
    local offs = {{-1,0},{1,0},{0,-1},{0,1},{-1,-1},{1,-1},{-1,1},{1,1}}
    for _, o in ipairs(offs) do
        dlT:AddText(imgui.ImVec2(pT.x+o[1], pT.y+o[2]), colOutline, text)
    end
    dlT:AddText(pT, colText, text)
    imgui.Dummy(imgui.GetItemRectSize and imgui.ImVec2(imgui.CalcTextSize(text).x, imgui.CalcTextSize(text).y) or imgui.ImVec2(imgui.CalcTextSize(text).x, S(18)))
    imgui.EndTooltip()
end

local function stepBtn(id, label, onClickFn, w, h2)
    local r,g,b = getAcc()
    imgui.PushStyleColor(imgui.Col.Button,        iv4(r*0.18,g*0.18,b*0.18,1.0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(r*0.45,g*0.45,b*0.45,1.0))
    imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(r*0.75,g*0.75,b*0.75,1.0))
    local clicked = imgui.Button(label.."##"..id, imgui.ImVec2(S(w or 44), S(h2 or 38)))
    imgui.PopStyleColor(3)
    if clicked then pcall(onClickFn) end
end

-- ============================================================
--  Š’Š�Š›Š�Š”Š�Š� 1: Š�Š•Š Š�Š˛Š¯Š�Š–
-- ============================================================
local function drawCharLeftInner(s, h)
    if St._resetCharScroll then imgui.SetScrollY(0) end
                secTitle(u8"\xc1\xe0\xeb\xe0\xed\xf1")
                dataRow(u8"SA$",    s.cashSas~="" and fmtMoney(s.cashSas) or "-", thGreen())
                dataRow(u8"\xc1\xe0\xed\xea", s.bank~="" and fmtMoney(s.bank) or "-", thAcc())
                dataRow(u8"\xc4\xe5\xef.", s.moneyDay~="" and fmtMoney(s.moneyDay) or "-", thGold())
                dataRow(u8"\xca\xe0\xf0\xf2\xe0", s.bankCard)
                if hasVal(s.cashVcs) then dataRow(u8"VC$", fmtMoney(s.cashVcs)) end
                if hasVal(s.btc)     then dataRow("BTC", fmtAmt(toNum(s.btc))) end
                if hasVal(s.euro)    then dataRow(CUR_AARP_SHORT, fmtAmt(toNum(s.euro))) end
                if hasVal(s.azCoins) or hasVal(s.accountState) then
                    local azRaw = hasVal(s.accountState) and s.accountState or s.azCoins
                    dataRow("AZ", fmtAmt(toNum(azRaw)), thGold())
                end
                do
                    local hasAccLeft = false
                    for i=1,6 do if hasVal(s.acc[i]) then hasAccLeft=true; break end end
                    if hasAccLeft then
                        _rowIndex = 0
                        secTitle(u8"\xd1\xf7\xb8\xf2\xe0")
                        for i=1,6 do
                            if hasVal(s.acc[i]) then
                                dataRow(u8"\xb9"..i, fmtMoney(s.acc[i]), thAcc())
                            end
                        end
                        if s.totalAcc ~= "" then
                            _rowIndex = 0
                            dataRow(u8"\xc8\xf2\xee\xe3", s.totalAcc, thGold())
                        end
                    end
                end
end

local function drawCharRightInner(s, h)
    if St._resetCharScroll then imgui.SetScrollY(0) end
                secTitle(u8"\xcb\xe8\xf7\xed\xee\xe5")
                dataRow(u8"\xd2\xe5\xeb\xe5\xf4\xee\xed",    s.phone)
                dataRow(u8"\xcf\xee\xeb",                     s.gender)
                dataRow(u8"\xc7\xe4\xee\xf0\xee\xe2\xfc\xe5", s.health,
                    (tonumber((s.health or ""):match("%d+")) or 100)>=80 and thGreen() or thRed())
                if hasVal(s.authDate) then
                    dataRow(u8"\xc0\xe2\xf2\xee\xf0\xe8\xe7\xe0\xf6\xe8\xff", u8(s.authDate), thGold())
                end
                dataRow(u8"\xd0\xe0\xe1\xee\xf2\xe0",         s.job)
                if hasVal(s.org) or hasVal(s.position) or hasVal(s.status) then
                    secTitle(u8"\xce\xf0\xe3\xe0\xed\xe8\xe7\xe0\xf6\xe8\xff")
                    dataRow(u8"\xce\xf0\xe3.",    s.org)
                    dataRow(u8"\xc4\xee\xeb\xe6.", s.position)
                    dataRow(u8"\xd1\xf2\xe0\xf2\xf3\xf1", s.status)
                end
                secTitle(u8"\xd1\xee\xf6\xe8\xe0\xeb\xfc\xed\xee\xe5")
                dataRow(u8"\xd1\xe5\xec\xfc\xff", s.family)
                dataRow(u8"\xc3\xf0\xe0\xe6\xe4.", s.citizenship)
                secTitle(u8"\xcf\xf0\xe0\xe2\xee\xe2\xee\xe9")
                dataRow(u8"\xd3\xf0. \xf0\xee\xe7.", s.wanted,
                    (s.wanted=="0" or s.wanted=="-") and thGreen() or thRed())
                dataRow(u8"\xc7\xe0\xea\xee\xed.", s.lawfulness)
                dataRow(u8"\xcf\xf0\xe5\xe4\xf3\xef\xf0.", s.warnings,
                    (s.warnings=="0" or s.warnings=="-") and thGreen() or thRed())
                dataRow(u8"\xc7\xe0\xe2\xe8\xf1\xe8\xec.", s.addiction)
                if hasVal(s.hotel) or hasVal(s.hotelRoom) or hasVal(s.trailer) then
                    secTitle(u8"\xc8\xec\xf3\xf9\xe5\xf1\xf2\xe2\xee")
                    dataRow(u8"\xce\xf2\xe5\xeb\xfc",     s.hotel)
                    dataRow(u8"\xca\xee\xec\xed\xe0\xf2\xe0", s.hotelRoom)
                    dataRow(u8"\xd2\xf0\xe5\xe9\xeb\xe5\xf0", s.trailer)
                end
                if #s.extra > 0 then
                    secTitle(u8"\xcf\xf0\xee\xf7\xe5\xe5")
                    for _, pair in ipairs(s.extra) do dataRow(u8(pair[1]), pair[2]) end
                end
end

-- ФИКС (п.8): левая и правая колонки — раздельные BeginChild/EndChild,
-- каждая со своим pcall. Если упадёт левая — правая всё равно рисуется
-- (раньше не было pcall ни на одной из них).
local function drawChar(s, h)
    _rowIndex = 0
    local gap  = 6
    local colW = (imgui.GetContentRegionAvail().x - gap) * 0.5

    imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
    imgui.BeginChild("##col_left", imgui.ImVec2(colW, h), false)
    local okL, errL = PCS_GUARD.call(drawCharLeftInner, s, h)
    imgui.EndChild()
    imgui.PopStyleColor()
    if not okL then
        pcall(sampAddChatMessage, "{FF6666}[PC Stats] " ..
            "\xee\xf8\xe8\xe1\xea\xe0\x20\xeb\xe5\xe2\xee\xe9\x20\xea\xee\xeb\xee\xed\xea\xe8\x20\xcf\xe5\xf0\xf1\xee\xed\xe0\xe6\xe0: " .. tostring(errL), -1)
    end

    imgui.SameLine(0, gap)

    imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
    imgui.BeginChild("##col_right", imgui.ImVec2(colW, h), false)
    local okR, errR = PCS_GUARD.call(drawCharRightInner, s, h)
    imgui.EndChild()
    imgui.PopStyleColor()
    if not okR then
        pcall(sampAddChatMessage, "{FF6666}[PC Stats] " ..
            "\xee\xf8\xe8\xe1\xea\xe0\x20\xef\xf0\xe0\xe2\xee\xe9\x20\xea\xee\xeb\xee\xed\xea\xe8\x20\xcf\xe5\xf0\xf1\xee\xed\xe0\xe6\xe0: " .. tostring(errR), -1)
    end

    St._resetCharScroll = false
end
-- ============================================================
local function drawBattleInner(s, h)
        secTitle(u8"\xc1\xee\xe5\xe2\xfb\xe5 \xc1\xee\xed\xf3\xf1\xfb")
        St.chipSide = false
        chip(u8"\xc7\xe0\xf9\xe8\xf2\xe0",        s.protection)
        chip(u8"\xd0\xe5\xe3\xe5\xed\xe5\xf0.",    s.regen)
        chip(u8"\xd3\xf0\xee\xed",                  s.damage)
        chip(u8"\xd3\xe4\xe0\xf7\xe0",              s.luck)
        chip(u8"\xcc\xe0\xea\xf1. HP",              s.maxHp)
        chip(u8"\xcc\xe0\xea\xf1. \xc1\xf0\xee\xed\xff", s.maxArmor)
        chip(u8"\xd8. \xee\xe3\xeb\xf3\xf8.",      s.stunChance)
        chip(u8"\xd8. \xee\xef\xfc\xff\xed.",      s.bleedChance)
        chip(u8"\xd8. \xf3\xea\xeb\xee\xed.",      s.dodgeChance)
        chip(u8"\xce\xf2\xf0\xe0\xe6. \xf3\xf0.",  s.reflectDamage)
        chip(u8"\xc1\xeb\xee\xea. \xf3\xf0.",      s.blockDamage)
        chip(u8"\xd1\xea\xee\xf0\xee\xf1\xf2\xf0.", s.fireRate)
        chip(u8"\xce\xf2\xea\xe0\xf2",              s.recoil)
        chip(u8"\xcf\xeb\xee\xe4",                   s.fruitStun)
        if St.chipSide then St.chipSide=false end

    -- ── нижний отступ, чтобы последняя строка не прилипала к краю окна ──
    imgui.Dummy(imgui.ImVec2(0, S(40)))
end

-- ФИКС (п.9): тот же паттерн — drawBattleInner под pcall
local function drawBattle(s, h)
    imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
    imgui.BeginChild("##sb", imgui.ImVec2(0,h), false,
        imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
    local ok, err = PCS_GUARD.call(drawBattleInner, s, h)
    imgui.EndChild()
    imgui.PopStyleColor()
    if not ok then
        pcall(sampAddChatMessage, "{FF6666}[PC Stats] " ..
            "\xee\xf8\xe8\xe1\xea\xe0\x20\xee\xf2\xf0\xe8\xf1\xee\xe2\xea\xe8\x20\xc1\xee\xed\xf3\xf1\xee\xe2: " .. tostring(err), -1)
    end
end

-- ============================================================
--  Š‘Š£Š¤Š•Š Š« Š�Š›Š�Š™Š”Š•Š Š˛Š’ Š Š�Š—Š�Š•Š Š� Š˛Š�Š¯Š�
-- ============================================================
 St.winWbuf = imgui.new.float(0.60)
 St.winHbuf = imgui.new.float(0.76)
local WIN_W_MIN = 0.38
local WIN_H_MIN = 0.42
 St.fontSizeBuf = imgui.new.float(1.25)
 St.borderThicknessBuf = imgui.new.float(1.2)
local FONT_SIZE_MIN = 0.7
local FONT_SIZE_MAX = 2.0
-- Š±Ń�Ń„ŠµŃ€Ń‹ Š´Š»Ń¸ Š½Š°Ń�Ń‚Ń€Š¾ŠµŠŗ Š°Š²Ń‚Š¾-Š¾Š±Š½Š¾Š²Š»ŠµŠ½ŠøŃ¸ (Š´Š¾Š»Š¶Š½Ń‹ Š±Ń‹Ń‚Ń� Š³Š»Š¾Š±Š°Š»Ń�Š½Ń‹Š¼Šø, Š½Šµ Š²Š½Ń�Ń‚Ń€Šø Ń€ŠµŠ½Š´ŠµŃ€Š°!)
local chkBuf = imgui.new.bool(false)
local chkBuf2 = imgui.new.bool(true)
local aBuf   = imgui.new.float(30.0)
-- Buffery kursov obmena valyut (celye chisla, chtoby ne bylo lishnih nulikov posle zapyatoy)
 St.rateAZBuf  = imgui.new.int(0)
 St.rateBTCBuf = imgui.new.int(0)
 St.rateEURBuf = imgui.new.int(0)
 St.rateVCBuf  = imgui.new.int(0)
 St.rateVCSellBuf = imgui.new.int(0)
 St.rateASCBuf = imgui.new.int(0)

-- ── буферы вкладки "Налоги" ──
St.taxAutoBuf         = imgui.new.bool(false)
St.taxIntervalBuf     = imgui.new.int(1)
St.taxPayOnLoginBuf   = imgui.new.bool(false)

-- ── горячая клавиша открытия меню (ждём следующее нажатие клавиши,
-- пока флаг включён — см. onKeyDown ниже и блок в "О скрипте") ──
St.awaitingHotkeyBind = false
-- ── состояние подтверждения опасных кнопок во вкладке "О скрипте"
-- (Выключить/Сбросить данные/Удалить скрипт): по просьбе первая кнопка
-- только "взводит" подтверждение на несколько секунд, реальное действие
-- срабатывает только по повторному нажатию в этом окне — так сложнее
-- случайно снести себе конфиг или сам файл скрипта ──
St._dangerConfirmKind = nil   -- "disable" | "reset" | "delete" | nil
St._dangerConfirmUntil = 0

-- otslezhivaem kakoe pole seychas redaktiruetsya, chtoby ne perezapisyvat bufer
-- kazhdyy kadr poka igrok pechataet (imenno eto vyzyvalo "migание"/skachushchie nuliki)
local _rateActive = {}

-- ── состояние окна "Настройки" вкладки "Финансы": по умолчанию оно
-- прикреплено к главному окну справа и двигается вместе с ним; кнопка
-- "Открепить" позволяет носить его отдельно ──
 St._financeSettingsOpen     = false
 St._financeSettingsDetached = false
local _financeSettingsPos      = nil   -- {x=,y=} запоминается, только пока панель откреплена
 St._mainWinPos  = nil
 St._mainWinSize = nil

-- ── ФИКС (по просьбе): общая панель "Настройки", открывается иконкой-
-- шестерёнкой в правом верхнем углу заголовка — доступна с ЛЮБОЙ
-- вкладки (в отличие от панели "Финансы" выше, эта не привязана к
-- конкретной вкладке и не закрывается при переключении между ними) ──
 St._settingsPanelOpen     = false
 St._settingsPanelDetached = false
local _settingsPanelPos       = nil   -- {x=,y=} запоминается, только пока панель откреплена
-- ── быстрая панель "Оформление" (гестерёнка в углу любой вкладки) ──


-- ── анимация сдвига главного окна влево при открытой (пристыкованной) панели
-- настроек "Финансы"; когда панель открывается — окно скрипта плавно уезжает
-- влево, чтобы освободить место панели, а при закрытии панели возвращается
-- обратно на своё место ──
 St._finShiftAnim       = 0.0   -- 0..1, текущая фаза анимации
 St._finShiftAppliedPx  = 0.0   -- сколько пикселей сдвига уже применено в прошлый кадр
 St._finShiftLastTime   = nil
 St._finShiftAnchorX    = nil   -- "домашняя" X-позиция окна без сдвига (запоминается только пока сдвиг == 0)

-- ============================================================
--  VKLADKA 5: VSEGO DENEG
-- ============================================================
local function rateInputRow(id, label, buf, cfgKey, suffix)
    local r,g,b = getAcc()
    imgui.TextColored(thDim(), label)
    if suffix and suffix ~= "" then
        imgui.SameLine(0, 4)
        imgui.TextColored(iv4(0.45,0.48,0.55,1.0), suffix)
    end
    -- dopolnitelnyy otstup mezhdu podpisyu i polem vvoda, chtoby oni ne slipalis
    imgui.Dummy(imgui.ImVec2(0, S(5)))
    -- poka pole aktivno (igrok pechataet) -- ne trogaem bufer, chtoby kursor ne skakal
    if not _rateActive[id] then
        buf[0] = math.floor((cfg[cfgKey] or 0) + 0.5)
    end
    imgui.PushStyleColor(imgui.Col.FrameBg,        iv4(r*0.16,g*0.16,b*0.16,1.0))
    imgui.PushStyleColor(imgui.Col.FrameBgHovered, iv4(r*0.28,g*0.28,b*0.28,1.0))
    imgui.PushStyleColor(imgui.Col.FrameBgActive,  iv4(r*0.40,g*0.40,b*0.40,1.0))
    imgui.PushStyleColor(imgui.Col.Border,         iv4(math.min(1,r*1.15),math.min(1,g*1.15),math.min(1,b*1.15),0.70))
    imgui.PushStyleColor(imgui.Col.Text,           iv4(1,1,1,1))
    local _svr = 0
    if pcall(imgui.PushStyleVar, imgui.StyleVar.FrameRounding, 8.0) then _svr = _svr + 1 end
    if pcall(imgui.PushStyleVar, imgui.StyleVar.FrameBorderSize, 1.6) then _svr = _svr + 1 end
    -- bolshe vertikalnogo padding'a vnutri polya -- cifry bolshe ne "prilipayut" k ramke sverhu/snizu
    if pcall(imgui.PushStyleVar, imgui.StyleVar.FramePadding, imgui.ImVec2(12, 10)) then _svr = _svr + 1 end
    local ok, changed = pcall(imgui.InputInt, "##rate"..id, buf, 0, 0)
    if ok and changed then
        if buf[0] < 0 then buf[0] = 0 end
        cfg[cfgKey] = buf[0]
        saveCfg()
    end
    local okA, isActive = pcall(imgui.IsItemActive)
    _rateActive[id] = okA and isActive or false
    if _svr > 0 then pcall(imgui.PopStyleVar, _svr) end
    imgui.PopStyleColor(5)
    imgui.Spacing()
end

-- ============================================================
--  ОБНОВЛЕНИЕ КУРСОВ ВАЛЮТ ЧЕРЕЗ ВНУТРИИГРОВОЙ ТЕЛЕФОН (без CEF)
-- ============================================================
-- Раньше скрипт пытался угадать номер вкладки телефона и кликать по
-- списку диалогов (sampSendDialogResponse) — ненадёжно, т.к. состав
-- вкладок/пунктов может отличаться. Теперь вместо угадывания скрипт
-- открывает приложение "Криптовалюта" НАПРЯМУЮ по его ID через
-- RakNet-пакет — тот же способ, что использует отдельный скрипт
-- CryptoRatesReader (payload "launchedApp|39"). Это сразу открывает
-- нужный экран без блуждания по меню.

local CRYPTO_APP_ID = 39 -- ID приложения "Криптовалюта" в телефоне Arizona RP

local _cefFetching   = false
 St._cefLastResult = ""  -- текстовый статус последней попытки (для UI)

-- ФИКС "крашит игру, если ждём оплаты налогов и ОДНОВРЕМЕННО обновляем
-- курс валют": обе операции независимо друг от друга шлют RakNet-пакеты
-- "открыть телефон"/"открыть приложение" и слушают один и тот же
-- sampev.onShowDialog — если они выполняются одновременно, пакеты и
-- обработка диалогов от разных операций перемешиваются (каждая думает,
-- что пришедший диалог — её), что портит состояние телефона на клиенте
-- и приводит к краху игры. _phoneOpBusy — простой общий "замок": обе
-- операции (payTaxesNow и fetchRatesViaCEF) проверяют его перед стартом
-- и не запускаются, пока телефон занят другой из них; выставляется в
-- true одновременно с началом операции и обязательно сбрасывается в
-- false на КАЖДОМ пути завершения (успех/провал/таймаут) ──
_phoneOpBusy = false
-- ФИКС (п.17): таймстемп начала операции — нужен watchdog'у в главном
-- цикле, чтобы принудительно сбросить флаг, если поток "завис" и не
-- дошёл ни до одного из путей завершения (успех/провал/таймаут)
St._phoneOpBusySince = nil

-- ── "Покупка $X VS $Y" / "Продажа $X VS $Y" с экрана "Криптовалюта" —
-- те же два числа, что читает CryptoRatesReader; хранятся только для
-- отображения в меню, на итоговый расчёт "Всего" не влияют ──
St._phoneBuy       = nil
St._phoneBuyFor    = nil
St._phoneSell      = nil
St._phoneSellFor   = nil
St._phoneRatesTime = nil

-- true/"waiting", пока скрипт ждёт открытия диалога с курсами валют
local _phoneFetchState = false

-- отправляет сырые байты через RakNet-битстрим (аналог sendBytes из
-- CryptoRatesReader)
local function sendPhoneBytes(bytes)
    local bitStream = raknetNewBitStream()
    for _, byte in ipairs(bytes) do raknetBitStreamWriteInt8(bitStream, byte) end
    raknetSendBitStream(bitStream)
    raknetDeleteBitStream(bitStream)
end

-- открывает телефон и сразу переключает его на приложение "Криптовалюта"
-- по фиксированному ID (CRYPTO_APP_ID) — без блуждания по вкладкам меню
local function openCryptoAppDirect()
    local payload = "launchedApp|" .. tostring(CRYPTO_APP_ID)
    local appPacket = {220, 18, #payload, 0}
    for i = 1, #payload do table.insert(appPacket, payload:byte(i)) end
    for _ = 1, 4 do table.insert(appPacket, 0) end
    sendPhoneBytes({220, 0, 80, 64}) -- открыть телефон
    wait(150)
    sendPhoneBytes(appPacket) -- открыть приложение "Криптовалюта"
end

-- вытаскивает число прямо перед/после ключевого слова currency в строке
-- вида "AZ-Coins   104.791 AZ - $3.667.685.000" или "Евро  44 EUR - $0" —
-- ищем именно курс (цену в SA$ за единицу), а не количество на руках,
-- поэтому берём число сразу после "$" в конце строки, если оно есть,
-- иначе — первое число в строке.
-- игра форматирует числа ТОЧКАМИ как разделителями тысяч, а не десятичными
-- точками: "44.211" это 44211, "3.667.685.000" это 3667685000, дробной
-- части там никогда не бывает. Поэтому просто выкидываем всё, что не
-- цифра (пробелы, точки, запятые), и получаем целое число — раньше точки
-- не вырезались и tonumber("44.211") превращался в 44.211, отсюда неверный курс.
local function parseGameNumber(str)
    if not str then return nil end
    local digits = tostring(str):gsub("[^%d]", "")
    if digits == "" then return nil end
    local n = tonumber(digits)
    -- ФИКС (п.23): очень длинная строка цифр (например, мусор из чата или
    -- склеенные случайные символы) может дать n == inf/-inf или nan после
    -- tonumber — дальнейший math.floor(inf) у вызывающего кода крашит игру
    if not n or n ~= n or n == math.huge or n == -math.huge then
        return nil
    end
    return n
end

-- Lua-шный string.lower() умеет опускать регистр только у ASCII a-z —
-- заглавные кириллические буквы в CP1251 (диапазон 0xC0-0xDF, плюс
-- Ё=0xA8) он не трогает вообще. Из-за этого сравнение needle
-- (написан строчными буквами) с текстом диалога, который игра всегда
-- присылает ЗАГЛАВНЫМИ (см. скриншот: "ТЕКУЩИЙ КУРС ДЛЯ ПОКУПКИ"),
-- никогда не совпадало — именно поэтому курс VC$ не читался, даже
-- когда искомая строка была найдена правильно. Эта функция опускает
-- регистр и у кириллических байт CP1251 тоже.
local function cp1251Lower(s)
    -- ── ВАЖНО (баг, из-за которого курс AARP/BTC не читался с телефона):
    -- раньше здесь лишь опускался регистр у КИРИЛЛИЦЫ, а латиница (AARP,
    -- BTC, VC$...) оставалась как есть. Игра присылает их ЗАГЛАВНЫМИ
    -- ("AARP", "BTC"), а needle-слова в extractPhoneRate/-LineStart
    -- написаны строчными ("aarp", "btc") — plain-подстрока "aarp" никогда
    -- не находила "AARP", и запасной (fallback) поиск по курсу AARP всегда
    -- проваливался, если не срабатывал точный regex-шаблон выше по файлу.
    -- Теперь сначала опускаем регистр ASCII через :lower() (латиница), а
    -- затем как и раньше — кириллицу вручную ──
    s = s:lower()
    s = s:gsub("[\xc0-\xdf]", function(c) return string.char(c:byte() + 0x20) end)
    s = s:gsub("\xa8", "\xb8") -- Ё -> ё (не входит в диапазон выше)
    return s
end

local function extractPhoneRate(text, needles)
    if not text or text == "" then return nil end
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local clean = stripColor(line)
        local low = cp1251Lower(clean)
        for _, n in ipairs(needles) do
            if low:find(n, 1, true) then
                local afterDollar = clean:match("%$%s*([%d%s%.,]+)%s*$")
                local numStr = afterDollar or clean:match("([%d%s%.,]+)")
                if numStr then
                    local v = parseGameNumber(numStr)
                    if v and v > 0 then return v end
                end
            end
        end
    end
    return nil
end

-- вариант extractPhoneRate, который требует, чтобы needle стоял именно в
-- НАЧАЛЕ строки (после обрезки пробелов/цветовых кодов), а не просто
-- где-то встречался — нужно для VC$: значение курса стоит на отдельной
-- строке вида "Курс продажи: 1234" в меню "Криптовалюта", а не рядом со
-- словом "VC$"/"vice city", поэтому обычный extractPhoneRate по этим
-- словам её не находил, и курс VC$ всегда оставался 0
local function extractPhoneRateLineStart(text, needles)
    if not text or text == "" then return nil end
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local clean = stripColor(line):gsub("^%s+", "")
        local low = cp1251Lower(clean)
        for _, n in ipairs(needles) do
            if low:find("^" .. n) then
                local afterDollar = clean:match("%$%s*([%d%s%.,]+)%s*$")
                local numStr = afterDollar or clean:match("([%d%s%.,]+)")
                if numStr then
                    local v = parseGameNumber(numStr)
                    if v and v > 0 then return v end
                end
            end
        end
    end
    return nil
end

-- крайний запасной вариант для VC$: если поиск по подписи строки не
-- сработал (сервер прислал другую формулировку/сломанную кодировку),
-- берём число прямо по НОМЕРУ строки — на экране "Криптовалюта" курс
-- покупки VC$ стабильно оказывается на 6-й строке диалога
local function extractPhoneRateLineNumber(text, lineNum)
    if not text or text == "" then return nil end
    local i = 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
        i = i + 1
        if i == lineNum then
            local clean = stripColor(line):gsub("^%s+", ""):gsub("%s+$", "")
            local afterDollar = clean:match("%$%s*([%d%s%.,]+)%s*$")
            local numStr = afterDollar or clean:match("([%d%s%.,]+)")
            if numStr then
                local v = parseGameNumber(numStr)
                if v and v > 0 then return v end
            end
            return nil
        end
    end
    return nil
end

-- точный шаблон числа: пропускаем всё, что не цифра, до первой цифры,
-- затем забираем цифры/точки/запятые — так же, как NUM в CryptoRatesReader
local NUM_PATTERN = '[^%d]-(%d[%d,.]*)'

-- ищет rate по точному шаблону вида "Bitcoin (BTC): 12345" и возвращает
-- число (или nil, если не нашлось/не число)
local function phoneNumFromPattern(text, pattern)
    local v = text:match(pattern)
    if not v then return nil end
    local n = parseGameNumber(v)
    if n and n > 0 then return n end
    return nil
end

-- разбирает текст диалога "курс валют" в телефоне и раскладывает найденные
-- значения по cfg.rateXXX/буферам полей ввода. Возвращает true, если хотя
-- бы один курс удалось распознать.
--
-- Экран "Криптовалюта" показывает курсы Bitcoin (BTC), Акции Arizona
-- (AARP, раньше называлась ЕВРО/euro) и
-- Arizona Coin (ASC) в формате "Название (СОКР): число" — это ровно тот
-- же формат, что успешно разбирает CryptoRatesReader, поэтому сначала
-- пробуем точные шаблоны под него, а на случай другого оформления —
-- запасной вариант через общий построчный поиск по ключевым словам.
local function parsePhoneRatesText(text)
    if not text or text == "" then return false end
    local body = stripColor(text)
    local gotAny = false

    local rBTC = phoneNumFromPattern(body, 'Bitcoin%s*%(%s*BTC%s*%)%s*:' .. NUM_PATTERN)
        or extractPhoneRate(body, {"btc", "bitcoin", "\xe1\xe8\xf2\xea\xee\xe9\xed"})
    local rEUR = phoneNumFromPattern(body, '\xc0\xea\xf6\xe8\xe8%s+Arizona%s*%(%s*AAR+P%s*%)%s*:' .. NUM_PATTERN)
        or phoneNumFromPattern(body, '\xc5\xc2\xd0\xce%s*%(%s*euro%s*%)%s*:' .. NUM_PATTERN)
        or extractPhoneRate(body, {"aarrp", "aarp", "\xe0\xea\xf6\xe8\xe8", "arizona", "eur", "\xe5\xe2\xf0\xee"})
    local rASC = phoneNumFromPattern(body, 'Arizona%s+Coin%s*%(%s*ASC%s*%)%s*:' .. NUM_PATTERN)
        or extractPhoneRate(body, {"asc", "\xe0\xf0\xe8\xe7\xee\xed\xe0 \xf1\xf2\xe5\xe9\xe1\xeb"})
    -- AZ-Coin и VC$ на этом экране обычно не показываются (см.
    -- CryptoRatesReader — там их тоже нет), но на всякий случай пробуем
    -- запасной поиск и для них, вдруг формат сервера отличается
    local rAZ  = extractPhoneRate(body, {"az-coin", "az \xea\xee\xe8\xed", "\xe0\xe7-\xea\xee\xe8\xed"})
    -- курс VC$ в меню "Криптовалюта" стоит не рядом со словом "VC$", а на
    -- отдельной строке с меткой "Текущий курс для покупки" — поэтому
    -- сначала ищем именно эту строку по началу строки (ищем по стему
    -- "покуп", чтобы ловить и "покупки", и "покупке"), и только если её
    -- нет — пробуем старый способ как запасной вариант
    local rVC  = extractPhoneRateLineStart(body, {"\xf2\xe5\xea\xf3\xf9\xe8\xe9 \xea\xf3\xf0\xf1 \xe4\xeb\xff \xef\xee\xea\xf3\xef"})
        or extractPhoneRate(body, {"vc$", "vice city", "\xe2\xe0\xe9\xf1 \xf1\xe8\xf2\xe8"})
        or extractPhoneRateLineNumber(body, 6)

    if rAZ  and rAZ  > 0 then cfg.rateAZ  = rAZ;  St.rateAZBuf[0]  = math.floor(rAZ  + 0.5); gotAny = true end
    if rBTC and rBTC > 0 then cfg.rateBTC = rBTC; St.rateBTCBuf[0] = math.floor(rBTC + 0.5); gotAny = true end
    if rEUR and rEUR > 0 then cfg.rateEUR = rEUR; St.rateEURBuf[0] = math.floor(rEUR + 0.5); gotAny = true end
    if rVC  and rVC  > 0 then cfg.rateVC  = rVC;  St.rateVCBuf[0]  = math.floor(rVC  + 0.5); gotAny = true end
    if rASC and rASC > 0 then cfg.rateASC = rASC; St.rateASCBuf[0] = math.floor(rASC + 0.5); gotAny = true end

    -- ── строка "Текущий курс для покупки/продажи" с телефонного экрана
    -- "Криптовалюта": на ней всегда идут ДВА числа подряд (курс и цена
    -- "за сколько") — ровно тот же формат, что разбирает CryptoRatesReader
    -- (buy/buyFor и sell/sellFor), поэтому берём оба точно так же и потом
    -- показываем в меню строкой "Покупка: $X VS $Y" / "Продажа: $X VS $Y".
    --
    -- ВАЖНО: в диалоге строка идёт с заглавной буквы ("Текущий курс..."),
    -- а наш шаблон-стем написан в нижнем регистре — поэтому сравниваем не
    -- с сырым body, а с его версией в нижнем регистре (cp1251Lower, как и
    -- в extractPhoneRateLineStart чуть выше). Позиции символов совпадают,
    -- так что захваченные NUM_PATTERN'ом цифры от регистра не зависят ──
    local bodyLow = cp1251Lower(body)
    local buy, buyFor = bodyLow:match(
        "\xf2\xe5\xea\xf3\xf9\xe8\xe9 \xea\xf3\xf0\xf1 \xe4\xeb\xff \xef\xee\xea\xf3\xef.-:" .. NUM_PATTERN .. NUM_PATTERN)
    local sell, sellFor = bodyLow:match(
        "\xf2\xe5\xea\xf3\xf9\xe8\xe9 \xea\xf3\xf0\xf1 \xe4\xeb\xff \xef\xf0\xee\xe4\xe0\xe6.-:" .. NUM_PATTERN .. NUM_PATTERN)
    if buy or sell then
        St._phoneBuy      = buy      or St._phoneBuy
        St._phoneBuyFor   = buyFor   or St._phoneBuyFor
        St._phoneSell     = sell     or St._phoneSell
        St._phoneSellFor  = sellFor  or St._phoneSellFor
        St._phoneRatesTime = os.date("%H:%M:%S")
        gotAny = true
        -- курс продажи тоже сохраняем как обычный курс (rateVCSell), а не
        -- только как текст для показа — раньше он терялся и не попадал в
        -- поле ручного ввода курсов ──
        local sellN = tonumber(sell)
        if sellN and sellN > 0 then cfg.rateVCSell = sellN; St.rateVCSellBuf[0] = math.floor(sellN + 0.5) end
        -- курс ПОКУПКИ (buy) пишем в основную существующую строку rateVC —
        -- именно её использует расчёт общего баланса (vcSA = vc * cfg.rateVC
        -- в drawFinance), поэтому важно, чтобы сюда попадало распознанное
        -- значение, а не оставался 0. Пишем его здесь (а не только через
        -- более раннюю/хрупкую эвристику rVC выше), потому что buy разбирается
        -- из того же надёжного шаблона "два числа подряд", что и sell,
        -- который уже гарантированно работает ──
        local buyN = tonumber(buy)
        if buyN and buyN > 0 then cfg.rateVC = buyN; St.rateVCBuf[0] = math.floor(buyN + 0.5) end
    end

    if gotAny then saveCfg() end
    return gotAny
end

-- проверяет, похож ли открывшийся диалог именно на экран "Курс валют"
-- приложения "Криптовалюта" (по заголовку либо по телу — так же, как
-- делает parseRates() в CryptoRatesReader), чтобы случайно не схватить
-- какой-то другой экран телефона
local function isCryptoRatesDialog(title, text)
    local marker = "\xca\xf3\xf0\xf1 \xe2\xe0\xeb\xfe\xf2" -- "Курс валют"
    local h = stripColor(tostring(title or ""))
    local b = stripColor(tostring(text or ""))
    return h:find(marker, 1, true) ~= nil or b:find(marker, 1, true) ~= nil
end

-- Запускает автообновление: открывает телефон и сразу переключает его на
-- приложение "Криптовалюта" по ID (см. openCryptoAppDirect), затем ждёт
-- диалог с курсами и читает его — см. sampev.onShowDialog.
local function fetchRatesViaCEF()
    if _cefFetching then return end
    if not isSampAvailable() then
        St._cefLastResult = "\xf1\xe0\xec\xef \xed\xe5 \xe4\xee\xf1\xf2\xf3\xef\xe5\xed"
        return
    end
    -- ФИКС "крашит игру": не трогаем телефон, если он сейчас занят другой
    -- операцией (например, идёт оплата налогов) — см. _phoneOpBusy выше
    if _phoneOpBusy then
        St._cefLastResult = "\xf2\xe5\xeb\xe5\xf4\xee\xed\x20\xe7\xe0\xed\xff\xf2\x20\xe4\xf0\xf3\xe3\xee\xe9\x20\xee\xef\xe5\xf0\xe0\xf6\xe8\xe5\xe9\x2c\x20\xef\xee\xef\xf0\xee\xe1\xf3\xe9\xf2\xe5\x20\xf7\xe5\xf0\xe5\xe7\x20\xef\xe0\xf0\xf3\x20\xf1\xe5\xea\xf3\xed\xe4" -- "телефон занят другой операцией, попробуйте через пару секунд"
        pcall(sampAddChatMessage, "{FF6666}[Stats] " .. tostring(St._cefLastResult), -1)
        return
    end
    _phoneOpBusy     = true
    St._phoneOpBusySince = os.time()
    _cefFetching     = true
    _phoneFetchState = "waiting"
    St._cefLastResult   = "\xee\xf2\xea\xf0\xfb\xe2\xe0\xe5\xec \xf2\xe5\xeb\xe5\xf4\xee\xed..."
    pcall(sampAddChatMessage, "{FFD700}[Stats] \xf0\x9f\x93\xb1 " .. "\xee\xf2\xea\xf0\xfb\xe2\xe0\xe5\xec \xf2\xe5\xeb\xe5\xf4\xee\xed \xe8 \xe8\xf9\xe5\xec \xea\xf3\xf0\xf1 \xe2\xe0\xeb\xfe\xf2...", -1)
    lua_thread.create(function()
        local okOpen = pcall(openCryptoAppDirect)
        if not okOpen then
            _phoneFetchState = false
            _cefFetching     = false
            _phoneOpBusy     = false
            St._cefLastResult = "\xed\xe5 \xf3\xe4\xe0\xeb\xee\xf1\xfc \xee\xf2\xea\xf0\xfb\xf2\xfc \xef\xf0\xe8\xeb\xee\xe6\xe5\xed\xe8\xe5 \xca\xf0\xe8\xef\xf2\xee\xe2\xe0\xeb\xfe\xf2\xe0 \xe2 \xf2\xe5\xeb\xe5\xf4\xee\xed\xe5"
            pcall(sampAddChatMessage, "{FF6666}[Stats] " .. tostring(St._cefLastResult), -1)
            return
        end
        local waited = 0
        while _phoneFetchState and waited < 8000 do
            wait(100); waited = waited + 100
        end
        if _phoneFetchState then
            -- за 8 секунд диалог с курсами так и не пришёл
            _phoneFetchState = false
            St._cefLastResult = "\xed\xe5 \xf3\xe4\xe0\xeb\xee\xf1\xfc \xee\xf2\xea\xf0\xfb\xf2\xfc \xec\xe5\xed\xfe \xca\xf0\xe8\xef\xf2\xee\xe2\xe0\xeb\xfe\xf2\xe0 \xe2 \xf2\xe5\xeb\xe5\xf4\xee\xed\xe5"
            pcall(sampAddChatMessage, "{FF6666}[Stats] " .. tostring(St._cefLastResult), -1)
        end
        -- на всякий случай закрываем всплывшие диалоги телефона, чтобы не
        -- оставить его открытым поверх интерфейса игрока
        for _=1,2 do pcall(sampCloseCurrentDialog, -1); wait(150) end
        -- доп. пауза "на остывание" телефона перед тем, как разрешить
        -- следующую операцию (оплату налогов и т.п.) — тот же приём, что и
        -- в onTaxPaymentSuccess, нужен именно для симметрии: раньше гонка
        -- "крипта → сразу что-то ещё с телефоном" была не защищена так же,
        -- как "налоги → сразу крипта"
        wait(250)
        _cefFetching = false
        _phoneOpBusy = false
    end)
end

-- ============================================================
--  ОПЛАТА НАЛОГОВ (вкладка "Налоги")
-- ------------------------------------------------------------
-- Открываем телефон RakNet-пакетом, находим и нажимаем иконку "Налоги" по
-- имени (числовой ID приложений ненадёжен — см. фикс ниже), ждём нужный
-- диалог, кликаем по нему.
--
-- Шаги:
--   1) открыть телефон, найти и нажать иконку "Налоги" на домашнем экране
--   2) в открывшемся приложении найти строку "Оплата всех налогов" и
--      выбрать её — открывается диалог подтверждения
--   3) в диалоге подтверждения нажать кнопку "Оплатить"
--   4) запомнить время оплаты (и сумму, если сервер прислал её в чат)
-- ============================================================

-- ПРАВКА по просьбе пользователя: возвращаем открытие через числовые ID
-- (ID=24, затем ID=5656) — на этом сервере/аккаунте они ведут именно в
-- "Налоги". Поиск иконки "Налоги" по названию (TAX_NEEDLE_APP_ICON) остаётся
-- в sampev.onShowDialog как резервный вариант — если сервер что-то поменяет
-- и эти два ID перестанут вести куда нужно, автоматика всё равно найдёт
-- нужный пункт по тексту, а не сломается молча.
local TAX_STEP_DELAY  = 200
local TAX_TIMEOUT_SEC = 18

local _taxState = 0 -- 0=простой, 1=ждём меню "Оплата всех налогов", 2=ждём диалог подтверждения,
                     -- 3=кнопка "Оплатить" уже нажата, ждём (не дольше _TAX_POST_PAY_WAIT_MS) диалог-
                     -- подтверждение "Успешно"/OK, который сервер иногда присылает ДОПОЛНИТЕЛЬНО —
                     -- см. фикс "надо ещё раз нажать Enter" в sampev.onShowDialog ниже
-- ФИКС (по жалобе "после оплаты налогов надо ещё раз нажать Enter, чтобы
-- закрыть телефон"): раньше _taxState сбрасывался в 0 СРАЗУ после клика по
-- "Оплатить" (внутри onTaxPaymentSuccess), поэтому если сервер присылал
-- ЕЩЁ ОДИН диалог-подтверждение (например "Успешно"/OK) уже ПОСЛЕ этого
-- сброса, автоматика его больше не ждала (см. проверку "_taxState ~= 0" в
-- начале tax-блока sampev.onShowDialog) — такой диалог оставался
-- необработанным, и игроку приходилось нажимать Enter вручную. Теперь
-- после клика "Оплатить" state переходит в 3 вместо немедленного сброса:
-- если за это время придёт ещё один диалог — сами нажимаем его первую
-- кнопку; если за _TAX_POST_PAY_WAIT_MS ничего не пришло, завершаем
-- оплату сами (тем же способом, что и раньше). _taxFinalizeDone защищает
-- от повторного вызова onTaxPaymentSuccess, если оба пути (пришедший
-- диалог и таймаут) сработают почти одновременно.
_TAX_POST_PAY_WAIT_MS = 1200
_taxFinalizeDone = false
-- ── проверка "игрок реально в игре, а не висит на экране логина/
-- регистрации/выбора персонажа": используется ПЕРЕД любым автоматическим
-- запуском оплаты налогов (и при входе, и по таймеру), чтобы скрипт
-- никогда не пытался открыть телефон/отправить диалоговые пакеты, пока
-- персонаж ещё не заспавнен — именно это раньше вызывало краш игры ──
local function isPlayerActuallySpawned()
    local ok, res = pcall(function()
        return sampIsLocalPlayerSpawned and sampIsLocalPlayerSpawned()
    end)
    return ok and res == true
end
local _taxIsAuto = false
-- ФИКС (по жалобе "в логах не показывается сумма оплаты налогов"): раньше
-- onTaxPaymentSuccess вызывалась из обработчика диалогов БЕЗ суммы (только
-- wasAuto), поэтому TX.addEntry/cfg.taxLastPayAmount получали 0 или старое
-- значение с прошлой оплаты. Сумма почти всегда видна прямо в тексте
-- диалога "Оплата всех налогов" (строка вида "... $12 345 ...") — вытаскиваем
-- её оттуда сразу как только видим этот диалог (см. tax-блок в
-- sampev.onShowDialog) и прокидываем во все точки вызова onTaxPaymentSuccess
_taxPendingAmount = 0
-- вытаскивает сумму ($ХХХ) из текста диалога налогов тем же способом, что и
-- разбор чатового сообщения "вы оплатили..." ниже (sampev.onServerMessage)
function extractTaxAmount(text)
    local sumStr = (text or ""):match("%$%s*([%d%s%.,]+)")
    return sumStr and parseGameNumber(sumStr) or 0
end
-- время (os.time()), когда сработает автооплата "при входе" (см. main());
-- nil, если оплата при входе выключена / ещё не запланирована / уже сработала —
-- используется вкладкой "Налоги" для живого обратного отсчёта в секундах
_taxLoginWaitEndTime = nil
-- true, если в этой игровой сессии "оплата при входе" уже отработала —
-- либо реально заплатила, либо была пропущена, т.к. налоги уже были
-- оплачены недавно (см. main()) — используется вкладкой "Налоги", чтобы
-- показать понятный статус вместо "??"
_taxLoginFired = false
-- true, если "оплата при входе" была пропущена именно потому, что налоги
-- уже были оплачены недавно (а не потому что уже реально заплатила сама)
_taxLoginSkippedRecent = false

local function splitTaxLines(text)
    local lines = {}
    for line in ((text or "") .. "\n"):gmatch("(.-)\n") do
        table.insert(lines, line)
    end
    return lines
end

-- открывает телефон и сразу пробует перейти к налогам через два ID подряд:
-- сначала 24 (раздел), затем 5656 (само приложение "Налоги"). Пакеты
-- "launchedApp|N" собираются прямо здесь (без отдельных top-level локалей —
-- в файле и так почти упёрлись в лимит Lua на 200 локальных переменных)
local function openTaxAppDirect()
    -- ФИКС (по жалобе "при повторной оплате меню налогов само не
    -- появляется, приходится открывать вручную"): если с прошлого раза
    -- на экране остался незакрытый диалог/экран телефона (даже несмотря
    -- на закрытие в конце onTaxPaymentSuccess — клиент иногда не успевает
    -- доиграть анимацию, особенно если следующая оплата запускается
    -- почти сразу), пакет "открыть телефон" может прийти на нестандартный
    -- экран, а не на домашний — и поиск иконки "Налоги"/"Банк" ничего не
    -- находит. Явно закрываем текущий диалог ПЕРЕД открытием телефона,
    -- чтобы каждый раз начинать с гарантированно чистого состояния.
    pcall(sampCloseCurrentDialog, -1)
    sendPhoneBytes({220, 0, 80, 64}) -- открыть телефон (домашний экран)
    lua_thread.create(function()
        local function sendLaunchApp(appId)
            local payload = "launchedApp|" .. tostring(appId)
            local pkt = {220, 18, #payload, 0}
            for i = 1, #payload do table.insert(pkt, payload:byte(i)) end
            for _ = 1, 4 do table.insert(pkt, 0) end
            sendPhoneBytes(pkt)
        end
        wait(150)
        sendLaunchApp(24)   -- раздел
        wait(150)
        sendLaunchApp(5656) -- приложение "Налоги"
    end)
end

-- ============================================================
--  ХРАНЕНИЕ ЛОГОВ (по просьбе): и лог оплат налогов (TX ниже), и лог
--  дохода PayDay/депозита (PD дальше по файлу) хранятся не вечно, а
--  только последние LOG_RETENTION_DAYS дней — при каждой загрузке лога
--  и при каждой новой записи более старые строки удаляются и из памяти
--  (St.taxEntries / St.incomeEntries), и из файла на диске. Оба лога
--  лежат в CFG_DIR (moonloader/config/PCStats/...), то есть в отдельных
--  файлах, а не в самом .lua.
-- ============================================================
-- ФИКС "more than 200 local variables": объявлены глобальными (без local) —
-- файл уже близок к лимиту Lua 5.1 в 200 локальных переменных верхнего
-- уровня, лишние локальные здесь были бы избыточны.
LOG_RETENTION_DAYS = 30

-- переводит дату "YYYY-MM-DD" (как её пишут TX/PD) в os.time() на полдень
-- этого дня — возвращает nil, если строка не распознана как дата
function pcs_dateToEpoch(dateStr)
    if type(dateStr) ~= "string" then return nil end
    local y, m, d = dateStr:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
    if not y then return nil end
    local ok, t = pcall(os.time, {
        year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12,
    })
    if ok and type(t) == "number" then return t end
    return nil
end

-- true, если запись с такой датой не старше maxDays дней (нераспознанную
-- дату не трогаем — считаем свежей, чтобы битая строка не удаляла лог)
function pcs_isEntryFresh(dateStr, maxDays)
    local ep = pcs_dateToEpoch(dateStr)
    if not ep then return true end
    return (os.time() - ep) <= (maxDays * 86400)
end

-- ============================================================
--  ЛОГ ОПЛАТ НАЛОГОВ (по просьбе: свой персистентный лог + календарь,
--  тем же способом, что и лог дохода PayDay — см. таблицу PD ниже) ──
-- ============================================================
local TX = {}
TX.LOG_FILE        = CFG_DIR .. "/tax_log.txt"
TX.MAX_ENTRIES_MEM = 2000
TX.MAX_LINES_FILE  = 3000
St.taxEntries = St.taxEntries or {} -- {date="YYYY-MM-DD", time="HH:MM", amount, auto=true/false}, новые сверху
St.taxLogLoaded = false

function TX.loadLog()
    St.taxEntries = {}
    local allLines = readLogTail(TX.LOG_FILE, TX.MAX_LINES_FILE, 40)
    if #allLines > TX.MAX_LINES_FILE then
        local keepFrom = #allLines - TX.MAX_LINES_FILE + 1
        local trimmed = {}
        for i = keepFrom, #allLines do trimmed[#trimmed+1] = allLines[i] end
        allLines = trimmed
        pcall(function()
            ensureCfgDir()
            local out = io.open(TX.LOG_FILE, "w")
            if out then
                for _, ln in ipairs(allLines) do out:write(ln, "\n") end
                out:close()
            end
        end)
    end
    -- формат строки: "YYYY-MM-DD|HH:MM|amount|auto(0/1)|noTax(0/1, необязательно)"
    -- ФИКС (по просьбе "чтоб в логах тоже писало что нет налогов"): пятое
    -- поле добавлено НЕОБЯЗАТЕЛЬНЫМ — старые строки в файле (без него)
    -- по-прежнему читаются нормально, просто считаются обычной оплатой
    for i = #allLines, 1, -1 do
        local d, t, amt, auto, noTax = allLines[i]:match(
            "^(%d%d%d%d%-%d%d%-%d%d)|(%d%d:%d%d)|(-?%d+)|([01])|([01])$")
        if not d then
            d, t, amt, auto = allLines[i]:match(
                "^(%d%d%d%d%-%d%d%-%d%d)|(%d%d:%d%d)|(-?%d+)|([01])$")
        end
        if d then
            table.insert(St.taxEntries, {
                date = d, time = t, amount = tonumber(amt) or 0, auto = (auto == "1"),
                noTax = (noTax == "1"),
            })
            if #St.taxEntries >= TX.MAX_ENTRIES_MEM then break end
        end
    end
    St.taxLogLoaded = true
    TX.pruneOld()
end

-- убирает из St.taxEntries (и, если что-то реально удалено, перезаписывает
-- сам файл на диске) записи старше LOG_RETENTION_DAYS дней — вызывается и
-- при загрузке лога, и при каждой новой записи, так что старьё чистится
-- само, без ручных действий
function TX.pruneOld()
    local removed = false
    for i = #St.taxEntries, 1, -1 do
        if not pcs_isEntryFresh(St.taxEntries[i].date, LOG_RETENTION_DAYS) then
            table.remove(St.taxEntries, i)
            removed = true
        end
    end
    if not removed then return end
    pcall(function()
        ensureCfgDir()
        local out = io.open(TX.LOG_FILE, "w")
        if out then
            -- St.taxEntries хранит новые сверху — на диске пишем в
            -- хронологическом порядке (как и раньше делал append)
            for i = #St.taxEntries, 1, -1 do
                local e = St.taxEntries[i]
                out:write(e.date .. "|" .. e.time .. "|" .. e.amount .. "|" ..
                    (e.auto and "1" or "0") .. "|" .. (e.noTax and "1" or "0") .. "\n")
            end
            out:close()
        end
    end)
end

-- добавляет одну запись об оплате налогов (или отметку "налогов не было",
-- если isNoTax=true) в память и дописывает в файл на диске
function TX.addEntry(isAuto, amount, isNoTax)
    if not St.taxLogLoaded then TX.loadLog() end
    amount = math.floor((amount or 0) + 0.5)
    local d = os.date("%Y-%m-%d")
    local t = os.date("%H:%M")
    table.insert(St.taxEntries, 1, {
        date = d, time = t, amount = amount, auto = isAuto and true or false,
        noTax = isNoTax and true or false,
    })
    while #St.taxEntries > TX.MAX_ENTRIES_MEM do table.remove(St.taxEntries) end
    pcall(function()
        ensureCfgDir()
        local f = io.open(TX.LOG_FILE, "a")
        if f then
            f:write(d .. "|" .. t .. "|" .. amount .. "|" .. (isAuto and "1" or "0") ..
                "|" .. (isNoTax and "1" or "0") .. "\n")
            f:close()
        end
    end)
    TX.pruneOld()
end

-- фиксирует успешную оплату (своей учётки), обновляет время/сумму последней оплаты
local function onTaxPaymentSuccess(isAuto, amount)
    -- ФИКС: защита от двойного выполнения — см. _taxFinalizeDone и
    -- _taxState=3 выше (может быть вызвана и обработчиком доп. диалога-
    -- подтверждения, и таймаутом ожидания этого диалога)
    if _taxFinalizeDone then return end
    _taxFinalizeDone = true
    cfg.taxLastPayTime   = os.time()
    if amount and amount > 0 then cfg.taxLastPayAmount = amount end
    saveCfg()
    -- ── по просьбе: красивее оформленное сообщение об оплате в чат — рамка
    -- из символов + сумма отдельной строкой золотым цветом + способ оплаты ──
    pcall(sampAddChatMessage, "{00FF88}\xe2\x94\x81\xe2\x94\x81\xe2\x94\x81\xe2\x94\x81\xe2\x94\x81\xe2\x94\x81\xe2\x94\x81\xe2\x94\x81\xe2\x94\x81\xe2\x94\x81\xe2\x94\x81\xe2\x94\x81\xe2\x94\x81\xe2\x94\x81", -1)
    pcall(sampAddChatMessage, "{00FF88}[PC Stats] \xe2\x9c\x85 " ..
        "\xcd\xe0\xeb\xee\xe3\xe8\x20\xf3\xf1\xef\xe5\xf8\xed\xee\x20\xee\xef\xeb\xe0\xf7\xe5\xed\xfb\x21", -1)
    if cfg.taxLastPayAmount and cfg.taxLastPayAmount > 0 then
        pcall(sampAddChatMessage, "{FFD700}  \xd1\xf3\xec\xec\xe0\x3a " ..
            fmtMoney(string.format("%.0f", cfg.taxLastPayAmount)), -1)
    end
    -- строка "Способ: ..." убрана по просьбе — она смешивала сырые
    -- CP1251-байты с u8()-конвертированным текстом (u8() ожидает UTF-8
    -- на входе, а тут ему передавали уже готовые CP1251-байты), из-за
    -- чего в чате вместо слова "автоматически"/"вручную" выводились
    -- каракули
    pcall(sampAddChatMessage, "{00FF88}\xe2\x94\x81\xe2\x94\x81\xe2\x94\x81\xe2\x94\x81\xe2\x94\x81\xe2\x94\x81\xe2\x94\x81\xe2\x94\x81\xe2\x94\x81\xe2\x94\x81\xe2\x94\x81\xe2\x94\x81\xe2\x94\x81\xe2\x94\x81", -1)
    pcall(function()
        local msg = u8"\xcd\xe0\xeb\xee\xe3\xe8\x20\xf3\xf1\xef\xe5\xf8\xed\xee\x20\xee\xef\xeb\xe0\xf7\xe5\xed\xfb\x21"
        if cfg.taxLastPayAmount and cfg.taxLastPayAmount > 0 then
            msg = msg .. "  (" .. fmtMoney(string.format("%.0f", cfg.taxLastPayAmount)) .. ")"
        end
        pcs_notify(msg, "success")
    end)
    _taxState = 0
    _taxExpectedDialogId = nil
    TX.addEntry(isAuto, amount or cfg.taxLastPayAmount or 0)
    -- ФИКС "крашит игру, если сразу после оплаты налогов делать что-то с
    -- криптой": раньше _phoneOpBusy сбрасывался в false СРАЗУ здесь, а
    -- реальная очистка телефона (программный Esc/закрытие диалога) шла
    -- ПОЗЖЕ, в отдельном потоке ниже (ещё 400+150мс). Если за это время
    -- игрок или автообновление курса успевали запустить fetchRatesViaCEF()
    -- / открыть "Криптовалюту", RakNet-пакеты "открыть телефон/приложение"
    -- уходили, пока клиент ещё доигрывал закрытие ПРЕДЫДУЩЕГО диалога
    -- налогов — два параллельных состояния телефона путались на клиенте
    -- и роняли игру. Теперь _phoneOpBusy держит замок до самого конца
    -- этой очистки (см. конец потока ниже), а не снимается заранее ──
    -- ── по просьбе: после оплаты скрипт сам "нажимает Esc" (программно
    -- закрывает диалог) один раз, чтобы телефон не оставался висеть на
    -- экране поверх интерфейса игрока — тот же приём, что и в фетче
    -- курса валют выше (sampCloseCurrentDialog(-1) с небольшой паузой,
    -- т.к. игра может ещё показывать экран-подтверждение оплаты) ──
    lua_thread.create(function()
        wait(400)
        pcall(sampCloseCurrentDialog, -1)
        wait(150)
        pcall(sampCloseCurrentDialog, -1)
        -- доп. пауза "на остывание" телефона перед тем, как разрешить
        -- следующую операцию (крипту/повторную оплату) — без неё клиент
        -- иногда не успевал доиграть анимацию закрытия предыдущего диалога
        wait(250)
        _phoneOpBusy = false -- телефон освободился, курс валют теперь можно обновлять
    end)
end

-- запускает оплату: открывает телефон/приложение и переводит state-машину
-- в режим ожидания (см. tax-блок внутри sampev.onShowDialog ниже)
-- ФИКС (по просьбе): жёсткая нижняя граница между двумя автооплатами —
-- 1 час, НЕЗАВИСИМО от cfg.taxAutoIntervalHours и от того, что именно
-- запустило оплату (таймер автооплаты, оплата при входе). Раньше при
-- перезапуске скрипта поток "оплата при входе" стартовал заново и мог
-- решить, что налоги нужно оплатить снова, если что-то в его собственных
-- флагах (не в cfg — cfg переживает обновление) сбилось. Эта проверка —
-- финальная страховка внутри самой payTaxesNow, а не только в потоке,
-- который её вызывает.
TAX_MIN_REPAY_SEC = 3600 -- глобальная (см. фикс "200 local variables" выше)
local function payTaxesNow(isAuto)
    if isAuto and cfg.taxLastPayTime and cfg.taxLastPayTime ~= 0
        and (os.time() - cfg.taxLastPayTime) < TAX_MIN_REPAY_SEC then
        -- налоги уже точно оплачивались меньше часа назад — тихо
        -- пропускаем, не открывая телефон и не трогая _taxState
        return
    end
    if _taxState ~= 0 then
        if not isAuto then
            pcall(sampAddChatMessage, "{FF6666}[PC Stats] " ..
                "\xd3\xe6\xe5\x20\xe2\xfb\xef\xee\xeb\xed\xff\xe5\xf2\xf1\xff\x2c\x20\xef\xee\xe4\xee\xe6\xe4\xe8\x2e", -1)
            pcall(pcs_notify, u8"\xd3\xe6\xe5\x20\xe2\xfb\xef\xee\xeb\xed\xff\xe5\xf2\xf1\xff\x2c\x20\xef\xee\xe4\xee\xe6\xe4\xe8\x2e", "warning")
        end
        return
    end
    -- ФИКС "крашит игру": не трогаем телефон, если он сейчас занят другой
    -- операцией (например, обновляется курс валют) — см. _phoneOpBusy выше.
    -- Для автооплаты просто тихо пропускаем этот цикл — фоновый поток
    -- проверяет условие раз в минуту и попробует снова на следующем круге ──
    if _phoneOpBusy then
        if not isAuto then
            pcall(sampAddChatMessage, "{FF6666}[PC Stats] " ..
                "\xd2\xe5\xeb\xe5\xf4\xee\xed\x20\xe7\xe0\xed\xff\xf2\x20\xe4\xf0\xf3\xe3\xee\xe9\x20\xee\xef\xe5\xf0\xe0\xf6\xe8\xe5\xe9\x2c\x20\xef\xee\xef\xf0\xee\xe1\xf3\xe9\xf2\xe5\x20\xf7\xe5\xf0\xe5\xe7\x20\xef\xe0\xf0\xf3\x20\xf1\xe5\xea\xf3\xed\xe4", -1)
            pcall(pcs_notify, u8"\xd2\xe5\xeb\xe5\xf4\xee\xed\x20\xe7\xe0\xed\xff\xf2\x20\xe4\xf0\xf3\xe3\xee\xe9\x20\xee\xef\xe5\xf0\xe0\xf6\xe8\xe5\xe9\x2c\x20\xef\xee\xef\xf0\xee\xe1\xf3\xe9\xf2\xe5\x20\xf7\xe5\xf0\xe5\xe7\x20\xef\xe0\xf0\xf3\x20\xf1\xe5\xea\xf3\xed\xe4", "warning")
        end
        return
    end
    -- ФИКС "крашит игру": финальная защита на случай, если payTaxesNow
    -- будет вызвана каким-то другим путём, помимо двух фоновых потоков
    -- выше (у них уже есть собственная проверка) — никогда не открываем
    -- телефон, если персонаж реально не заспавнен (экран логина/
    -- регистрации/выбора персонажа) ──
    if not isPlayerActuallySpawned() then
        if not isAuto then
            pcall(sampAddChatMessage, "{FF6666}[PC Stats] " ..
                "\xed\xe5\xeb\xfc\xe7\xff\x20\xee\xef\xeb\xe0\xf2\xe8\xf2\xfc\x20\xed\xe0\xeb\xee\xe3\xe8\x20\xe4\xee\x20\xf1\xef\xe0\xe2\xed\xe0\x20\xef\xe5\xf0\xf1\xee\xed\xe0\xe6\xe0", -1)
        end
        return
    end
    _taxIsAuto = isAuto
    _phoneOpBusy = true
    St._phoneOpBusySince = os.time()
    _taxState  = 1
    _taxNavAttempts = 0
    _taxFinalizeDone = false
    _taxPendingAmount = 0
    local okOpen = pcall(openTaxAppDirect)
    if not okOpen then
        _taxState = 0
        _taxExpectedDialogId = nil
        _phoneOpBusy = false
        pcall(sampAddChatMessage, "{FF6666}[PC Stats] " ..
            "\xed\xe5\x20\xf3\xe4\xe0\xeb\xee\xf1\xfc\x20\xee\xf2\xea\xf0\xfb\xf2\xfc\x20\xef\xf0\xe8\xeb\xee\xe6\xe5\xed\xe8\xe5\x20\xcd\xe0\xeb\xee\xe3\xe8\x20\xe2\x20\xf2\xe5\xeb\xe5\xf4\xee\xed\xe5", -1)
        pcall(pcs_notify, u8"\xed\xe5\x20\xf3\xe4\xe0\xeb\xee\xf1\xfc\x20\xee\xf2\xea\xf0\xfb\xf2\xfc\x20\xef\xf0\xe8\xeb\xee\xe6\xe5\xed\xe8\xe5\x20\xcd\xe0\xeb\xee\xe3\xe8\x20\xe2\x20\xf2\xe5\xeb\xe5\xf4\xee\xed\xe5", "error")
        return
    end
    lua_thread.create(function()
        local waited = 0
        local resent = false
        while _taxState ~= 0 and waited < TAX_TIMEOUT_SEC * 1000 do
            wait(100); waited = waited + 100
            -- ── ФИКС "открывает телефон, но не открывает меню": если за
            -- половину таймаута от сервера не пришло НИ ОДНОГО диалога
            -- (значит и _taxState всё ещё =1, и ни один onShowDialog не
            -- переключил его хотя бы на =2), скорее всего первый пакет
            -- открытия телефона потерялся (CEF телефона не успел
            -- инициализироваться) — пробуем открыть телефон ЕЩЁ РАЗ один
            -- раз, не дожидаясь полного провала ──
            if not resent and _taxState == 1 and waited >= math.floor(TAX_TIMEOUT_SEC * 1000 / 2) then
                resent = true
                pcall(openTaxAppDirect)
            end
        end
        if _taxState ~= 0 then
            _taxState = 0
            _taxExpectedDialogId = nil
            pcall(sampAddChatMessage, "{FF6666}[PC Stats] " ..
                "\xed\xe0\xeb\xee\xe3\xee\xe2\xfb\xe9\x20\xec\xe5\xed\xfe\x20\xed\xe5\x20\xee\xf2\xea\xf0\xfb\xeb\xf1\xff\x20\xe2\xee\xe2\xf0\xe5\xec\xff", -1)
            pcall(pcs_notify, u8"\xed\xe0\xeb\xee\xe3\xee\xe2\xfb\xe9\x20\xec\xe5\xed\xfe\x20\xed\xe5\x20\xee\xf2\xea\xf0\xfb\xeb\xf1\xff\x20\xe2\xee\xe2\xf0\xe5\xec\xff", "error")
            -- ФИКС: не отпускаем замок телефона мгновенно — пробуем закрыть
            -- то, что могло зависнуть на экране, и только потом, с паузой,
            -- снимаем блокировку (тот же приём, что и в onTaxPaymentSuccess)
            pcall(sampCloseCurrentDialog, -1)
            wait(150)
            pcall(sampCloseCurrentDialog, -1)
            wait(250)
            _phoneOpBusy = false
        end
    end)
end

-- ---- ключевые слова для распознавания диалогов/сообщений (raw CP1251,
-- т.к. игра присылает текст диалогов и чата "как есть", БЕЗ конвертации) ----
local TAX_NEEDLE_PAY_ALL = "\xce\xef\xeb\xe0\xf2\xe0\x20\xe2\xf1\xe5\xf5\x20\xed\xe0\xeb\xee\xe3\xee\xe2" -- "Оплата всех налогов"
local TAX_NEEDLE_PAY_BTN = "\xce\xef\xeb\xe0\xf2\xe8\xf2\xfc" -- "Оплатить"
-- ФИКС (по просьбе): если сам диалог "Оплата всех налогов" открылся, но
-- внутри него сервер написал "У вас нет налогов, которые требуется
-- оплатить" (кнопки "Оплатить" нет вообще) — раньше это молча попадало в
-- общее "не нашёл кнопку Оплатить" ниже. Теперь такой текст распознаётся
-- отдельно и в чат уходит ТО ЖЕ сообщение, что видно в самом меню, а не
-- обезличенная техническая ошибка.
local TAX_NEEDLE_NO_TAX = "\xed\xe5\xf2\x20\xed\xe0\xeb\xee\xe3\xee\xe2" -- "нет налогов"
-- ── имя иконки приложения "Налоги" на главном экране телефона — телефон
-- всегда открывается на домашнем экране (см. фикс с Банковским ID=24 выше),
-- поэтому скрипт ищет и нажимает эту иконку прямо в списке диалога, так
-- же, как это делает игрок вручную ──
local TAX_NEEDLE_APP_ICON = "\xcd\xe0\xeb\xee\xe3" -- "Налог" (иконка "Налоги")
-- ФИКС (по жалобе "приходится самому открывать Банк, потом уже налоги"):
-- если сервер перенёс раздел "Налоги" внутрь папки "Банк", прямой поиск
-- "Налог" на домашнем экране ничего не найдёт — тогда как резервный шаг
-- ищем и нажимаем именно "Банк" (см. использование ниже, в sampev.onShowDialog)
local BANK_NEEDLE_APP_ICON = "\xc1\xe0\xed\xea" -- "Банк"
-- ФИКС (по жалобе "скрипт открывает оплату штрафов на авто вместо
-- налогов"): пункт "Штрафы" может встретиться в том же списке, что и
-- "Налог"/"Банк" (домашний экран телефона, папка "Банк" и т.п.) —
-- резервная навигация по иконкам НИКОГДА не должна нажимать на строку,
-- где есть это слово, даже если в ней случайно тоже встретится "Налог"
-- как часть более длинного описания
TAX_NEEDLE_FINE = "\xd8\xf2\xf0\xe0\xf4" -- "Штраф"
local TAX_NAV_MAX_ATTEMPTS = 5 -- сколько раз пробуем кликнуть по иконке/пунктам меню, прежде чем сдаться
local _taxNavAttempts = 0
-- ФИКС (п.19): id диалога, который сейчас реально ожидается (устанавливается
-- при переходе _taxState -> 2), и флаг "ответ в этот диалог уже отправлен" —
-- защита от гонки с чужими диалогами (другой скрипт/сервер) и от повторной
-- отправки ответа в один и тот же диалог
local _taxExpectedDialogId = nil
local _taxAnsweredThisDialog = false
local TAX_WORD    = "\xed\xe0\xeb\xee\xe3" -- "налог"
local PAID_WORD   = "\xee\xef\xeb\xe0\xf2\xe8\xeb" -- "оплатил" (оплатил/оплатили/оплатила)

-- ФИКС (по просьбе "удали только систему оплаты отеля"): вся система
-- автопродления/оплаты отеля (автооплата по таймеру, лог продлений,
-- state-машина диалога телефона, парсинг вариантов продления и сама
-- payHotelNow/HT) удалена целиком. Отображение полей "Отель"/"Комната"
-- из /stats (см. p.hotel/p.hotelRoom и dataRow выше по файлу) —
-- отдельная чисто информационная функциональность, она не затронута.
function payTaxesThenHotel(isAuto)
    payTaxesNow(isAuto)
end

-- ============================================================
--  Š£Š§Š‘Š¢ Š”Š�Š¥ŠŠŠ PAYDAY (Š·Š°Ń€ŠæŠ»Š°Ń‚Š°/Š´ŠµŠæŠ¾Š·ŠøŃ‚/Š°ŠŗŃ�Ń‹/AZ ŠøŠ· Ń‡Š°Ń‚Š°)
-- ------------------------------------------------------------
-- Каждые ~30 минут сервер шлёт в чат блок из нескольких строк подряд
-- ("БАНКОВСКИЙ ЧЕК ..."). Копим их построчно в буфер (как и в блоке
-- налогов выше), а через 600мс паузы без новых строк блока — считаем
-- блок завершённым, разбираем накопленные значения и добавляем запись
-- в лог дохода (вкладка "Финансы"). Ключевые слова снова заданы raw
-- CP1251-байтами (см. комментарий про TAX_WORD/PAID_WORD выше) —
-- сравниваются они с текстом чата как есть, БЕЗ конвертации.
--
-- ВАЖНО про структуру: всё содержимое (константы, буфер, функции)
-- намеренно сложено в ОДНУ новую локальную таблицу PD, а не объявлено
-- отдельными "local"-ами/"local function" — компилятор Lua 5.1/LuaJIT
-- ограничивает главный чанк 200 активными локальными переменными
-- (см. существующий комментарий у St про лимит апвэлью), а этот файл
-- уже был близко к пределу. Один "local PD = {}" вместо 17 отдельных
-- локальных не расходует лишние слоты.
local PD = {}
PD.HEADER   = "\xc1\xc0\xcd\xca\xce\xc2\xd1\xca\xc8\xc9\x20\xd7\xc5\xca" -- "БАНКОВСКИЙ ЧЕК"
PD.DEP_WORD = "\xd2\xe5\xea\xf3\xf9\xe0\xff\x20\xf1\xf3\xec\xec\xe0\x20\xed\xe0\x20\xe4\xe5\xef\xee\xe7\xe8\xf2\xe5" -- "Текущая сумма на депозите"
PD.SAL_WORD = "\xce\xe1\xf9\xe0\xff\x20\xe7\xe0\xf0\xe0\xe1\xee\xf2\xed\xe0\xff\x20\xef\xeb\xe0\xf2\xe0" -- "Общая заработная плата"
PD.AZ_WORD  = "\xc1\xe0\xeb\xe0\xed\xf1\x20\xed\xe0\x20\xe4\xee\xed\xe0\xf2" -- "Баланс на донат" (без дефиса — дефис не нужен для plain-поиска)
PD.GOT_WORD = "\xc2\xfb\x20\xef\xee\xeb\xf3\xf7\xe8\xeb\xe8" -- "Вы получили"
-- ФИКС (по жалобе "ЗП и ДП не показываются"): формулировки PayDay-чека на
-- сервере могли слегка измениться (заглавные/строчные буквы, "Зарплата"
-- вместо "Общая заработная плата" и т.п.) — раньше find() по единственной
-- точной фразе молча переставал находить совпадение НАВСЕГДА, без единой
-- ошибки в чате или консоли. Теперь для заголовка/зарплаты/депозита
-- проверяется НЕСКОЛЬКО вероятных вариантов формулировки, регистронезависимо
-- (через cp1251Lower). Если реальный текст на сервере отличается ещё
-- сильнее — см. PD._debugUnmatched ниже, он подскажет точный текст.
PD.HEADER_ALTS = {
    PD.HEADER,
    "\xc1\xe0\xed\xea\xee\xe2\xf1\xea\xe8\xe9\x20\xf7\xe5\xea", -- "Банковский чек"
}
PD.SAL_WORD_ALTS = {
    PD.SAL_WORD,
    "\xe7\xe0\xf0\xe0\xe1\xee\xf2\xed\xe0\xff\x20\xef\xeb\xe0\xf2\xe0", -- "заработная плата"
    "\xe7\xe0\xf0\xef\xeb\xe0\xf2\xe0", -- "зарплата"
}
PD.DEP_WORD_ALTS = {
    PD.DEP_WORD,
    "\xf1\xf3\xec\xec\xe0\x20\xed\xe0\x20\xe4\xe5\xef\xee\xe7\xe8\xf2\xe5", -- "сумма на депозите"
    "\xe4\xe5\xef\xee\xe7\xe8\xf2", -- "депозит" (последний, самый широкий вариант)
}
-- ищет ЛЮБУЮ из альтернатив в тексте, регистронезависимо (CP1251)
local function pdFindAny(lowClean, alts)
    for _, w in ipairs(alts) do
        if lowClean:find(cp1251Lower(w), 1, true) then return true end
    end
    return false
end
-- ФИКС: если PayDay-чек пришёл (сработал PD.HEADER_ALTS), но НИ зарплата,
-- НИ депозит ни разу не распознались за весь блок — разово (не чаще раза
-- в минуту) пишем в чат ПЕРВУЮ непонятую строку блока как есть, чтобы было
-- видно точный текст для дальнейшей донастройки без догадок
PD._lastDebugTime = 0
local function pdDebugUnmatched(rawLine)
    local nowT = os.time()
    if nowT - (PD._lastDebugTime or 0) < 60 then return end
    PD._lastDebugTime = nowT
    pcall(sampAddChatMessage, "{FFAA00}[PC Stats DBG] " ..
        "\xed\xe5\x20\xf0\xe0\xf1\xef\xee\xe7\xed\xe0\xeb\x20\xf1\xf2\xf0\xee\xea\xf3\x20\xf7\xe5\xea\xe0\x3a\x20" .. tostring(rawLine), -1)
end
-- ФИКС "не считает доход с дивидендного договора": сервер шлёт эту
-- строку САМА ПО СЕБЕ (не внутри блока "БАНКОВСКИЙ ЧЕК"), поэтому
-- старый код никогда её не видел — St._paydayCollecting был выключен,
-- и PD.onLine выходил на первой же проверке. Теперь эта строка
-- распознаётся отдельно, независимо от блока чека (см. PD.onStandaloneLine
-- ниже), поэтому доход с дивидендов начал засчитываться ──
PD.DIV_WORD = "\xc4\xe8\xe2\xe8\xe4\xe5\xed\xf2\xed\xfb\xe9\x20\xe4\xee\xe3\xee\xe2\xee\xf0" -- "Дивидентный договор"

PD.LOG_FILE         = CFG_DIR .. "/income_log.txt"
PD.MAX_ENTRIES_MEM  = 3000 -- сколько последних записей держим в памяти
PD.MAX_LINES_FILE   = 4000 -- при превышении — файл обрезается до последних N строк

St.incomeEntries = St.incomeEntries or {} -- {date="YYYY-MM-DD", time="HH:MM", salary, deposit, aksy, az, total}, новые сверху
St.incomeLoaded  = false
St._paydayBuf        = nil
St._paydayCollecting = false
St._paydayLastLineT  = 0

-- вытаскивает число сразу после "(+" или "(+$" — используется для суммы
-- прироста ("gain") в строках вида "... $2.359.088 (+$50.000)" или
-- "... 340 AZ (+20 AZ)"
-- ФИКС "ДЕПОЗИТ НЕ СЧИТАЕТСЯ": между "+" и цифрами игра ставит значок
-- валюты (не всегда обычный "$", часто отдельный глиф-иконка — как в
-- строке "Текущая сумма на депозите: [иконка]1.005.385.681 (+[иконка]
-- 1.179.544)"). Старый паттерн допускал после "+" только литеральный "$"
-- (необязательный) — если между "+" и цифрой стоял именно глиф-иконка,
-- совпадения не было вообще, explicitG оставался nil, и прирост депозита
-- не засчитывался. Теперь, как и в extractPlusAmount ниже, просто
-- пропускаем любые НЕ-цифры между "+" и первой цифрой.
function PD.extractGainAfterPlus(clean)
    local g = clean:match("%(%+%D-([%d][%d%s,%.]*)")
    return g and parseGameNumber(g) or nil
end

-- первое число в строке (с необязательным "$" перед ним)
function PD.extractFirstNumber(clean)
    local n = clean:match("%$?([%d][%d%s,%.]*)")
    return n and parseGameNumber(n) or nil
end

-- вытаскивает число после "+" в строках вроде "Вы получили +🰢20.000 за
-- Дивидентный договор" — между "+" и цифрами игра ставит значок валюты
-- (не всегда обычный "$", иногда отдельная иконка-глиф), поэтому просто
-- пропускаем НЕ-цифры между "+" и первой цифрой, а не ищем "$" буквально
function PD.extractPlusAmount(clean)
    local n = clean:match("%+%D-([%d][%d%s,%.]*)")
    return n and parseGameNumber(n) or nil
end

-- при первом обращении читает income_log.txt в St.incomeEntries; заодно
-- обрезает файл на диске, если он успел разрастись (например, скрипт
-- стоит месяцами) — иначе загрузка со временем становится всё медленнее
function PD.loadIncomeLog()
    St.incomeEntries = {}
    local allLines = readLogTail(PD.LOG_FILE, PD.MAX_LINES_FILE, 48)
    -- обрезаем файл, если строк накопилось слишком много
    if #allLines > PD.MAX_LINES_FILE then
        local keepFrom = #allLines - PD.MAX_LINES_FILE + 1
        local trimmed = {}
        for i = keepFrom, #allLines do trimmed[#trimmed+1] = allLines[i] end
        allLines = trimmed
        pcall(function()
            ensureCfgDir()
            local out = io.open(PD.LOG_FILE, "w")
            if out then
                for _, ln in ipairs(allLines) do out:write(ln, "\n") end
                out:close()
            end
        end)
    end
    -- парсим строки: "YYYY-MM-DD|HH:MM|salary|deposit|aksy|az" — новые сверху
    for i = #allLines, 1, -1 do
        local d, t, sal, dep, aks, az = allLines[i]:match(
            "^(%d%d%d%d%-%d%d%-%d%d)|(%d%d:%d%d)|(-?%d+)|(-?%d+)|(-?%d+)|(-?%d+)$")
        if d then
            sal = tonumber(sal) or 0; dep = tonumber(dep) or 0
            aks = tonumber(aks) or 0; az  = tonumber(az)  or 0
            table.insert(St.incomeEntries, {
                date = d, time = t, salary = sal, deposit = dep, aksy = aks, az = az,
                total = sal + dep + aks,
            })
            if #St.incomeEntries >= PD.MAX_ENTRIES_MEM then break end
        end
    end
    St.incomeLoaded = true
    PD.pruneOldIncome()
end

-- убирает из St.incomeEntries (зарплата/депозит/акции/АЗ) записи старше
-- LOG_RETENTION_DAYS дней, и если что-то удалено — перезаписывает файл
-- на диске (см. TX.pruneOld выше, та же логика для лога налогов)
function PD.pruneOldIncome()
    local removed = false
    for i = #St.incomeEntries, 1, -1 do
        if not pcs_isEntryFresh(St.incomeEntries[i].date, LOG_RETENTION_DAYS) then
            table.remove(St.incomeEntries, i)
            removed = true
        end
    end
    if not removed then return end
    pcall(function()
        ensureCfgDir()
        local out = io.open(PD.LOG_FILE, "w")
        if out then
            for i = #St.incomeEntries, 1, -1 do
                local e = St.incomeEntries[i]
                out:write(e.date .. "|" .. e.time .. "|" .. e.salary .. "|" ..
                    e.deposit .. "|" .. e.aksy .. "|" .. e.az .. "\n")
            end
            out:close()
        end
    end)
end

-- добавляет одну запись PayDay: сохраняет в память (сверху списка),
-- дописывает строку в лог-файл на диске (append, без перезаписи всего
-- файла) и увеличивает счётчики "за всё время", которые переживают любую
-- будущую обрезку истории
function PD.addIncomeEntry(salary, deposit, aksy, az)
    if not St.incomeLoaded then PD.loadIncomeLog() end
    salary = math.floor((salary or 0) + 0.5)
    deposit = math.floor((deposit or 0) + 0.5)
    aksy = math.floor((aksy or 0) + 0.5)
    az = math.floor((az or 0) + 0.5)
    local total = salary + deposit + aksy
    if total == 0 and az == 0 then return end -- пустой блок, нечего сохранять

    local d = os.date("%Y-%m-%d")
    local t = os.date("%H:%M")
    table.insert(St.incomeEntries, 1, {
        date = d, time = t, salary = salary, deposit = deposit, aksy = aksy, az = az, total = total,
    })
    while #St.incomeEntries > PD.MAX_ENTRIES_MEM do
        table.remove(St.incomeEntries)
    end

    cfg.incomeAllTimeMoney = (cfg.incomeAllTimeMoney or 0) + total
    cfg.incomeAllTimeAZ    = (cfg.incomeAllTimeAZ or 0) + az
    saveCfg()

    -- ── п.8: запоминаем момент последнего PayDay, чтобы фоновый поток
    -- (см. main()) мог предсказать следующий (через ~30 минут, см.
    -- комментарий про интервал сервера в начале модуля PD выше) и
    -- напомнить за 5 минут до него; сбрасываем флаг срабатывания напоминания ──
    St._pdLastEpoch = os.time()
    St._pdReminderFired = false

    -- ФИКС (по просьбе): всплывающее уведомление о получении PayDay
    -- (срабатывает и на обычный чек, и на отдельную строку "Дивидентный
    -- договор" — обе ветки идут через этот единственный choke-point)
    pcall(function()
        local msg = "PayDay: +" .. fmtMoney(string.format("%.0f", total))
        if az > 0 then msg = msg .. "   +" .. fmtInt(az) .. " AZ" end
        pcs_notify(msg, "payday")
    end)

    pcall(function()
        ensureCfgDir()
        local f = io.open(PD.LOG_FILE, "a")
        if f then
            f:write(d .. "|" .. t .. "|" .. salary .. "|" .. deposit .. "|" .. aksy .. "|" .. az .. "\n")
            f:close()
        end
    end)
    PD.pruneOldIncome()
end

-- разбирает одну строку чата как часть блока PayDay; возвращает true,
-- если строка распознана и относится к текущему блоку
function PD.onLine(clean)
    local low = cp1251Lower(clean)
    if pdFindAny(low, PD.HEADER_ALTS) then
        -- ФИКС "ДОХОД ПРИХОДИТ ДВУМЯ СТРОКАМИ": раньше здесь буфер всегда
        -- пересоздавался с нуля ("aksy = 0"), даже если непосредственно
        -- перед этим уже пришла отдельная строка про дивидендный договор
        -- (см. PD.onStandaloneLine ниже) и успела накопить aksy в буфер —
        -- эти деньги затирались и потом дивиденды всё равно писались
        -- отдельной строкой в лог, а не вместе с зарплатой/депозитом.
        -- Теперь существующий буфер (и то, что уже накоплено в aksy)
        -- сохраняется, а не обнуляется.
        St._paydayBuf = St._paydayBuf or { aksy = 0 }
        St._paydayCollecting = true
        St._paydaySawSalary = false
        St._paydaySawDeposit = false
        return true
    end
    if not St._paydayCollecting or not St._paydayBuf then return false end
    local p = St._paydayBuf

    if pdFindAny(low, PD.DEP_WORD_ALTS) then
        -- строка вида "Текущая сумма на депозите: $500.000" показывает
        -- ТЕКУЩИЙ ОСТАТОК на депозите, а не начисленный за этот чек
        -- процент — поэтому старый код (искавший "(+$X)", как у зарплаты)
        -- почти всегда находил 0, и депозит не учитывался вообще.
        -- Теперь: если в строке всё же есть явный прирост "(+$X)" —
        -- используем его; если нет — считаем прирост сами как разницу
        -- между текущим остатком и остатком, замеченным на предыдущем
        -- чеке (сохраняется в cfg.pdLastDepositBalance между сессиями).
        St._paydaySawDeposit = true
        local after     = clean:match(":%s*(.+)$")
        local totalDep  = (after and PD.extractFirstNumber(after)) or PD.extractFirstNumber(clean) or 0
        local explicitG = PD.extractGainAfterPlus(clean)
        if explicitG then
            p.deposit = explicitG
        else
            local prev = cfg.pdLastDepositBalance
            if prev ~= nil and totalDep > prev then
                p.deposit = totalDep - prev
            else
                p.deposit = 0 -- первый запуск скрипта или остаток не увеличился (снятие/без изменений)
            end
        end
        cfg.pdLastDepositBalance = totalDep
        return true
    end
    if pdFindAny(low, PD.SAL_WORD_ALTS) then
        St._paydaySawSalary = true
        local after = clean:match(":%s*(.+)$")
        p.salary = (after and PD.extractFirstNumber(after)) or PD.extractFirstNumber(clean) or 0
        return true
    end
    if clean:find(PD.AZ_WORD, 1, true) then
        p.az = PD.extractGainAfterPlus(clean) or 0
        return true
    end
    if clean:find(PD.GOT_WORD, 1, true) then
        local g = clean:match("%+%$?([%d%s,%.]+)")
        if g then p.aksy = (p.aksy or 0) + (parseGameNumber(g) or 0) end
        return true
    end
    -- ФИКС: строка внутри уже начавшегося чека ("БАНКОВСКИЙ ЧЕК" сработал),
    -- но ни под одно из известных полей не подошла — если ЗП/ДП так и не
    -- нашлись за весь чек, это, скорее всего, значит, что сервер изменил
    -- формулировку сильнее, чем покрывают текущие альтернативы. Один раз
    -- в минуту показываем точный текст строки — чтобы можно было прислать
    -- его и уточнить нужные фразы, вместо гадания.
    if not St._paydaySawSalary and not St._paydaySawDeposit then
        pdDebugUnmatched(clean)
    end
    return false
end

-- разбирает строку чата, которая приходит САМА ПО СЕБЕ, а не частью
-- блока "БАНКОВСКИЙ ЧЕК" (например "Вы получили +20.000 за Дивидентный
-- договор (выдаётся каждый часовой PayDay)") — вызывается независимо от
-- PD.onLine/St._paydayCollecting, поэтому срабатывает в любой момент.
-- ФИКС "ДОХОД ДВУМЯ СТРОКАМИ": раньше эта сумма сразу же писалась в лог
-- отдельной, самостоятельной записью (addIncomeEntry(0,0,amt,0)) — из-за
-- этого один и тот же PayDay мог давать ДВЕ строки в логе: одну с
-- дивидендами и отдельную с зарплатой/депозитом, вместо одной общей.
-- Теперь сумма просто добавляется в тот же буфер, что и зарплата/депозит/
-- донат-баланс, и общий дебаунс-флаш (см. sampev.onServerMessage, 600мс
-- тишины) сведёт всё в одну строку, как и должно быть.
function PD.onStandaloneLine(clean)
    if not clean:find(PD.DIV_WORD, 1, true) then return false end
    local amt = PD.extractPlusAmount(clean)
    if not amt or amt <= 0 then return false end
    if cfg.incomeTrackEnabled == false then return true end
    St._paydayBuf = St._paydayBuf or { aksy = 0 }
    St._paydayBuf.aksy = (St._paydayBuf.aksy or 0) + amt
    return true
end

-- вызывается через 600мс после последней распознанной строки блока —
-- если за это время не пришло новых строк, блок считается завершённым
function PD.flush()
    local p = St._paydayBuf
    St._paydayBuf = nil
    St._paydayCollecting = false
    if not p then return end
    if cfg.incomeTrackEnabled == false then return end
    PD.addIncomeEntry(p.salary or 0, p.deposit or 0, p.aksy or 0, p.az or 0)
end

-- ---- фоновый поток: автооплата по таймеру ----
lua_thread.create(function()
    while true do
        wait(60000) -- раз в минуту — достаточно для часовых интервалов, не грузит

        pcall(function()
            -- ФИКС "крашит игру": та же защита, что и у "Оплаты при
            -- входе" — никогда не пытаемся открыть телефон, пока игрок
            -- реально не заспавнен (например, висит на экране логина/
            -- регистрации/выбора персонажа) ──
            if cfg.taxAutoEnabled and _taxState == 0 and isPlayerActuallySpawned() then
                local intervalSec = cfg.taxAutoIntervalHours * 3600
                if cfg.taxLastPayTime == 0 or (os.time() - cfg.taxLastPayTime) >= intervalSec then
                    pcall(sampAddChatMessage, "{FFD700}[PC Stats] " ..
                        "\xc0\xe2\xf2\xee\xee\xef\xeb\xe0\xf2\xe0\x3a\x20\xe7\xe0\xef\xf3\xf1\xea\xe0\xfe\x20\xee\xef\xeb\xe0\xf2\xf3\x20\xed\xe0\xeb\xee\xe3\xee\xe2\x2e\x2e\x2e", -1)
                    payTaxesNow(true)
                end
            end
        end)

        -- п.8: напоминание "до PayDay осталось 5 минут" — считаем от
        -- времени последнего замеченного PayDay + ~1 час (см. PD.addIncomeEntry)
        pcall(function()
            if cfg.toastEnabled ~= false and cfg.notifyPaydayReminderEnabled ~= false and St._pdLastEpoch then
                -- ФИКС "напоминание за 5 минут до PayDay не работает": тут
                -- был расчёт "+3600" (через час), хотя сам PayDay на
                -- сервере приходит примерно раз в ~30 минут (см. комментарий
                -- в начале модуля PD выше) — окно "осталось <=5 минут"
                -- почти никогда не совпадало с реальным временем следующей
                -- выплаты, поэтому напоминание либо не показывалось вовсе,
                -- либо всплывало в случайный момент.
                local remain = (St._pdLastEpoch + 1800) - os.time()
                if remain > 0 and remain <= 300 and not St._pdReminderFired then
                    St._pdReminderFired = true
                    pcs_notify(u8"\xc4\xee\x20PayDay\x20\xee\xf1\xf2\xe0\xeb\xee\xf1\xfc\x20\x35\x20\xec\xe8\xed\xf3\xf2\x21", "info")
                end
            end
        end)
    end
end)

-- ============================================================
--  Šš Š£Š ŠŠ« Š’ŠŠ›Š®Š¢ ŠŸŠ Š•Š”Š¤Ā  ARZ-WIKI (statichesky snapshot)
-- ------------------------------------------------------------
-- Tablitsa kursov obmena valyut po serveram Arizona RP, sobrannaya
-- s stranitsy arz-wiki.com/arz-rp/articles/currency-exchange/.
-- Znachenie kazhdogo polya - tsena PRODAZHI 1 edinitsy valyuty v SA$
-- (t.e. skolko SA$ igrok poluchit za 1 VC$/BTC/AZ/EUR/ASC).
-- Eto snimok na moment 24.07.2026 - kursy na servere menyayutsya,
-- tak chto tablitsu stoit periodicheski obnovlyat' vruchnuyu so
-- stranitsy vyshe. Ispolzuetsya kak bystryy istochnik kursov, kogda
-- igrok ne hochet otkryvat' telefon (fetchRatesViaCEF).
-- ============================================================
local ARZ_WIKI_RATES = {
    ["Brainburg"]    = { vc=124, btc=64644, az=35000, eur=4622, asc=46000 },
    ["Bumble Bee"]   = { vc=112, btc=63939, az=35000, eur=4445, asc=46000 },
    ["Casa Grande"]  = { vc=112, btc=64660, az=35000, eur=4945, asc=46000 },
    ["Chandler"]     = { vc=129, btc=63120, az=35000, eur=2909, asc=46000 },
    ["Christmas"]    = { vc=112, btc=64652, az=35000, eur=4901, asc=46000 },
    ["Drake"]        = { vc=112, btc=63936, az=35000, eur=4888, asc=46000 },
    ["Faraway"]      = { vc=112, btc=64749, az=35000, eur=4890, asc=46000 },
    ["Gilbert"]      = { vc=112, btc=63910, az=35000, eur=9592, asc=46000 },
    ["Glendale"]     = { vc=112, btc=64436, az=35000, eur=5753, asc=46000 },
    ["Holiday"]      = { vc=112, btc=63120, az=35000, eur=5431, asc=46000 },
    ["Kingman"]      = { vc=112, btc=64791, az=35000, eur=6946, asc=46000 },
    ["Love"]         = { vc=112, btc=64660, az=35000, eur=5122, asc=46000 },
    ["Mesa"]         = { vc=160, btc=64744, az=35000, eur=3538, asc=46000 },
    ["Mirage"]       = { vc=112, btc=64193, az=35000, eur=4959, asc=46000 },
    ["Mobile 1"]     = {         btc=72986, az=35000, eur=5048, asc=46000 },
    ["Mobile 2"]     = {         btc=89441, az=35000, eur=5739, asc=45000 },
    ["Mobile 3"]     = {         btc=66533, az=35000, eur=6439, asc=46000 },
    ["Page"]         = { vc=112, btc=64515, az=35000, eur=4696, asc=46000 },
    ["Payson"]       = { vc=112, btc=64660, az=35000, eur=4820, asc=46000 },
    ["Phoenix"]      = { vc=131, btc=64660, az=35000, eur=1673, asc=46000 },
    ["Prescott"]     = { vc=112, btc=63939, az=35000, eur=5438, asc=46000 },
    ["Queen Creek"]  = { vc=112, btc=64665, az=35000, eur=5393, asc=46000 },
    ["Red Rock"]     = { vc=114, btc=64515, az=35000, eur=3903, asc=46000 },
    ["Saint Rose"]   = { vc=123, btc=63365, az=35000, eur=4844, asc=46000 },
    ["Scottdale"]    = { vc=148, btc=64665, az=35000, eur=2438, asc=46000 },
    ["Sedona"]       = { vc=112, btc=64660, az=35000, eur=4857, asc=46000 },
    ["Show Low"]     = { vc=112, btc=64086, az=35000, eur=6842, asc=46000 },
    ["Space"]        = { vc=112, btc=62933,           eur=4862, asc=46000 },
    ["Sun City"]     = { vc=112, btc=63120, az=35000, eur=5626, asc=46000 },
    ["Surprise"]     = { vc=112, btc=64471, az=35000, eur=4976, asc=46000 },
    ["Tucson"]       = { vc=183, btc=64736, az=35000, eur=2827, asc=46000 },
    ["Vice City"]    = {         btc=97368, az=35000, eur=5048, asc=43000 },
    ["Wednesday"]    = { vc=112, btc=63936, az=35000, eur=3134, asc=46000 },
    ["Winslow"]      = { vc=112, btc=64665, az=35000, eur=6063, asc=46000 },
    ["Yava"]         = { vc=112, btc=63935, az=35000, eur=4485, asc=46000 },
    ["Yuma"]         = { vc=132, btc=64644, az=35000, eur=7238, asc=46000 },
}

-- ── ishet zapis' v ARZ_WIKI_RATES po imeni servera: snachala tochnoe
-- sovpadenie, potom bez ucheta registra, potom po vhozhdeniyu podstroki
-- (na sluchay esli detectArzServerName() vernul chto-to vrode
-- "Arizona Role Play | Tucson" celikom) ──
function findWikiRatesForServer(name)
    if not name or name == "" then return nil, nil end
    if ARZ_WIKI_RATES[name] then return ARZ_WIKI_RATES[name], name end
    local low = name:lower()
    for k, v in pairs(ARZ_WIKI_RATES) do
        if k:lower() == low then return v, k end
    end
    for k, v in pairs(ARZ_WIKI_RATES) do
        if low:find(k:lower(), 1, true) then return v, k end
    end
    return nil, nil
end

-- ── primenyaet naydennye v ARZ_WIKI_RATES kursy k cfg.rateXXX i
-- sootvetstvuyuschim buferam poley vvoda, sohranyaet konfig. silent=true
-- - bez soobscheniy v chat (ispolzuetsya pri tihoy avtozagruzke pri
-- vhode na server) ──
function applyWikiRatesForServer(serverName, silent)
    local r, matched = findWikiRatesForServer(serverName)
    if not r then
        if not silent then
            pcall(sampAddChatMessage, "{FF6666}[Stats] \xe2\x9a\xa0\xef\xb8\x8f " ..
                "\xed\xe5 \xed\xe0\xe9\xe4\xe5\xed\xfb \xea\xf3\xf0\xf1\xfb \xe4\xeb\xff \xf1\xe5\xf0\xe2\xe5\xf0\xe0: " ..
                tostring(serverName or "?"), -1)
        end
        return false
    end
    if r.vc  then cfg.rateVC  = r.vc;  St.rateVCBuf[0]  = math.floor(r.vc  + 0.5) end
    if r.btc then cfg.rateBTC = r.btc; St.rateBTCBuf[0] = math.floor(r.btc + 0.5) end
    if r.az  then cfg.rateAZ  = r.az;  St.rateAZBuf[0]  = math.floor(r.az  + 0.5) end
    if r.eur then cfg.rateEUR = r.eur; St.rateEURBuf[0] = math.floor(r.eur + 0.5) end
    if r.asc then cfg.rateASC = r.asc; St.rateASCBuf[0] = math.floor(r.asc + 0.5) end
    saveCfg()
    if not silent then
        pcall(sampAddChatMessage, "{00FF88}[Stats] \xe2\x9c\x85 " ..
            "\xea\xf3\xf0\xf1\xfb \xe7\xe0\xe3\xf0\xf3\xe6\xe5\xed\xfb \xe4\xeb\xff \xf1\xe5\xf0\xe2\xe5\xf0\xe0 " ..
            tostring(matched) .. " (arz-wiki.com)", -1)
    end
    return true
end

-- ── zagruzhaet kursy iz tablitsy ARZ_WIKI_RATES dlya servera, na
-- kotorom seychas nahoditsya igrok. Esli vklyucheno avtoopredelenie
-- (cfg.vcAutoDetectServer) - server berйтsya cherez detectArzServerName()
-- (nativnaya SAMP-funkciya sampGetCurrentServerName), inache - iz
-- vruchnuyu vvedennogo cfg.vcServerName ──

-- ── определяет текущий сервер Arizona RP, к которому подключён игрок,
-- через нативную SAMP-функцию sampGetCurrentServerName(); используется
-- в панели настроек "Финансы" при включённом автоопределении сервера
-- (cfg.vcAutoDetectServer). Обёрнуто в pcall, чтобы отсутствие функции
-- (например, до подключения к серверу) не приводило к краху скрипта ──
function detectArzServerName()
    if type(sampGetCurrentServerName) ~= "function" then
        return nil
    end
    local ok, name = pcall(sampGetCurrentServerName)
    if not ok or type(name) ~= "string" or name == "" then
        return nil
    end
    -- раньше здесь вырезался "хвост" строки регуляркой ("([%a%-]+)%s*$"),
    -- из-за чего в название сервера попадал мусор вроде "X3" или обрывки
    -- слова "Role Play" — сайт потом не мог сматчить это с настоящим
    -- названием города, и игрок не находился в списке своего сервера.
    -- Вместо этого ищем среди ИЗВЕСТНЫХ названий серверов (см.
    -- ARZ_WIKI_RATES) точное вхождение — так на выходе всегда чистое
    -- "Page"/"Tucson"/etc, независимо от того, что ещё есть в строке.
    local lower = name:lower()
    -- ФИКС (п.22): раньше "лучший" обновлялся только при строго большей
    -- длине needle, а перебор шёл через pairs() (порядок не определён) —
    -- при совпадении длины (например "Mobile" внутри "Mobile 1"/"Mobile 2"/
    -- "Mobile 3") мог "победить" не тот сервер в зависимости от случайного
    -- порядка обхода таблицы. Теперь собираем всех реально совпавших
    -- кандидатов и детерминированно сортируем по длине названия (по
    -- убыванию), берём самое длинное/специфичное совпадение.
    local candidates = {}
    for serverName in pairs(ARZ_WIKI_RATES) do
        local needle = serverName:lower()
        if lower:find(needle, 1, true) then
            candidates[#candidates+1] = serverName
        end
    end
    if #candidates == 0 then return nil end
    table.sort(candidates, function(a, b) return #a > #b end)
    return candidates[1]
end

function fetchArzWikiRates(silent)
    local name = cfg.vcAutoDetectServer and detectArzServerName() or cfg.vcServerName
    return applyWikiRatesForServer(name, silent)
end

-- ── круглый тумблер вкл/выкл: зелёный = включено, красный = выключено ──
local function drawToggleSwitch(id, isOn)
    local w, h2 = S(34), S(18)
    local p  = imgui.GetCursorScreenPos()
    local dl = imgui.GetWindowDrawList()
    imgui.InvisibleButton(id, imgui.ImVec2(w, h2))
    local clicked = imgui.IsItemClicked and imgui.IsItemClicked() or false
    local hovered = imgui.IsItemHovered and imgui.IsItemHovered() or false
    local bgCol
    if isOn then
        bgCol = hovered and iv4(0.30,0.90,0.46,1.0) or iv4(0.20,0.78,0.35,1.0)
    else
        bgCol = hovered and iv4(0.95,0.30,0.30,1.0) or iv4(0.80,0.20,0.20,1.0)
    end
    dl:AddRectFilled(imgui.ImVec2(p.x, p.y), imgui.ImVec2(p.x+w, p.y+h2),
        imgui.ColorConvertFloat4ToU32(bgCol), h2/2)
    dl:AddRect(imgui.ImVec2(p.x, p.y), imgui.ImVec2(p.x+w, p.y+h2),
        imgui.ColorConvertFloat4ToU32(iv4(0,0,0,0.45)), h2/2, 0, 1.4)
    local knobR = h2/2 - 2
    local knobX = isOn and (p.x + w - h2/2) or (p.x + h2/2)
    dl:AddCircleFilled(imgui.ImVec2(knobX, p.y + h2/2), knobR,
        imgui.ColorConvertFloat4ToU32(iv4(1,1,1,0.95)))
    return clicked
end

-- ── skruglenie uglov knopok (ispolzuyetsya tochechno tam, gde nuzhno "krasivee") ──
local function prettyBtnPush(round)
    local n = 0
    if pcall(imgui.PushStyleVar, imgui.StyleVar.FrameRounding, round or 8.0) then n = n + 1 end
    return n
end
local function prettyBtnPop(n)
    if n and n > 0 then pcall(imgui.PopStyleVar, n) end
end

-- ── единый "современный" стиль для всплывающих окон выбора цвета/курса —
-- скруглённые углы + мягкая акцентная рамка вместо стандартных острых
-- углов imgui. Вызывать ПЕРЕД imgui.BeginPopup(...), парную функцию —
-- после imgui.EndPopup() ──
local function pushModernPopupStyle()
    local r,g,b = getAcc()
    local n = 0
    if pcall(imgui.PushStyleVar, imgui.StyleVar.PopupRounding, 14.0) then n = n + 1 end
    if pcall(imgui.PushStyleVar, imgui.StyleVar.PopupBorderSize, 1.4) then n = n + 1 end
    if pcall(imgui.PushStyleVar, imgui.StyleVar.WindowPadding, imgui.ImVec2(16, 14)) then n = n + 1 end
    imgui.PushStyleColor(imgui.Col.PopupBg, iv4(0.08,0.085,0.11,0.99))
    imgui.PushStyleColor(imgui.Col.Border,  iv4(r*0.75,g*0.75,b*0.75,0.85))
    return n
end
local function popModernPopupStyle(n)
    imgui.PopStyleColor(2)
    if n and n > 0 then pcall(imgui.PopStyleVar, n) end
end

-- ============================================================
--  МИНИ-КАЛЕНДАРЬ (общий виджет для лога дохода PayDay и лога оплат
--  налогов) — по просьбе: вместо "неудобной" постраничной пролистки
--  логов, кнопка открывает всплывающее окно с календарём месяца, где
--  дни с записями подсвечены; клик по такому дню выбирает его.
--  Сложено в одну локальную таблицу Cal (а не в отдельные local'ы) по
--  той же причине, что и PD/TX выше — экономия слотов top-level locals ──
-- ============================================================
local Cal = {}
Cal.WD = { -- Пн..Вс, календарь начинается с понедельника
    u8"\xcf\xed", u8"\xc2\xf2", u8"\xd1\xf0", u8"\xd7\xf2", u8"\xcf\xf2", u8"\xd1\xe1", u8"\xc2\xf1",
}
Cal.MONTHS = {
    u8"\xdf\xed\xe2\xe0\xf0\xfc", u8"\xd4\xe5\xe2\xf0\xe0\xeb\xfc", u8"\xcc\xe0\xf0\xf2", u8"\xc0\xef\xf0\xe5\xeb\xfc",
    u8"\xcc\xe0\xe9", u8"\xc8\xfe\xed\xfc", u8"\xc8\xfe\xeb\xfc", u8"\xc0\xe2\xe3\xf3\xf1\xf2",
    u8"\xd1\xe5\xed\xf2\xff\xe1\xf0\xfc", u8"\xce\xea\xf2\xff\xe1\xf0\xfc", u8"\xcd\xee\xff\xe1\xf0\xfc", u8"\xc4\xe5\xea\xe0\xe1\xf0\xfc",
}

function Cal.daysInMonth(y, m)
    local t = os.time({year = y, month = m + 1, day = 0, hour = 12})
    return tonumber(os.date("%d", t))
end

-- день недели 1-го числа месяца, 1=Пн..7=Вс (os.date("%w") даёт 0=Вс..6=Сб)
function Cal.firstWeekdayMonFirst(y, m)
    local t = os.time({year = y, month = m, day = 1, hour = 12})
    local wd = tonumber(os.date("%w", t))
    return (wd == 0) and 7 or wd
end

-- рисует сам грид календаря внутри уже открытого popup/окна.
-- state       — таблица {calY=, calM=} для хранения текущего показанного месяца (переживает между кадрами)
-- markedDates — set {["YYYY-MM-DD"]=true, ...} — какие дни подсвечивать
-- onPickDate  — function(dateStr) вызывается при клике по ПОДСВЕЧЕННОМУ дню
function Cal.draw(state, markedDates, onPickDate)
    local nowY, nowM = tonumber(os.date("%Y")), tonumber(os.date("%m"))
    state.calY = state.calY or nowY
    state.calM = state.calM or nowM
    local r, g, b = getAcc()

    imgui.PushStyleColor(imgui.Col.Button,        iv4(r*0.30,g*0.30,b*0.30,1.0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(r*0.55,g*0.55,b*0.55,1.0))
    imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(r,g,b,1.0))
    if imgui.Button(u8"\xab##calPrevM", imgui.ImVec2(S(26), S(24))) then
        state.calM = state.calM - 1
        if state.calM < 1 then state.calM = 12; state.calY = state.calY - 1 end
    end
    imgui.SameLine(0, S(8))
    imgui.TextColored(iv4(1,1,1,1), Cal.MONTHS[state.calM] .. "  " .. tostring(state.calY))
    imgui.SameLine(0, S(8))
    if imgui.Button(u8"\xbb##calNextM", imgui.ImVec2(S(26), S(24))) then
        state.calM = state.calM + 1
        if state.calM > 12 then state.calM = 1; state.calY = state.calY + 1 end
    end
    imgui.PopStyleColor(3)
    imgui.Spacing()

    local cellW = S(30)
    do
        local p = imgui.GetCursorScreenPos()
        for i = 1, 7 do
            imgui.SetCursorScreenPos(imgui.ImVec2(p.x + (i - 1) * (cellW + S(4)), p.y))
            imgui.TextColored(thDim(), Cal.WD[i])
        end
        imgui.SetCursorScreenPos(imgui.ImVec2(p.x, p.y + S(18)))
    end

    local dim     = Cal.daysInMonth(state.calY, state.calM)
    local startWd = Cal.firstWeekdayMonFirst(state.calY, state.calM)
    local todayStr = os.date("%Y-%m-%d")

    local _spacingPushed = pcall(imgui.PushStyleVar, imgui.StyleVar.ItemSpacing, imgui.ImVec2(S(4), S(4)))
    local col = 0
    for _ = 1, startWd - 1 do
        imgui.Dummy(imgui.ImVec2(cellW, S(24)))
        imgui.SameLine(0, S(4))
        col = col + 1
    end
    for d = 1, dim do
        local dateStr  = string.format("%04d-%02d-%02d", state.calY, state.calM, d)
        local hasData  = markedDates[dateStr] == true
        local isToday  = dateStr == todayStr
        local btnBg    = hasData and iv4(r*0.62,g*0.62,b*0.62,1.0) or iv4(0.14,0.15,0.18,1.0)
        local btnHov   = hasData and iv4(r*0.85,g*0.85,b*0.85,1.0) or iv4(0.22,0.23,0.27,1.0)
        imgui.PushStyleColor(imgui.Col.Button,        btnBg)
        imgui.PushStyleColor(imgui.Col.ButtonHovered, btnHov)
        imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(r,g,b,1.0))
        imgui.PushStyleColor(imgui.Col.Text, isToday and iv4(1,0.92,0.55,1) or (hasData and iv4(1,1,1,1) or iv4(0.55,0.56,0.60,1)))
        if imgui.Button(tostring(d) .. "##calDay" .. dateStr, imgui.ImVec2(cellW, S(24))) and hasData then
            onPickDate(dateStr)
            pcall(imgui.CloseCurrentPopup)
        end
        imgui.PopStyleColor(4)
        col = col + 1
        if col % 7 ~= 0 then imgui.SameLine(0, S(4)) end
    end
    if _spacingPushed then pcall(imgui.PopStyleVar) end
end

-- ── всплывающее окно "Настройки" вкладки "Финансы": вынесено в отдельную
-- функцию, чтобы не раздувать список апвэлью drawTotal (лимит Lua — 60) ──
function drawFinanceSettingsBlock(r, g, b)
    local avW  = imgui.GetContentRegionAvail().x

    -- ── единая кнопка "Настройки" — открывает/закрывает панель настроек
    -- вкладки "Финансы". Панель больше не всплывающий popup, а отдельное
    -- окно, прикреплённое справа от главного окна (см. drawFinanceSettingsPanel).
    -- Цвет кнопки сделан отдельным (нейтрально-серо-голубым), а не акцентным,
    -- чтобы она визуально отличалась от остальных кнопок вкладки ──
    -- цвет кнопки "Настройки" завязан на акцентный цвет темы (r,g,b),
    -- а не на фиксированный серый — чтобы кнопка не выглядела "мёртвой"
    local _fsOn = {r*0.85 + 0.10, g*0.55 + 0.10, b*1.00}
    local _fsAc = {math.min(1,r*1.15), math.min(1,g*1.15), math.min(1,b*1.15)} -- цвет кнопки, когда панель открыта (подсветка)
    local sbc = St._financeSettingsOpen and _fsAc or _fsOn
    imgui.PushStyleColor(imgui.Col.Button,        iv4(sbc[1]*0.55,sbc[2]*0.55,sbc[3]*0.55,1.0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(sbc[1]*0.80,sbc[2]*0.80,sbc[3]*0.80,1.0))
    imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(sbc[1],sbc[2],sbc[3],1.0))
    do local _pb = prettyBtnPush(10.0)
    if imgui.Button(u8"  \xcd\xe0\xf1\xf2\xf0\xee\xe9\xea\xe8##financeSettingsBtn", imgui.ImVec2(avW, S(36))) then
        St._financeSettingsOpen = not St._financeSettingsOpen
    end
    prettyBtnPop(_pb) end
    imgui.PopStyleColor(3)
end

-- ── содержимое панели "Настройки" вкладки "Финансы" — вынесено отдельно
-- от самого окна (drawFinanceSettingsPanel), чтобы окно можно было рисовать
-- вне вкладки "Финансы" (оно теперь отдельное, пристыкованное окно) ──
function drawFinanceSettingsPanelContent(r, g, b)
    imgui.TextColored(thDim(), u8"\xcd\xe0\xf1\xf2\xf0\xee\xe9\xea\xe8 \xe2\xea\xeb\xe0\xe4\xea\xe8 \xab\xd4\xe8\xed\xe0\xed\xf1\xfb\xbb:")
    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()

    -- ── единая кнопка: обновляет и EUR/BTC, и VC$/AZ/EURO/ASC под сервер ──
    imgui.TextColored(iv4(0.70,0.82,1.0,1.0), u8"\xca\xf3\xf0\xf1\xfb \xe2\xe0\xeb\xfe\xf2")
    imgui.Spacing()

    -- ── ручной выбор сервера убран по требованию: сервер теперь всегда
    -- определяется автоматически (по текущему SAMP-серверу), без тумблера ──
    cfg.vcAutoDetectServer = true
    do
        local detectedNow = detectArzServerName()
        if detectedNow then
            imgui.TextColored(iv4(0.5,0.52,0.58,1.0), u8"\xd1\xe5\xf0\xe2\xe5\xf0: ")
            imgui.SameLine(0,4)
            imgui.TextColored(iv4(0.40,0.90,0.55,1.0), detectedNow)
        else
            imgui.TextColored(iv4(0.95,0.55,0.30,1.0), u8"\xd1\xe5\xf0\xe2\xe5\xf0 \xed\xe5 \xee\xef\xf0\xe5\xe4\xe5\xeb\xb8\xed 3 \xe7\xe0\xe9\xe4\xe8\xf2\xe5 \xed\xe0 \xf1\xe5\xf0\xe2\xe5\xf0")
        end
    end
    imgui.Spacing()

    -- ── кнопка "Обновить с телефона": сама открывает игровой телефон и
    -- сразу переключает его на приложение "Криптовалюта" по ID через
    -- RakNet (без блуждания по вкладкам меню — см. openCryptoAppDirect()),
    -- затем читает актуальные курсы прямо из диалога — см. fetchRatesViaCEF()
    -- и sampev.onShowDialog. Найденные значения (и покупка, и продажа)
    -- сразу подставляются в поля ручного ввода курсов (rateInputRow) ниже ──
    do
        local busy2 = _cefFetching
        local phBg = busy2 and {0.85,0.68,0.15} or {0.20,0.65,0.85}
        local phLbl = busy2
            and u8"  \xee\xe1\xed\xee\xe2\xeb\xe5\xed\xe8\xe5..."
            or  u8"  \xce\xe1\xed\xee\xe2\xe8\xf2\xfc \xf1 \xf2\xe5\xeb\xe5\xf4\xee\xed\xe0"
        imgui.PushStyleColor(imgui.Col.Button,        iv4(phBg[1]*0.55,phBg[2]*0.55,phBg[3]*0.55,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(phBg[1]*0.75,phBg[2]*0.75,phBg[3]*0.75,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(phBg[1],phBg[2],phBg[3],1.0))
        do local _pb3 = prettyBtnPush(9.0)
        if imgui.Button(phLbl.."##financeRefPhone", imgui.ImVec2(imgui.GetContentRegionAvail().x, S(32))) then
            fetchRatesViaCEF()
        end
        prettyBtnPop(_pb3) end
        imgui.PopStyleColor(3)
    end
    imgui.Spacing()

    -- ── ручной ввод курсов валют: кнопка открывает всплывающее окно
    -- с полями AZ-Coins/BTC/Евро/VC$/ASC (перенесено сюда с вкладки
    -- "Финансы", раньше был раскрывающийся блок прямо там). Под кнопкой —
    -- статус последнего обновления с телефона и строки "Покупка"/
    -- "Продажа" (те же два числа, что читает CryptoRatesReader со строк
    -- "Текущий курс для покупки/продажи" на экране "Криптовалюта" — см.
    -- parsePhoneRatesText), показываются всегда, без отдельной кнопки-
    -- переключателя ──
    do
        local pr1,pg1,pb1 = getAcc()
        imgui.PushStyleColor(imgui.Col.Button,        iv4(pr1*0.20,pg1*0.20,pb1*0.20,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(pr1*0.34,pg1*0.34,pb1*0.34,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(pr1*0.48,pg1*0.48,pb1*0.48,1.0))
        do local _pbm = prettyBtnPush(9.0)
        if imgui.Button(u8"\x20\x20\xc2\xe2\xe5\xf1\xf2\xe8\x20\xea\xf3\xf0\xf1\x20\xe2\xf0\xf3\xf7\xed\xf3\xfe\x20\x20##openManualRates", imgui.ImVec2(imgui.GetContentRegionAvail().x, S(32))) then
            imgui.OpenPopup("##manualRatesPopup")
        end
        prettyBtnPop(_pbm) end
        imgui.PopStyleColor(3)

        if St._cefLastResult ~= "" or St._phoneBuy or St._phoneSell then
            imgui.Spacing()
            if St._cefLastResult ~= "" then
                imgui.TextColored(iv4(0.5,0.52,0.58,1.0), "  " .. u8(St._cefLastResult))
            end
            if St._phoneBuy then
                imgui.TextColored(iv4(0.55,0.95,0.55,1.0),
                    "  " .. u8"\xcf\xee\xea\xf3\xef\xea\xe0" .. ": $" .. tostring(St._phoneBuy)
                    .. " VS $" .. tostring(St._phoneBuyFor or "-"))
            end
            if St._phoneSell then
                imgui.TextColored(iv4(0.95,0.75,0.35,1.0),
                    "  " .. u8"\xcf\xf0\xee\xe4\xe0\xe6\xe0" .. ": $" .. tostring(St._phoneSell)
                    .. " VS $" .. tostring(St._phoneSellFor or "-"))
            end
            if St._phoneRatesTime then
                imgui.TextColored(iv4(0.5,0.52,0.58,1.0), "  " .. u8"\xce\xe1\xed\xee\xe2\xeb\xe5\xed\xee" .. ": " .. St._phoneRatesTime)
            end
        end

        pcall(imgui.SetNextWindowSize, imgui.ImVec2(S(280), 0), imgui.Cond and imgui.Cond.Appearing or 0)
        local _mps1 = pushModernPopupStyle()
        -- ФИКС: BeginPopup/EndPopup теперь под pcall (тот же класс защиты,
        -- что и у остальных попапов) — раньше здесь не было вообще никакой
        -- защиты, и любая ошибка внутри (например, в rateInputRow) ломала
        -- стек imgui так же, как раньше это делала оплата налогов.
        local began1 = false
        local ok1, err1 = pcall(function()
        if imgui.BeginPopup("##manualRatesPopup") then
            began1 = true
            imgui.TextColored(thDim(), u8"\xca\xf3\xf0\xf1\x20\xe2\xe0\xeb\xfe\xf2\x20\xe2\xf0\xf3\xf7\xed\xf3\xfe\x3a")
            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()
            imgui.PushItemWidth(S(220))
            rateInputRow("az",  "AZ-Coins", St.rateAZBuf,  "rateAZ")
            rateInputRow("btc", "BTC",      St.rateBTCBuf, "rateBTC")
            rateInputRow("eur", CUR_AARP_SHORT, St.rateEURBuf, "rateEUR")
            rateInputRow("vc",  "VC$",       St.rateVCBuf,  "rateVC")
            rateInputRow("asc", u8"\xca\xf3\xf0\xf1 ASC", St.rateASCBuf, "rateASC")
            imgui.PopItemWidth()
            imgui.Spacing()
            do
                local pr2,pg2,pb2 = getAcc()
                imgui.PushStyleColor(imgui.Col.Button,        iv4(pr2*0.22,pg2*0.22,pb2*0.22,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(pr2*0.40,pg2*0.40,pb2*0.40,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(pr2*0.58,pg2*0.58,pb2*0.58,1.0))
                do local _pbd = prettyBtnPush(8.0)
                if imgui.Button(u8"\xc3\xee\xf2\xee\xe2\xee##closeManualRates", imgui.ImVec2(imgui.GetContentRegionAvail().x, S(30))) then
                    imgui.CloseCurrentPopup()
                end
                prettyBtnPop(_pbd) end
                imgui.PopStyleColor(3)
            end
        end
        end) -- конец pcall
        if began1 then pcall(imgui.EndPopup) end
        popModernPopupStyle(_mps1)
        if not ok1 then
            pcall(sampAddChatMessage, "{FF6666}[PC Stats] " ..
                "\xee\xf8\xe8\xe1\xea\xe0\x20\xef\xee\xef\xe0\xef\xe0\x20\xea\xf3\xf0\xf1\xee\xe2: " .. tostring(err1), -1)
        end
    end
    imgui.Dummy(imgui.ImVec2(0, S(4)))

    -- 2) переключить раскладку (список / два столбика)
    imgui.TextColored(iv4(0.70,0.82,1.0,1.0), u8"\xd0\xe0\xf1\xea\xeb\xe0\xe4\xea\xe0")
    imgui.Spacing()
    if drawToggleSwitch("##financeColSw", cfg.financeTwoCol) then
        cfg.financeTwoCol = not cfg.financeTwoCol
        saveCfg()
    end
    imgui.SameLine(0, S(8))
    imgui.TextColored(iv4(0.85,0.87,0.95,1.0), cfg.financeTwoCol
        and u8"\xe4\xe2\xe0 \xf1\xf2\xee\xeb\xe1\xe8\xea\xe0"
        or  u8"\xee\xe1\xfb\xf7\xed\xfb\xe9 \xf1\xef\xe8\xf1\xee\xea")
    imgui.Spacing()
    imgui.Dummy(imgui.ImVec2(0, S(4)))

    -- ── тумблер "Статус на сервере / время в игре" (всплывающее окно
    -- с временем последнего захода и таймером сессии) убран по просьбе —
    -- эта информация теперь и так всегда видна в шапке вкладки "Персонаж" ──

    -- ── АВТО-ОБНОВЛЕНИЕ: поставлен сразу под тумблером "Раскладка", чтобы
    -- оба одиночных тумблера панели шли вместе, одним блоком ──
    imgui.TextColored(iv4(0.70,0.82,1.0,1.0), u8"\xc0\xe2\xf2\xee-\xee\xe1\xed\xee\xe2\xeb\xe5\xed\xe8\xe5")
    imgui.Spacing()
    if drawToggleSwitch("##autoRefreshSw", cfg.autoRefresh) then
        cfg.autoRefresh = not cfg.autoRefresh
        chkBuf[0] = cfg.autoRefresh
        saveCfg()
    end
    imgui.SameLine(0, S(8))
    imgui.TextColored(iv4(1,1,1,1), u8"\xc2\xea\xeb\xfe\xf7\xe8\xf2\xfc")
    imgui.Spacing()
    if cfg.autoRefresh then
        imgui.Dummy(imgui.ImVec2(0, S(6)))
        imgui.TextColored(iv4(0.70,0.82,1.0,1.0), u8"\xc8\xed\xf2\xe5\xf0\xe2\xe0\xeb:")
        imgui.SameLine(0,8)
        imgui.TextColored(iv4(1,1,1,1), cfg.autoInterval..u8" \xf1\xe5\xea")
        do
            imgui.PushStyleColor(imgui.Col.FrameBg,          iv4(r*0.14,g*0.14,b*0.14,1.0))
            imgui.PushStyleColor(imgui.Col.FrameBgHovered,   iv4(r*0.24,g*0.24,b*0.24,1.0))
            imgui.PushStyleColor(imgui.Col.FrameBgActive,    iv4(r*0.35,g*0.35,b*0.35,1.0))
            imgui.PushStyleColor(imgui.Col.SliderGrab,       iv4(r,g,b,1.0))
            imgui.PushStyleColor(imgui.Col.SliderGrabActive, iv4(math.min(1,r*1.2),math.min(1,g*1.2),math.min(1,b*1.2)))
            do local _svc3=0
            if pcall(imgui.PushStyleVar,imgui.StyleVar.FrameRounding,12.0) then _svc3=_svc3+1 end
            if pcall(imgui.PushStyleVar,imgui.StyleVar.GrabRounding,12.0) then _svc3=_svc3+1 end
            if pcall(imgui.PushStyleVar,imgui.StyleVar.GrabMinSize,32.0) then _svc3=_svc3+1 end
            if pcall(imgui.PushStyleVar,imgui.StyleVar.FramePadding,imgui.ImVec2(6, 8)) then _svc3=_svc3+1 end
            if imgui.SliderFloat("##ai2", aBuf, 10.0, 300.0) then
                cfg.autoInterval = math.floor(aBuf[0]+0.5); saveCfg()
            end
            if _svc3>0 then pcall(imgui.PopStyleVar,_svc3) end; end
            imgui.PopStyleColor(5)
        end
    end

    imgui.Spacing()
    imgui.Dummy(imgui.ImVec2(0, S(4)))

    imgui.Spacing()
    imgui.Dummy(imgui.ImVec2(0, S(4)))

    -- 3) выбор категорий для общего итога
    imgui.TextColored(iv4(0.70,0.82,1.0,1.0), u8"\xd7\xf2\xee \xf3\xf7\xe8\xf2\xfb\xe2\xe0\xf2\xfc \xe2 \xab\xc2\xd1\xc5\xc3\xce \xc2\xc8\xd0\xd2\xce\xc2\xbb")
    imgui.Spacing()

    -- ── общий тумблер "Валюты (все)" убран по просьбе — по умолчанию
    -- все категории (включая все 5 валют) и так включены (см. defCfg /
    -- loadCfg выше: incCash..incASC = true по умолчанию), отдельные
    -- тумблеры ниже управляют каждой категорией самостоятельно ──
    imgui.Separator()
    imgui.Spacing()

    local _flt = {
        { u8"\xcd\xe0\xeb\xe8\xf7\xed\xfb\xe5", "incCash" },
        { u8"\xc1\xe0\xed\xea",                  "incBank" },
        { u8"\xc4\xe5\xef\xee\xe7\xe8\xf2",       "incDep"  },
        { u8"\xcb\xe8\xf7\xed\xfb\xe5 \xf1\xf7\xe5\xf2\xe0", "incAcc" },
        { "AZ-Coins", "incAZ"  },
        { "BTC",      "incBTC" },
        { CUR_AARP_SHORT, "incEUR" },
        { "VC$",      "incVC"  },
        { "ASC",      "incASC" },
    }
    for i, fl in ipairs(_flt) do
        local isOn = cfg[fl[2]]
        if drawToggleSwitch("##ftg"..fl[2], isOn) then
            cfg[fl[2]] = not isOn
            saveCfg()
        end
        imgui.SameLine(0, S(8))
        imgui.TextColored(isOn and iv4(0.85,0.95,0.88,1.0) or iv4(0.55,0.55,0.58,1.0), fl[1])
    end

    imgui.Spacing()
    imgui.Dummy(imgui.ImVec2(0, S(4)))
    do
        local pr,pg,pb = getAcc()
        imgui.PushStyleColor(imgui.Col.Button,        iv4(pr*0.22,pg*0.22,pb*0.22,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(pr*0.40,pg*0.40,pb*0.40,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(pr*0.58,pg*0.58,pb*0.58,1.0))
        do local _pbc = prettyBtnPush(8.0)
        if imgui.Button(u8"\xc7\xe0\xea\xf0\xfb\xf2\xfc##closeFinanceSettings", imgui.ImVec2(imgui.GetContentRegionAvail().x, S(30))) then
            St._financeSettingsOpen = false
        end
        prettyBtnPop(_pbc) end
        imgui.PopStyleColor(3)
    end
end

-- ── отдельное окно панели настроек вкладки "Финансы". По умолчанию
-- пристыковано справа от главного окна и двигается вместе с ним; кнопка
-- "Открепить" позволяет носить его отдельно в любом месте экрана ──
local function drawFinanceSettingsPanel()
    if not St._financeSettingsOpen then return end
    if not St._mainWinPos or not St._mainWinSize then return end

    local panelW = S(320)

    -- ФИКС (п.13): SetNextWindowPos/SetNextWindowSize обёрнуты в pcall —
    -- при неожиданном nil в St._mainWinPos/_financeSettingsPos (гонка
    -- между кадрами) они раньше могли упасть ДО imgui.Begin, оставляя
    -- imgui.SetNext* состояние неопределённым на следующий Begin
    if not St._financeSettingsDetached then
        pcall(imgui.SetNextWindowPos, imgui.ImVec2(St._mainWinPos.x + St._mainWinSize.x + S(10), St._mainWinPos.y), imgui.Cond.Always)
        pcall(imgui.SetNextWindowSize, imgui.ImVec2(panelW, St._mainWinSize.y), imgui.Cond.Always)
    else
        pcall(imgui.SetNextWindowSize, imgui.ImVec2(panelW, St._mainWinSize.y), imgui.Cond.Once)
        if _financeSettingsPos then
            pcall(imgui.SetNextWindowPos, imgui.ImVec2(_financeSettingsPos.x, _financeSettingsPos.y), imgui.Cond.Once)
        else
            pcall(imgui.SetNextWindowPos, imgui.ImVec2(St._mainWinPos.x + St._mainWinSize.x + S(10), St._mainWinPos.y), imgui.Cond.Once)
        end
    end

    applyStyle()
    -- ФИКС "ЗАВИСАНИЯ" ФИНАНСОВ: ниже Begin()/End() и всё содержимое между
    -- ними теперь обёрнуты в pcall с гарантированным вызовом End(). Раньше
    -- любая необработанная ошибка внутри drawFinanceSettingsPanelContent
    -- (например, временный nil в курсах валют) прерывала выполнение ДО
    -- imgui.End() — Begin/End оставались "разомкнутыми", и на следующем
    -- кадре это ломало весь imgui-стек: окно вкладки "Финансы" переставало
    -- реагировать (то самое "зависание" при открытии настроек в Финансах).
    -- Теперь Begin/End всегда парные, а паника внутри панели один раз
    -- гасится через pcall и не валит остальной интерфейс.
    -- (NoMove umyshlenno ne ispolzuetsya - Cond.Always vyshe i tak
    -- prinuditelno vozvraschaet okno na mesto kazhdyy kadr, poka ono ne otkrepleno;
    -- NoResize dobavlen, chtoby panel ne menyala razmer ot sluchaynogo peretaskivaniya
    -- za kray i vsegda ostavalas odnogo razmera)
    local flags = imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize
    local beganPanel = false
    local panelOk = pcall(function()
        if not imgui.Begin("###financeSettingsPanel", nil, flags) then return end
        beganPanel = true
        imgui.SetWindowFontScale(St.UI_SCALE * (cfg.fontSize > 0 and cfg.fontSize or 1.25))

        if St._financeSettingsDetached then
            local okP, p = pcall(imgui.GetWindowPos)
            if okP and p then _financeSettingsPos = {x = p.x, y = p.y} end
        end

        -- закрытие панели по Esc теперь целиком обрабатывается в onKeyDown()
        -- (см. ниже) — раньше здесь был свой независимый перехват через
        -- imgui.IsKeyPressed, который конфликтовал с onKeyDown: оба слушателя
        -- реагировали на одно и то же нажатие Esc, но по разным путям, и в
        -- результате первое нажатие закрывало только эту панель, а onKeyDown
        -- не успевал (или не мог) погасить событие для игры, поэтому второе
        -- нажатие Esc долетало до Arizona и открывало её меню паузы поверх
        -- уже закрытого нашего окна. Теперь Esc обрабатывается один раз в
        -- одном месте — это устраняет и двойное нажатие, и утечку в паузу.

        -- ── шапка панели: заголовок + кнопка "Открепить/Закрепить" ──
        do
            local aw = imgui.GetContentRegionAvail().x
            imgui.TextColored(iv4(1,1,1,1), u8"\xcd\xe0\xf1\xf2\xf0\xee\xe9\xea\xe8 \xf4\xe8\xed\xe0\xed\xf1\xee\xe2")
            imgui.SameLine(math.max(0, aw - S(104)))
            local pr,pg,pb = getAcc()
            imgui.PushStyleColor(imgui.Col.Button,        iv4(pr*0.22,pg*0.22,pb*0.22,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(pr*0.40,pg*0.40,pb*0.40,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(pr*0.58,pg*0.58,pb*0.58,1.0))
            local detachLbl = St._financeSettingsDetached
                and u8"\xc7\xe0\xea\xf0\xe5\xef\xe8\xf2\xfc"
                or  u8"\xce\xf2\xea\xf0\xe5\xef\xe8\xf2\xfc"
            if imgui.Button(detachLbl.."##financeDetachBtn", imgui.ImVec2(S(104), S(24))) then
                St._financeSettingsDetached = not St._financeSettingsDetached
                if St._financeSettingsDetached then
                    local okP, p = pcall(imgui.GetWindowPos)
                    if okP and p then _financeSettingsPos = {x = p.x, y = p.y} end
                end
            end
            imgui.PopStyleColor(3)
        end
        imgui.Separator()
        imgui.Spacing()

        local r, g, b = getAcc()
        drawFinanceSettingsPanelContent(r, g, b)
    end)

    if beganPanel then
        pcall(imgui.End)
    end
    if not panelOk then
        -- панель вызвала ошибку — не пытаемся рисовать её каждый кадр без остановки,
        -- закрываем, чтобы не спамить один и тот же краш
        St._financeSettingsOpen = false
    end
end


-- ── кнопка-копия итога "ВСЕГО ВИРТОВ" в чат: тоже вынесена отдельно ──
function drawGrandTotalCopyButton(aw, hh, r, g, b, bigTxt)
    local btnW2, btnH2 = S(44), S(32)
    imgui.SetCursorPos(imgui.ImVec2(aw - btnW2 - S(12), (hh - btnH2)*0.5))
    imgui.PushStyleColor(imgui.Col.Button,        iv4(r*0.25,g*0.25,b*0.25,1.0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(r*0.65,g*0.65,b*0.65,1.0))
    imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(r,      g,      b,      1.0))
    do local _svg = prettyBtnPush(7.0)
    if imgui.Button(">>##cpGrandTotal", imgui.ImVec2(btnW2, btnH2)) then
        pcall(sampAddChatMessage, "{FFD700}[MSW] \xf0\x9f\x92\x8e " .. "\xc2\xd1\xc5\xc3\xce \xc2\xc8\xd0\xd2\xce\xc2: " .. bigTxt, -1)
    end
    prettyBtnPop(_svg) end
    imgui.PopStyleColor(3)
end

-- "2026-08-25" -> "25.08.2026"
function PD.fmtDateRu(d)
    local y, mo, da = tostring(d or ""):match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
    if not y then return tostring(d or "") end
    return da .. "." .. mo .. "." .. y
end

-- ── одна строка мини-таблицы дохода PayDay: Время | Зарплата | Депозит |
-- Аксы/предметы | AZ | Итого — колонки размечены вручную через
-- SetCursorScreenPos (своя реализация вместо imgui.Columns/BeginTable,
-- которые в этом файле нигде больше не используются) ──
function PD.drawIncomeRow(entry)
    local avail = imgui.GetContentRegionAvail().x
    local h     = S(28)
    local dl    = imgui.GetWindowDrawList()
    local p     = imgui.GetCursorScreenPos()
    local rr,rg,rb = getRowBgColor()
    _rowIndex = _rowIndex + 1
    local shade = (_rowIndex % 2 == 0) and 0.13 or 0.07
    local minV  = (_rowIndex % 2 == 0) and 0.10 or 0.05
    local bgR = math.max(rr*shade, minV)
    local bgG = math.max(rg*shade, minV)
    local bgB = math.max(rb*shade, minV)
    dl:AddRectFilled(imgui.ImVec2(p.x, p.y), imgui.ImVec2(p.x+avail, p.y+h),
        imgui.ColorConvertFloat4ToU32(iv4(bgR,bgG,bgB,0.98)), 4)

    local cols = {
        { w = 0.14, txt = entry.time,                                                     col = thDim() },
        { w = 0.23, txt = fmtMoney(string.format("%.0f", entry.salary)),                   col = thGreen() },
        { w = 0.23, txt = fmtMoney(string.format("%.0f", entry.deposit)),                  col = thGold() },
        { w = 0.20, txt = entry.aksy > 0 and fmtMoney(string.format("%.0f", entry.aksy)) or "-", col = thAcc() },
        { w = 0.08, txt = entry.az > 0 and fmtInt(entry.az) or "-",                        col = thGold() },
        { w = 0.12, txt = fmtMoney(string.format("%.0f", entry.total)),                    col = iv4(0.55,0.95,0.55,1.0) },
    }
    local x = p.x + S(8)
    for _, c in ipairs(cols) do
        local cw = avail * c.w
        imgui.SetCursorScreenPos(imgui.ImVec2(x, p.y + S(5)))
        imgui.TextColored(c.col, u8(c.txt))
        x = x + cw
    end
    imgui.SetCursorScreenPos(imgui.ImVec2(p.x, p.y + h))
end

-- ── секция "Доход по PayDay" на вкладке "Финансы": тумблер автосбора +
-- 3 плашки-итоги (общий заработок / за сегодня / за неделю) + таблица
-- по самому свежему дню, встречающемуся в логе. Данные собираются
-- автоматически через PD.onLine/PD.flush (см. sampev.onServerMessage) ──
function PD.drawIncomeSection()
    if not St.incomeLoaded then PD.loadIncomeLog() end
    local aw = imgui.GetContentRegionAvail().x

    secTitle(u8"\xc4\xee\xf5\xee\xe4\x20\xef\xee\x20\x50\x61\x79\x44\x61\x79")

    do
        local isOn = cfg.incomeTrackEnabled ~= false
        if drawToggleSwitch("##incomeTrackToggle", isOn) then
            cfg.incomeTrackEnabled = not isOn
            saveCfg()
        end
        imgui.SameLine(0, S(8))
        imgui.TextColored(iv4(1,1,1,1),
            u8"\xc0\xe2\xf2\xee\xec\xe0\xf2\xe8\xf7\xe5\xf1\xea\xe8\x20\xf1\xf7\xe8\xf2\xe0\xf2\xfc\x20\xe7\xe0\xf0\xef\xeb\xe0\xf2\xf3\x2f\xe4\xe5\xef\xee\xe7\xe8\xf2\x2f\x41\x5a\x20\xe8\xe7\x20\xf7\xe0\xf2\xe0\x20\x28\x50\x61\x79\x44\x61\x79\x29")
        imgui.Dummy(imgui.ImVec2(0, S(4)))
    end

    imgui.Spacing()

    -- сумма "сегодня" + список всех дат, встречающихся в логе (для навигации/календаря)
    local today = os.date("%Y-%m-%d")
    local sumToday, azToday = 0, 0
    local seenDates, dateList = {}, {}
    for _, e in ipairs(St.incomeEntries) do
        if e.date == today then
            sumToday = sumToday + e.total; azToday = azToday + e.az
        end
        if not seenDates[e.date] then
            seenDates[e.date] = true
            dateList[#dateList+1] = e.date
        end
    end
    table.sort(dateList, function(a, b) return a > b end)
    -- ── по просьбе: "за неделю" — это реальная календарная неделя
    -- (понедельник-сегодня), а не "последние 7 дат, когда были записи".
    -- Так плашка сама "обновляется"/обнуляется в понедельник, без какого-
    -- либо отдельного таймера сброса — она просто каждый раз считается
    -- заново от текущего начала недели ──
    local wd = tonumber(os.date("%w")) -- 0=Вс..6=Сб
    local mondayOffsetDays = (wd == 0) and 6 or (wd - 1)
    local weekStart = os.date("%Y-%m-%d", os.time() - mondayOffsetDays * 86400)
    local sumWeek, azWeek = 0, 0
    for _, e in ipairs(St.incomeEntries) do
        if e.date >= weekStart and e.date <= today then
            sumWeek = sumWeek + e.total; azWeek = azWeek + e.az
        end
    end

    local allTimeMoney = cfg.incomeAllTimeMoney or 0
    local allTimeAZ    = cfg.incomeAllTimeAZ or 0

    local function moneyAz(sum, az)
        local s = fmtMoney(string.format("%.0f", sum))
        if az and az > 0 then s = s .. "   " .. fmtInt(az) .. " AZ" end
        return s
    end

    local tileW = (aw - S(12)) / 3
    metricTile(u8"\xce\xe1\xf9\xe8\xe9\x20\xe7\xe0\xf0\xe0\xe1\xee\xf2\xee\xea", moneyAz(allTimeMoney, allTimeAZ), thGold(), tileW)
    imgui.SameLine(0, S(6))
    metricTile(u8"\xc7\xe0\x20\xf1\xe5\xe3\xee\xe4\xed\xff", moneyAz(sumToday, azToday), thAcc(), tileW)
    imgui.SameLine(0, S(6))
    metricTile(u8"\xc7\xe0\x20\xed\xe5\xe4\xe5\xeb\xfe", moneyAz(sumWeek, azWeek), thGreen(), tileW)

    imgui.Spacing()
    imgui.Dummy(imgui.ImVec2(0, S(4)))

    if #dateList == 0 then
        imgui.TextColored(thDim(), "  " ..
            u8"\xcf\xee\xea\xe0\x20\xed\xe5\xf2\x20\xed\xe8\x20\xee\xe4\xed\xee\xe9\x20\xe7\xe0\xef\xe8\xf1\xe8\x20\x50\x61\x79\x44\x61\x79\x2e\x20\xc4\xe0\xed\xed\xfb\xe5\x20\xef\xee\xff\xe2\xff\xf2\xf1\xff\x20\xe0\xe2\xf2\xee\xec\xe0\xf2\xe8\xf7\xe5\xf1\xea\xe8\x2c\x20\xea\xee\xe3\xe4\xe0\x20\xef\xf0\xe8\xe4\xb8\xf2\x20\xe7\xe0\xf0\xef\xeb\xe0\xf2\xe0\x2e")
        return
    end

    -- ── навигация по дням ("логи за прошедшие дни"): dateList отсортирован
    -- от самой свежей даты к самой старой, St._pdDateIdx — индекс в нём
    -- (1 = сегодня/последняя запись, больше = более старые дни) ──
    St._pdDateIdx = St._pdDateIdx or 1
    if St._pdDateIdx < 1 then St._pdDateIdx = 1 end
    if St._pdDateIdx > #dateList then St._pdDateIdx = #dateList end
    local shownDate = dateList[St._pdDateIdx]

    do
        -- ── по просьбе: убрали кнопки-стрелки постраничной навигации по
        -- дням — вместо них одна крупная кнопка-плитка на всю ширину,
        -- открывающая тот же попап с календарём/логами. Оформление:
        -- скруглённые углы, вертикальный градиент, мягкая тень, крупный
        -- шрифт заголовка ──
        local r, g, b = getAcc()
        local dl = imgui.GetWindowDrawList()
        local p0 = imgui.GetCursorScreenPos()
        local btnW = imgui.GetContentRegionAvail().x
        local btnH = S(52)
        local rounding = S(12)

        local hovered = imgui.IsMouseHoveringRect(p0, imgui.ImVec2(p0.x + btnW, p0.y + btnH), true)

        -- тень
        dl:AddRectFilled(imgui.ImVec2(p0.x + S(2), p0.y + S(4)),
            imgui.ImVec2(p0.x + btnW + S(2), p0.y + btnH + S(4)),
            imgui.ColorConvertFloat4ToU32(iv4(0, 0, 0, 0.35)), rounding)

        -- градиентная заливка (светлее сверху, темнее снизу; ярче при наведении)
        local topMul, botMul = hovered and 1.05 or 0.85, hovered and 0.55 or 0.40
        local colTop = imgui.ColorConvertFloat4ToU32(iv4(r*topMul, g*topMul, b*topMul, 1.0))
        local colBot = imgui.ColorConvertFloat4ToU32(iv4(r*botMul, g*botMul, b*botMul, 1.0))
        dl:AddRectFilledMultiColor(p0, imgui.ImVec2(p0.x + btnW, p0.y + btnH),
            colTop, colTop, colBot, colBot)
        dl:AddRect(p0, imgui.ImVec2(p0.x + btnW, p0.y + btnH),
            imgui.ColorConvertFloat4ToU32(iv4(1, 1, 1, hovered and 0.25 or 0.12)), rounding, 0, 1.5)

        local title = u8"\xca\xe0\xeb\xe5\xed\xe4\xe0\xf0\xfc\x20\xe8\x20\xeb\xee\xe3\xe8\x20PayDay"
        local subtitle = PD.fmtDateRu(shownDate) .. "   (" .. tostring(St._pdDateIdx) .. " " ..
            u8"\xe8\xe7" .. " " .. tostring(#dateList) .. ")"

        pcall(imgui.SetWindowFontScale, 1.35)
        local titleSz = imgui.CalcTextSize(title)
        pcall(imgui.SetWindowFontScale, 1.0)
        local subSz = imgui.CalcTextSize(subtitle)
        local blockH = titleSz.y + subSz.y + S(4)
        local textX = p0.x + S(16)
        local textY = p0.y + (btnH - blockH) / 2

        dl:AddText(imgui.ImVec2(textX, textY), imgui.ColorConvertFloat4ToU32(iv4(1,1,1,1)), title)
        -- crude "bigger font" for the title: draw it twice with tiny offset for a bolder look
        dl:AddText(imgui.ImVec2(textX + 0.5, textY), imgui.ColorConvertFloat4ToU32(iv4(1,1,1,1)), title)
        dl:AddText(imgui.ImVec2(textX, textY + titleSz.y + S(4)),
            imgui.ColorConvertFloat4ToU32(iv4(0.92,0.94,0.98,0.85)), subtitle)

        -- иконка-стрелка справа, намекающая, что это открывает попап
        local arrowTxt = u8"\xbb"
        local arrowSz = imgui.CalcTextSize(arrowTxt)
        dl:AddText(imgui.ImVec2(p0.x + btnW - arrowSz.x - S(16), p0.y + (btnH - arrowSz.y) / 2),
            imgui.ColorConvertFloat4ToU32(iv4(1,1,1,0.8)), arrowTxt)

        imgui.SetCursorScreenPos(p0)
        if imgui.InvisibleButton("##pdOpenCalendarBig", imgui.ImVec2(btnW, btnH)) then
            imgui.OpenPopup("##pdCalendarPopup")
        end
        if imgui.IsItemHovered and imgui.IsItemHovered() then
            pcall(function()
                imgui.BeginTooltip()
                imgui.TextColored(iv4(0.75,0.80,0.90,1.0), u8"\xca\xe0\xeb\xe5\xed\xe4\xe0\xf0\xfc\x20\xef\xee\x20\xe4\xed\xff\xec\x20\xf1\x20\x50\x61\x79\x44\x61\x79")
                imgui.EndTooltip()
            end)
        end

        St._pdCalState = St._pdCalState or {}
        -- ФИКС "МЕНЮ САМО ПЕРЕМЕЩАЕТСЯ": по умолчанию imgui открывает попап
        -- ровно там, где сейчас находится курсор мыши в момент клика — а
        -- кнопка-плитка широкая на всю ширину окна, поэтому клик в разных
        -- её точках открывал попап в разных местах на экране. Фиксируем
        -- позицию попапа относительно самой плитки (Cond.Appearing — только
        -- в момент открытия, дальше окно можно свободно подвинуть).
        pcall(imgui.SetNextWindowPos, imgui.ImVec2(p0.x, p0.y + btnH + S(4)), imgui.Cond.Appearing)
        local _mpsC = pushModernPopupStyle()
        -- ФИКС: BeginPopup/EndPopup под pcall — раньше без защиты
        local beganC = false
        local okC, errC = pcall(function()
        if imgui.BeginPopup("##pdCalendarPopup") then
            beganC = true
            imgui.TextColored(thDim(), u8"\xc4\xed\xe8\x20\xf1\x20\xef\xee\xeb\xf3\xf7\xe5\xed\xed\xfb\xec\x20PayDay\x20\xef\xee\xe4\xf1\xe2\xe5\xf7\xe5\xed\xfb")
            imgui.Spacing()
            Cal.draw(St._pdCalState, seenDates, function(pickedDate)
                for idx, dt in ipairs(dateList) do
                    if dt == pickedDate then St._pdDateIdx = idx; break end
                end
            end)
        end
        end) -- конец pcall
        if beganC then pcall(imgui.EndPopup) end
        popModernPopupStyle(_mpsC)
        if not okC then
            pcall(sampAddChatMessage, "{FF6666}[PC Stats] " ..
                "\xee\xf8\xe8\xe1\xea\xe0\x20\xea\xe0\xeb\xe5\xed\xe4\xe0\xf0\xff\x20PayDay: " .. tostring(errC), -1)
        end
    end

    -- итог выбранного дня (по всем колонкам, включая депозит)
    do
        local dSum, dAz = 0, 0
        for _, e in ipairs(St.incomeEntries) do
            if e.date == shownDate then dSum = dSum + e.total; dAz = dAz + e.az end
        end
        imgui.TextColored(thGreen(), "  " .. u8"\xc8\xf2\xee\xe3\xee\x20\xe7\xe0\x20\xe4\xe5\xed\xfc" .. ": " .. moneyAz(dSum, dAz))
    end

    -- заголовок мини-таблицы (те же пропорции колонок, что и в PD.drawIncomeRow)
    do
        local avail = imgui.GetContentRegionAvail().x
        local p = imgui.GetCursorScreenPos()
        local headers = {
            { w = 0.14, txt = u8"\xc2\xf0\xe5\xec\xff" },
            { w = 0.23, txt = u8"\xc7\xe0\xf0\xef\xeb\xe0\xf2\xe0" },
            { w = 0.23, txt = u8"\xc4\xe5\xef\xee\xe7\xe8\xf2" },
            { w = 0.20, txt = u8"\xc0\xea\xf1\xfb\x2f\xef\xf0\xe5\xe4\xec\xe5\xf2\xfb" },
            { w = 0.08, txt = "AZ" },
            { w = 0.12, txt = u8"\xc8\xf2\xee\xe3\xee" },
        }
        local x = p.x + S(8)
        for _, hd in ipairs(headers) do
            local cw = avail * hd.w
            imgui.SetCursorScreenPos(imgui.ImVec2(x, p.y))
            imgui.TextColored(thDim(), hd.txt)
            x = x + cw
        end
        imgui.SetCursorScreenPos(imgui.ImVec2(p.x, p.y + S(18)))
    end

    imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
    imgui.BeginChild("##incomeTbl", imgui.ImVec2(0, S(220)), false)
    _rowIndex = 0
    local shown = 0
    for _, e in ipairs(St.incomeEntries) do
        if e.date == shownDate then
            PD.drawIncomeRow(e)
            shown = shown + 1
            if shown >= 200 then break end
        end
    end
    if shown == 0 then
        imgui.TextColored(thDim(), "  " .. u8"\xed\xe5\xf2\x20\xe7\xe0\xef\xe8\xf1\xe5\xe9\x20\xe7\xe0\x20\xf1\xe5\xe3\xee\xe4\xed\xff")
    end
    imgui.EndChild()
    imgui.PopStyleColor()
end

-- ── общий расчёт итоговой суммы (используется и вкладкой "Всего", и
-- тонким всплывающим окном профиля в правом верхнем углу — см. п.6/14) ──
function computeGrandTotal(s)
    local cash = toNum(s.cashSas)
    local bank = toNum(s.bank)
    local dep  = toNum(s.moneyDay)
    local accT = 0
    for i=1,6 do accT = accT + toNum(s.acc[i]) end

    local az  = toNum(hasVal(s.accountState) and s.accountState or s.azCoins)
    local btc = toNum(s.btc)
    local eur = toNum(s.euro)
    local vc  = toNum(s.cashVcs)
    local asc = tonumber(cfg.ascAmount) or 0

    local azSA  = az  * cfg.rateAZ
    local btcSA = btc * cfg.rateBTC
    local eurSA = eur * cfg.rateEUR
    local vcSA  = vc  * cfg.rateVC
    local ascSA = asc * cfg.rateASC

    local cashInc = cfg.incCash and cash or 0
    local bankInc = cfg.incBank and bank or 0
    local depInc  = cfg.incDep  and dep  or 0
    local accInc  = cfg.incAcc  and accT or 0
    local azInc   = cfg.incAZ  and azSA  or 0
    local btcInc  = cfg.incBTC and btcSA or 0
    local eurInc  = cfg.incEUR and eurSA or 0
    local vcInc   = cfg.incVC  and vcSA  or 0
    local ascInc  = cfg.incASC and ascSA or 0

    local grand = cashInc + bankInc + depInc + accInc + azInc + btcInc + eurInc + vcInc + ascInc
    if grand < 0 then grand = 0 end

    -- ФИКС КРАШЕЙ "attempt to compare/format ... nil" на вкладке "Финансы":
    -- drawTotal() (ниже по файлу) использует не только cashInc/bankInc/...,
    -- но и "сырые" cash/bank/dep/accT/az/btc/eur/vc/asc/azSA/btcSA/eurSA/
    -- vcSA/ascSA — а ВСЕ они были local только здесь, внутри
    -- computeGrandTotal. Возвращаем весь набор наружу одним списком, чтобы
    -- ни одна переменная в drawTotal больше не оставалась nil.
    local curSum = azInc + btcInc + eurInc + vcInc + ascInc
    return grand, cashInc, bankInc, depInc, accInc, curSum,
        cash, bank, dep, accT, az, btc, eur, vc, asc, azSA, btcSA, eurSA, vcSA, ascSA
end

-- ФИКС (п.7): тот же паттерн — drawTotalInner под pcall, EndChild/
-- PopStyleColor гарантированы
function drawTotalInner(s, h)
    if St._resetCharScroll then imgui.SetScrollY(0) end
        local r,g,b = getAcc()

        -- ── кнопка управления вкладкой "Всего": подписана текстом, читаемый
        -- шрифт, толщина рамки 4px ──────────────────────────────────────
        -- (кнопка "Цели" перенесена на вкладку "Настройки", см. drawSettings)
        drawFinanceSettingsBlock(r, g, b)

        -- ── карточка "Меню" (команда чата для открытия окна) перенесена в
        -- панель "Настройки финансов" (кнопка "Настройки" выше) — см.
        -- drawFinanceSettingsPanelContent, раздел "Команда открытия меню" ──

        local grand, cashInc, bankInc, depInc, accInc, curSum,
            cash, bank, dep, accT, az, btc, eur, vc, asc, azSA, btcSA, eurSA, vcSA, ascSA
            = computeGrandTotal(s)

        -- bolshaya plashka "Vsego virtov" (s avtoumensheniem shrifta pod razmer okna)
        do
            local dl = imgui.GetWindowDrawList()
            local p  = imgui.GetCursorScreenPos()
            local aw = imgui.GetContentRegionAvail().x
            local hh = S(80)
            dl:AddRectFilled(
                imgui.ImVec2(p.x,      p.y),
                imgui.ImVec2(p.x+aw,   p.y+hh),
                imgui.ColorConvertFloat4ToU32(iv4(r*0.20,g*0.20,b*0.20,0.97)), 12)
            dl:AddRect(
                imgui.ImVec2(p.x,      p.y),
                imgui.ImVec2(p.x+aw,   p.y+hh),
                imgui.ColorConvertFloat4ToU32(iv4(r,g,b,0.90)), 12, 0, 1.5)
            dl:AddRectFilled(
                imgui.ImVec2(p.x,   p.y+6),
                imgui.ImVec2(p.x+4, p.y+hh-6),
                imgui.ColorConvertFloat4ToU32(iv4(r,g,b,1.0)), 2)
            imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
            imgui.BeginChild("##totbig", imgui.ImVec2(aw, hh), false,
                imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
                imgui.SetCursorPos(imgui.ImVec2(S(16), S(10)))
                imgui.TextColored(thDim(), u8"\xc2\xd1\xc5\xc3\xce \xc2\xc8\xd0\xd2\xce\xc2")
                local bigTxt = fmtMoney(string.format("%.0f", grand))
                -- podgonyaem masshtab shrifta pod shirinu okna, chtoby ochen bolshie summy (trilliony) ne obrezalis
                local baseScale = St.UI_SCALE * (cfg.fontSize > 0 and cfg.fontSize or 1.25)
                local availTxtW = aw - S(28)
                local okCTS, tsz = pcall(imgui.CalcTextSize, bigTxt)
                local shrink = 1.0
                if okCTS and tsz and tsz.x and tsz.x > availTxtW and tsz.x > 0 then
                    shrink = availTxtW / tsz.x
                    if shrink < 0.45 then shrink = 0.45 end
                end
                if shrink < 0.999 then pcall(imgui.SetWindowFontScale, baseScale * shrink) end
                imgui.SetCursorPos(imgui.ImVec2(S(16), S(32)))
                imgui.TextColored(getElemColor("grandtotal", thGold()), bigTxt)
                recolorOnClick("grandtotal")
                if shrink < 0.999 then pcall(imgui.SetWindowFontScale, baseScale) end

                -- кнопка-копия: вывести "ВСЕГО ВИРТОВ" в чат (как белые кнопки на вкладке "Персонаж")
                drawGrandTotalCopyButton(aw, hh, r, g, b, bigTxt)
            imgui.EndChild()
            imgui.PopStyleColor()

            -- "svoya fishka": polosa raspredeleniya bogatstva
            if grand > 0 then
                local segs = {
                    { v = cashInc, col = {0.30,0.85,0.50}, name = u8"\xcd\xe0\xeb\xe8\xf7\xed\xfb\xe5" },
                    { v = bankInc, col = {0.35,0.62,0.95}, name = u8"\xc1\xe0\xed\xea" },
                    { v = depInc,  col = {0.95,0.78,0.25}, name = u8"\xc4\xe5\xef\xee\xe7\xe8\xf2" },
                    { v = accInc,  col = {0.65,0.55,0.95}, name = u8"\xd1\xf7\xe5\xf2\xe0" },
                    { v = curSum,  col = {0.95,0.45,0.55}, name = u8"\xc2\xe0\xeb\xfe\xf2\xfb" },
                }
                local by = p.y + hh + S(10)
                local bh = S(14)
                -- фон полосы (более крупная, с лёгкой рамкой снизу) — так проще разглядеть сегменты
                dl:AddRectFilled(imgui.ImVec2(p.x, by), imgui.ImVec2(p.x+aw, by+bh),
                    imgui.ColorConvertFloat4ToU32(iv4(0.08,0.08,0.10,1.0)), bh/2)
                local bx = p.x
                for i=1,#segs do
                    local sv = segs[i].v
                    -- доп. страховка: если какое-то значение всё же придёт nil
                    -- (например, из-за будущих правок), не падаем, а просто
                    -- пропускаем этот сегмент вместо краша всей вкладки
                    if type(sv) == "number" and sv > 0 then
                        local sw2 = aw * (sv / grand)
                        local c = segs[i].col
                        dl:AddRectFilled(imgui.ImVec2(bx, by), imgui.ImVec2(bx+sw2, by+bh),
                            imgui.ColorConvertFloat4ToU32(iv4(c[1],c[2],c[3],1.0)))
                        -- тонкий разделитель между сегментами, чтобы было видно границы
                        if bx > p.x then
                            dl:AddLine(imgui.ImVec2(bx, by), imgui.ImVec2(bx, by+bh),
                                imgui.ColorConvertFloat4ToU32(iv4(0,0,0,0.35)), 1)
                        end
                        -- наведение мышью прямо на цвет в самом графике — показываем процент
                        do
                            imgui.SetCursorScreenPos(imgui.ImVec2(bx, by))
                            imgui.InvisibleButton("##segHover"..i, imgui.ImVec2(sw2, bh))
                            if imgui.IsItemHovered and imgui.IsItemHovered() then
                                imgui.BeginTooltip()
                                imgui.Text(string.format("%s: %.1f%%", segs[i].name, sv/grand*100))
                                imgui.EndTooltip()
                            end
                        end
                        bx = bx + sw2
                    end
                end
                dl:AddRect(imgui.ImVec2(p.x, by), imgui.ImVec2(p.x+aw, by+bh),
                    imgui.ColorConvertFloat4ToU32(iv4(1,1,1,0.14)), bh/2, 0, 1.2)
                imgui.SetCursorScreenPos(imgui.ImVec2(p.x, by+bh))
                imgui.Dummy(imgui.ImVec2(aw, S(10)))

                -- легенда: только цветной квадратик + название (без цифр); процент — во всплывающей подсказке при наведении
                do
                    local avL = imgui.GetContentRegionAvail().x
                    local usedX = 0
                    for i=1,#segs do
                        local sv = segs[i].v
                        if sv > 0 then
                            local c    = segs[i].col
                            local pct  = sv / grand * 100
                            local txt  = segs[i].name
                            local tw   = imgui.CalcTextSize(txt).x
                            local itemW = S(16) + 4 + tw + S(14)
                            if usedX > 0 and usedX + itemW > avL then
                                usedX = 0
                            elseif usedX > 0 then
                                imgui.SameLine(0, S(14))
                            end
                            local lp = imgui.GetCursorScreenPos()
                            dl:AddRectFilled(
                                imgui.ImVec2(lp.x, lp.y+2),
                                imgui.ImVec2(lp.x+S(10), lp.y+S(12)),
                                imgui.ColorConvertFloat4ToU32(iv4(c[1],c[2],c[3],1.0)), 3)
                            imgui.Dummy(imgui.ImVec2(S(14), S(14)))
                            if imgui.IsItemHovered() then
                                imgui.BeginTooltip()
                                imgui.Text(string.format("%s: %.0f%%", txt, pct))
                                imgui.EndTooltip()
                            end
                            imgui.SameLine(0,4)
                            imgui.TextColored(iv4(0.85,0.87,0.95,1.0), txt)
                            usedX = usedX + itemW
                        end
                    end
                end
                imgui.Spacing()
            end
        end
        imgui.Spacing()


        if cfg.financeTwoCol then
            -- ── ДВА СТОЛБИКА: слева наличные/банк/депозит/счета, справа валюты ──
            local okCols = pcall(imgui.Columns, 2, "##fincols", false)
            _rowIndex = 0
            secTitle(u8"\xcd\xe0\xeb\xe8\xf7\xed\xfb\xe5 \xf1\xf0\xe5\xe4\xf1\xf2\xe2\xe0")
            dataRow(u8"\xcd\xe0 \xf0\xf3\xea\xe0\xf5", fmtMoney(string.format("%.0f", cash)), thGreen())
            dataRow(u8"\xc1\xe0\xed\xea",              fmtMoney(string.format("%.0f", bank)), thAcc())
            dataRow(u8"\xc4\xe5\xef\xee\xe7\xe8\xf2",  fmtMoney(string.format("%.0f", dep)),  thGold())
            if accT > 0 then
                dataRow(u8"\xcb\xe8\xf7\xed\xfb\xe5 \xf1\xf7\xe5\xf2\xe0", fmtMoney(string.format("%.0f", accT)), thAcc())
            end
            if okCols then pcall(imgui.NextColumn) end
            _rowIndex = 0
            secTitle(u8"\xc2\xe0\xeb\xfe\xf2\xfb")
            if az > 0 then
                dataRow("AZ-Coins", fmtAmt(az).." AZ  -  "..fmtMoney(string.format("%.0f", azSA)), thGold())
            end
            if btc > 0 then
                dataRow("BTC", fmtAmt(btc).." BTC  -  "..fmtMoney(string.format("%.0f", btcSA)), thGold())
            end
            if eur > 0 then
                dataRow(CUR_AARP_SHORT, fmtAmt(eur).." AARRP  -  "..fmtMoney(string.format("%.0f", eurSA)), thGold())
            end
            if vc > 0 then
                dataRow("VC$", fmtAmt(vc).." VC$  -  "..fmtMoney(string.format("%.0f", vcSA)), thGold())
            end
            if asc > 0 then
                dataRow("ASC", fmtAmt(asc).." ASC  -  "..fmtMoney(string.format("%.0f", ascSA)), thGold())
            end
            if az<=0 and btc<=0 and eur<=0 and vc<=0 and asc<=0 then
                imgui.Spacing()
                imgui.TextColored(thDim(), u8"  \xed\xe5\xf2 \xe4\xe0\xed\xed\xfb\xf5 \xef\xee \xe2\xe0\xeb\xfe\xf2\xe0\xec")
            end
            if okCols then pcall(imgui.Columns, 1) end
            imgui.Spacing()
        else
        -- nalichnye sredstva (SA$)
        _rowIndex = 0
        secTitle(u8"\xcd\xe0\xeb\xe8\xf7\xed\xfb\xe5 \xf1\xf0\xe5\xe4\xf1\xf2\xe2\xe0")
        dataRow(u8"\xcd\xe0 \xf0\xf3\xea\xe0\xf5", fmtMoney(string.format("%.0f", cash)), thGreen())
        dataRow(u8"\xc1\xe0\xed\xea",              fmtMoney(string.format("%.0f", bank)), thAcc())
        dataRow(u8"\xc4\xe5\xef\xee\xe7\xe8\xf2",  fmtMoney(string.format("%.0f", dep)),  thGold())
        if accT > 0 then
            dataRow(u8"\xcb\xe8\xf7\xed\xfb\xe5 \xf1\xf7\xe5\xf2\xe0", fmtMoney(string.format("%.0f", accT)), thAcc())
        end
        imgui.Dummy(imgui.ImVec2(0, S(6)))

        -- valyuty + formula konvertacii (tolko chtenie, kursy nastraivayutsya v Nastroykah)
        _rowIndex = 0
        secTitle(u8"\xc2\xe0\xeb\xfe\xf2\xfb")
        if az > 0 then
            dataRow("AZ-Coins", fmtAmt(az).." AZ  -  "..fmtMoney(string.format("%.0f", azSA)), thGold())
        end
        if btc > 0 then
            dataRow("BTC", fmtAmt(btc).." BTC  -  "..fmtMoney(string.format("%.0f", btcSA)), thGold())
        end
        if eur > 0 then
            dataRow(CUR_AARP_SHORT, fmtAmt(eur).." AARRP  -  "..fmtMoney(string.format("%.0f", eurSA)), thGold())
        end
        if vc > 0 then
            dataRow("VC$", fmtAmt(vc).." VC$  -  "..fmtMoney(string.format("%.0f", vcSA)), thGold())
        end
        if asc > 0 then
            dataRow("ASC", fmtAmt(asc).." ASC  -  "..fmtMoney(string.format("%.0f", ascSA)), thGold())
        end
        if az<=0 and btc<=0 and eur<=0 and vc<=0 and asc<=0 then
            imgui.Spacing()
            imgui.TextColored(thDim(), u8"  \xed\xe5\xf2 \xe4\xe0\xed\xed\xfb\xf5 \xef\xee \xe2\xe0\xeb\xfe\xf2\xe0\xec")
        end
        end
        imgui.Spacing()

        -- ── "Доход по PayDay": зарплата/депозит/аксы/AZ, распознанные из
        -- чата (см. PD.drawIncomeSection выше) ──
        PD.drawIncomeSection()

    -- ── нижний отступ, чтобы последний блок не прилипал к краю окна ──
    imgui.Dummy(imgui.ImVec2(0, S(40)))
end

local function drawTotal(s, h)
    _rowIndex = 0
    imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
    imgui.BeginChild("##stot", imgui.ImVec2(0, h), false)
    local ok, err = PCS_GUARD.call(drawTotalInner, s, h)
    imgui.EndChild()
    imgui.PopStyleColor()
    St._resetCharScroll = false
    if not ok then
        pcall(sampAddChatMessage, "{FF6666}[PC Stats] " ..
            "\xee\xf8\xe8\xe1\xea\xe0\x20\xee\xf2\xf0\xe8\xf1\xee\xe2\xea\xe8\x20\xc2\xf1\xe5\xe3\xee: " .. tostring(err), -1)
    end
end


-- ============================================================
--  Š’Š�Š›Š�Š”Š�Š� 3: Š¯Š�Š�Š¢Š Š˛Š™Š�Š�
-- ============================================================
-- ── универсальный блок "квадратик цвета + кнопка Изменить + кнопка Авто +
-- всплывающий пикер" — используется для цвета текста / фона окна скрипта /
-- обводки (по образцу уже существующих блоков "Свой цвет" и "Фон строк") ──
-- ── строка цвета "1:1" как на референс-скриншоте: подпись сверху,
-- под ней в одну строку — 3 слайдера R/G/B, квадратик-превью цвета и
-- кнопка "Авто" (сброс к цвету темы). Всё видно сразу, без всплывающих
-- окон — по просьбе "изменить функционал для изменения цвета" ──
-- ── буфер для попапа выбора цвета у строк-полосок в "Настройках"
-- (кнопка "Авто" убрана — теперь клик по самому квадратику/полоске цвета
-- открывает точно такое же окно выбора цвета, как клик по тексту) ──
local _colorRowPopupVec = {}

function drawColorRowInline(titleU8, rBuf, gBuf, bBuf, cfgRKey, cfgGKey, cfgBKey, defR, defG, defB, whiteChrome, uidSeed, toggleFn)
    local uid = uidSeed or titleU8
    -- ФИКС (по просьбе): полоска цвета на всю ширину заменена на
    -- компактный квадратик рядом с подписью — вместо secTitle()+
    -- полноширинной кнопки теперь подпись и квадратик в одну строку
    local swSize = S(30)
    imgui.AlignTextToFramePadding()
    imgui.TextColored(thDim(), titleU8)
    imgui.SameLine(0, S(10))

    if whiteChrome then
        -- нейтрально-белая кнопка/квадратик — не перекрашивается акцентом
        imgui.PushStyleColor(imgui.Col.Button,        iv4(0.94,0.94,0.96,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered,  iv4(1.0, 1.0, 1.0, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive,   iv4(0.85,0.85,0.88,1.0))
    else
        imgui.PushStyleColor(imgui.Col.Button,        iv4(rBuf[0],gBuf[0],bBuf[0],1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(rBuf[0],gBuf[0],bBuf[0],1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(rBuf[0],gBuf[0],bBuf[0],1.0))
    end
    -- ФИКС (по просьбе): квадратики "покрасивее" — сильнее скруглённые
    -- углы + тонкая контрастная обводка по периметру (белая полупрозрачная
    -- в тёмном режиме, тёмная в светлом), чтобы квадратик не сливался
    -- визуально с фоном, даже если цвет совпадает с фоном скрипта
    local _pbSw = prettyBtnPush(9.0)
    local swPos = imgui.GetCursorScreenPos()
    local swClicked = imgui.Button("##swatch_"..uid, imgui.ImVec2(swSize, swSize))
    prettyBtnPop(_pbSw)
    imgui.PopStyleColor(3)
    do
        local dlSw = imgui.GetWindowDrawList()
        local ringCol = cfg.uiLightMode and iv4(0.20,0.20,0.24,0.55) or iv4(1,1,1,0.35)
        dlSw:AddRect(swPos, imgui.ImVec2(swPos.x+swSize, swPos.y+swSize),
            imgui.ColorConvertFloat4ToU32(ringCol), 9.0, 0, 1.4)
    end
    if swClicked then imgui.OpenPopup("##swatchPopup_"..uid) end
    if imgui.IsItemHovered and imgui.IsItemHovered() then
        pcall(function()
            imgui.BeginTooltip()
            imgui.TextColored(iv4(0.75,0.80,0.90,1.0),
                u8"\xed\xe0\xe6\xec\xe8\xf2\xe5\x2c\x20\xf7\xf2\xee\xe1\xfb\x20\xf1\xec\xe5\xed\xe8\xf2\xfc\x20\xf6\xe2\xe5\xf2")
            imgui.EndTooltip()
        end)
    end

    -- ФИКС (по просьбе): справа от квадратика цвета — тумблер вкл/выкл
    -- (та же кнопка-переключатель drawToggleSwitch, что и у "Включить все
    -- всплывающие уведомления"), для рядов, где это уместно (например
    -- "Тон меню") — включает/выключает свой цвет одним кликом, без
    -- необходимости открывать попап и жать "Сброс цвета"
    if toggleFn then
        imgui.SameLine(0, S(10))
        pcall(toggleFn, rBuf, gBuf, bBuf)
    end

    pcall(imgui.SetNextWindowSize, imgui.ImVec2(S(300), 0), imgui.Cond and imgui.Cond.Appearing or 0)
    local _mpsRow = pushModernPopupStyle()

    -- ФИКС (п.11): BeginPopup/EndPopup под pcall; popModernPopupStyle
    -- остаётся снаружи pcall (как и было раньше) — теперь и EndPopup
    -- гарантирован через beganPopup
    local beganRow = false
    local okRow, errRow = pcall(function()
    if imgui.BeginPopup("##swatchPopup_"..uid) then
        beganRow = true
        local changed = false
        local okPicker = pcall(function()
            local vec = _colorRowPopupVec[uid]
            if not vec then
                vec = imgui.new("float[3]", {rBuf[0], gBuf[0], bBuf[0]})
                _colorRowPopupVec[uid] = vec
            end
            imgui.PushItemWidth(S(220))
            local flags = 0
            pcall(function() flags = imgui.ColorEditFlags.PickerHueBar + imgui.ColorEditFlags.DisplayHex end)
            if imgui.ColorPicker3("##cprow"..uid, vec, flags) then
                rBuf[0], gBuf[0], bBuf[0] = vec[0], vec[1], vec[2]
                changed = true
            end
            imgui.PopItemWidth()
        end)
        if not okPicker then
            -- запасной вариант (обычные ползунки), если ColorPicker3 недоступен в этой сборке mimgui
            imgui.PushItemWidth(150)
            if imgui.SliderFloat("R##ir_"..uid, rBuf, 0.0, 1.0) then changed = true end
            if imgui.SliderFloat("G##ig_"..uid, gBuf, 0.0, 1.0) then changed = true end
            if imgui.SliderFloat("B##ib_"..uid, bBuf, 0.0, 1.0) then changed = true end
            imgui.PopItemWidth()
        end
        if changed then
            cfg[cfgRKey]=rBuf[0]; cfg[cfgGKey]=gBuf[0]; cfg[cfgBKey]=bBuf[0]; saveCfg()
        end

        imgui.Spacing()
        local awPop  = imgui.GetContentRegionAvail().x
        local halfWP = (awPop - 8) * 0.5
        imgui.PushStyleColor(imgui.Col.Button,        iv4(0.35,0.06,0.06,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(0.55,0.10,0.10,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(0.75,0.16,0.16,1.0))
        if imgui.Button(u8"\xd1\xe1\xf0\xee\xf1\x20\xf6\xe2\xe5\xf2\xe0##rowrst_"..uid, imgui.ImVec2(halfWP, S(28))) then
            cfg[cfgRKey] = -1; cfg[cfgGKey] = -1; cfg[cfgBKey] = -1
            rBuf[0] = defR; gBuf[0] = defG; bBuf[0] = defB
            _colorRowPopupVec[uid] = nil
            saveCfg()
        end
        imgui.PopStyleColor(3)
        imgui.SameLine(0, 8)
        do
            local pr,pg,pb = getAcc()
            imgui.PushStyleColor(imgui.Col.Button,        iv4(pr*0.22,pg*0.22,pb*0.22,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(pr*0.40,pg*0.40,pb*0.40,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(pr*0.58,pg*0.58,pb*0.58,1.0))
            if imgui.Button(u8"\xc7\xe0\xea\xf0\xfb\xf2\xfc##rowclose_"..uid, imgui.ImVec2(halfWP, S(28))) then
                imgui.CloseCurrentPopup()
            end
            imgui.PopStyleColor(3)
        end
    end
    end) -- конец pcall

    if beganRow then pcall(imgui.EndPopup) end
    popModernPopupStyle(_mpsRow)
    if not okRow then
        pcall(sampAddChatMessage, "{FF6666}[PC Stats] " ..
            "\xee\xf8\xe8\xe1\xea\xe0\x20\xef\xee\xef\xe0\xef\xe0\x20\xf6\xe2\xe5\xf2\xe0\x20\xf1\xf2\xf0\xee\xea\xe8: " .. tostring(errRow), -1)
    end

    imgui.Spacing()
    imgui.Dummy(imgui.ImVec2(0, S(9)))
end

function drawSimpleColorPicker(titleU8, uid, rBuf, gBuf, bBuf, cfgRKey, cfgGKey, cfgBKey, pickerVecKey, defR, defG, defB)
    -- ФИКС "вид не меняется": раньше квадратик был принудительно белым
    -- (whiteChrome=true) по прежней просьбе "верни как было" — из-за
    -- этого полоска НИКОГДА не показывала реально выбранный цвет, сколько
    -- бы его ни меняли в пикере (ровно то, что видно на скриншотах —
    -- везде одинаковые белые прямоугольники). Теперь полоска красится в
    -- реальный текущий цвет (whiteChrome=false), как и у "Акцент"/"Фон
    -- строк" выше ──
    drawColorRowInline(titleU8, rBuf, gBuf, bBuf, cfgRKey, cfgGKey, cfgBKey, defR, defG, defB, false, uid)
end

-- ── по просьбе: закрытие меню больше НЕ спрашивает подтверждения даже
-- если настройки менялись в этой сессии — закрываем сразу. Функция
-- drawCloseConfirmPopup ниже оставлена в файле (вдруг понадобится вернуть),
-- но St._closeConfirmOpen теперь никогда не становится true, поэтому она
-- ничего не рисует ──
function requestCloseMenu()
    forceCloseMenuNow()
end

function forceCloseMenuNow()
    St._closeConfirmOpen = false
    St._settingsTouchedThisSession = false
    St.winOpen = false; St.activeTab = 1; _sw_win_init = nil
    St._financeSettingsOpen = false; St._finShiftAnim = 0.0
    St._finShiftAppliedPx = 0.0; St._finShiftAnchorX = nil
    St._settingsPanelOpen = false
    -- ФИКС (п.18): закрытие меню теперь гарантированно сбрасывает все
    -- "подвисшие" состояния (иначе, например, ожидание диалога налогов
    -- или захват горячей клавиши могли остаться активными после того,
    -- как игрок уже закрыл меню)
    _taxState = 0
    _phoneOpBusy = false
    _phoneFetchState = false
    St._phoneOpBusySince = nil
    _taxExpectedDialogId = nil
    _taxAnsweredThisDialog = false
    St.awaitingHotkeyBind = false
    St._dangerConfirmKind = nil
    -- по просьбе: при закрытии меню сразу гасим все всплывающие
    -- уведомления, а не ждём, пока они сами доиграют анимацию/таймер —
    -- чтобы после закрытия меню на экране гарантированно ничего не
    -- "зависало" поверх игры
    pcall(function() if type(pcs_notify_clear) == "function" then pcs_notify_clear() end end)
end

-- маленькое тонкое окно-подтверждение по центру экрана; вызывается
-- каждый кадр, сама ничего не рисует, если попап не открыт. Использует
-- обычный BeginPopup (как и все прочие попапы в скрипте), а не
-- BeginPopupModal — на всякий случай, чтобы не зависеть от того, есть
-- ли модальные попапы в этой сборке mimgui.
function drawCloseConfirmPopup()
    if not St._closeConfirmOpen then
        St._closeConfirmOpenedOnce = false
        return
    end
    if not St._closeConfirmOpenedOnce then
        St._closeConfirmOpenedOnce = true
        pcall(imgui.OpenPopup, "##pcsCloseConfirm")
    end
    pcall(function()
        local io_ = imgui.GetIO()
        imgui.SetNextWindowPos(imgui.ImVec2(io_.DisplaySize.x*0.5, io_.DisplaySize.y*0.5),
            imgui.Cond and imgui.Cond.Appearing or 0, imgui.ImVec2(0.5, 0.5))
    end)
    pcall(imgui.SetNextWindowSize, imgui.ImVec2(S(280), 0), imgui.Cond and imgui.Cond.Appearing or 0)
    local _mpsCC = pushModernPopupStyle()

    -- ФИКС (п.3): тот же паттерн, что и в drawProfilePopup — BeginPopup/
    -- содержимое/EndPopup под pcall, EndPopup гарантирован
    local beganPopup = false
    local ok, err = pcall(function()
    if imgui.BeginPopup("##pcsCloseConfirm") then
        beganPopup = true
        imgui.TextColored(iv4(1,1,1,1),
            u8"\xc2\xfb\x20\xe8\xe7\xec\xe5\xed\xe8\xeb\xe8\x20\xed\xe0\xf1\xf2\xf0\xee\xe9\xea\xe8\x2e")
        imgui.TextColored(thDim(),
            u8"\x28\xe2\xf1\xb8\x20\xf3\xe6\xe5\x20\xf1\xee\xf5\xf0\xe0\xed\xe5\xed\xee\x2c\x20\xfd\xf2\xee\x20\xef\xf0\xee\xf1\xf2\xee\x20\xef\xee\xe4\xf2\xe2\xe5\xf0\xe6\xe4\xe5\xed\xe8\xe5\x29")
        imgui.Spacing()
        local awCC = imgui.GetContentRegionAvail().x
        local halfCC = (awCC - 8) * 0.5
        imgui.PushStyleColor(imgui.Col.Button,        iv4(0.30,0.30,0.32,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(0.42,0.42,0.46,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(0.55,0.55,0.60,1.0))
        if imgui.Button(u8"\xce\xf2\xec\xe5\xed\xe0##ccCancel", imgui.ImVec2(halfCC, S(30))) then
            St._closeConfirmOpen = false
            imgui.CloseCurrentPopup()
        end
        imgui.PopStyleColor(3)
        imgui.SameLine(0, 8)
        local pr,pg,pb = getAcc()
        imgui.PushStyleColor(imgui.Col.Button,        iv4(pr*0.55,pg*0.55,pb*0.55,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(pr*0.78,pg*0.78,pb*0.78,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(pr,pg,pb,1.0))
        if imgui.Button(u8"\xc7\xe0\xea\xf0\xfb\xf2\xfc##ccClose", imgui.ImVec2(halfCC, S(30))) then
            imgui.CloseCurrentPopup()
            forceCloseMenuNow()
        end
        imgui.PopStyleColor(3)
    else
        -- попап закрылся сам (клик мимо/Escape внутри ImGui) — считаем
        -- это как "Отмена", иначе флаг остался бы навсегда true и попап
        -- было бы невозможно открыть повторно
        if St._closeConfirmOpenedOnce then
            St._closeConfirmOpen = false
        end
    end
    end) -- конец pcall

    if beganPopup then pcall(imgui.EndPopup) end
    if not ok then
        St._closeConfirmOpen = false
        pcall(sampAddChatMessage, "{FF6666}[PC Stats] " ..
            "\xee\xf8\xe8\xe1\xea\xe0\x20\xef\xee\xef\xe0\xef\xe0\x20\xef\xee\xe4\xf2\xe2\xe5\xf0\xe6\xe4\xe5\xed\xe8\xff: " .. tostring(err), -1)
    end
    popModernPopupStyle(_mpsCC)
end

-- ФИКС (п.5): содержимое вынесено в drawSettingsInner, наружная
-- drawSettings делает BeginChild/EndChild гарантированно, а
-- drawSettingsInner вызывается через pcall — ошибка внутри вкладки
-- "Настройки" больше не ломает internal-стек imgui на следующий кадр.
function drawSettingsInner(h, sw, sh)
    if St._resetSettScroll then imgui.SetScrollY(0) end
            local r,g,b = getAcc()

        -- ── шапка настроек (как в Market Helper: карточка-секция сверху)
        do
            local aw = imgui.GetContentRegionAvail().x
            local hh = S(52)
            local dl = imgui.GetWindowDrawList()
            local p = imgui.GetCursorScreenPos()
            dl:AddRectFilled(imgui.ImVec2(p.x,p.y), imgui.ImVec2(p.x+aw,p.y+hh),
                imgui.ColorConvertFloat4ToU32(iv4(r*0.14,g*0.14,b*0.14,0.98)), 10)
            dl:AddRect(imgui.ImVec2(p.x,p.y), imgui.ImVec2(p.x+aw,p.y+hh),
                imgui.ColorConvertFloat4ToU32(iv4(r,g,b,0.70)), 10, 0, 1.3)
            dl:AddRectFilled(imgui.ImVec2(p.x,p.y+8), imgui.ImVec2(p.x+4,p.y+hh-8),
                imgui.ColorConvertFloat4ToU32(iv4(r,g,b,1.0)), 2)
            imgui.SetCursorPosX(imgui.GetCursorPosX()+S(14))
            imgui.SetCursorPosY(imgui.GetCursorPosY()+S(10))
            imgui.TextColored(iv4(1,1,1,1), u8"\xcd\xe0\xf1\xf2\xf0\xee\xe9\xea\xe8")
            imgui.SetCursorPosX(imgui.GetCursorPosX()+S(14))
            imgui.TextColored(thDim(), u8"\xe8\xed\xf2\xe5\xf0\xf4\xe5\xe9\xf1 \xb7 \xf3\xef\xf0\xe0\xe2\xeb\xe5\xed\xe8\xe5 \xb7 \xf3\xe2\xe5\xe4\xee\xec\xeb\xe5\xed\xe8\xff")
            imgui.Dummy(imgui.ImVec2(0, S(14)))
        end

        -- ── единая кнопка выбора цвета: вынесена наверх вкладки, открывает
        -- одно окно сразу с готовыми цветами, своим цветом и цветом фона
        -- строк (раньше было разбросано тремя блоками ниже по вкладке) ──
        do
            local prT,pgT,pbT = getAcc()
            -- ярче, чем было (было ×0.20/0.36/0.52)
            imgui.PushStyleColor(imgui.Col.Button,        iv4(math.min(1,prT*0.55),math.min(1,pgT*0.55),math.min(1,pbT*0.55),1.0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(math.min(1,prT*0.78),math.min(1,pgT*0.78),math.min(1,pbT*0.78),1.0))
            imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(prT,pgT,pbT,1.0))
            do local _pbTop = prettyBtnPush(10.0)
            if imgui.Button(u8"\xc2\xfb\xe1\xee\xf0\x20\xf6\xe2\xe5\xf2\xe0##openColorSettingsPopup", imgui.ImVec2(imgui.GetContentRegionAvail().x, S(34))) then
                if cfg.custR < 0 then
                    local _a = getTheme().acc
                    St.custRbuf[0]=_a[1]; St.custGbuf[0]=_a[2]; St.custBbuf[0]=_a[3]
                end
                if cfg.rowBgR < 0 then
                    local _a2 = getTheme().acc
                    St.rowBgRbuf[0]=_a2[1]; St.rowBgGbuf[0]=_a2[2]; St.rowBgBbuf[0]=_a2[3]
                end
                imgui.OpenPopup("##colorSettingsPopup")
            end
            prettyBtnPop(_pbTop) end
            imgui.PopStyleColor(3)

            pcall(imgui.SetNextWindowSize, imgui.ImVec2(S(300), 0), imgui.Cond and imgui.Cond.Appearing or 0)
            local _mpsTop = pushModernPopupStyle()
            -- ФИКС: отдельный pcall именно вокруг BeginPopup/EndPopup этого
            -- попапа. Раньше при ошибке где-то в его содержимом (например,
            -- в переборе ALL_STYLE_PRESETS) внешний pcall в drawSettings
            -- ловил ошибку и не крашил игру В ЭТОТ момент, но EndPopup для
            -- "##colorSettingsPopup" при этом пропускался — стек imgui
            -- оставался разбалансирован и мог крашнуть игру позже, на
            -- следующем кадре (в том числе при переключении вкладки).
            local beganTop = false
            local okTop, errTop = pcall(function()
            if imgui.BeginPopup("##colorSettingsPopup") then
                beganTop = true
                -- Edinyy spisok vseh presetov (temy + kombo), edinyy dizayn
                -- knopok, dubley po tsvetu aktsenta sredi presetov net.
                local ALL_STYLE_PRESETS = {
                    {u8(THEMES[1].name), 0.43,0.71,1.0,  0.43*0.35,0.71*0.35,1.0*0.35,  1},
                    {u8(THEMES[2].name), 0.30,0.85,0.45, 0.30*0.35,0.85*0.35,0.45*0.35, 2},
                    {u8(THEMES[3].name), 1.0, 0.55,0.20, 1.0*0.35, 0.55*0.35,0.20*0.35, 3},
                    {u8(THEMES[4].name), 0.75,0.45,1.0,  0.75*0.35,0.45*0.35,1.0*0.35,  4},
                    {u8(THEMES[5].name), 1.0, 0.80,0.25, 1.0*0.35, 0.80*0.35,0.25*0.35, 5},
                    {u8(THEMES[6].name), 1.0, 0.25,0.25, 1.0*0.35, 0.25*0.35,0.25*0.35, 6},
                    {u8"\xce\xea\xe5\xe0\xed",         0.10,0.72,0.90, 0.05,0.35,0.55},  -- Ocean
                    {u8"\xd0\xee\xe7\xe0",             0.98,0.35,0.65, 0.50,0.08,0.22},  -- Rose
                    {u8"\xc4\xe6\xf3\xed\xe3\xeb\xe8", 0.35,0.88,0.55, 0.08,0.38,0.18},  -- Jungle
                    {u8"\xc3\xf0\xee\xe7\xe0",         0.75,0.22,0.95, 0.28,0.05,0.42},  -- Thunder
                    {u8"\xd5\xf0\xee\xec",             0.92,0.78,0.20, 0.42,0.32,0.04},  -- Chrome
                    -- "Кровь" убрана (по просьбе, дубль по цвету и по
                    -- смыслу с готовой темой "Blood" из THEMES[6] выше)
                    {u8"\xd1\xed\xe5\xe3",             0.88,0.95,1.00, 0.22,0.38,0.52},  -- Snow
                    {u8"\xd0\xf3\xf1\xf2\xfc",         0.60,0.88,0.35, 0.18,0.38,0.08},  -- Rust
                    {u8"\xd0\xe5\xf1\xf3\xf0\xf1",     0.20,0.90,0.45, 0.05,0.30,0.14},  -- Resurs
                    {u8"\xc7\xee\xeb\xee\xf2\xee",     0.98,0.80,0.15, 0.40,0.30,0.03},  -- Zoloto
                    {u8"\xca\xee\xf0\xe0\xeb\xeb",     0.15,0.85,0.75, 0.04,0.32,0.30},  -- Korall
                    -- ── добавленные по просьбе дополнительные цвета ──
                    {u8"\xc0\xec\xe5\xf2\xe8\xf1\xf2", 0.65,0.35,0.90, 0.24,0.10,0.36},  -- Ametist
                    {u8"\xcc\xff\xf2\xe0",             0.25,0.95,0.75, 0.06,0.36,0.28},  -- Myata
                    {u8"\xcb\xe0\xe9\xec",             0.70,0.95,0.15, 0.24,0.34,0.03},  -- Laym
                    {u8"\xc8\xed\xe4\xe8\xe3\xee",     0.30,0.35,0.95, 0.08,0.10,0.42},  -- Indigo
                    {u8"\xd4\xeb\xe0\xec\xe8\xed\xe3\xee", 1.0,0.45,0.55, 0.42,0.10,0.16}, -- Flamingo
                    {u8"\xd1\xf2\xe0\xeb\xfc",         0.55,0.65,0.75, 0.16,0.20,0.26},  -- Stal
                }

                imgui.TextColored(thDim(), u8"\xc3\xee\xf2\xee\xe2\xfb\xe5\x20\xf6\xe2\xe5\xf2\xe0\x3a")
                imgui.Spacing()
                local av_c  = imgui.GetContentRegionAvail().x
                local perRow = 3
                local gap    = S(6)
                local btnWC  = (av_c - (perRow-1)*gap) / perRow
                for i, cp in ipairs(ALL_STYLE_PRESETS) do
                    local col = (i-1) % perRow
                    if col > 0 then imgui.SameLine(0, gap) end
                    local cName = cp[1]
                    local aR,aG,aB = cp[2],cp[3],cp[4]
                    local bR,bG,bB = cp[5],cp[6],cp[7]
                    local themeIdx = cp[8]
                    local isAct
                    if themeIdx then
                        isAct = (cfg.theme == themeIdx and cfg.custR < 0)
                    else
                        isAct = math.abs((cfg.custR>=0 and cfg.custR or getTheme().acc[1])-aR)<0.01
                               and math.abs((cfg.custG>=0 and cfg.custG or getTheme().acc[2])-aG)<0.01
                               and math.abs((cfg.custB>=0 and cfg.custB or getTheme().acc[3])-aB)<0.01
                               and math.abs((cfg.rowBgR>=0 and cfg.rowBgR or aR)-bR)<0.01
                    end
                    local tip = u8"\xcf\xf0\xe5\xf1\xe5\xf2\x20\xab" .. cName .. u8"\xbb\x3a\x20\xed\xe0\xe6\xec\xe8\xf2\xe5\x2c\x20\xf7\xf2\xee\xe1\xfb\x20\xef\xf0\xe8\xec\xe5\xed\xe8\xf2\xfc"
                    if drawStyleSwatchButton("stylepreset"..i, cName, aR,aG,aB, bR,bG,bB, btnWC, S(46), isAct, tip) then
                        if themeIdx then
                            cfg.theme=themeIdx; cfg.custR=-1; cfg.custG=-1; cfg.custB=-1
                            St.custRbuf[0]=aR; St.custGbuf[0]=aG; St.custBbuf[0]=aB
                        else
                            cfg.custR=aR; cfg.custG=aG; cfg.custB=aB
                            cfg.rowBgR=bR; cfg.rowBgG=bG; cfg.rowBgB=bB
                            St.custRbuf[0]=aR; St.custGbuf[0]=aG; St.custBbuf[0]=aB
                            St.rowBgRbuf[0]=bR; St.rowBgGbuf[0]=bG; St.rowBgBbuf[0]=bB
                        end
                        saveCfg()
                    end
                    if col == perRow-1 then imgui.Spacing() end
                end

                imgui.Spacing()
                do
                    local pr3,pg3,pb3 = getAcc()
                    imgui.PushStyleColor(imgui.Col.Button,        iv4(pr3*0.22,pg3*0.22,pb3*0.22,1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(pr3*0.40,pg3*0.40,pb3*0.40,1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(pr3*0.58,pg3*0.58,pb3*0.58,1.0))
                    do local _pbc = prettyBtnPush(8.0)
                    if imgui.Button(u8"\xc7\xe0\xea\xf0\xfb\xf2\xfc##closeColorSettingsPopup", imgui.ImVec2(imgui.GetContentRegionAvail().x, S(30))) then
                        imgui.CloseCurrentPopup()
                    end
                    prettyBtnPop(_pbc) end
                    imgui.PopStyleColor(3)
                end
            end
            end) -- конец pcall
            if beganTop then pcall(imgui.EndPopup) end
            popModernPopupStyle(_mpsTop)
            if not okTop then
                pcall(sampAddChatMessage, "{FF6666}[PC Stats] " ..
                    "\xee\xf8\xe8\xe1\xea\xe0\x20\xef\xee\xef\xe0\xef\xe0\x20\xe2\xfb\xe1\xee\xf0\xe0\x20\xf6\xe2\xe5\xf2\xe0: " .. tostring(errTop), -1)
            end
        end
        imgui.Spacing()
        imgui.Dummy(imgui.ImVec2(0, S(9)))


        secTitle(u8"\xd0\xe0\xe7\xec\xe5\xf0 \xee\xea\xed\xe0")
        local curWPct = cfg.winWPct > 0 and cfg.winWPct or 0.60
        local curHPct = cfg.winHPct > 0 and cfg.winHPct or 0.76
        St.winWbuf[0] = curWPct
        St.winHbuf[0] = curHPct

        -- Š�Š°Ń€Ń‚Š¾Ń‡ŠŗŠ° Ń� Š´Š²Ń�Š¼Ń¸ Ń�Š»Š°Š¹Š´ŠµŃ€Š°Š¼Šø
        do
            local dl_s = imgui.GetWindowDrawList()
            local pp_s = imgui.GetCursorScreenPos()
            local aw_s = imgui.GetContentRegionAvail().x
            local cardH = S(168)
            dl_s:AddRectFilled(
                imgui.ImVec2(pp_s.x,      pp_s.y),
                imgui.ImVec2(pp_s.x+aw_s, pp_s.y+cardH),
                imgui.ColorConvertFloat4ToU32(iv4(r*0.10,g*0.10,b*0.10,0.92)), 10)
            dl_s:AddRect(
                imgui.ImVec2(pp_s.x,      pp_s.y),
                imgui.ImVec2(pp_s.x+aw_s, pp_s.y+cardH),
                imgui.ColorConvertFloat4ToU32(iv4(r*0.45,g*0.45,b*0.45,0.75)), 10, 0, 1.2)
            imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
            imgui.BeginChild("##sizec", imgui.ImVec2(aw_s, cardH), false,
                imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)

                -- ŠØŠøŃ€ŠøŠ½Š°
                imgui.SetCursorPos(imgui.ImVec2(S(16), S(14)))
                imgui.TextColored(iv4(0.70,0.82,1.0,1.0), u8"\xd8\xe8\xf0\xe8\xed\xe0")
                imgui.SameLine(0,8)
                imgui.TextColored(iv4(1,1,1,1), string.format("%.0f%%", curWPct*100))
                imgui.SameLine(0,6)
                imgui.TextColored(iv4(0.45,0.48,0.55,1.0), string.format("(%.0fpx)", sw*curWPct))
                imgui.SetCursorPos(imgui.ImVec2(S(16), S(44)))
                imgui.PushItemWidth(aw_s - S(32))
                imgui.PushStyleColor(imgui.Col.FrameBg,          iv4(r*0.14,g*0.14,b*0.14,1.0))
                imgui.PushStyleColor(imgui.Col.FrameBgHovered,   iv4(r*0.24,g*0.24,b*0.24,1.0))
                imgui.PushStyleColor(imgui.Col.FrameBgActive,    iv4(r*0.35,g*0.35,b*0.35,1.0))
                imgui.PushStyleColor(imgui.Col.SliderGrab,       iv4(r,g,b,1.0))
                imgui.PushStyleColor(imgui.Col.SliderGrabActive, iv4(math.min(1,r*1.2),math.min(1,g*1.2),math.min(1,b*1.2)))
                imgui.PushStyleColor(imgui.Col.Border, iv4(r*0.7,g*0.7,b*0.7,0.55))
                do local _svc2=0
                if pcall(imgui.PushStyleVar,imgui.StyleVar.FrameRounding,16.0) then _svc2=_svc2+1 end
                if pcall(imgui.PushStyleVar,imgui.StyleVar.GrabRounding,16.0) then _svc2=_svc2+1 end
                if pcall(imgui.PushStyleVar,imgui.StyleVar.GrabMinSize,38.0) then _svc2=_svc2+1 end
                if pcall(imgui.PushStyleVar,imgui.StyleVar.FrameBorderSize,1.2) then _svc2=_svc2+1 end
                if pcall(imgui.PushStyleVar,imgui.StyleVar.FramePadding,imgui.ImVec2(6, 8)) then _svc2=_svc2+1 end
                imgui.SliderFloat("##sw2", St.winWbuf, WIN_W_MIN, 0.98)
                if St.winWbuf[0] < WIN_W_MIN then St.winWbuf[0] = WIN_W_MIN end
                cfg.winWPct = St.winWbuf[0]
                if imgui.IsItemDeactivatedAfterEdit and imgui.IsItemDeactivatedAfterEdit() then
                    _sw_win_init = nil
                    saveCfg()
                end
                if _svc2>0 then pcall(imgui.PopStyleVar,_svc2) end; end
                imgui.PopStyleColor(6)
                imgui.PopItemWidth()

                -- Š’Ń‹Ń�Š¾Ń‚Š°
                imgui.SetCursorPos(imgui.ImVec2(S(16), S(96)))
                imgui.TextColored(iv4(0.70,0.82,1.0,1.0), u8"\xc2\xfb\xf1\xee\xf2\xe0")
                imgui.SameLine(0,8)
                imgui.TextColored(iv4(1,1,1,1), string.format("%.0f%%", curHPct*100))
                imgui.SameLine(0,6)
                imgui.TextColored(iv4(0.45,0.48,0.55,1.0), string.format("(%.0fpx)", sh*curHPct))
                imgui.SetCursorPos(imgui.ImVec2(S(16), S(126)))
                imgui.PushItemWidth(aw_s - S(32))
                imgui.PushStyleColor(imgui.Col.FrameBg,          iv4(r*0.14,g*0.14,b*0.14,1.0))
                imgui.PushStyleColor(imgui.Col.FrameBgHovered,   iv4(r*0.24,g*0.24,b*0.24,1.0))
                imgui.PushStyleColor(imgui.Col.FrameBgActive,    iv4(r*0.35,g*0.35,b*0.35,1.0))
                imgui.PushStyleColor(imgui.Col.SliderGrab,       iv4(r,g,b,1.0))
                imgui.PushStyleColor(imgui.Col.SliderGrabActive, iv4(math.min(1,r*1.2),math.min(1,g*1.2),math.min(1,b*1.2)))
                imgui.PushStyleColor(imgui.Col.Border, iv4(r*0.7,g*0.7,b*0.7,0.55))
                do local _svc2=0
                if pcall(imgui.PushStyleVar,imgui.StyleVar.FrameRounding,16.0) then _svc2=_svc2+1 end
                if pcall(imgui.PushStyleVar,imgui.StyleVar.GrabRounding,16.0) then _svc2=_svc2+1 end
                if pcall(imgui.PushStyleVar,imgui.StyleVar.GrabMinSize,38.0) then _svc2=_svc2+1 end
                if pcall(imgui.PushStyleVar,imgui.StyleVar.FrameBorderSize,1.2) then _svc2=_svc2+1 end
                if pcall(imgui.PushStyleVar,imgui.StyleVar.FramePadding,imgui.ImVec2(6, 8)) then _svc2=_svc2+1 end
                imgui.SliderFloat("##sh2", St.winHbuf, WIN_H_MIN, 0.98)
                if St.winHbuf[0] < WIN_H_MIN then St.winHbuf[0] = WIN_H_MIN end
                cfg.winHPct = St.winHbuf[0]
                if imgui.IsItemDeactivatedAfterEdit and imgui.IsItemDeactivatedAfterEdit() then
                    _sw_win_init = nil
                    saveCfg()
                end
                if _svc2>0 then pcall(imgui.PopStyleVar,_svc2) end; end
                imgui.PopStyleColor(6)
                imgui.PopItemWidth()

            imgui.EndChild()
            imgui.PopStyleColor()
        end
        imgui.Spacing()
        imgui.Dummy(imgui.ImVec2(0, S(9)))

        -- ā”€ā”€ Š Š�Š—Š�Š•Š  ŠØŠ Š�Š¤Š¢Š� ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€
        secTitle(u8"\xd0\xe0\xe7\xec\xe5\xf0 \xf8\xf0\xe8\xf4\xf2\xe0")
        do
            local curFS = cfg.fontSize > 0 and cfg.fontSize or 1.25
            St.fontSizeBuf[0] = curFS
            local dl_f = imgui.GetWindowDrawList()
            local pp_f = imgui.GetCursorScreenPos()
            local aw_f = imgui.GetContentRegionAvail().x
            local cardHf = S(46)
            dl_f:AddRectFilled(
                imgui.ImVec2(pp_f.x,      pp_f.y),
                imgui.ImVec2(pp_f.x+aw_f, pp_f.y+cardHf),
                imgui.ColorConvertFloat4ToU32(iv4(r*0.10,g*0.10,b*0.10,0.92)), 10)
            dl_f:AddRect(
                imgui.ImVec2(pp_f.x,      pp_f.y),
                imgui.ImVec2(pp_f.x+aw_f, pp_f.y+cardHf),
                imgui.ColorConvertFloat4ToU32(iv4(r*0.45,g*0.45,b*0.45,0.75)), 10, 0, 1.2)
            imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
            imgui.BeginChild("##fszc", imgui.ImVec2(aw_f, cardHf), false,
                imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)

                imgui.SetCursorPos(imgui.ImVec2(S(16), (cardHf - S(22))*0.5))
                imgui.TextColored(iv4(0.70,0.82,1.0,1.0), u8"\xd8\xf0\xe8\xf4\xf2")
                imgui.SameLine(0,8)
                imgui.TextColored(iv4(1,1,1,1), string.format("%.0f%%", curFS*100))
                imgui.SameLine(0,10)
                stepBtn("fs_minus", "-", function()
                    cfg.fontSize = math.max(FONT_SIZE_MIN, math.floor((cfg.fontSize - 0.05)*100+0.5)/100)
                    St.fontSizeBuf[0] = cfg.fontSize; saveCfg()
                end, 28, 22)
                imgui.SameLine(0,4)
                stepBtn("fs_plus", "+", function()
                    cfg.fontSize = math.min(FONT_SIZE_MAX, math.floor((cfg.fontSize + 0.05)*100+0.5)/100)
                    St.fontSizeBuf[0] = cfg.fontSize; saveCfg()
                end, 28, 22)

            imgui.EndChild()
            imgui.PopStyleColor()
        end
        imgui.Spacing()
        imgui.Dummy(imgui.ImVec2(0, S(9)))

        -- ── оформление меню: толщина обводки окна, радужная
        -- (переливающаяся) обводка (тумблер "Вкладки как раньше" убран
        -- по просьбе — боковое меню слева теперь всегда включено) ──
        secTitle(u8"\xce\xf4\xee\xf0\xec\xeb\xe5\xed\xe8\xe5\x20\xec\xe5\xed\xfe")
        do
            -- толщина обводки окна
            imgui.TextColored(iv4(0.70,0.82,1.0,1.0), u8"\xd2\xee\xeb\xf9\xe8\xed\xe0\x20\xee\xe1\xe2\xee\xe4\xea\xe8\x20\xec\xe5\xed\xfe")
            imgui.SameLine(0,6)
            imgui.TextColored(iv4(1,1,1,1), string.format("%.1fpx", cfg.borderThickness or 1.2))
            imgui.PushItemWidth(-1)
            St.borderThicknessBuf[0] = cfg.borderThickness or 1.2
            if imgui.SliderFloat("##borderThickSlider", St.borderThicknessBuf, 0.5, 6.0) then
                cfg.borderThickness = St.borderThicknessBuf[0]
                saveCfg()
            end
            imgui.PopItemWidth()
            imgui.Spacing()

            -- радужная (переливающаяся) обводка — тумблер (свитч слева,
            -- подпись справа от него), под ползунком толщины обводки
            local rbOn = cfg.rainbowBorder and true or false
            if drawToggleSwitch("##rainbowBorderToggle", rbOn) then
                cfg.rainbowBorder = not rbOn
                saveCfg()
            end
            imgui.SameLine(0, S(8))
            imgui.TextColored(iv4(0.70,0.82,1.0,1.0), u8"\xd0\xe0\xe4\xf3\xe6\xed\xe0\xff\x20\x28\xef\xe5\xf0\xe5\xeb\xe8\xe2\xe0\xfe\xf9\xe0\xff\xf1\xff\x29\x20\xee\xe1\xe2\xee\xe4\xea\xe0")
        end
        imgui.Spacing()
        imgui.Dummy(imgui.ImVec2(0, S(9)))


    -- ═══════════════════════════════════════════════════════════
    --  ЦВЕТА ИНТЕРФЕЙСА (как в MMT: пресеты + RGB-ряды)
    -- ═══════════════════════════════════════════════════════════
    secTitle(u8"\xc6\xe2\xe5\xf2\xe0 \xe8\xed\xf2\xe5\xf0\xf4\xe5\xe9\xf1\xe0")
    imgui.Spacing()

    -- пресеты (2×3)
    do
        local presets = {
            {u8"\xc7\xe5\xeb\xb8\xed\xe0\xff",     0.25, 0.85, 0.35},
            {u8"\xd1\xe8\xed\xff\xff",             0.25, 0.55, 0.95},
            {u8"\xd4\xe8\xee\xeb\xe5\xf2\xee\xe2\xe0\xff", 0.60, 0.35, 0.90},
            {u8"\xce\xf0\xe0\xed\xe6\xe5\xe2\xe0\xff",     0.95, 0.55, 0.15},
            {u8"\xc2\xe8\xf8\xed\xb8\xe2\xe0\xff",         0.80, 0.20, 0.35},
            {u8"\xc3\xf0\xe0\xf4\xe8\xf2",                 0.55, 0.58, 0.62},
        }
        local gap = S(6)
        local aw = imgui.GetContentRegionAvail().x
        local btnW = (aw - gap * 2) / 3
        for i, p in ipairs(presets) do
            local name, pr, pg, pb = p[1], p[2], p[3], p[4]
            if i > 1 and (i - 1) % 3 ~= 0 then imgui.SameLine(0, gap) end
            imgui.PushStyleColor(imgui.Col.Button,        iv4(pr * 0.55, pg * 0.55, pb * 0.55, 1.0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(pr * 0.75, pg * 0.75, pb * 0.75, 1.0))
            imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(pr, pg, pb, 1.0))
            if imgui.Button(name .. "##preset" .. i, imgui.ImVec2(btnW, S(30))) then
                cfg.custR, cfg.custG, cfg.custB = pr, pg, pb
                if St.custRbuf then St.custRbuf[0], St.custGbuf[0], St.custBbuf[0] = pr, pg, pb end
                cfg.rowBgR, cfg.rowBgG, cfg.rowBgB = pr * 0.35, pg * 0.35, pb * 0.35
                if St.rowBgRbuf then St.rowBgRbuf[0], St.rowBgGbuf[0], St.rowBgBbuf[0] = pr * 0.35, pg * 0.35, pb * 0.35 end
                cfg.outlineR, cfg.outlineG, cfg.outlineB = pr, pg, pb
                if St.outlineRbuf then St.outlineRbuf[0], St.outlineGbuf[0], St.outlineBbuf[0] = pr, pg, pb end
                saveCfg()
            end
            imgui.PopStyleColor(3)
            if i % 3 == 0 and i < #presets then imgui.Dummy(imgui.ImVec2(0, S(4))) end
        end
    end
    imgui.Spacing()

    -- helper: ряд R G B + квадрат + подпись (стиль MMT)
    local function mmtColorRow(labelU8, rKey, gKey, bKey, defR, defG, defB, uid)
        local rr = (cfg[rKey] and cfg[rKey] >= 0) and cfg[rKey] or defR
        local gg = (cfg[gKey] and cfg[gKey] >= 0) and cfg[gKey] or defG
        local bb = (cfg[bKey] and cfg[bKey] >= 0) and cfg[bKey] or defB
        local Ri = math.floor(rr * 255 + 0.5)
        local Gi = math.floor(gg * 255 + 0.5)
        local Bi = math.floor(bb * 255 + 0.5)
        local cellW = S(56)
        local cellH = S(26)
        local gap = S(4)
        -- R/G/B ячейки
        local function cell(txt, col)
            imgui.PushStyleColor(imgui.Col.Button, col)
            imgui.PushStyleColor(imgui.Col.ButtonHovered, col)
            imgui.PushStyleColor(imgui.Col.ButtonActive, col)
            imgui.Button(txt, imgui.ImVec2(cellW, cellH))
            imgui.PopStyleColor(3)
        end
        cell(string.format("R: %d##%sr", Ri, uid), iv4(rr * 0.55 + 0.15, 0.12, 0.12, 1.0))
        imgui.SameLine(0, gap)
        cell(string.format("G: %d##%sg", Gi, uid), iv4(0.12, gg * 0.55 + 0.15, 0.12, 1.0))
        imgui.SameLine(0, gap)
        cell(string.format("B: %d##%sb", Bi, uid), iv4(0.12, 0.12, bb * 0.55 + 0.15, 1.0))
        imgui.SameLine(0, gap)
        -- квадрат-пикер
        local key = "_mmtVec_" .. uid
        if not St[key] then St[key] = imgui.new.float[3](rr, gg, bb) end
        St[key][0], St[key][1], St[key][2] = rr, gg, bb
        imgui.PushItemWidth(S(36))
        local flags = 0
        pcall(function()
            flags = imgui.ColorEditFlags.NoInputs + imgui.ColorEditFlags.NoLabel
                + (imgui.ColorEditFlags.PickerHueBar or 0)
        end)
        if imgui.ColorEdit3("##mmt" .. uid, St[key], flags) then
            cfg[rKey], cfg[gKey], cfg[bKey] = St[key][0], St[key][1], St[key][2]
            -- синхрон буферов если есть
            if uid == "main" and St.custRbuf then
                St.custRbuf[0], St.custGbuf[0], St.custBbuf[0] = cfg[rKey], cfg[gKey], cfg[bKey]
            elseif uid == "text" and St.textRbuf then
                St.textRbuf[0], St.textGbuf[0], St.textBbuf[0] = cfg[rKey], cfg[gKey], cfg[bKey]
            elseif uid == "bg" and St.winBgRbuf then
                St.winBgRbuf[0], St.winBgGbuf[0], St.winBgBbuf[0] = cfg[rKey], cfg[gKey], cfg[bKey]
            elseif uid == "acc" and St.outlineRbuf then
                St.outlineRbuf[0], St.outlineGbuf[0], St.outlineBbuf[0] = cfg[rKey], cfg[gKey], cfg[bKey]
            elseif uid == "chat" and St.chatRbuf then
                St.chatRbuf[0], St.chatGbuf[0], St.chatBbuf[0] = cfg[rKey], cfg[gKey], cfg[bKey]
            end
            saveCfg()
        end
        imgui.PopItemWidth()
        imgui.SameLine(0, S(8))
        imgui.TextColored(iv4(1, 1, 1, 1), labelU8)
        imgui.Dummy(imgui.ImVec2(0, S(2)))
    end

    local ar, ag, ab = getAcc()
    mmtColorRow(u8"\xce\xf1\xed\xee\xe2\xed\xee\xe9 \xf6\xe2\xe5\xf2", "custR", "custG", "custB", ar, ag, ab, "main")
    mmtColorRow(u8"\xc6\xe2\xe5\xf2 \xf2\xe5\xea\xf1\xf2\xe0", "textR", "textG", "textB", 1.0, 1.0, 1.0, "text")
    mmtColorRow(u8"\xc6\xe2\xe5\xf2 \xf4\xee\xed\xe0", "winBgR", "winBgG", "winBgB", 0.0, 0.0, 0.0, "bg")
    mmtColorRow(u8"\xc0\xea\xf6\xe5\xed\xf2", "outlineR", "outlineG", "outlineB", ar, ag, ab, "acc")
    mmtColorRow(u8"\xcf\xf0\xe5\xf4\xe8\xea\xf1 \xf1\xea\xf0\xe8\xef\xf2\xe0 \xe2 \xf7\xe0\xf2\xe5", "chatR", "chatG", "chatB", 0.0, 1.0, 0.53, "chat")

    imgui.Spacing()
    imgui.TextColored(thDim(), u8"\xd1\xec\xfb\xf1\xeb\xee\xe2\xfb\xe5 \xf6\xe2\xe5\xf2\xe0:")
    imgui.Spacing()
    mmtColorRow(u8"\xd3\xf1\xef\xe5\xf5 / \xe3\xee\xf2\xee\xe2\xee", "successR", "successG", "successB", 0.25, 0.92, 0.48, "ok")
    mmtColorRow(u8"\xcf\xf0\xe5\xe4\xf3\xef\xf0\xe5\xe6\xe4\xe5\xed\xe8\xe5", "warnR", "warnG", "warnB", 1.0, 0.82, 0.20, "warn")
    mmtColorRow(u8"\xce\xf8\xe8\xe1\xea\xe0 / \xee\xef\xe0\xf1\xed\xee\xf1\xf2\xfc", "errorR", "errorG", "errorB", 1.0, 0.30, 0.30, "err")

    imgui.Spacing()
    -- сброс цветов
    do
        local pr, pg, pb = getAcc()
        imgui.PushStyleColor(imgui.Col.Button,        iv4(0.45, 0.12, 0.12, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(0.65, 0.18, 0.18, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(0.85, 0.25, 0.25, 1.0))
        if imgui.Button(u8"\xd1\xe1\xf0\xee\xf1 \xf6\xe2\xe5\xf2\xee\xe2 \xea \xf3\xec\xee\xeb\xf7\xe0\xed\xe8\xfe##resetColors", imgui.ImVec2(-1, S(28))) then
            cfg.custR, cfg.custG, cfg.custB = -1, -1, -1
            cfg.textR, cfg.textG, cfg.textB = -1, -1, -1
            cfg.winBgR, cfg.winBgG, cfg.winBgB = -1, -1, -1
            cfg.outlineR, cfg.outlineG, cfg.outlineB = -1, -1, -1
            cfg.chatR, cfg.chatG, cfg.chatB = -1, -1, -1
            cfg.rowBgR, cfg.rowBgG, cfg.rowBgB = -1, -1, -1
            cfg.successR, cfg.successG, cfg.successB = -1, -1, -1
            cfg.warnR, cfg.warnG, cfg.warnB = -1, -1, -1
            cfg.errorR, cfg.errorG, cfg.errorB = -1, -1, -1
            saveCfg()
        end
        imgui.PopStyleColor(3)
    end
    imgui.Spacing()
    imgui.Dummy(imgui.ImVec2(0, S(6)))


secTitle(u8"\xd1\xeb\xf3\xf7\xe0\xe9\xed\xfb\xe9\x20\xf6\xe2\xe5\xf2")
    do
        local pr4,pg4,pb4 = getAcc()
        imgui.PushStyleColor(imgui.Col.Button,        iv4(pr4*0.35,pg4*0.35,pb4*0.35,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(pr4*0.55,pg4*0.55,pb4*0.55,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(pr4*0.75,pg4*0.75,pb4*0.75,1.0))
        do local _pbRnd = prettyBtnPush(9.0)
        if imgui.Button(u8"\xd1\xeb\xf3\xf7\xe0\xe9\xed\xfb\xe9\x20\xf6\xe2\xe5\xf2##randomAccentColor", imgui.ImVec2(imgui.GetContentRegionAvail().x, S(34))) then
            math.randomseed((os.time() or 0) + (os.clock() or 0) * 1000)
            -- акцент/фон строк — не слишком тёмные (0.35..1.0 на канал),
            -- чтобы оставались хорошо заметны на тёмном фоне
            local rr = 0.35 + math.random() * 0.65
            local gg = 0.35 + math.random() * 0.65
            local bb = 0.35 + math.random() * 0.65
            cfg.custR, cfg.custG, cfg.custB = rr, gg, bb
            St.custRbuf[0], St.custGbuf[0], St.custBbuf[0] = rr, gg, bb

            local rr2 = 0.35 + math.random() * 0.65
            local gg2 = 0.35 + math.random() * 0.65
            local bb2 = 0.35 + math.random() * 0.65
            cfg.rowBgR, cfg.rowBgG, cfg.rowBgB = rr2, gg2, bb2
            St.rowBgRbuf[0], St.rowBgGbuf[0], St.rowBgBbuf[0] = rr2, gg2, bb2

            -- текст — держим светлым (0.75..1.0 на канал), чтобы оставался читаемым
            local rt = 0.75 + math.random() * 0.25
            local gt = 0.75 + math.random() * 0.25
            local bt = 0.75 + math.random() * 0.25
            cfg.textR, cfg.textG, cfg.textB = rt, gt, bt
            St.textRbuf[0], St.textGbuf[0], St.textBbuf[0] = rt, gt, bt

            -- фон скрипта больше не рандомизируется (по просьбе убрана
            -- возможность менять фон вручную) — остаётся от темы

            -- обводка — как акцент/фон строк, хорошо заметная
            local ro = 0.35 + math.random() * 0.65
            local go = 0.35 + math.random() * 0.65
            local bo = 0.35 + math.random() * 0.65
            cfg.outlineR, cfg.outlineG, cfg.outlineB = ro, go, bo
            St.outlineRbuf[0], St.outlineGbuf[0], St.outlineBbuf[0] = ro, go, bo

            saveCfg()
        end
        prettyBtnPop(_pbRnd) end
        imgui.PopStyleColor(3)
    end

    -- ── по просьбе: вкладка "Уведомления" перенесена сюда же, в
    -- "Настройки", отдельным разделом ниже (была отдельной вкладкой) ──
    imgui.Dummy(imgui.ImVec2(0, S(9)))
    imgui.Separator()
    imgui.Dummy(imgui.ImVec2(0, S(9)))
    
    
    -- (самообновление реализовано: карточка "Обновления" во вкладке
    -- "О скрипте", см. PCS_UPDATE / drawAboutInner)

    drawNotificationsSection()

    -- ── нижний отступ, чтобы последний блок не прилипал к краю окна ──
    imgui.Dummy(imgui.ImVec2(0, S(40)))
end

local function drawSettings(h, sw, sh)
    imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
    imgui.BeginChild("##sset", imgui.ImVec2(0, h), false)
    local ok, err = PCS_GUARD.call(drawSettingsInner, h, sw, sh)
    imgui.EndChild()
    imgui.PopStyleColor()
    St._resetSettScroll = false
    if not ok then
        pcall(sampAddChatMessage, "{FF6666}[PC Stats] " ..
            "\xee\xf8\xe8\xe1\xea\xe0\x20\xee\xf2\xf0\xe8\xf1\xee\xe2\xea\xe8\x20\xe2\xea\xeb\xe0\xe4\xea\xe8\x20\xcd\xe0\xf1\xf2\xf0\xee\xe9\xea\xe8: " .. tostring(err), -1)
    end
end

-- ============================================================
--  РАЗДЕЛ "УВЕДОМЛЕНИЯ" (по просьбе объединён внутрь вкладки "Настройки",
--  рисуется как продолжение того же скролла — своего собственного
--  child-окна и отступов сверху/снизу больше нет, см. вызов выше) —
--  оформление тостов + сообщение при входе + напоминание про PayDay +
--  уведомление об обновлении курса валют. cfg.toastEnabled — главный
--  переключатель, при выключении отключает ВСЕ уведомления разом ──
-- ============================================================
function drawNotificationsSection()
    local _tcAw = imgui.GetContentRegionAvail().x

    -- ── главный переключатель: отключает АБСОЛЮТНО все всплывающие
    -- уведомления разом (тосты + PayDay/курс/вход) — pcs_notify сам
    -- проверяет cfg.toastEnabled на входе, так что остальным местам
    -- ничего дополнительно проверять не нужно ──
    secTitle(u8"\xc3\xeb\xe0\xe2\xed\xfb\xe9\x20\xef\xe5\xf0\xe5\xea\xeb\xfe\xf7\xe0\xf2\xe5\xeb\xfc")
    do
        local isOn = cfg.toastEnabled ~= false
        if drawToggleSwitch("##toastEnabledToggle", isOn) then
            cfg.toastEnabled = not isOn
            saveCfg()
            pcs_apply_toast_settings()
        end
        imgui.SameLine(0, S(8))
        imgui.TextColored(iv4(1,1,1,1), u8"\xc2\xea\xeb\xfe\xf7\xe8\xf2\xfc\x20\xe2\xf1\xe5\x20\xe2\xf1\xef\xeb\xfb\xe2\xe0\xfe\xf9\xe8\xe5\x20\xf3\xe2\xe5\xe4\xee\xec\xeb\xe5\xed\xe8\xff")
    end

    imgui.Dummy(imgui.ImVec2(0, S(9)))
    imgui.Separator()
    imgui.Dummy(imgui.ImVec2(0, S(6)))

    -- ── три отдельных вида уведомлений — каждый со своим тумблером,
    -- дополнительно к общему выключателю выше ──
    secTitle(u8"\xd2\xe8\xef\xfb\x20\xf3\xe2\xe5\xe4\xee\xec\xeb\xe5\xed\xe8\xe9")
    do
        local isOn = cfg.notifyWelcomeEnabled ~= false
        if drawToggleSwitch("##notifyWelcomeToggle", isOn) then
            cfg.notifyWelcomeEnabled = not isOn; saveCfg()
        end
        imgui.SameLine(0, S(8))
        imgui.TextColored(iv4(1,1,1,1), u8"\xd1\xee\xee\xe1\xf9\xe5\xed\xe8\xe5\x20\xef\xf0\xe8\x20\xe2\xf5\xee\xe4\xe5\x20\x28\xea\xee\xec\xe0\xed\xe4\xe0\x20\xee\xf2\xea\xf0\xfb\xf2\xe8\xff\x20\xec\xe5\xed\xfe\x29")
    end
    imgui.Spacing()
    do
        local isOn = cfg.notifyPaydayReminderEnabled ~= false
        if drawToggleSwitch("##notifyPdReminderToggle", isOn) then
            cfg.notifyPaydayReminderEnabled = not isOn; saveCfg()
        end
        imgui.SameLine(0, S(8))
        imgui.TextColored(iv4(1,1,1,1), u8"\xcd\xe0\xef\xee\xec\xe8\xed\xe0\xed\xe8\xe5\x20\xe7\xe0\x20\x35\x20\xec\xe8\xed\xf3\xf2\x20\xe4\xee\x20PayDay")
    end

    -- ФИКС (по просьбе): тумблер "Обновление курса валют" убран совсем.
    -- ФИКС (по просьбе): тумблер "Автообновлять курс по таймеру" и слайдер
    -- интервала убраны совсем — обновление курса больше не выполняется
    -- по таймеру автоматически.

    imgui.Dummy(imgui.ImVec2(0, S(9)))
    imgui.Separator()
    imgui.Dummy(imgui.ImVec2(0, S(6)))

    -- ── оформление плашек (тосты) ──
    secTitle(u8"\xce\xf4\xee\xf0\xec\xeb\xe5\xed\xe8\xe5\x20\xef\xeb\xe0\xf8\xe5\xea")

    imgui.Spacing()
    imgui.TextColored(thDim(), u8"\xcf\xee\xeb\xee\xe6\xe5\xed\xe8\xe5\x20\xed\xe0\x20\xfd\xea\xf0\xe0\xed\xe5")
    do
        local r0,g0,b0 = getAcc()
        local function _posBtn(lbl, active, onClick)
            if active then
                imgui.PushStyleColor(imgui.Col.Button,        iv4(r0,g0,b0,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(r0,g0,b0,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(r0,g0,b0,1.0))
            else
                imgui.PushStyleColor(imgui.Col.Button,        iv4(r0*0.25,g0*0.25,b0*0.25,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(r0*0.45,g0*0.45,b0*0.45,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(r0*0.65,g0*0.65,b0*0.65,1.0))
            end
            if imgui.Button(lbl, imgui.ImVec2((_tcAw - S(12))/4, S(28))) then onClick() end
            imgui.PopStyleColor(3)
        end
        _posBtn(u8"\xd1\xeb\xe5\xe2\xe0##toastPosLeft", cfg.toastPosH == "left", function()
            cfg.toastPosH = "left"; saveCfg(); pcs_apply_toast_settings()
        end)
        imgui.SameLine(0, S(4))
        _posBtn(u8"\xd1\xef\xf0\xe0\xe2\xe0##toastPosRight", cfg.toastPosH ~= "left", function()
            cfg.toastPosH = "right"; saveCfg(); pcs_apply_toast_settings()
        end)
        imgui.SameLine(0, S(4))
        _posBtn(u8"\xd1\xe2\xe5\xf0\xf5\xf3##toastPosTop", cfg.toastPosV == "top", function()
            cfg.toastPosV = "top"; saveCfg(); pcs_apply_toast_settings()
        end)
        imgui.SameLine(0, S(4))
        _posBtn(u8"\xd1\xed\xe8\xe7\xf3##toastPosBottom", cfg.toastPosV ~= "top", function()
            cfg.toastPosV = "bottom"; saveCfg(); pcs_apply_toast_settings()
        end)
    end

    imgui.Spacing()
    do
        if not St.toastWidthBuf then St.toastWidthBuf = imgui.new.float(cfg.toastWidth or 320) end
        imgui.TextColored(thDim(), u8"\xd8\xe8\xf0\xe8\xed\xe0\x20\xef\xeb\xe0\xf8\xea\xe8")
        imgui.SetNextItemWidth(_tcAw)
        if imgui.SliderFloat("##toastWidth", St.toastWidthBuf, 200, 520, "%.0f px") then
            cfg.toastWidth = St.toastWidthBuf[0]; saveCfg(); pcs_apply_toast_settings()
        end
    end

    imgui.Spacing()
    do
        if not St.toastRoundBuf then St.toastRoundBuf = imgui.new.float(cfg.toastCornerRadius or 8) end
        imgui.TextColored(thDim(), u8"\xd1\xea\xf0\xf3\xe3\xeb\xe5\xed\xe8\xe5\x20\xf3\xe3\xeb\xee\xe2")
        imgui.SetNextItemWidth(_tcAw)
        if imgui.SliderFloat("##toastRound", St.toastRoundBuf, 0, 20, "%.0f") then
            cfg.toastCornerRadius = St.toastRoundBuf[0]; saveCfg(); pcs_apply_toast_settings()
        end
    end

    imgui.Spacing()
    do
        if not St.toastDurBuf then St.toastDurBuf = imgui.new.float(cfg.toastDuration or 6.0) end
        imgui.TextColored(thDim(), u8"\xc4\xeb\xe8\xf2\xe5\xeb\xfc\xed\xee\xf1\xf2\xfc\x20\xef\xee\xea\xe0\xe7\xe0\x2c\x20\xf1\xe5\xea")
        imgui.SetNextItemWidth(_tcAw)
        if imgui.SliderFloat("##toastDuration", St.toastDurBuf, 1.5, 20.0, "%.1f") then
            cfg.toastDuration = St.toastDurBuf[0]; saveCfg(); pcs_apply_toast_settings()
        end
    end

    imgui.Spacing()
    do
        if not St.toastAnimBuf then St.toastAnimBuf = imgui.new.float(cfg.toastAnimSpeed or 10.0) end
        imgui.TextColored(thDim(), u8"\xd1\xea\xee\xf0\xee\xf1\xf2\xfc\x20\xe0\xed\xe8\xec\xe0\xf6\xe8\xe8\x20\xef\xee\xff\xe2\xeb\xe5\xed\xe8\xff\x2f\xe8\xf1\xf7\xe5\xe7\xed\xee\xe2\xe5\xed\xe8\xff")
        imgui.SetNextItemWidth(_tcAw)
        if imgui.SliderFloat("##toastAnim", St.toastAnimBuf, 2.0, 25.0, "%.1f") then
            cfg.toastAnimSpeed = St.toastAnimBuf[0]; saveCfg(); pcs_apply_toast_settings()
        end
    end

    imgui.Spacing()
    do
        if not St.toastMaxvBuf then St.toastMaxvBuf = imgui.new.float(cfg.toastMaxVisible or 5) end
        imgui.TextColored(thDim(), u8"\xcc\xe0\xea\xf1\x2e\x20\xef\xeb\xe0\xf8\xe5\xea\x20\xee\xe4\xed\xee\xe2\xf0\xe5\xec\xe5\xed\xed\xee")
        imgui.SetNextItemWidth(_tcAw)
        if imgui.SliderFloat("##toastMaxv", St.toastMaxvBuf, 1, 10, "%.0f") then
            cfg.toastMaxVisible = math.floor(St.toastMaxvBuf[0]); saveCfg(); pcs_apply_toast_settings()
        end
    end

    imgui.Spacing()
    do
        if not St.toastBgBuf then
            St.toastBgBuf = imgui.new.float[3](cfg.toastBgR or 0.08, cfg.toastBgG or 0.08, cfg.toastBgB or 0.10)
        end
        imgui.TextColored(thDim(), u8"\xd6\xe2\xe5\xf2\x20\xf4\xee\xed\xe0")
        imgui.SetNextItemWidth(_tcAw)
        if imgui.ColorEdit3("##toastBg", St.toastBgBuf) then
            cfg.toastBgR, cfg.toastBgG, cfg.toastBgB = St.toastBgBuf[0], St.toastBgBuf[1], St.toastBgBuf[2]
            saveCfg(); pcs_apply_toast_settings()
        end
    end

    imgui.Spacing()
    do
        if not St.toastTextBuf then
            St.toastTextBuf = imgui.new.float[3](cfg.toastTextR or 0.94, cfg.toastTextG or 0.94, cfg.toastTextB or 0.96)
        end
        imgui.TextColored(thDim(), u8"\xd6\xe2\xe5\xf2\x20\xf2\xe5\xea\xf1\xf2\xe0")
        imgui.SetNextItemWidth(_tcAw)
        if imgui.ColorEdit3("##toastText", St.toastTextBuf) then
            cfg.toastTextR, cfg.toastTextG, cfg.toastTextB = St.toastTextBuf[0], St.toastTextBuf[1], St.toastTextBuf[2]
            saveCfg(); pcs_apply_toast_settings()
        end
    end

    -- ФИКС (по просьбе): ручной тумблер "Рамка плашки" убран — теперь
    -- рамка у уведомлений включается автоматически, синхронно с
    -- "Радужная (переливающейся) обводкой" главного меню (см. cfg.rainbowBorder,
    -- вкладка "Настройки" → "Оформление меню"). См. _draw_toast ниже.

    -- ── по просьбе: кнопки, чтобы проверить, как выглядят всплывающие
    -- уведомления, прямо здесь в настройках, не выходя и не дожидаясь
    -- реального события (оплаты, курса и т.п.) ──
    imgui.Dummy(imgui.ImVec2(0, S(9)))
    imgui.Separator()
    imgui.Dummy(imgui.ImVec2(0, S(6)))
    secTitle(u8"\xd2\xe5\xf1\xf2\x20\xf3\xe2\xe5\xe4\xee\xec\xeb\xe5\xed\xe8\xe9")
    imgui.Spacing()
    do
        local btnW = (_tcAw - S(12)) / 4
        -- ФИКС (по просьбе): кнопки "Тест" теперь окрашены под цвет
        -- реального уведомления этого типа (PCS_NOTIF_COLORS, см. выше по
        -- файлу) — раньше все пять кнопок были одинаковыми серыми, и
        -- нельзя было сразу понять, какая кнопка какой тип покажет
        local function _testBtn(lbl, kind)
            local c = (PCS_NOTIF_COLORS and PCS_NOTIF_COLORS[kind]) or {getAcc()}
            imgui.PushStyleColor(imgui.Col.Button,        iv4(c[1]*0.45, c[2]*0.45, c[3]*0.45, 1.0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(c[1]*0.75, c[2]*0.75, c[3]*0.75, 1.0))
            imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(c[1],      c[2],      c[3],      1.0))
            if imgui.Button(lbl, imgui.ImVec2(btnW, S(28))) then
                pcall(pcs_toast_test, kind)
            end
            imgui.PopStyleColor(3)
        end
        _testBtn(u8"\xc8\xed\xf4\xee##toastTestInfo", "info")
        imgui.SameLine(0, S(4))
        _testBtn(u8"\xd3\xf1\xef\xe5\xf5##toastTestOk", "success")
        imgui.SameLine(0, S(4))
        _testBtn(u8"\xc2\xed\xe8\xec\xe0\xed\xe8\xe5##toastTestWarn", "warning")
        imgui.SameLine(0, S(4))
        _testBtn(u8"\xce\xf8\xe8\xe1\xea\xe0##toastTestErr", "error")
        imgui.SameLine(0, S(4))
        _testBtn(u8"PayDay##toastTestPd", "payday")
    end
end

-- ============================================================
--  Š’Š�Š›Š�Š”Š�Š� 4: Š˛ Š�Š�Š Š�Š�Š¢Š•  (Š²Ń�Šµ Š±Š»Š¾ŠŗŠø Ń� ŠŗŃ€Š°Ń�ŠøŠ²Š¾Š¹ Ń€Š°Š¼ŠŗŠ¾Š¹)
-- ============================================================
-- FIX (po prosbe): obschaya panel "Nastroyki" -- otdelnoe okno,
-- pristykovannoe sprava ot glavnogo okna (po umolchaniyu) ili svobodno
-- peremeschaemoe ("Otkrepit"), kotoroe mozhno otkryt ikonkoy-shesterenkoy
-- iz LYUBOY vkladki, ne pereklyuchayas na samu vkladku "Nastroyki".
-- Soderzhimoe -- tot zhe samyy drawSettings(), chto i v obychnoy vkladke,
-- prosto otrisovannyy v bolee uzkom konteynere --
local function drawGlobalSettingsPanel()
    if not St._settingsPanelOpen then return end
    if not St._mainWinPos or not St._mainWinSize then return end

    local panelW = S(340)
    local sw = imgui.GetIO().DisplaySize.x
    local sh = imgui.GetIO().DisplaySize.y

    if not St._settingsPanelDetached then
        imgui.SetNextWindowPos(imgui.ImVec2(St._mainWinPos.x + St._mainWinSize.x + S(10), St._mainWinPos.y), imgui.Cond.Always)
        imgui.SetNextWindowSize(imgui.ImVec2(panelW, St._mainWinSize.y), imgui.Cond.Always)
    else
        imgui.SetNextWindowSize(imgui.ImVec2(panelW, St._mainWinSize.y), imgui.Cond.Once)
        if _settingsPanelPos then
            imgui.SetNextWindowPos(imgui.ImVec2(_settingsPanelPos.x, _settingsPanelPos.y), imgui.Cond.Once)
        else
            imgui.SetNextWindowPos(imgui.ImVec2(St._mainWinPos.x + St._mainWinSize.x + S(10), St._mainWinPos.y), imgui.Cond.Once)
        end
    end

    applyStyle()
    local flags = imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoTitleBar

    -- ФИКС (п.1): Begin/содержимое/End теперь под pcall с гарантированным
    -- End — ошибка внутри панели больше не оставляет imgui-стек "разомкнутым"
    -- на следующий кадр (класс крашей "оплатил налоги → краш"). При ошибке
    -- панель принудительно закрывается, чтобы не пытаться рисоваться каждый
    -- кадр и не спамить чат.
    local beganWin = false
    local ok, err = pcall(function()
    imgui.Begin("###globalSettingsPanel", nil, flags)
    beganWin = true
    imgui.SetWindowFontScale(St.UI_SCALE * (cfg.fontSize > 0 and cfg.fontSize or 1.25))

    if St._settingsPanelDetached then
        local okP, p = pcall(imgui.GetWindowPos)
        if okP and p then _settingsPanelPos = {x = p.x, y = p.y} end
    end

    do
        local aw = imgui.GetContentRegionAvail().x
        imgui.TextColored(iv4(1,1,1,1), ICON_USER .. "  " .. u8"\xc8\xe3\xf0\xee\xea\x20\xe8\x20\xed\xe0\xf1\xf2\xf0\xee\xe9\xea\xe8")
        imgui.SameLine(math.max(0, aw - S(104)))
        local pr,pg,pb = getAcc()
        imgui.PushStyleColor(imgui.Col.Button,        iv4(pr*0.22,pg*0.22,pb*0.22,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(pr*0.40,pg*0.40,pb*0.40,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(pr*0.58,pg*0.58,pb*0.58,1.0))
        local detachLbl = St._settingsPanelDetached
            and u8"\xc7\xe0\xea\xf0\xe5\xef\xe8\xf2\xfc"
            or  u8"\xce\xf2\xea\xf0\xe5\xef\xe8\xf2\xfc"
        if imgui.Button(detachLbl.."##settingsPanelDetachBtn", imgui.ImVec2(S(104), S(24))) then
            St._settingsPanelDetached = not St._settingsPanelDetached
            if St._settingsPanelDetached then
                local okP, p = pcall(imgui.GetWindowPos)
                if okP and p then _settingsPanelPos = {x = p.x, y = p.y} end
            end
        end
        imgui.PopStyleColor(3)
    end
    imgui.Separator()
    imgui.Spacing()

    -- ── ФИКС (по просьбе): краткая карточка с ником игрока/сервером и
    -- быстрым тумблером всплывающих уведомлений — открывается по клику
    -- на ту же кнопку-иконку, что раньше открывала только настройки.
    -- Полные настройки (включая раздел про сами уведомления, где можно
    -- настроить цвет/позицию/размер/длительность) остаются ниже ──
    do
        local r0,g0,b0 = getAcc()
        local aw2 = imgui.GetContentRegionAvail().x
        local cardH = S(78)
        local dl = imgui.GetWindowDrawList()
        local cp = imgui.GetCursorScreenPos()
        dl:AddRectFilled(
            imgui.ImVec2(cp.x, cp.y),
            imgui.ImVec2(cp.x+aw2, cp.y+cardH),
            imgui.ColorConvertFloat4ToU32(iv4(r0*0.14,g0*0.14,b0*0.14,1.0)), 8)
        dl:AddRect(
            imgui.ImVec2(cp.x, cp.y),
            imgui.ImVec2(cp.x+aw2, cp.y+cardH),
            imgui.ColorConvertFloat4ToU32(iv4(r0*0.55,g0*0.55,b0*0.55,0.55)), 8, 0, 1)

        imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
        imgui.BeginChild("##globalProfileCard", imgui.ImVec2(aw2, cardH), false)
        imgui.SetCursorPos(imgui.ImVec2(S(10), S(8)))

        local nick = (St.statsData and hasVal(St.statsData.name)) and St.statsData.name
            or u8"\xcd\xe5\xe8\xe7\xe2\xe5\xf1\xf2\xed\xee\x20\x28\xed\xe5\xf2\x20\x2f\x73\x74\x61\x74\x73\x29"
        local srv = (cfg.vcAutoDetectServer and detectArzServerName()) or cfg.vcServerName
        if not hasVal(srv) then srv = u8"\xcd\xe5\x20\xee\xef\xf0\xe5\xe4\xe5\xeb\xb8\xed" end

        imgui.TextColored(iv4(0.75,0.75,0.80,1.0), u8"\xcd\xe8\xea")
        imgui.SameLine(S(70))
        imgui.TextColored(iv4(1,1,1,1), tostring(nick))

        imgui.SetCursorPos(imgui.ImVec2(S(10), S(30)))
        imgui.TextColored(iv4(0.75,0.75,0.80,1.0), u8"\xd1\xe5\xf0\xe2\xe5\xf0")
        imgui.SameLine(S(70))
        imgui.TextColored(iv4(1,1,1,1), tostring(srv))

        imgui.SetCursorPos(imgui.ImVec2(S(10), S(52)))
        do
            local isOn = cfg.toastEnabled ~= false
            if drawToggleSwitch("##profileToastToggle", isOn) then
                cfg.toastEnabled = not isOn
                saveCfg()
                pcs_apply_toast_settings()
            end
            imgui.SameLine(0, S(8))
            imgui.TextColored(iv4(1,1,1,1), u8"\xc2\xea\xeb\xfe\xf7\xe8\xf2\xfc\x20\xf3\xe2\xe5\xe4\xee\xec\xeb\xe5\xed\xe8\xff")
        end
        imgui.EndChild()
        imgui.PopStyleColor()
        imgui.Dummy(imgui.ImVec2(0, S(6)))
    end

    local panelContentH = imgui.GetContentRegionAvail().y - S(38)
    drawSettings(panelContentH, sw, sh)

    do
        local pr,pg,pb = getAcc()
        imgui.PushStyleColor(imgui.Col.Button,        iv4(pr*0.22,pg*0.22,pb*0.22,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(pr*0.40,pg*0.40,pb*0.40,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(pr*0.58,pg*0.58,pb*0.58,1.0))
        do local _pbc = prettyBtnPush(8.0)
        if imgui.Button(u8"\xc7\xe0\xea\xf0\xfb\xf2\xfc##closeGlobalSettingsPanel", imgui.ImVec2(imgui.GetContentRegionAvail().x, S(30))) then
            St._settingsPanelOpen = false
        end
        prettyBtnPop(_pbc) end
        imgui.PopStyleColor(3)
    end
    end) -- конец pcall

    if beganWin then pcall(imgui.End) end
    if not ok then
        St._settingsPanelOpen = false
        pcall(sampAddChatMessage, "{FF6666}[PC Stats] " ..
            "\xee\xf8\xe8\xe1\xea\xe0\x20\xef\xe0\xed\xe5\xeb\xe8\x20\xed\xe0\xf1\xf2\xf0\xee\xe5\xea: " .. tostring(err), -1)
    end
end

-- ── п.6/14: тонкое всплывающее окно профиля в правом верхнем углу —
-- ТОЛЬКО ник (крупно), ЗП ниже, сервер ниже, и итоговая сумма со
-- вкладки "Финансы" (см. computeGrandTotal), продублированная сюда.
-- Раньше та же кнопка открывала целую боковую панель с полными
-- настройками — по просьбе оставляем только эту компактную карточку;
-- полные настройки остаются доступны на вкладке "Настройки" ──
local function drawProfilePopup()
    if not St._profilePopupOpen then
        St._profilePopupOpenedOnce = false
        return
    end
    if not St._profilePopupOpenedOnce then
        St._profilePopupOpenedOnce = true
        pcall(imgui.OpenPopup, "##pcsProfilePopup")
    end
    pcall(imgui.SetNextWindowSize, imgui.ImVec2(S(220), 0), imgui.Cond and imgui.Cond.Appearing or 0)
    local _mpsP = pushModernPopupStyle()

    -- ФИКС (п.2): BeginPopup/содержимое/EndPopup под pcall, EndPopup
    -- гарантирован через beganPopup. popModernPopupStyle остаётся снаружи
    -- pcall (как и раньше) — стиль снимается со стека в любом случае.
    local beganPopup = false
    local ok, err = pcall(function()
    if imgui.BeginPopup("##pcsProfilePopup") then
        beganPopup = true
        local s = St.statsData or {}
        local nick = hasVal(s.name) and s.name
            or u8"\xcd\xe5\xe8\xe7\xe2\xe5\xf1\xf2\xed\xee"
        local srv = (cfg.vcAutoDetectServer and detectArzServerName()) or cfg.vcServerName
        if not hasVal(srv) then srv = u8"\xcd\xe5\x20\xee\xef\xf0\xe5\xe4\xe5\xeb\xb8\xed" end

        -- ЗП: берём зарплату из самой свежей записи лога PayDay, если
        -- она есть за сегодня — иначе просто текущий банк как ближайший
        -- доступный эквивалент "заработка"
        local salaryVal = nil
        if St.incomeEntries and #St.incomeEntries > 0 then
            local today = os.date("%Y-%m-%d")
            for i = #St.incomeEntries, 1, -1 do
                local e = St.incomeEntries[i]
                if e.date == today then salaryVal = e.salary; break end
            end
        end
        if not salaryVal then salaryVal = toNum(s.bank) end

        local grand = computeGrandTotal(s)

        pcall(imgui.SetWindowFontScale, 1.25)
        imgui.TextColored(iv4(1,1,1,1), tostring(nick))
        pcall(imgui.SetWindowFontScale, 1.0)

        imgui.Spacing()
        imgui.TextColored(thDim(), u8"\xd7\xcf")
        imgui.SameLine(0, S(6))
        imgui.TextColored(iv4(0.95,0.95,1.0,1.0), fmtMoney(string.format("%.0f", salaryVal)))

        imgui.Spacing()
        imgui.TextColored(thDim(), u8"\xd1\xe5\xf0\xe2\xe5\xf0")
        imgui.SameLine(0, S(6))
        imgui.TextColored(iv4(0.95,0.95,1.0,1.0), tostring(srv))

        imgui.Dummy(imgui.ImVec2(0, S(4)))
        imgui.Separator()
        imgui.Dummy(imgui.ImVec2(0, S(4)))

        imgui.TextColored(thDim(), u8"\xc2\xd1\xc5\xc3\xce\x20\xc2\xc8\xd0\xd2\xce\xc2")
        imgui.TextColored(thGold(), fmtMoney(string.format("%.0f", grand)))

        imgui.Dummy(imgui.ImVec2(0, S(6)))
        local pr,pg,pb = getAcc()
        imgui.PushStyleColor(imgui.Col.Button,        iv4(pr*0.25,pg*0.25,pb*0.25,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(pr*0.45,pg*0.45,pb*0.45,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(pr*0.65,pg*0.65,pb*0.65,1.0))
        if imgui.Button(u8"\xc7\xe0\xea\xf0\xfb\xf2\xfc##closeProfilePopup", imgui.ImVec2(-1, S(26))) then
            imgui.CloseCurrentPopup()
            St._profilePopupOpen = false
        end
        imgui.PopStyleColor(3)
    else
        St._profilePopupOpen = false
        St._profilePopupOpenedOnce = false
    end
    end) -- конец pcall

    if beganPopup then pcall(imgui.EndPopup) end
    if not ok then
        St._profilePopupOpen = false
        St._profilePopupOpenedOnce = false
        pcall(sampAddChatMessage, "{FF6666}[PC Stats] " ..
            "\xee\xf8\xe8\xe1\xea\xe0\x20\xef\xee\xef\xe0\xef\xe0\x20\xef\xf0\xee\xf4\xe8\xeb\xff: " .. tostring(err), -1)
    end
    popModernPopupStyle(_mpsP)
end

-- ФИКС (п.6): тот же паттерн, что и у drawSettings. drawFn внутри
-- aboutCard тоже защищён отдельно (см. п.12).
function drawAboutInner(h)
    if St._resetSettScroll then imgui.SetScrollY(0) end
        local r,g,b = getAcc()
        local rra,rga,rba = getRowBgColor()
        local dl_a  = imgui.GetWindowDrawList()

        -- Š‘Š°Š½Š½ŠµŃ€
        imgui.Spacing()
        local bannerH = SFtext(86) * 0.98
        local ps_a    = imgui.GetCursorScreenPos()
        local aw_a    = imgui.GetContentRegionAvail().x
        -- Š¤Š¾Š½ Š±Š°Š½Š½ŠµŃ€Š° Ń€ŠµŠ°Š³ŠøŃ€Ń�ŠµŃ‚ Š½Š° rowBg
        local banBgR = math.max(rra*0.22, 0.06)
        local banBgG = math.max(rga*0.22, 0.06)
        local banBgB = math.max(rba*0.22, 0.06)
        dl_a:AddRectFilled(
            imgui.ImVec2(ps_a.x,      ps_a.y),
            imgui.ImVec2(ps_a.x+aw_a, ps_a.y+bannerH),
            imgui.ColorConvertFloat4ToU32(iv4(banBgR,banBgG,banBgB,1.0)), 12)
        dl_a:AddRectFilled(
            imgui.ImVec2(ps_a.x,      ps_a.y),
            imgui.ImVec2(ps_a.x+aw_a*0.5, ps_a.y+bannerH),
            imgui.ColorConvertFloat4ToU32(iv4(rra*0.10,rga*0.10,rba*0.10,0.5)), 12)
        -- обводка баннера сделана ещё тоньше по просьбе (было 1.3)
        dl_a:AddRect(
            imgui.ImVec2(ps_a.x,      ps_a.y),
            imgui.ImVec2(ps_a.x+aw_a, ps_a.y+bannerH),
            imgui.ColorConvertFloat4ToU32(iv4(r,g,b,1.0)), 12, 0, 0.9)
        -- Š²ŠµŃ€Ń…Š½Ń¸Ń¸ Š°ŠŗŃ†ŠµŠ½Ń‚Š½Š°Ń¸ ŠæŠ¾Š»Š¾Ń�ŠŗŠ°
        dl_a:AddRectFilled(
            imgui.ImVec2(ps_a.x+20,      ps_a.y),
            imgui.ImVec2(ps_a.x+aw_a-20, ps_a.y+3),
            imgui.ColorConvertFloat4ToU32(iv4(r,g,b,1.0)), 2)
        -- Š½ŠøŠ¶Š½Ń¸Ń¸ Š°ŠŗŃ†ŠµŠ½Ń‚Š½Š°Ń¸ ŠæŠ¾Š»Š¾Ń�ŠŗŠ°
        dl_a:AddRectFilled(
            imgui.ImVec2(ps_a.x+20,      ps_a.y+bannerH-3),
            imgui.ImVec2(ps_a.x+aw_a-20, ps_a.y+bannerH),
            imgui.ColorConvertFloat4ToU32(iv4(r,g,b,0.7)), 2)
        -- Ń¸Ń€ŠŗŠ¾Ń�Ń‚Ń� Ń„Š¾Š½Š° Š±Š°Š½Š½ŠµŃ€Š° Š´Š»Ń¸ Š°Š´Š°ŠæŃ‚Š°Ń†ŠøŠø Ń‚ŠµŠŗŃ�Ń‚Š°
        local banBright = banBgR*0.299 + banBgG*0.587 + banBgB*0.114
        local banTitleCol = banBright > 0.35 and iv4(0.05,0.05,0.10,1.0) or iv4(1,1,1,1)

        imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
        imgui.BeginChild("##banner", imgui.ImVec2(aw_a, bannerH), false,
            imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
            local title1 = "PC Stats"
            local title2 = "v" .. SCRIPT_VER .. "  |  Arizona RP PC"
            local sz1 = imgui.CalcTextSize(title1)
            local sz2 = imgui.CalcTextSize(title2)
            imgui.SetCursorPos(imgui.ImVec2(aw_a*0.5 - sz1.x*0.5, SFtext(14)))
            imgui.TextColored(banTitleCol, title1)
            imgui.SetCursorPos(imgui.ImVec2(aw_a*0.5 - sz2.x*0.5, SFtext(44)))
            imgui.TextColored(thAccBright(), title2)
        imgui.EndChild()
        imgui.PopStyleColor()
        imgui.Spacing()

        -- ── лёгкая карточка: тоньше рамка, чем infoCard() в других вкладках —
        -- здесь текста немного, тяжёлая рамка смотрелась слишком грузно ──
        local function aboutCard(id, cardH, drawFn)
            cardH = SFtext(cardH)
            local rr2,rg2,rb2 = getRowBgColor()
            local dlc = imgui.GetWindowDrawList()
            local pc  = imgui.GetCursorScreenPos()
            local awc = imgui.GetContentRegionAvail().x
            local bgR = math.max(rr2*0.13, 0.07)
            local bgG = math.max(rg2*0.13, 0.07)
            local bgB = math.max(rb2*0.13, 0.07)
            dlc:AddRectFilled(
                imgui.ImVec2(pc.x,     pc.y),
                imgui.ImVec2(pc.x+awc, pc.y+cardH),
                imgui.ColorConvertFloat4ToU32(iv4(bgR,bgG,bgB,0.97)), 10)
            dlc:AddRect(
                imgui.ImVec2(pc.x,     pc.y),
                imgui.ImVec2(pc.x+awc, pc.y+cardH),
                imgui.ColorConvertFloat4ToU32(iv4(r*0.55,g*0.55,b*0.55,0.50)), 10, 0, 0.8)
            imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
            imgui.BeginChild(id, imgui.ImVec2(awc - 2, cardH), false,
                imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
                -- ФИКС (п.12): drawFn — колбэк, может упасть; оборачиваем
                -- только его
                local okFn, errFn = PCS_GUARD.call(drawFn, awc, cardH)
            imgui.EndChild()
            imgui.PopStyleColor()
            imgui.Spacing()
            if not okFn then
                pcall(sampAddChatMessage, "{FF6666}[PC Stats] " ..
                    "\xee\xf8\xe8\xe1\xea\xe0\x20\xea\xe0\xf0\xf2\xee\xf7\xea\xe8\x20\xce\x20\xf1\xea\xf0\xe8\xef\xf2\xe5: " .. tostring(errFn), -1)
            end
        end

        -- размер текста вкладки "О скрипте" приведён к 100% (раньше был
        -- дополнительно уменьшен до 98%, а заголовки карточек ещё и
        -- увеличены до 108% — по просьбе весь текст сделан одного,
        -- обычного размера, без доп. масштабирования)
        local aboutBaseScale = St.UI_SCALE * (cfg.fontSize > 0 and cfg.fontSize or 1.25)

        secTitle(u8"\xd0\xe0\xe7\xf0\xe0\xe1\xee\xf2\xf7\xe8\xea")
        -- ── карточка разработчика расширена: компактные прямоугольные
        -- кнопки Telegram/Discord (примерно 20:4 по пропорциям) выведены
        -- прямо сюда, отдельная большая карточка "Связь" с крупными
        -- круглыми кнопками убрана — так меню компактнее ──
        aboutCard("##devcard", 118, function(aw, ch)
            imgui.SetWindowFontScale(aboutBaseScale)
            imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(12)))
            imgui.TextColored(iv4(0.55,0.62,0.80,1.0), u8"\xd0\xe0\xe7\xf0\xe0\xe1\xee\xf2\xf7\xe8\xea:")
            imgui.SameLine(0,8)
            imgui.TextColored(thAccBright(), "Marco_Santiago (19)")
            imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(42)))
            imgui.TextColored(iv4(0.55,0.62,0.80,1.0), u8"\xc2\xe5\xf0\xf1\xe8\xff:")
            imgui.SameLine(0,8)
            imgui.TextColored(iv4(1,1,1,1), "v" .. SCRIPT_VER)
            imgui.SameLine(0,14)
            imgui.TextColored(iv4(0.55,0.62,0.80,1.0), u8"\xcf\xf0\xee\xe5\xea\xf2:")
            imgui.SameLine(0,8)
            imgui.TextColored(iv4(0.90,0.90,0.90,1.0), "Arizona RP PC")
            imgui.SetWindowFontScale(aboutBaseScale)

            -- компактные прямоугольные кнопки связи (~20x4 по пропорциям)
            local btnCW, btnCH = SFtext(96), SFtext(20)
            local gapC = SFtext(10)
            imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(96)))
            do
                local tgHandle = "@Marco8877"
                local tgUrl    = "https://t.me/Marco8877"
                imgui.PushStyleColor(imgui.Col.Button,        iv4(0.09,0.42,0.68,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(0.13,0.58,0.90,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(0.18,0.72,1.00,1.0))
                do local _pbtg = prettyBtnPush(6.0)
                if imgui.Button(u8"Telegram##tgopen", imgui.ImVec2(btnCW, btnCH)) then
                    -- сначала пробуем открыть ссылку без консоли (WinAPI
                    -- ShellExecuteA), и только если ffi недоступен —
                    -- запасной os.execute('start ...'), который может на
                    -- мгновение показать окно cmd.exe
                    local opened = winOpenUrl(tgUrl)
                    if not opened then
                        pcall(function()
                            opened = os.execute('start "" "' .. tgUrl .. '"') ~= nil
                        end)
                    end
                    pcall(function()
                        if imgui.SetClipboardText then imgui.SetClipboardText(tgHandle) end
                    end)
                    if opened then
                        -- sampAddChatMessage хочет сырые CP1251-байты, а не UTF8 —
                        -- u8() тут был лишним и превращал текст в чате в кракозябры
                        pcall(sampAddChatMessage, "{00FF88}[MSW] \xf0\x9f\x93\xa2 " .. "\xee\xf2\xea\xf0\xfb\xe2\xe0\xfe \xd2\xe5\xeb\xe5\xe3\xf0\xe0\xec: " .. tgHandle, -1)
                    else
                        pcall(sampAddChatMessage, "{00CCFF}[MSW] \xf0\x9f\x93\x8b Telegram: " .. tgHandle .. " (\xf1\xea\xee\xef\xe8\xf0\xee\xe2\xe0\xed\xee)", -1)
                    end
                end
                prettyBtnPop(_pbtg) end
                imgui.PopStyleColor(3)
            end
            imgui.SameLine(0, gapC)
            do
                local dcHandle = "@marco_santiago888"
                imgui.PushStyleColor(imgui.Col.Button,        iv4(0.22,0.24,0.68,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(0.29,0.33,0.86,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(0.37,0.42,1.00,1.0))
                do local _pbdc = prettyBtnPush(6.0)
                if imgui.Button(u8"Discord##dccopy", imgui.ImVec2(btnCW, btnCH)) then
                    local copied = false
                    pcall(function()
                        if imgui.SetClipboardText then
                            imgui.SetClipboardText(dcHandle)
                            copied = true
                        end
                    end)
                    if copied then
                        pcall(sampAddChatMessage, "{00FF88}[MSW] \xf0\x9f\x93\xa2 " .. "\xd1\xea\xee\xef\xe8\xf0\xee\xe2\xe0\xed\xee: " .. dcHandle, -1)
                    else
                        pcall(sampAddChatMessage, "{7289DA}[MSW] \xf0\x9f\x93\x8b Discord: " .. dcHandle, -1)
                    end
                end
                prettyBtnPop(_pbdc) end
                imgui.PopStyleColor(3)
            end
        end)


        -- ── карточка "Обновления": показывает установленную и
        -- актуальную (с GitHub) версию, кнопка "Проверить" запускает
        -- PCS_UPDATE.check(), а когда найдено обновление — рядом
        -- появляется кнопка "Обновить до vX", которая скачивает файл
        -- и перезаписывает им сам скрипт (PCS_UPDATE.install(), см.
        -- секцию "САМООБНОВЛЕНИЕ" в самом начале файла) ──
        secTitle(u8"\xce\xe1\xed\xee\xe2\xeb\xe5\xed\xe8\xff")
        aboutCard("##updcard", 130, function(aw, ch)
            imgui.SetWindowFontScale(aboutBaseScale)
            local U = PCS_UPDATE

            imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(12)))
            imgui.TextColored(iv4(0.55,0.62,0.80,1.0), u8"\xd2\xe5\xea\xf3\xf9\xe0\xff\x20\xe2\xe5\xf0\xf1\xe8\xff\x3a")
            imgui.SameLine(0,8)
            imgui.TextColored(iv4(1,1,1,1), "v" .. SCRIPT_VER)

            imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(32)))
            imgui.TextColored(iv4(0.55,0.62,0.80,1.0), u8"\xc0\xea\xf2\xf3\xe0\xeb\xfc\xed\xe0\xff\x20\xe2\xe5\xf0\xf1\xe8\xff\x3a")
            imgui.SameLine(0,8)
            if not U then
                imgui.TextColored(iv4(0.6,0.6,0.6,1.0), u8"\xed\xe5\xe8\xe7\xe2\xe5\xf1\xf2\xed\xee")
            elseif U.state.checking then
                imgui.TextColored(iv4(0.6,0.6,0.6,1.0), u8"\xef\xf0\xee\xe2\xe5\xf0\xea\xe0\x2e\x2e\x2e")
            elseif U.state.ver_remote then
                if U.state.available then
                    imgui.TextColored(thGold(), "v" .. U.state.ver_remote .. u8"\x20\x28\xee\xe1\xed\xee\xe2\xeb\xe5\xed\xe8\xe5\x21\x29")
                else
                    imgui.TextColored(iv4(0.40,1.00,0.50,1.0), "v" .. U.state.ver_remote)
                end
            else
                imgui.TextColored(iv4(0.6,0.6,0.6,1.0), u8"\xed\xe5\xe8\xe7\xe2\xe5\xf1\xf2\xed\xee")
            end

            local btnW, btnH = SFtext(150), SFtext(24)
            imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(58)))
            imgui.PushStyleColor(imgui.Col.Button,        iv4(r*0.30,g*0.30,b*0.30,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(r*0.48,g*0.48,b*0.48,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(r*0.65,g*0.65,b*0.65,1.0))
            do local _pbu = prettyBtnPush(6.0)
            if imgui.Button(u8"\xcf\xf0\xee\xe2\xe5\xf0\xe8\xf2\xfc##updcheck", imgui.ImVec2(btnW, btnH)) then
                if U then U.check(false) end
            end
            prettyBtnPop(_pbu) end
            imgui.PopStyleColor(3)

            if U and U.state.available then
                imgui.SameLine(0, SFtext(10))
                imgui.PushStyleColor(imgui.Col.Button,        iv4(0.55,0.40,0.06,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(0.70,0.52,0.10,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(0.85,0.64,0.14,1.0))
                do local _pbi = prettyBtnPush(6.0)
                local instLabel = U.state.installing
                    and (u8"\xd3\xf1\xf2\xe0\xed\xe0\xe2\xeb\xe8\xe2\xe0\xfe\x2e\x2e\x2e" .. "##updinstall")
                    or  (u8"\xce\xe1\xed\xee\xe2\xe8\xf2\xfc\x20\xe4\xee\x20v" .. (U.state.ver_remote or "?") .. "##updinstall")
                if imgui.Button(instLabel, imgui.ImVec2(btnW, btnH)) then
                    if not U.state.installing then U.install() end
                end
                prettyBtnPop(_pbi) end
                imgui.PopStyleColor(3)
            end

            
            -- прогресс скачивания 0..100%
            if U and (U.state.installing or (U.state.dlProg and U.state.dlProg > 0 and U.state.dlProg < 100)) then
                local p = tonumber(U.state.dlProg) or 0
                if p < 0 then p = 0 end
                if p > 100 then p = 100 end
                imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(90)))
                imgui.PushStyleColor(imgui.Col.PlotHistogram, iv4(0.20, 0.75, 0.35, 1.0))
                imgui.ProgressBar(p / 100, imgui.ImVec2(aw - SFtext(32), SFtext(18)),
                    tostring(math.floor(p)) .. "%")
                imgui.PopStyleColor(1)
                if U.state.dlStatus and U.state.dlStatus ~= "" then
                    imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(112)))
                    imgui.TextColored(iv4(0.55,0.62,0.80,1.0), tostring(U.state.dlStatus))
                end
            elseif U and U.state.dlProg == 100 then
                imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(90)))
                imgui.PushStyleColor(imgui.Col.PlotHistogram, iv4(0.20, 0.75, 0.35, 1.0))
                imgui.ProgressBar(1.0, imgui.ImVec2(aw - SFtext(32), SFtext(18)), "100%")
                imgui.PopStyleColor(1)
            end

imgui.SetWindowFontScale(aboutBaseScale)
        end)


        -- Карточка описания скрипта
        secTitle(u8"\xce\xef\xe8\xf1\xe0\xed\xe8\xe5")
        aboutCard("##desccard", 128, function(aw, ch)
            imgui.SetWindowFontScale(aboutBaseScale)
            imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(12)))
            imgui.PushTextWrapPos(aw - SFtext(16))
            imgui.TextColored(iv4(0.85,0.87,0.95,1.0),
                u8"\x50\x43\x20\x53\x74\x61\x74\x73\x20\xef\xee\xea\xe0\xe7\xfb\xe2\xe0\xe5\xf2\x20\xf1\xf2\xe0\xf2\xe8\xf1\xf2\xe8\xea\xf3\x20\xe8\x20\xf4\xe8\xed\xe0\xed\xf1\xfb\x20\xef\xe5\xf0\xf1\xee\xed\xe0\xe6\xe0\x20\xe2\x20\xee\xe4\xed\xee\xec\x20\xf3\xe4\xee\xe1\xed\xee\xec\x20\xee\xea\xed\xe5\x3a\x20\xe1\xe0\xeb\xe0\xed\xf1\x2c\x20\xea\xf3\xf0\xf1\xfb\x20\xe2\xe0\xeb\xfe\xf2\x2c\x20\xe0\xe2\xf2\xee\x2d\xee\xe1\xed\xee\xe2\xeb\xe5\xed\xe8\xe5\x20\xef\xee\xea\xe0\xe7\xe0\xf2\xe5\xeb\xe5\xe9\x2e\x20\xce\xf2\xe4\xe5\xeb\xfc\xed\xe0\xff\x20\xe2\xea\xeb\xe0\xe4\xea\xe0\x20\x22\xcd\xe0\xeb\xee\xe3\xe8\x22\x20\xf3\xec\xe5\xe5\xf2\x20\xf1\xe0\xec\xe0\x20\xee\xef\xeb\xe0\xf7\xe8\xe2\xe0\xf2\xfc\x20\xed\xe0\xeb\xee\xe3\xe8\x3a\x20\xef\xee\x20\xea\xed\xee\xef\xea\xe5\x20\xe2\xf0\xf3\xf7\xed\xf3\xfe\x2c\x20\xef\xee\x20\xf0\xe0\xf1\xef\xe8\xf1\xe0\xed\xe8\xfe\x20\x28\xe0\xe2\xf2\xee\xee\xef\xeb\xe0\xf2\xe0\x20\xf1\x20\xe2\xfb\xe1\xee\xf0\xee\xec\x20\xe8\xed\xf2\xe5\xf0\xe2\xe0\xeb\xe0\x20\xe2\x20\xf7\xe0\xf1\xe0\xf5\x29\x2c\x20\xef\xf0\xe8\x20\xe2\xf5\xee\xe4\xe5\x20\xe2\x20\xe8\xe3\xf0\xf3\x20\x28\xe6\xe4\xb8\xf2\x20\x31\x2d\x32\x20\xec\xe8\xed\xf3\xf2\xfb\x20\xef\xee\xf1\xeb\xe5\x20\xe7\xe0\xf5\xee\xe4\xe0\x20\xe8\x20\xef\xeb\xe0\xf2\xe8\xf2\x20\xf1\xe0\xec\xe0\x29\x20\xe8\x20\xef\xee\x20\xea\xee\xec\xe0\xed\xe4\xe5\x20\x2f\x70\x61\x79\x74\x61\x78\x20\xe8\xe7\x20\xf7\xe0\xf2\xe0\x2e")
            imgui.PopTextWrapPos()
            imgui.SetWindowFontScale(aboutBaseScale)
        end)


        -- ── отдельный блок "Команды": команды скрипта вынесены сюда из
        -- текста описания, каждая со своей кнопкой "Копировать" (по
        -- просьбе) — копирует команду вместе со слэшем в буфер обмена ──
        
secTitle(u8"\xca\xee\xec\xe0\xed\xe4\xfb")
        aboutCard("##cmdscard", 102, function(aw, ch)
            imgui.SetWindowFontScale(aboutBaseScale)
            local btnW, btnH = SFtext(96), SFtext(22)
            local rowY1, rowY2 = SFtext(12), SFtext(56)

            local function copyCmdRow(y, labelU8, cmdStr, uid)
                imgui.SetCursorPos(imgui.ImVec2(SFtext(16), y))
                imgui.TextColored(iv4(0.55,0.62,0.80,1.0), labelU8)
                imgui.SetCursorPos(imgui.ImVec2(SFtext(16), y + SFtext(17)))
                imgui.TextColored(thAccBright(), "/" .. cmdStr)

                imgui.SetCursorPos(imgui.ImVec2(aw - btnW - SFtext(16), y + SFtext(5)))
                imgui.PushStyleColor(imgui.Col.Button,        iv4(r*0.30,g*0.30,b*0.30,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(r*0.48,g*0.48,b*0.48,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(r*0.65,g*0.65,b*0.65,1.0))
                do local _pbc = prettyBtnPush(6.0)
                if imgui.Button(u8"\xca\xee\xef\xe8\xf0\xee\xe2\xe0\xf2\xfc##"..uid, imgui.ImVec2(btnW, btnH)) then
                    pcall(function()
                        if imgui.SetClipboardText then imgui.SetClipboardText("/" .. cmdStr) end
                    end)
                    pcall(sampAddChatMessage, "{00FF88}[PC Stats] \xca\xee\xec\xe0\xed\xe4\xe0\x20\xf1\xea\xee\xef\xe8\xf0\xee\xe2\xe0\xed\xe0\x3a\x20/" .. cmdStr, -1)
                end
                prettyBtnPop(_pbc) end
                imgui.PopStyleColor(3)
            end

            copyCmdRow(rowY1, u8"\xce\xf2\xea\xf0\xfb\xf2\xfc\x20\xec\xe5\xed\xfe\x20\xf1\xea\xf0\xe8\xef\xf2\xe0\x3a", tostring(cfg.menuOpenCmd or "sw"), "cmdmenu")
            copyCmdRow(rowY2, u8"\xce\xef\xeb\xe0\xf2\xe8\xf2\xfc\x20\xed\xe0\xeb\xee\xe3\xe8\x3a", "paytax", "cmdtax")
            imgui.SetWindowFontScale(aboutBaseScale)
        end)


        -- ── управление меню: команда открытия и горячая клавиша — по
        -- просьбе перенесено сюда (раньше жило во вкладке "Финансы" →
        -- панель настроек) и переоформлено в общем стиле вкладки "О
        -- скрипте" (карточка вместо голых полей) ──
        secTitle(u8"\xd3\xef\xf0\xe0\xe2\xeb\xe5\xed\xe8\xe5\x20\xec\xe5\xed\xfe")
        aboutCard("##menucmdcard", 108, function(aw, ch)
            imgui.SetWindowFontScale(aboutBaseScale)
            local applyW = SFtext(96)
            imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(12)))
            imgui.TextColored(iv4(0.55,0.62,0.80,1.0), u8"\xca\xee\xec\xe0\xed\xe4\xe0\x20\xee\xf2\xea\xf0\xfb\xf2\xe8\xff\x20\xec\xe5\xed\xfe:")

            imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(30)))
            imgui.PushItemWidth(math.max(SFtext(60), aw - applyW - SFtext(40)))
            imgui.PushStyleColor(imgui.Col.FrameBg,        iv4(r*0.14,g*0.14,b*0.14,1.0))
            imgui.PushStyleColor(imgui.Col.FrameBgHovered, iv4(r*0.20,g*0.20,b*0.20,1.0))
            imgui.PushStyleColor(imgui.Col.FrameBgActive,  iv4(r*0.28,g*0.28,b*0.28,1.0))
            imgui.InputText("##menuCmdInputAbout", St.menuCmdBuf, 16)
            imgui.PopStyleColor(3)
            imgui.PopItemWidth()

            imgui.SameLine(0, SFtext(8))
            imgui.PushStyleColor(imgui.Col.Button,        iv4(r*0.30,g*0.30,b*0.30,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(r*0.48,g*0.48,b*0.48,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(r*0.65,g*0.65,b*0.65,1.0))
            do local _pbmc = prettyBtnPush(6.0)
            if imgui.Button(u8"\xcf\xf0\xe8\xec\xe5\xed\xe8\xf2\xfc##applyMenuCmdAbout", imgui.ImVec2(applyW, SFtext(22))) then
                local newCmd = ""
                pcall(function() newCmd = ffi.string(St.menuCmdBuf) end)
                local ok2, appliedCmd = registerMenuCommand(newCmd)
                if ok2 then
                    cfg.menuOpenCmd = appliedCmd
                    saveCfg()
                    pcall(sampAddChatMessage, "{00FF88}[PC Stats] \xe2\x9c\x85 " .. "\xea\xee\xec\xe0\xed\xe4\xe0\x20\xee\xf2\xea\xf0\xfb\xf2\xe8\xff\x20\xec\xe5\xed\xfe: /" .. appliedCmd, -1)
                else
                    pcall(sampAddChatMessage, "{FF6666}[PC Stats] \xe2\x9a\xa0\xef\xb8\x8f " .. "\xed\xe5\x20\xf3\xe4\xe0\xeb\xee\xf1\xfc\x20\xef\xf0\xe8\xec\xe5\xed\xe8\xf2\xfc\x20\xea\xee\xec\xe0\xed\xe4\xf3", -1)
                end
            end
            prettyBtnPop(_pbmc) end
            imgui.PopStyleColor(3)

            imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(58)))
            imgui.TextColored(iv4(0.55,0.62,0.80,1.0), u8"\xc3\xee\xf0\xff\xf7\xe0\xff\x20\xea\xeb\xe0\xe2\xe8\xf8\xe0:")

            imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(76)))
            local hkBtnW = SFtext(120)
            imgui.PushStyleColor(imgui.Col.Button,        iv4(r*0.30,g*0.30,b*0.30,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(r*0.48,g*0.48,b*0.48,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(r*0.65,g*0.65,b*0.65,1.0))
            do local _pbhk = prettyBtnPush(6.0)
            local hkLabel = St.awaitingHotkeyBind
                and u8"\xcd\xe0\xe6\xec\xe8\xf2\xe5\x20\xea\xeb\xe0\xe2\xe8\xf8\xf3\x2e\x2e\x2e##hkAssign"
                or  u8"\xcd\xe0\xe7\xed\xe0\xf7\xe8\xf2\xfc##hkAssign"
            if imgui.Button(hkLabel, imgui.ImVec2(hkBtnW, SFtext(22))) then
                St.awaitingHotkeyBind = true
            end
            prettyBtnPop(_pbhk) end
            imgui.PopStyleColor(3)

            if cfg.menuHotkeyVK and cfg.menuHotkeyVK > 0 then
                imgui.SameLine(0, SFtext(8))
                imgui.PushStyleColor(imgui.Col.Button,        iv4(0.35,0.14,0.14,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(0.55,0.20,0.20,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(0.70,0.26,0.26,1.0))
                do local _pbhkr = prettyBtnPush(6.0)
                if imgui.Button(u8"\xd1\xe1\xf0\xee\xf1##hkReset", imgui.ImVec2(SFtext(70), SFtext(22))) then
                    cfg.menuHotkeyVK = 0
                    St.awaitingHotkeyBind = false
                    saveCfg()
                    pcall(sampAddChatMessage, "{00FF88}[PC Stats] \xc3\xee\xf0\xff\xf7\xe0\xff\x20\xea\xeb\xe0\xe2\xe8\xf8\xe0\x20\xf1\xe1\xf0\xee\xf8\xe5\xed\xe0", -1)
                end
                prettyBtnPop(_pbhkr) end
                imgui.PopStyleColor(3)
            end

            imgui.SameLine(0, SFtext(10))
            if St.awaitingHotkeyBind then
                imgui.TextColored(thGold(), u8"\xcd\xe0\xe6\xec\xe8\xf2\xe5\x20\xeb\xfe\xe1\xf3\xfe\x20\xea\xeb\xe0\xe2\xe8\xf8\xf3\x2e\x2e\x2e\x20\x28Esc\x20\xe4\xeb\xff\x20\xee\xf2\xec\xe5\xed\xfb\x29")
            else
                imgui.TextColored(iv4(0.50,0.54,0.62,1.0), u8"\xd2\xe5\xea\xf3\xf9\xe0\xff\x3a\x20" .. vkName(cfg.menuHotkeyVK))
            end
            imgui.SetWindowFontScale(aboutBaseScale)
        end)


        -- ── ФИКС (по просьбе): три "опасные" кнопки управления скриптом
        -- (Выключить/Сброс данных/Удалить) перенесены из этой карточки
        -- в нижнюю панель вкладки "О скрипте" — см. drawDangerButtonsRow()
        -- ниже и её вызов в нижней панели вместо кнопки "Закрыть" ──

    -- ── нижний отступ, чтобы последний блок не прилипал к краю окна ──
    imgui.Dummy(imgui.ImVec2(0, S(40)))
end

local function drawAbout(h)
    imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
    -- ubrali NoScrollbar/NoScrollWithMouse: teper mozhno prokrutit koleskom
    -- myshi ili polosoy sprava, esli tekst ne pomeshchaetsya v okno
    imgui.BeginChild("##sabout", imgui.ImVec2(0,h), false)
    local ok, err = PCS_GUARD.call(drawAboutInner, h)
    imgui.EndChild()
    imgui.PopStyleColor()
    St._resetSettScroll = false
    if not ok then
        pcall(sampAddChatMessage, "{FF6666}[PC Stats] " ..
            "\xee\xf8\xe8\xe1\xea\xe0\x20\xee\xf2\xf0\xe8\xf1\xee\xe2\xea\xe8\x20\xce\x20\xf1\xea\xf0\xe8\xef\xf2\xe5: " .. tostring(err), -1)
    end
end

-- ── три "опасные" кнопки управления скриптом (Выключить/Сброс
-- данных/Удалить), вынесены из вкладки "О скрипте" в нижнюю панель — по
-- просьбе, вместо кнопки "Закрыть". Каждая требует повторного нажатия в
-- течение 5 секунд (антидребезг для самого игрока — чтобы случайный клик
-- не снёс конфиг или сам файл) ──
function drawDangerButtonsRow(aw, r, g, b)
    local now = os.clock()
    local confirming = St._dangerConfirmKind ~= nil and now < St._dangerConfirmUntil
    if St._dangerConfirmKind ~= nil and now >= St._dangerConfirmUntil then
        St._dangerConfirmKind = nil
    end

    local btnW = (aw - S(8)*2) / 3
    local function dangerBtn(kind, idleLabelU8, confirmLabelU8, x, y, w, accentMode, onConfirm)
        imgui.SetCursorPos(imgui.ImVec2(x, y))
        local isThis = confirming and St._dangerConfirmKind == kind
        if accentMode then
            -- ── кнопка "Перезагрузить" — нейтральный акцентный цвет, а не
            -- красный (это не разрушительное действие, как остальные три) ──
            if isThis then
                imgui.PushStyleColor(imgui.Col.Button,        iv4(math.min(1,r*0.95),math.min(1,g*0.95),math.min(1,b*0.95),1.0))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(math.min(1,r*1.10),math.min(1,g*1.10),math.min(1,b*1.10),1.0))
                imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(math.min(1,r*1.25),math.min(1,g*1.25),math.min(1,b*1.25),1.0))
            else
                imgui.PushStyleColor(imgui.Col.Button,        iv4(r*0.30,g*0.30,b*0.30,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(r*0.50,g*0.50,b*0.50,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(r*0.68,g*0.68,b*0.68,1.0))
            end
        elseif isThis then
            imgui.PushStyleColor(imgui.Col.Button,        iv4(0.75,0.18,0.18,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(0.90,0.24,0.24,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(1.00,0.30,0.30,1.0))
        else
            imgui.PushStyleColor(imgui.Col.Button,        iv4(0.35,0.06,0.06,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(0.58,0.12,0.12,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(0.80,0.22,0.22,1.0))
        end
        do local _pbd = prettyBtnPush(6.0)
        local label = isThis and confirmLabelU8 or idleLabelU8
        if imgui.Button(label .. "##danger" .. kind, imgui.ImVec2(w, S(40))) then
            if isThis then
                St._dangerConfirmKind = nil
                onConfirm()
            else
                St._dangerConfirmKind = kind
                St._dangerConfirmUntil = os.clock() + 5.0
            end
        end
        prettyBtnPop(_pbd) end
        imgui.PopStyleColor(3)
    end

    local yStart = imgui.GetCursorPosY()
    dangerBtn("disable",
        ICON_POWER .. "  " .. u8"\xc2\xfb\xea\xeb\xfe\xf7\xe8\xf2\xfc",
        u8"\xd2\xee\xf7\xed\xee\x3f",
        0, yStart, btnW, false,
        function()
            pcall(sampAddChatMessage, "{FF6666}[PC Stats] " ..
                "\xd1\xea\xf0\xe8\xef\xf2\x20\xee\xf2\xea\xeb\xfe\xf7\xe5\xed", -1)
            local ok, scr = pcall(thisScript)
            if ok and scr then pcall(function() scr:unload() end) end
        end)
    dangerBtn("reset",
        ICON_UNDO .. "  " .. u8"\xd1\xe1\xf0\xee\xf1\x20\xe4\xe0\xed\xed\xfb\xf5",
        u8"\xd2\xee\xf7\xed\xee\x3f",
        btnW + S(8), yStart, btnW, false,
        function()
            pcall(os.remove, CFG_FILE)
            pcall(os.remove, CFG_FILE_OLD)
            pcall(sampAddChatMessage, "{FFAA00}[PC Stats] " ..
                "\xc4\xe0\xed\xed\xfb\xe5\x20\xf1\xe1\xf0\xee\xf8\xe5\xed\xfb\x2c\x20\xef\xe5\xf0\xe5\xe7\xe0\xef\xf3\xf1\xea\xe0\xe9\xf2\xe5\x20\xf1\xea\xf0\xe8\xef\xf2", -1)
        end)
    dangerBtn("delete",
        ICON_TRASH .. "  " .. u8"\xd3\xe4\xe0\xeb\xe8\xf2\xfc",
        u8"\xd2\xee\xf7\xed\xee\x3f",
        (btnW + S(8)) * 2, yStart, btnW, false,
        function()
            pcall(os.remove, CFG_FILE)
            pcall(os.remove, CFG_FILE_OLD)
            local ok, scr = pcall(thisScript)
            local path = ok and scr and scr.path
            pcall(sampAddChatMessage, "{FF6666}[PC Stats] " ..
                "\xd1\xea\xf0\xe8\xef\xf2\x20\xf3\xe4\xe0\xeb\xb8\xed", -1)
            if ok and scr then pcall(function() scr:unload() end) end
            if path then pcall(os.remove, path) end
        end)

    -- ── ФИКС (по просьбе): добавлена кнопка "Перезагрузить скрипт" —
    -- отдельной строкой ниже трёх "опасных" кнопок, нейтрального (не
    -- красного) цвета, так как это не разрушительное действие. Пробуем
    -- штатный script:reload() из MoonLoader API; если в этой сборке его
    -- нет — откатываемся на unload() с сообщением в чат (скрипт всё
    -- равно перезапустится сам, если зарегистрирован автозагрузчиком,
    -- либо игроку нужно будет запустить его заново вручную) ──
    local yReload = yStart + S(40) + S(10)
    dangerBtn("reload",
        ICON_SYNC .. "  " .. u8"\xcf\xe5\xf0\xe5\xe7\xe0\xe3\xf0\xf3\xe7\xe8\xf2\xfc\x20\xf1\xea\xf0\xe8\xef\xf2",
        u8"\xd2\xee\xf7\xed\xee\x3f",
        0, yReload, aw, true,
        function()
            local ok, scr = pcall(thisScript)
            local reloaded = false
            if ok and scr and type(scr.reload) == "function" then
                reloaded = pcall(function() scr:reload() end)
            end
            if reloaded then
                pcall(sampAddChatMessage, "{00FF88}[PC Stats] \xf0\x9f\x94\x84 " ..
                    "\xd1\xea\xf0\xe8\xef\xf2\x20\xef\xe5\xf0\xe5\xe7\xe0\xef\xf3\xf9\xe5\xed", -1)
            else
                pcall(sampAddChatMessage, "{FFAA00}[PC Stats] " ..
                    "\xed\xe5\x20\xf3\xe4\xe0\xeb\xee\xf1\xfc\x20\xef\xe5\xf0\xe5\xe7\xe0\xef\xf3\xf1\xf2\xe8\xf2\xfc\x20\xe0\xe2\xf2\xee\xec\xe0\xf2\xe8\xf7\xe5\xf1\xea\xe8\x3b\x20\xf1\xea\xf0\xe8\xef\xf2\x20\xe2\xfb\xe3\xf0\xf3\xe6\xe5\xed\x2c\x20\xe7\xe0\xef\xf3\xf1\xf2\xe8\xf2\xe5\x20\xe7\xe0\xed\xee\xe2\xee\x20\xe2\xf0\xf3\xf7\xed\xf3\xfe\x20\x28F4\x20\x2f\x20\xef\xe5\xf0\xe5\xe7\xe0\xf5\xee\xe4\x20\xe2\x20\xef\xe0\xef\xea\xf3\x20moonloader\x29", -1)
                local ok2, scr2 = pcall(thisScript)
                if ok2 and scr2 then pcall(function() scr2:unload() end) end
            end
        end)

    if confirming then
        local hintY = (St._dangerConfirmKind == "reload") and (yReload + S(40) + S(4)) or (yStart + S(40) + S(4))
        imgui.SetCursorPosY(hintY)
        imgui.TextColored(thGold(), u8"\xcd\xe0\xe6\xec\xe8\xf2\xe5\x20\xea\xed\xee\xef\xea\xf3\x20\xe5\xf9\xb8\x20\xf0\xe0\xe7\x2c\x20\xf7\xf2\xee\xe1\xfb\x20\xef\xee\xe4\xf2\xe2\xe5\xf0\xe4\xe8\xf2\xfc")
    end
end

-- ============================================================
--  ВКЛАДКА "НАЛОГИ"
-- ============================================================
function fmtTaxTime(t)
    if not t or t == 0 then return u8"\xed\xe5\xf2\x20\xe4\xe0\xed\xed\xfb\xf5" end
    return os.date("%d.%m.%Y %H:%M:%S", t)
end

-- ФИКС "битые ??? в тексте": раньше эта функция возвращала строку, где
-- кириллица была НЕ обёрнута в u8() (сырые CP1251-байты), а вызывающий
-- код склеивал её с ДРУГИМИ, уже u8()-конвертированными кусками и
-- передавал всё разом в imgui.TextColored — а mimgui всегда ждёт UTF-8.
-- Сырые CP1251-байты внутри UTF-8-строки — невалидная последовательность,
-- поэтому на экране вместо кириллицы вылезали "?" (как раз то самое
-- "10???" на скриншоте). Теперь ВЕСЬ текст здесь идёт через u8() ──
function fmtTaxAgo(t)
    if not t or t == 0 then return "" end
    local d = os.time() - t
    if d < 60 then return " (" .. d .. u8" \xf1\x2e \xed\xe0\xe7\xe0\xe4)" end
    if d < 3600 then return " (" .. math.floor(d/60) .. u8" \xec\xe8\xed\x2e \xed\xe0\xe7\xe0\xe4)" end
    if d < 86400 then return " (" .. math.floor(d/3600) .. u8" \xf7\x2e \xed\xe0\xe7\xe0\xe4)" end
    return " (" .. math.floor(d/86400) .. u8" \xe4\x2e \xed\xe0\xe7\xe0\xe4)"
end

-- форматирует секунды в "Чч Mм" / "Mм Cс" — для отображения оставшегося
-- времени до следующей оплаты (и "Автооплата", и "При входе")
function fmtDuration(sec)
    sec = math.max(0, math.floor(sec + 0.5))
    local hh = math.floor(sec / 3600)
    local mm = math.floor((sec % 3600) / 60)
    local ss = sec % 60
    if hh > 0 then return hh .. u8"\xf7\x20" .. mm .. u8"\xec" end
    if mm > 0 then return mm .. u8"\xec\x20" .. ss .. u8"\xf1" end
    return ss .. u8"\xf1"
end

-- ── тумблер настройки вкладки "Оплата": свитч + подпись + (опционально)
-- пояснение под ним серым цветом, единый стиль для всей вкладки ──
function taxToggleRow(id, labelU8, isOn, onToggle, descU8)
    if drawToggleSwitch(id, isOn) then
        onToggle(not isOn)
        saveCfg()
    end
    imgui.SameLine(0, S(8))
    imgui.TextColored(iv4(1,1,1,1), labelU8)
    if descU8 then
        imgui.TextColored(thDim(), "  "..descU8)
    end
    imgui.Dummy(imgui.ImVec2(0, S(4)))
end

function drawTaxesInner(h)
    local r, g, b = getAcc()

    -- ФИКС (по просьбе): "Своя оплата" теперь красивая карточка с рамкой
    -- (в цвет акцента) вместо голого текста на фоне — короче, без лишних
    -- повторов слова "оплата" в каждой строке
    do
        local dl_sp = imgui.GetWindowDrawList()
        local p_sp  = imgui.GetCursorScreenPos()
        local aw_sp = imgui.GetContentRegionAvail().x
        local hasAmt = cfg.taxLastPayAmount and cfg.taxLastPayAmount > 0
        local cardH_sp = hasAmt and S(64) or S(44)
        dl_sp:AddRectFilled(p_sp, imgui.ImVec2(p_sp.x+aw_sp, p_sp.y+cardH_sp),
            imgui.ColorConvertFloat4ToU32(iv4(r*0.08,g*0.08,b*0.08,0.85)), 10)
        dl_sp:AddRect(p_sp, imgui.ImVec2(p_sp.x+aw_sp, p_sp.y+cardH_sp),
            imgui.ColorConvertFloat4ToU32(iv4(r,g,b,0.55)), 10, 0, 1.3)
        imgui.SetCursorScreenPos(imgui.ImVec2(p_sp.x + S(12), p_sp.y + S(9)))
        imgui.TextColored(thAcc(), u8"\xd1\xe2\xee\xff\x20\xee\xef\xeb\xe0\xf2\xe0")
        imgui.SetCursorScreenPos(imgui.ImVec2(p_sp.x + S(12), p_sp.y + S(28)))
        imgui.TextColored(iv4(1,1,1,1), fmtTaxTime(cfg.taxLastPayTime)..fmtTaxAgo(cfg.taxLastPayTime))
        if hasAmt then
            imgui.SetCursorScreenPos(imgui.ImVec2(p_sp.x + S(12), p_sp.y + S(46)))
            imgui.TextColored(thGold(), fmtMoney(string.format("%.0f", cfg.taxLastPayAmount)))
        end
        imgui.SetCursorScreenPos(imgui.ImVec2(p_sp.x, p_sp.y + cardH_sp + S(8)))
    end

    -- ── по просьбе: персистентный лог оплат налогов с тем же
    -- календарём, что и у дохода PayDay (см. TX-таблицу и Cal выше) ──
    imgui.Separator()
    imgui.Dummy(imgui.ImVec2(0, S(6)))
    imgui.TextColored(thAcc(), u8"  \xc8\xf1\xf2\xee\xf0\xe8\xff\x20\xee\xef\xeb\xe0\xf2")
    imgui.Spacing()
    if not St.taxLogLoaded then TX.loadLog() end


    -- ── по просьбе: отдельная кнопка "Календарь оплат" убрана — попап
    -- календаря теперь открывается той же кнопкой "Логи оплат" ниже,
    -- если день ещё не выбирался (см. её обработчик) ──
    do
        imgui.PushStyleColor(imgui.Col.Button,        iv4(r*0.22,g*0.22,b*0.22,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(r*0.42,g*0.42,b*0.42,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(r*0.60,g*0.60,b*0.60,1.0))
        do local _pbTL = prettyBtnPush(8.0)
        -- ФИКС КРАША (усилено): позиция кнопки теперь сохраняется в St,
        -- а не в локальной переменной drawTaxesInner — сам попап рисуется
        -- отдельной функцией drawTaxPopupsGlobal(), вызываемой КАЖДЫЙ
        -- кадр вне зависимости от активной вкладки (см. её объявление и
        -- комментарий ниже), поэтому доступ к позиции нужен и оттуда.
        St._taxLogBtnScreenPos = imgui.GetCursorScreenPos()
        if imgui.Button(u8"\xcb\xee\xe3\xe8\x20\xee\xef\xeb\xe0\xf2##taxOpenLogsModal", imgui.ImVec2(-1, S(30))) then
            if St._taxLogSelectedDate then
                St._taxLogEntriesPopupOpen = true
            else
                -- ФИКС "кнопка Логи оплат не работает": раньше здесь стоял
                -- imgui.OpenPopup("##taxCalendarPopup") прямо тут, внутри
                -- дочернего окна "##staxes" (см. drawTaxes/BeginChild выше).
                -- Реальный imgui.BeginPopup с этим же ID вызывается из
                -- drawTaxPopupsGlobal() — СНАРУЖИ этого дочернего окна, на
                -- каждом кадре независимо от вкладки. imgui считает ID попапа
                -- с учётом текущего стека окон, поэтому OpenPopup(),
                -- вызванный внутри "##staxes", и BeginPopup(), вызванный вне
                -- его, получали РАЗНЫЕ внутренние ID для одной и той же
                -- строки "##taxCalendarPopup" — попап технически "открывался",
                -- но BeginPopup снаружи его никогда не находил и ничего не
                -- рисовал. Теперь просто выставляем флаг, а сам
                -- imgui.OpenPopup вызывается из drawTaxPopupsGlobal() — из
                -- того же контекста, что и BeginPopup (тот же приём, что уже
                -- используется для St._taxLogEntriesPopupOpen ниже).
                St._taxCalendarPopupOpen = true
                St._taxCalendarPopupOpenedOnce = false
            end
        end
        prettyBtnPop(_pbTL) end
        imgui.PopStyleColor(3)
    end
    imgui.Spacing()
    -- ФИКС КРАША "при оплате налогов сразу переключиться на другую
    -- вкладку" (усилено по повторной жалобе): раньше попапы календаря и
    -- журнала оплат рисовались прямо здесь, внутри drawTaxesInner(), т.е.
    -- ТОЛЬКО пока активна вкладка "Налоги". Если попап был открыт через
    -- imgui.OpenPopup(), а игрок в этот же миг переключал вкладку,
    -- drawTaxesInner() на следующих кадрах больше не вызывался — но сам
    -- попап оставался числиться "открытым" в внутреннем стеке imgui,
    -- потому что imgui.BeginPopup()/EndPopup() для него больше НИ РАЗУ
    -- не вызывались. Незакрытый таким образом попап рано или поздно
    -- ломает стек всплывающих окон imgui и крашит игру — именно это и
    -- есть первопричина краша, а не только сам BeginChild/EndChild.
    -- Теперь отрисовка обоих попапов вынесена в отдельную функцию
    -- drawTaxPopupsGlobal() (см. её объявление ниже), которая вызывается
    -- БЕЗУСЛОВНО на каждом кадре из главного цикла — независимо от того,
    -- какая вкладка сейчас активна. Поэтому imgui.BeginPopup() для обоих
    -- ID гарантированно "навещается" каждый кадр, попап either рисуется,
    -- либо (если это уже не тот кадр, что открыл его) сам собой считается
    -- закрытым штатными средствами imgui — стек никогда не остаётся
    -- висеть в незакрытом состоянии из-за переключения вкладки.

    -- ── удобный общий расчёт "когда налоги точно снова нужны" — на
    -- основе того же интервала, что использует и "Автооплата", и
    -- "При входе" (см. main()), чтобы обе секции ниже показывали
    -- согласованное между собой время, а не выдуманные отдельные ──
    local _intervalSec = math.max(1, tonumber(cfg.taxAutoIntervalHours) or 1) * 3600
    local _sinceLastPay = (cfg.taxLastPayTime ~= 0) and (os.time() - cfg.taxLastPayTime) or nil
    local _dueInSec = _sinceLastPay and math.max(0, _intervalSec - _sinceLastPay) or nil

    imgui.Dummy(imgui.ImVec2(0, S(6)))

    imgui.PushStyleColor(imgui.Col.Button,        iv4(r*0.55,g*0.55,b*0.55,1.0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(r*0.78,g*0.78,b*0.78,1.0))
    imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(r,g,b,1.0))
    if imgui.Button(u8"  \xce\xef\xeb\xe0\xf2\xe8\xf2\xfc\x20\xed\xe0\xeb\xee\xe3\xe8\x20\xf1\xe5\xe9\xf7\xe0\xf1  ", imgui.ImVec2(-1, S(38))) then
        payTaxesThenHotel(false)
    end
    if imgui.IsItemHovered and imgui.IsItemHovered() then
        pcall(function()
            imgui.BeginTooltip()
            imgui.TextColored(iv4(0.75,0.80,0.90,1.0), u8"\xce\xf2\xea\xf0\xee\xe5\xf2\x20\xf2\xe5\xeb\xe5\xf4\xee\xed\x20\xe8\x20\xef\xf0\xff\xec\xee\x20\xf1\xe5\xe9\xf7\xe0\xf1\x20\xee\xef\xeb\xe0\xf2\xe8\xf2\x20\xe2\xf1\xe5\x20\xed\xe0\xeb\xee\xe3\xe8")
            imgui.EndTooltip()
        end)
    end
    imgui.PopStyleColor(3)
    imgui.TextColored(thDim(), "  "..u8"\xce\xf2\xea\xf0\xee\xe5\xf2\x20\xf2\xe5\xeb\xe5\xf4\xee\xed\x20\xe8\x20\xee\xef\xeb\xe0\xf2\xe8\xf2\x20\xe2\xf1\xe5\x20\xed\xe0\xeb\xee\xe3\xe8\x20\xef\xf0\xff\xec\xee\x20\xf1\xe5\xe9\xf7\xe0\xf1")

    -- ── красивый статус процесса, пока идёт автоматическая оплата
    -- (открытие телефона / поиск нужного пункта меню) ──
    if _taxState ~= 0 then
        imgui.Dummy(imgui.ImVec2(0, S(6)))
        imgui.TextColored(thGold(), "  \xe2\x8f\xb3 "..u8"\xc8\xe4\xb8\xf2\x20\xee\xef\xeb\xe0\xf2\xe0\x20\xed\xe0\xeb\xee\xe3\xee\xe2\x2e\x2e\x2e")
        imgui.TextColored(thDim(),  "  "..u8"\xce\xf2\xea\xf0\xfb\xe2\xe0\xfe\x20\xf2\xe5\xeb\xe5\xf4\xee\xed\x20\xe8\x20\xe8\xf9\xf3\x20\xed\xf3\xe6\xed\xfb\xe9\x20\xef\xf3\xed\xea\xf2\x20\xec\xe5\xed\xfe")
    end

    imgui.Dummy(imgui.ImVec2(0, S(10)))
    imgui.Separator()
    imgui.Dummy(imgui.ImVec2(0, S(6)))

    -- ── автооплата (тумблер + интервал в часах) ──
    imgui.TextColored(thAcc(), u8"  \xc0\xe2\xf2\xee\xee\xef\xeb\xe0\xf2\xe0")
    imgui.Spacing()
    taxToggleRow("##taxAutoSw", u8"\xc2\xea\xeb\xfe\xf7\xe8\xf2\xfc\x20\xe0\xe2\xf2\xee\xee\xef\xeb\xe0\xf2\xf3", cfg.taxAutoEnabled,
        function(v) cfg.taxAutoEnabled = v; St.taxAutoBuf[0] = v end,
        u8"\xd1\xea\xf0\xe8\xef\xf2\x20\xf1\xe0\xec\x20\xe1\xf3\xe4\xe5\xf2\x20\xee\xef\xeb\xe0\xf7\xe8\xe2\xe0\xf2\xfc\x20\xed\xe0\xeb\xee\xe3\xe8\x20\xef\xee\x20\xf2\xe0\xe9\xec\xe5\xf0\xf3\x2c\x20\xe1\xe5\xe7\x20\xf2\xe2\xee\xe5\xe3\xee\x20\xf3\xf7\xe0\xf1\xf2\xe8\xff")

    -- ── статус "когда следующая": вместо голого слайдера — понятная
    -- строка. Если автооплата выключена — не показываем её вовсе (нечего
    -- показывать). Если включена и налоги ещё не платились ни разу — так
    -- и говорим. Если включена и время ещё не подошло — показываем,
    -- сколько осталось. Если время уже подошло — фоновый поток проверяет
    -- это раз в минуту (см. main()), так и пишем, вместо "??" ──
    if cfg.taxAutoEnabled then
        if not _sinceLastPay then
            imgui.TextColored(thGold(), "  "..u8"\xd1\xeb\xe5\xe4\xf3\xfe\xf9\xe0\xff\x20\xef\xf0\xee\xe2\xe5\xf0\xea\xe0\x3a\x20\xe2\x20\xf2\xe5\xf7\xe5\xed\xe8\xe5\x20\xec\xe8\xed\xf3\xf2\xfb\x20\x28\xed\xe5\xf2\x20\xe4\xe0\xed\xed\xfb\xf5\x20\xee\x20\xef\xee\xf1\xeb\xe5\xe4\xed\xe5\xe9\x20\xee\xef\xeb\xe0\xf2\xe5\x29")
        elseif _dueInSec and _dueInSec > 0 then
            imgui.TextColored(thGold(), "  "..u8"\xd1\xeb\xe5\xe4\xf3\xfe\xf9\xe0\xff\x20\xef\xf0\xee\xe2\xe5\xf0\xea\xe0\x20\xf7\xe5\xf0\xe5\xe7\x3a\x20"..fmtDuration(_dueInSec))
        else
            imgui.TextColored(thGold(), "  "..u8"\xd1\xf0\xee\xea\x20\xef\xee\xe4\xee\xf8\xb8\xeb\x20\x97\x20\xef\xf0\xee\xe2\xe5\xf0\xea\xe0\x20\xf0\xe0\xe7\x20\xe2\x20\xec\xe8\xed\xf3\xf2\xf3")
        end
        imgui.Dummy(imgui.ImVec2(0, S(4)))
    end

    -- ФИКС (по просьбе): слайдер интервала оплаты стилизован в цвет
    -- акцента (был дефолтный серый imgui), плюс крупный читаемый номер
    -- часов справа от подписи вместо мелкого текста внутри слайдера.
    -- ФИКС (по просьбе "кулдаун минимум до 5 дней"): потолок слайдера
    -- поднят с 24ч до 120ч (5 суток) — при значениях от суток и больше
    -- рядом дополнительно показываем "(N дн)" для читаемости
    imgui.TextColored(thDim(), "  "..u8"\xc8\xed\xf2\xe5\xf0\xe2\xe0\xeb")
    imgui.SameLine(0, S(6))
    local _ivHrs = St.taxIntervalBuf[0]
    local _ivLbl = tostring(_ivHrs) .. " " .. u8"\xf7"
    if _ivHrs >= 24 then
        local _ivDays = _ivHrs / 24
        local _ivDaysStr = (math.floor(_ivDays) == _ivDays) and tostring(math.floor(_ivDays))
            or string.format("%.1f", _ivDays)
        _ivLbl = _ivLbl .. "  (" .. _ivDaysStr .. " " .. u8"\xe4\xed" .. ")"
    end
    imgui.TextColored(thAcc(), _ivLbl)
    imgui.PushStyleColor(imgui.Col.FrameBg,        iv4(r*0.16,g*0.16,b*0.16,1.0))
    imgui.PushStyleColor(imgui.Col.FrameBgHovered, iv4(r*0.24,g*0.24,b*0.24,1.0))
    imgui.PushStyleColor(imgui.Col.FrameBgActive,  iv4(r*0.30,g*0.30,b*0.30,1.0))
    imgui.PushStyleColor(imgui.Col.SliderGrab,      iv4(r,g,b,1.0))
    imgui.PushStyleColor(imgui.Col.SliderGrabActive,iv4(math.min(1,r*1.2),math.min(1,g*1.2),math.min(1,b*1.2),1.0))
    imgui.PushItemWidth(-1)
    if imgui.SliderInt('##taxInterval', St.taxIntervalBuf, 1, 120, "%d "..u8"\xf7") then
        cfg.taxAutoIntervalHours = St.taxIntervalBuf[0]
        saveCfg()
    end
    imgui.PopItemWidth()
    imgui.PopStyleColor(5)

    imgui.Dummy(imgui.ImVec2(0, S(10)))
    imgui.Separator()
    imgui.Dummy(imgui.ImVec2(0, S(6)))

    -- ── оплата при входе: ждём ровно 1 минуту после захода в игру и
    -- сами оплачиваем налоги, без участия игрока (стандартизировано
    -- на 1 минуту, по просьбе) ──
    imgui.TextColored(thAcc(), u8"  \xcf\xf0\xe8\x20\xe2\xf5\xee\xe4\xe5")
    imgui.Spacing()
    taxToggleRow("##taxPayOnLoginSw", u8"\xce\xef\xeb\xe0\xf2\xe0\x20\xef\xf0\xe8\x20\xe2\xf5\xee\xe4\xe5\x20\xe2\x20\xe8\xe3\xf0\xf3", cfg.taxPayOnLogin,
        function(v) cfg.taxPayOnLogin = v; St.taxPayOnLoginBuf[0] = v end,
        u8"\xef\xee\xf1\xeb\xe5\x20\xe7\xe0\xf5\xee\xe4\xe0\x20\xe2\x20\xe8\xe3\xf0\xf3\x20\xf1\xea\xf0\xe8\xef\xf2\x20\xef\xee\xe4\xee\xe6\xe4\xb8\xf2\x20\x31\x20\xec\xe8\xed\xf3\xf2\xf3\x20\xe8\x20\xf1\xe0\xec\x20\xee\xef\xeb\xe0\xf2\xe8\xf2\x20\xed\xe0\xeb\xee\xe3\xe8")

    -- ── статус: раньше здесь мог бесконечно висеть "??", если отсчёт
    -- ещё не запускался или уже отработал в сессии — теперь всегда
    -- понятный текст для каждого возможного состояния ──
    if cfg.taxPayOnLogin then
        if _taxLoginWaitEndTime then
            local remain = math.max(0, math.floor(_taxLoginWaitEndTime - os.time() + 0.5))
            imgui.TextColored(thGold(), "  "..u8"\xce\xef\xeb\xe0\xf2\xe0\x20\xf7\xe5\xf0\xe5\xe7\x3a\x20"..fmtDuration(remain))
        elseif _taxLoginSkippedRecent then
            imgui.TextColored(thDim(), "  "..u8"\xd3\xe6\xe5\x20\xee\xef\xeb\xe0\xf7\xe5\xed\xee\x20\xed\xe5\xe4\xe0\xe2\xed\xee\x20\x97\x20\xef\xf0\xee\xef\xf3\xf9\xe5\xed\xee\x20\xed\xe0\x20\xfd\xf2\xee\xf2\x20\xe7\xe0\xf5\xee\xe4")
        elseif _taxLoginFired then
            imgui.TextColored(thDim(), "  "..u8"\xd3\xe6\xe5\x20\xf1\xf0\xe0\xe1\xee\xf2\xe0\xeb\xee\x20\xe2\x20\xfd\xf2\xee\xe9\x20\xf1\xe5\xf1\xf1\xe8\xe8")
        else
            imgui.TextColored(thDim(), "  "..u8"\xce\xe6\xe8\xe4\xe0\xe5\xf2\x20\xe2\xf5\xee\xe4\xe0\x20\xe2\x20\xe8\xe3\xf0\xf3\x2e\x2e\x2e")
        end
    end

    imgui.Dummy(imgui.ImVec2(0, S(30)))
end

-- ФИКС "КРАШИТ ИГРУ ПРИ ПЕРЕХОДЕ НА ДРУГУЮ ВКЛАДКУ ПОСЛЕ ОПЛАТЫ НАЛОГОВ":
-- раньше imgui.BeginChild("##staxes")/imgui.EndChild() были прямо внутри
-- drawTaxes() без pcall — если где-то в отрисовке вкладки (после свежей
-- оплаты меняются cfg.taxLastPayAmount, St.taxEntries, открыт попап лога/
-- календаря и т.п.) вылетала любая ошибка, выполнение прыгало прямо к
-- внешнему pcall главного кадра, а imgui.EndChild() для "##staxes" так и
-- не вызывался. BeginChild без парного EndChild ломает imgui-стек окон
-- НАВСЕГДА (не только этот кадр) — именно это на следующем кадре (когда
-- пользователь переключался на другую вкладку/"Финансы") крашило игру.
-- Теперь по тому же принципу, что и у drawFinanceSettingsPanel (см. её
-- комментарий "ФИКС ЗАВИСАНИЯ ФИНАНСОВ" выше): BeginChild/EndChild всегда
-- парные, а всё содержимое между ними оборачивается в pcall.
-- ФИКС КРАША (усилено, см. подробный комментарий в drawTaxesInner выше
-- в месте, откуда раньше рисовались эти же попапы): календарь выбора дня
-- и журнал оплат за день теперь всегда "навещаются" через BeginPopup()
-- каждый кадр, вне зависимости от того, открыта ли вкладка "Налоги" —
-- вызывается безусловно из главного цикла окна (см. imgui.OnFrame ниже
-- по файлу). Всё содержимое обёрнуто в pcall — ошибка внутри одного
-- попапа больше не может утащить за собой весь кадр и сломать imgui.
-- ФИКС (п.4): раньше вся функция была ОДНИМ pcall, а оба
-- popModernPopupStyle вызывались ВНУТРИ него. Если ошибка происходила
-- ДО EndPopup (например, внутри Cal.draw), pcall перехватывал её и
-- выполнение прыгало наружу, минуя popModernPopupStyle — стиль
-- оставался в стеке imgui НАВСЕГДА (тот же класс краша, что и с
-- Begin/End). Теперь каждый попап — отдельный pcall, а
-- popModernPopupStyle для него вызывается СНАРУЖИ этого pcall, всегда;
-- EndPopup тоже гарантирован через флаг beganPopup.
local function drawTaxPopupsGlobal()
    local r, g, b = getAcc()

    -- ── попап календаря ──
    do
        local taxDates = {}
        for _, e in ipairs(St.taxEntries or {}) do taxDates[e.date] = true end

        St._taxCalState = St._taxCalState or {}
        local anchor = St._taxLogBtnScreenPos
        if anchor then
            pcall(imgui.SetNextWindowPos, imgui.ImVec2(anchor.x, anchor.y + S(34)), imgui.Cond.Appearing)
        end

        -- ФИКС "кнопка Логи оплат не работает": сам imgui.OpenPopup теперь
        -- вызывается ЗДЕСЬ, в том же контексте (вне дочернего окна
        -- "##staxes"), что и BeginPopup ниже — раньше OpenPopup вызывался
        -- из drawTaxesInner (внутри "##staxes"), из-за чего оба получали
        -- разные внутренние ID для одной и той же строки, и попап никогда
        -- не открывался (см. комментарий у кнопки "Логи оплат" выше). Тот
        -- же приём (флаг + "открыт один раз"), что и у попапа с записями
        -- дня ниже.
        if St._taxCalendarPopupOpen and not St._taxCalendarPopupOpenedOnce then
            St._taxCalendarPopupOpenedOnce = true
            pcall(imgui.OpenPopup, "##taxCalendarPopup")
        end

        local _mpsT = pushModernPopupStyle()

        local beganCal = false
        local okCal, errCal = pcall(function()
            if imgui.BeginPopup("##taxCalendarPopup") then
                beganCal = true
                imgui.TextColored(thDim(), u8"\xc4\xed\xe8\x20\xf1\x20\xee\xef\xeb\xe0\xf2\xee\xe9\x20\xed\xe0\xeb\xee\xe3\xee\xe2\x20\xef\xee\xe4\xf1\xe2\xe5\xf7\xe5\xed\xfb")
                imgui.Spacing()
                Cal.draw(St._taxCalState, taxDates, function(pickedDate)
                    St._taxLogSelectedDate = pickedDate
                    imgui.CloseCurrentPopup()
                    St._taxLogEntriesPopupOpen = true
                    St._taxCalendarPopupOpen = false
                    St._taxCalendarPopupOpenedOnce = false
                end)
            end
        end)
        if beganCal then
            pcall(imgui.EndPopup)
        elseif okCal then
            -- попап закрылся сам (клик мимо/Esc) — сбрасываем флаги,
            -- чтобы кнопка могла открыть его заново
            St._taxCalendarPopupOpen = false
            St._taxCalendarPopupOpenedOnce = false
        end
        popModernPopupStyle(_mpsT) -- ФИКС (п.4): всегда снаружи pcall
        if not okCal then
            St._taxCalendarPopupOpen = false
            St._taxCalendarPopupOpenedOnce = false
            pcall(sampAddChatMessage, "{FF6666}[PC Stats] " ..
                "\xee\xf8\xe8\xe1\xea\xe0\x20\xea\xe0\xeb\xe5\xed\xe4\xe0\xf0\xff\x20\xed\xe0\xeb\xee\xe3\xee\xe2: " .. tostring(errCal), -1)
        end
    end

    -- ── всплывающее окно с карточками оплат за выбранный день ──
    -- ФИКС (по просьбе): окно сделано заметно крупнее (было 300px
    -- шириной с автовысотой) — фиксированная ширина 420px и минимум
    -- 60% высоты главного окна, чтобы список оплат за день помещался
    -- без микроскроллинга
    if St._taxLogEntriesPopupOpen then
        if not St._taxLogEntriesOpenedOnce then
            St._taxLogEntriesOpenedOnce = true
            pcall(imgui.OpenPopup, "##taxLogEntriesPopup")
        end
        local popupW = S(420)
        local popupH = (St._mainWinSize and math.max(S(320), St._mainWinSize.y * 0.6)) or S(420)
        pcall(imgui.SetNextWindowSize, imgui.ImVec2(popupW, popupH), imgui.Cond and imgui.Cond.Appearing or 0)
        if St._mainWinPos and St._mainWinSize then
            pcall(imgui.SetNextWindowPos,
                imgui.ImVec2(St._mainWinPos.x + St._mainWinSize.x/2 - popupW/2, St._mainWinPos.y + S(40)),
                imgui.Cond.Appearing)
        end
        local _mpsTL = pushModernPopupStyle()

        local beganLog = false
        local okLog, errLog = pcall(function()
            if imgui.BeginPopup("##taxLogEntriesPopup") then
                beganLog = true
                imgui.TextColored(thAcc(), "  " .. PD.fmtDateRu(St._taxLogSelectedDate))
                imgui.Spacing()
                imgui.Separator()
                imgui.Spacing()
                local shownTx = 0
                for _, e in ipairs(St.taxEntries or {}) do
                    if e.date == St._taxLogSelectedDate then
                        shownTx = shownTx + 1
                        local dl_tl = imgui.GetWindowDrawList()
                        local p_tl = imgui.GetCursorScreenPos()
                        local aw_tl = imgui.GetContentRegionAvail().x
                        local cardH_tl = S(72)
                        dl_tl:AddRectFilled(p_tl, imgui.ImVec2(p_tl.x+aw_tl, p_tl.y+cardH_tl),
                            imgui.ColorConvertFloat4ToU32(iv4(r*0.10,g*0.10,b*0.10,0.92)), 8)
                        dl_tl:AddRect(p_tl, imgui.ImVec2(p_tl.x+aw_tl, p_tl.y+cardH_tl),
                            imgui.ColorConvertFloat4ToU32(e.noTax and iv4(0.85,0.65,0.15,0.55) or iv4(0.25,0.85,0.35,0.55)), 8, 0, 1.2)
                        imgui.SetCursorScreenPos(imgui.ImVec2(p_tl.x + S(14), p_tl.y + S(8)))
                        -- ФИКС (по просьбе "чтоб в логах тоже писало что нет налогов"):
                        -- запись "налогов не было" — сумма всегда 0, показывать её как
                        -- "$0" вводит в заблуждение, поэтому вместо суммы прочерк
                        imgui.TextColored(iv4(1,1,1,1), e.time .. "  \xe2\x80\x94  " ..
                            (e.noTax and "\x2d\x2d" or fmtMoney(string.format("%.0f", e.amount))))
                        imgui.SetCursorScreenPos(imgui.ImVec2(p_tl.x + S(14), p_tl.y + S(32)))
                        imgui.TextColored(thDim(), u8"\xc2\xf0\xe5\xec\xff\x20\xee\xef\xeb\xe0\xf2\xfb\x3a\x20" ..
                            (e.auto and u8"\xe0\xe2\xf2\xee\xec\xe0\xf2\xe8\xf7\xe5\xf1\xea\xe8" or u8"\xe2\xf0\xf3\xf7\xed\xf3\xfe"))
                        imgui.SetCursorScreenPos(imgui.ImVec2(p_tl.x + S(14), p_tl.y + S(50)))
                        if e.noTax then
                            imgui.TextColored(thAcc(), u8"\xd1\xf2\xe0\xf2\xf3\xf1\x3a\x20\xcd\xe0\xeb\xee\xe3\xee\xe2\x20\xed\xe5\x20\xe1\xfb\xeb\xee")
                        else
                            imgui.TextColored(thGreen(), u8"\xd1\xf2\xe0\xf2\xf3\xf1\x3a\x20\xd3\xf1\xef\xe5\xf8\xed\xee")
                        end
                        imgui.SetCursorScreenPos(imgui.ImVec2(p_tl.x, p_tl.y + cardH_tl + S(8)))
                    end
                end
                if shownTx == 0 then
                    imgui.TextColored(thDim(), "  " .. u8"\xed\xe5\xf2\x20\xe7\xe0\xef\xe8\xf1\xe5\xe9\x20\xe7\xe0\x20\xfd\xf2\xee\xf2\x20\xe4\xe5\xed\xfc")
                end
                imgui.Spacing()
                local pr5,pg5,pb5 = getAcc()
                imgui.PushStyleColor(imgui.Col.Button,        iv4(pr5*0.25,pg5*0.25,pb5*0.25,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(pr5*0.45,pg5*0.45,pb5*0.45,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(pr5*0.65,pg5*0.65,pb5*0.65,1.0))
                if imgui.Button(u8"\xc7\xe0\xea\xf0\xfb\xf2\xfc##closeTaxLogEntries", imgui.ImVec2(-1, S(30))) then
                    imgui.CloseCurrentPopup()
                    St._taxLogEntriesPopupOpen = false
                end
                imgui.PopStyleColor(3)
            end
        end)
        if beganLog then
            pcall(imgui.EndPopup)
        elseif okLog then
            St._taxLogEntriesPopupOpen = false
            St._taxLogEntriesOpenedOnce = false
        end
        popModernPopupStyle(_mpsTL) -- ФИКС (п.4): всегда снаружи pcall
        if not okLog then
            -- та же защита, что и у drawTaxes: сбрасываем флаги попапов,
            -- чтобы сломанный кадр не повторялся бесконечно с тем же крашем
            St._taxLogEntriesPopupOpen = false
            St._taxLogEntriesOpenedOnce = false
            pcall(sampAddChatMessage, "{FF6666}[PC Stats] " ..
                "\xee\xf8\xe8\xe1\xea\xe0\x20\xef\xee\xef\xe0\xef\xe0\x20\xed\xe0\xeb\xee\xe3\xee\xe2: " .. tostring(errLog), -1)
        end
    end
end

local function drawTaxes(h)
    imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
    imgui.BeginChild("##staxes", imgui.ImVec2(0, h), false)
    local ok, err = PCS_GUARD.call(drawTaxesInner, h)
    imgui.EndChild()
    imgui.PopStyleColor()
    if not ok then
        -- сбрасываем состояние попапов вкладки, чтобы сломанный кадр не
        -- повторялся раз за разом с тем же крашем
        St._taxLogEntriesPopupOpen = false
        St._taxLogEntriesOpenedOnce = false
        pcall(sampAddChatMessage, "{FF6666}[PC Stats] " ..
            "\xee\xf8\xe8\xe1\xea\xe0\x20\xee\xf2\xf0\xe8\xf1\xee\xe2\xea\xe8\x20\xe2\xea\xeb\xe0\xe4\xea\xe8\x20\xcd\xe0\xeb\xee\xe3\xe8: " .. tostring(err), -1)
    end
end

-- ============================================================
--  ГОРЯЧАЯ КЛАВИША ОТКРЫТИЯ МЕНЮ (onKeyDown)
-- ============================================================
-- ФИКС (по просьбе — возвращено): закрытие меню скрипта по Esc снова
-- включено (раньше было намеренно отключено по прежней просьбе). Пока
-- окно ЗАКРЫТО — Esc скрипту не нужен, обычное меню паузы Arizona
-- открывается как всегда. onKeyDown здесь отвечает ТОЛЬКО за открытие
-- меню, когда оно ЗАКРЫТО: пока St.winOpen == false, mimgui неактивен
-- и не перехватывает клавиатуру, так что глобальный onKeyDown() исправно
-- получает нажатия. Захват новой клавиши при назначении, переключение
-- меню этой клавишей и закрытие по Esc, пока меню УЖЕ ОТКРЫТО,
-- обрабатываются отдельно — через imgui.IsKeyPressed внутри
-- imgui.OnFrame (см. ниже), потому что пока окно открыто, mimgui сам
-- "съедает" системные сообщения клавиш ещё до того, как они дошли бы
-- досюда ──
function onKeyDown(key)
    if St.winOpen then return end -- meню уже открыто — см. imgui.OnFrame
    if not cfg.menuHotkeyVK or cfg.menuHotkeyVK == 0 or key ~= cfg.menuHotkeyVK then
        return
    end

    local chatActive, dialogActive = false, false
    pcall(function() if sampIsChatInputActive then chatActive = sampIsChatInputActive() end end)
    pcall(function() if sampIsDialogActive then dialogActive = sampIsDialogActive() end end)
    if chatActive or dialogActive then return end

    if type(toggleMenuWindow) == "function" then
        pcall(toggleMenuWindow)
    end
end

-- ============================================================
--  ГЛАВНОЕ ОКНО
-- ============================================================
-- ── защита от краша игры: если внутри отрисовки кадра (что угодно —
-- ошибка в вычислениях, нил-значение, что-то в imgui) вылетит ошибка,
-- весь кадр оборачивается в pcall. Если imgui.Begin() уже был вызван,
-- но что-то упало до imgui.End() — не оставляем imgui в неверном
-- состоянии (это само по себе крашит игру на следующем кадре), а
-- принудительно закрываем окно и вызываем End() один раз ──
local _mainWinBegan = false

imgui.OnFrame(
    function() return St.winOpen end,
    function(self)
        St._gMain = PCS_GUARD.snap()
        local _okFrame, _errFrame = pcall(function()
        if St.winOpen then
        -- FIX: сбрасываем счётчики уникальных ID в начале каждого кадра
        St._metricTileIdx = 0
        St._chipIdx = 0
        St.chipSide = false

        -- ── горячая клавиша открытия/закрытия меню: пока окно скрипта
        -- ОТКРЫТО, mimgui сам активно перехватывает клавиатуру
        -- (WantCaptureKeyboard) и "съедает" системное сообщение клавиши
        -- ДО того, как оно дошло бы до глобального onKeyDown() — именно
        -- из-за этого горячая клавиша не срабатывала ни для назначения,
        -- ни для закрытия меню, пока оно открыто (onKeyDown() в это
        -- время попросту не вызывается). Пока окно открыто, ловим
        -- нажатия через imgui.IsKeyPressed — сам mimgui успевает
        -- записать состояние клавиши в СВОЙ внутренний буфер до того,
        -- как решит "съесть" исходное системное сообщение, так что
        -- IsKeyPressed видит нажатие исправно. onKeyDown() при этом
        -- остаётся отвечать только за открытие меню, когда оно ЗАКРЫТО
        -- (тогда mimgui неактивен и ничего не перехватывает) ──
        if St.awaitingHotkeyBind then
            local caught = nil
            for vk = 8, 222 do
                local ok, pressed = pcall(imgui.IsKeyPressed, vk)
                if ok and pressed then caught = vk; break end
            end
            if caught then
                St.awaitingHotkeyBind = false
                if caught ~= 27 then -- Esc отменяет назначение, ничего не сохраняем
                    cfg.menuHotkeyVK = caught
                    pcall(saveCfg)
                    pcall(sampAddChatMessage, "{00FF88}[PC Stats] \xc3\xee\xf0\xff\xf7\xe0\xff\x20\xea\xeb\xe0\xe2\xe8\xf8\xe0\x20\xed\xe0\xe7\xed\xe0\xf7\xe5\xed\xe0\x3a\x20" .. vkName(caught), -1)
                end
            end
        elseif cfg.menuHotkeyVK and cfg.menuHotkeyVK > 0 then
            -- ФИКС: явно repeat=false — иначе если физическую клавишу
            -- держать чуть дольше ~0.25с, ImGui сам начинает повторно
            -- считать её "нажатой" (стандартный key-repeat), и меню
            -- само открывается/закрывается по кругу, пока клавиша зажата
            local ok, pressed = pcall(imgui.IsKeyPressed, cfg.menuHotkeyVK, false)
            if ok and pressed and not (imgui.IsAnyItemActive and imgui.IsAnyItemActive()) then
                pcall(toggleMenuWindow)
            end
        end

        -- ── закрытие меню скрипта по Esc (по просьбе, возвращено). Не
        -- закрываем, если сейчас идёт назначение горячей клавиши (в той
        -- ветке Esc уже означает "отмена назначения" — см. выше) и если
        -- фокус сейчас в текстовом поле ввода (там Esc логичнее просто
        -- снять фокус, чем закрывать всё меню).
        -- ФИКС "закрыл по Esc — потом команда/хотхей не открывают
        -- меню обратно": раньше Esc закрывал окно НАПРЯМУЮ (St.winOpen =
        -- false), в обход toggleMenuWindow() и его антидребезга — из-за
        -- этого метка последнего переключения оставалась "старой" (от
        -- момента, когда меню открылось), и если сразу после Esc игрок
        -- пытался снова открыть меню командой/хотхеем в течение короткого
        -- окна антидребезга, toggleMenuWindow() считал это "слишком
        -- быстрым повтором" и молча игнорировал попытку — меню казалось
        -- намертво зависшим в закрытом состоянии. Теперь Esc тоже идёт
        -- через toggleMenuWindow() (он и так корректно закроет открытое
        -- окно), поэтому антидребезг остаётся ЕДИНЫМ для всех источников
        -- переключения и не мешает сам себе ──
        if not St.awaitingHotkeyBind then
            local okEsc, pressedEsc = pcall(imgui.IsKeyPressed, 27, false)
            if okEsc and pressedEsc and not (imgui.IsAnyItemActive and imgui.IsAnyItemActive()) then
                pcall(toggleMenuWindow)
            end
        end

        local sw = imgui.GetIO().DisplaySize.x
        local sh = imgui.GetIO().DisplaySize.y

        -- Š°Š²Ń‚Š¾Š¼Š°Ń�Ń¨Ń‚Š°Š± Š²Ń�ŠµŠ³Š¾ UI ŠæŠ¾Š´ Ń‚ŠµŠŗŃ�Ń‰ŠµŠµ Ń€Š°Š·Ń€ŠµŃ¨ŠµŠ½ŠøŠµ (Š±Š°Š·Š° 1080p)
        if sh > 0 then
            St.UI_SCALE = math.max(St.UI_SCALE_MIN, math.min(St.UI_SCALE_MAX, sh / 1080.0))
        end

        -- ŠµŃ�Š»Šø Ń€Š°Š·Ń€ŠµŃ¨ŠµŠ½ŠøŠµ/Ń€Š°Š·Š¼ŠµŃ€ ŠøŠ³Ń€Š¾Š²Š¾Š³Š¾ Š¾ŠŗŠ½Š° ŠøŠ·Š¼ŠµŠ½ŠøŠ»Š¾Ń�Ń� (Š²Ń‹Ń¨ŠµŠ» ŠøŠ· Š¾ŠŗŠ½Š° / Ń�Š¼ŠµŠ½ŠøŠ» Ń€Š°Š·Ń€ŠµŃ¨ŠµŠ½ŠøŠµ) ā€”
        -- Š·Š°Ń�Ń‚Š°Š²Š»Ń¸ŠµŠ¼ ŠæŠµŃ€ŠµŃ�Ń‡ŠøŃ‚Š°Ń‚Ń� Ń€Š°Š·Š¼ŠµŃ€ ŠøŠ¼ŠæŠ»Ń�Ń‚-Š¾ŠŗŠ½Š°, ŠøŠ½Š°Ń‡Šµ Cond.Once Š±Š¾Š»Ń�Ń¸Šµ Š½Šµ Š´Š°Ń�Ń‚ ŠµŠ¼Ń� ŠøŠ·Š¼ŠµŠ½ŠøŃ‚Ń�Ń�Ń¸
        if math.abs(sw - St._lastSw) > 2 or math.abs(sh - St._lastSh) > 2 then
            if St._lastSw > 0 then _sw_win_init = nil end
            St._lastSw, St._lastSh = sw, sh
        end

        local wPct = cfg.winWPct > 0 and cfg.winWPct or 0.60
        local hPct = cfg.winHPct > 0 and cfg.winHPct or 0.76
        local ww   = math.floor(sw * wPct)
        local wh   = math.floor(sh * hPct)
        -- Š¶Ń‘Ń�Ń‚ŠŗŠøŠµ Š³Ń€Š°Š½ŠøŃ†Ń‹, Ń‡Ń‚Š¾Š±Ń‹ Š¾ŠŗŠ½Š¾ Š½Šµ Ń�Ń‚Š°Š»Š¾ ŠŗŃ€Š¾Ń¨ŠµŃ‡Š½Ń‹Š¼ Š½Š° Š¼Š°Š»ŠµŠ½Ń�ŠŗŠøŃ… Ń€Š°Š·Ń€ŠµŃ¨ŠµŠ½ŠøŃ¸Ń… (Š½Š°ŠæŃ€. 1280x720)
        -- ŠøŠ»Šø Š½Šµ Š²Ń‹Š»ŠµŠ·Š»Š¾ Š·Š° ŠæŃ€ŠµŠ´ŠµŠ»Ń‹ Ń�ŠŗŃ€Š°Š½Š° Š½Š° Ń�Š²ŠµŃ€Ń…Ń¨ŠøŃ€Š¾ŠŗŠøŃ… Š¼Š¾Š½ŠøŃ‚Š¾Ń€Š°Ń…
        ww = math.max(math.floor(sw * 0.30), math.min(ww, math.floor(sw * 0.98)))
        wh = math.max(math.floor(sh * 0.35), math.min(wh, math.floor(sh * 0.95)))

        if not _sw_win_init then
            imgui.SetNextWindowSize(imgui.ImVec2(ww, wh), imgui.Cond.Always)
            imgui.SetNextWindowPos(imgui.ImVec2(sw*0.5, sh*0.5), imgui.Cond.Always, imgui.ImVec2(0.5,0.5))
            _sw_win_init = true
        else
            imgui.SetNextWindowSize(imgui.ImVec2(ww, wh), imgui.Cond.Once)
        end

        -- ── анимированный сдвиг главного окна влево, пока открыта (и
        -- пристыкована) панель настроек "Финансы"; двигаем окно только
        -- на кадрах, где фаза анимации реально меняется, чтобы в остальное
        -- время окно оставалось свободно перетаскиваемым мышью ──
        do
            local tnow = os.clock()
            if St._finShiftLastTime == nil then St._finShiftLastTime = tnow end
            local dt = tnow - St._finShiftLastTime
            St._finShiftLastTime = tnow
            if dt < 0 or dt > 0.5 then dt = 0 end -- защита от скачков (первый кадр / лаги)

            local target = ((St._financeSettingsOpen and not St._financeSettingsDetached)
                or (St._settingsPanelOpen and not St._settingsPanelDetached)) and 1.0 or 0.0
            local speed  = 6.0 -- скорость анимации, полный сдвиг за ~1/speed сек
            if St._finShiftAnim < target then
                St._finShiftAnim = math.min(target, St._finShiftAnim + dt*speed)
            elseif St._finShiftAnim > target then
                St._finShiftAnim = math.max(target, St._finShiftAnim - dt*speed)
            end

            -- FIX: раньше сдвигали на всю ширину панели (330), это было
            -- слишком далеко. Теперь сдвигаем на небольшое фиксированное
            -- расстояние (~4 маленьких квадратика по 24px) — если нужно
            -- ещё меньше/больше, просто поменяй число 96 ниже.
            local finShiftPx = S(96) * St._finShiftAnim

            -- FIX: раньше сдвиг считался ПРИРАЩЕНИЕМ к позиции окна из
            -- прошлого кадра (St._mainWinPos), которая сама уже могла быть
            -- сдвинута или устареть (например, после закрытия/переоткрытия
            -- окна). Ошибки накапливались и окно улетало влево гораздо
            -- сильнее, чем ширина панели. Теперь запоминаем "домашнюю"
            -- (несдвинутую) позицию окна ОДИН раз, когда сдвига ещё нет,
            -- и дальше всегда считаем целевую позицию от неё, а не от
            -- позиции прошлого кадра — дрейф невозможен в принципе.
            if St._finShiftAppliedPx < 0.5 and St._mainWinPos then
                St._finShiftAnchorX = St._mainWinPos.x
            end

            St._finShiftAppliedPx = finShiftPx

            if St._finShiftAnchorX and finShiftPx > 0.01 then
                imgui.SetNextWindowPos(imgui.ImVec2(St._finShiftAnchorX - finShiftPx, St._mainWinPos.y), imgui.Cond.Always)
            end
        end

        applyStyle()
        -- Š¼Š°Ń�Ń�Ń‚Š°Š± Ń�Ń€ŠøŃ„Ń‚Š°: ŠæŃ€ŠøŠ¼ŠµŠ½Ń¸ŠµŠ¼ Ń‡ŠµŃ€ŠµŠ· SetWindowFontScale ŠæŠ¾Ń�Š»Šµ Begin
        -- Š¯Š° Š�Š� Š¾ŠŗŠ½Š¾ Š¼Š¾Š¶Š½Š¾ Š´Š²ŠøŠ³Š°Ń‚Ń� Šø Š¼ŠµŠ½Ń¸Ń‚Ń� Ń€Š°Š·Š¼ŠµŃ€ Š¼Ń‹Ń�ŠŗŠ¾Š¹ (Š½Š° Š¼Š¾Š±ŠøŠ»Šµ Ń¨Ń‚Š¾
        -- Š±Ń‹Š»Š¾ Š¾Ń‚ŠŗŠ»ŃˇŃ‡ŠµŠ½Š¾, Ń‡Ń‚Š¾Š±Ń‹ Ń�Š»Ń�Ń‡Š°Š¹Š½Ń‹Šµ Ń‚Š°ŠæŃ‹ Š½Šµ Š´Š²ŠøŠ³Š°Š»Šø Š¾ŠŗŠ½Š¾ Š½Š° Ń‚Š°Ń‡Ń�ŠŗŃ€ŠøŠ½Šµ)
        local flags = imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoTitleBar
        PCS_GUARD.mark("frame: before Begin")
        imgui.Begin("###sw", nil, flags)
        _mainWinBegan = true
        PCS_GUARD.mark("frame: Begin ok")
        imgui.SetWindowFontScale(St.UI_SCALE * (cfg.fontSize > 0 and cfg.fontSize or 1.25))

        -- закрытие главного меню по Esc теперь целиком в onKeyDown() —
        -- см. блок "ЗАКРЫТИЕ ГЛАВНОГО МЕНЮ ПО ESC" выше по файлу; там оно
        -- срабатывает надёжно независимо от фокуса ImGui-окна


        -- ā”€ā”€ Š�Š�Š�Š¢Š˛Š�Š¯Š«Š™ Š—Š�Š“Š˛Š›Š˛Š’Š˛Š� ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€
        do
            local r0,g0,b0 = getAcc()
            local dl0 = imgui.GetWindowDrawList()
            local wp  = imgui.GetCursorScreenPos()
            local aw0 = imgui.GetContentRegionAvail().x
            local th0 = S(36)
            dl0:AddRectFilled(
                imgui.ImVec2(wp.x,      wp.y),
                imgui.ImVec2(wp.x+aw0,  wp.y+th0),
                imgui.ColorConvertFloat4ToU32(iv4(r0*0.12,g0*0.12,b0*0.12,1.0)), 10)
            dl0:AddRect(
                imgui.ImVec2(wp.x,      wp.y),
                imgui.ImVec2(wp.x+aw0,  wp.y+th0),
                imgui.ColorConvertFloat4ToU32(iv4(r0*0.55,g0*0.55,b0*0.55,0.60)), 10, 0, 1)
            dl0:AddRectFilled(
                imgui.ImVec2(wp.x,   wp.y+4),
                imgui.ImVec2(wp.x+4, wp.y+th0-4),
                imgui.ColorConvertFloat4ToU32(iv4(r0,g0,b0,1.0)), 2)
            imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
            imgui.BeginChild("##titlebar", imgui.ImVec2(aw0, th0), false)
            pcall(function()
                local titleStr = u8"  PC Stats  v" .. SCRIPT_VER
                local tsz = imgui.CalcTextSize(titleStr)
                imgui.SetCursorPos(imgui.ImVec2(aw0*0.5 - tsz.x*0.5, (th0 - tsz.y)*0.5))
                imgui.TextColored(iv4(1,1,1,1), titleStr)

                -- ФИКС (по просьбе): кнопка-иконка в правом верхнем углу
                -- (открывавшая drawProfilePopup) убрана из шапки полностью.
                -- St._profilePopupOpen принудительно держим выключенным —
                -- сама функция drawProfilePopup() в файле осталась
                -- нетронутой на случай, если понадобится вернуть позже.
                St._profilePopupOpen = false
            end) -- ФИКС: содержимое шапки под pcall, EndChild ниже гарантирован
            imgui.EndChild()
            imgui.PopStyleColor()
        end
        imgui.Spacing()

        -- ── БОКОВОЕ МЕНЮ (разделы) + ОБЛАСТЬ КОНТЕНТА ──────────────────
        -- по уточнению игрока переключатель "Вкладки как раньше" убран из
        -- "Настроек", а сам режим навсегда переключён на старый вид —
        -- единый ряд вкладок СВЕРХУ, как в более ранней версии скрипта
        -- (боковое меню слева отключено) ──
        local oldLayout = true
        local collapsed = cfg.sidebarCollapsed and not oldLayout
        local sideW   = oldLayout and 0 or (collapsed and S(52) or S(112))
        local gapSB   = oldLayout and 0 or S(6)
        local availSB = imgui.GetContentRegionAvail()
        local contW   = availSB.x - sideW - gapSB
        local fullH   = availSB.y

        if not oldLayout then
            imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
            imgui.BeginChild("##sidebarNav", imgui.ImVec2(sideW, fullH), false)
                -- ── гамбургер (☰): сворачивает/разворачивает подписи разделов ──
                do
                    local pr0,pg0,pb0 = getAcc()
                    imgui.PushStyleColor(imgui.Col.Button,        iv4(pr0*0.15,pg0*0.15,pb0*0.15,1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(pr0*0.32,pg0*0.32,pb0*0.32,1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(pr0*0.50,pg0*0.50,pb0*0.50,1.0))
                    if imgui.Button("\xe2\x98\xb0##sidebarCollapseBtn", imgui.ImVec2(sideW, S(30))) then
                        cfg.sidebarCollapsed = not cfg.sidebarCollapsed
                        saveCfg()
                    end
                    imgui.PopStyleColor(3)
                end
                imgui.Dummy(imgui.ImVec2(0, S(6)))

                local curSection = sectionOfTab(St.activeTab)
                for si, sec in ipairs(SECTION_DEFS) do
                    if si > 1 then imgui.Dummy(imgui.ImVec2(0, S(5))) end
                    local btnLabel = collapsed and sec.icon or sec.label
                    if tabButton(btnLabel, curSection == si, sideW, sec.r, sec.g, sec.b, S(46)) then
                        if curSection ~= si then
                            St._resetCharScroll = true; St._resetSettScroll = true; St.accPopupOpen = false
                            St._financeSettingsOpen = false
                            -- ФИКС КРАША ПРИ ПЕРЕХОДЕ С "НАЛОГИ" НА ДРУГУЮ ВКЛАДКУ:
                            -- если попап лога/календаря налогов был открыт (St._taxLogEntriesPopupOpen),
                            -- он был зарегистрирован через imgui.OpenPopup внутри BeginChild("##staxes"),
                            -- который рисуется ТОЛЬКО когда активна вкладка "Налоги". После переключения
                            -- вкладки drawTaxes() больше не вызывается, а popup остаётся висеть в
                            -- открытом состоянии — на следующем кадре это ломает imgui-стек попапов и
                            -- крашит игру. Явно закрываем и сбрасываем флаги при уходе со вкладки.
                            St._taxLogEntriesPopupOpen = false
                            St._taxLogEntriesOpenedOnce = false
                            local newTab = sec.tabs[1].tab
                            St.activeTab = newTab
                            if cfg.lastTab ~= newTab then cfg.lastTab = newTab; saveCfg() end
                        end
                    end
                    if collapsed and imgui.IsItemHovered() then
                        outlinedTooltip(sec.name, sec.r, sec.g, sec.b)
                    end
                end
            imgui.EndChild()
            imgui.PopStyleColor()

            imgui.SameLine(0, gapSB)
        end

        imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
        imgui.BeginChild("##sectionContent", imgui.ImVec2(contW, fullH), false)
-- ФИКС: содержимое "##sectionContent" (весь блок вкладок, шапка
-- метрик, диспетчер вкладок drawSettings/drawAbout/drawTaxes/drawTotal/
-- drawChar/drawBattle и т.п.) теперь под pcall. Раньше ошибка в ЛЮБОЙ
-- строке этого блока (а он рисуется КАЖДЫЙ кадр, для ЛЮБОЙ активной
-- вкладки) пропускала imgui.EndChild() ниже, и следующий imgui.End()
-- для главного окна попадал на несбалансированный стек — тот же класс
-- краша, что был у налогов, только на уровень выше.
St._gSC = PCS_GUARD.snap()
local _okSC, _errSC = pcall(function()

        if oldLayout then
            -- ── старый единый ряд из 7 вкладок сверху (без бокового меню) ──
            local flat = flattenTabs()
            local avOL = imgui.GetContentRegionAvail().x
            local nOL  = #flat
            local twOL = (avOL - (nOL-1)*S(4)) / nOL
            for i, td in ipairs(flat) do
                if i > 1 then imgui.SameLine(0,S(4)) end
                if tabButton(td.label, St.activeTab==td.tab, twOL, td.r, td.g, td.b) then
                    if St.activeTab ~= td.tab then
                        St._resetCharScroll = true; St._resetSettScroll = true; St.accPopupOpen = false
                        St._financeSettingsOpen = false
                        -- см. фикс краша при уходе со вкладки "Налоги" выше
                        St._taxLogEntriesPopupOpen = false
                        St._taxLogEntriesOpenedOnce = false
                    end
                    St.activeTab = td.tab
                    if cfg.lastTab ~= td.tab then cfg.lastTab = td.tab; saveCfg() end
                end
            end
            imgui.Spacing()
        end

        -- под-вкладки внутри текущего раздела (у "Персонаж" — 3: Персонаж/
        -- Бой/Финансы, у "Налоги" — 2: Оплата/Логи; у остальных разделов
        -- под-вкладок нет, строка просто не рисуется). В старом layout
        -- (без бокового меню) все 7 вкладок уже показаны одним рядом выше —
        -- этот блок пропускаем, чтобы не дублировать.
        if not oldLayout then
        do
            local sec = SECTION_DEFS[sectionOfTab(St.activeTab)]
            if sec and #sec.tabs > 1 then
                local avSub = imgui.GetContentRegionAvail().x
                local nSub  = #sec.tabs
                local twSub = (avSub - (nSub-1)*S(4)) / nSub
                for i, td in ipairs(sec.tabs) do
                    if i > 1 then imgui.SameLine(0,S(4)) end
                    if tabButton(td.label, St.activeTab==td.tab, twSub, sec.r,sec.g,sec.b) then
                        if St.activeTab ~= td.tab then
                            St._resetCharScroll = true; St._resetSettScroll = true; St.accPopupOpen = false
                            St._financeSettingsOpen = false
                            -- см. фикс краша при уходе со вкладки "Налоги" выше
                            St._taxLogEntriesPopupOpen = false
                            St._taxLogEntriesOpenedOnce = false
                        end
                        St.activeTab = td.tab
                        if cfg.lastTab ~= td.tab then cfg.lastTab = td.tab; saveCfg() end
                    end
                end
                imgui.Spacing()
            end
        end
        end

        -- Š´ŠµŠŗŠ¾Ń€Š°Ń‚ŠøŠ²Š½Š°Ń¸ Š»ŠøŠ½ŠøŃ¸ ŠæŠ¾Š´ Š²ŠŗŠ»Š°Š´ŠŗŠ°Š¼Šø
        do
            local r3,g3,b3 = getAcc()
            local dl3 = imgui.GetWindowDrawList()
            local ps  = imgui.GetCursorScreenPos()
            local aw3 = imgui.GetContentRegionAvail().x
            dl3:AddRectFilled(
                imgui.ImVec2(ps.x,     ps.y+2),
                imgui.ImVec2(ps.x+aw3, ps.y+3),
                imgui.ColorConvertFloat4ToU32(iv4(r3*0.45,g3*0.45,b3*0.45,0.60)))
        end
        imgui.Spacing()

        -- ā”€ā”€ ŠØŠ�Š�Š�Š� Š�Š•Š Š�Š˛Š¯Š�Š–Š� (Ń‚Š¾Š»Ń�ŠŗŠ¾ Š½Š° Š²ŠŗŠ»Š°Š´ŠŗŠµ 1) ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€
        if St.activeTab == 1 and St.statsData and St.statsData.name ~= "" then
            local r2,g2,b2 = getAcc()
            local rr2,rg2,rb2 = getRowBgColor()
            local dl2 = imgui.GetWindowDrawList()
            local ph  = imgui.GetCursorScreenPos()
            local aw  = imgui.GetContentRegionAvail().x
            local hdrH = (hasVal(St.statsData.authDate) or _sessionStartTime) and S(78) or S(60)
            -- Ń„Š¾Š½ Ń�Š°ŠæŠŗŠø: Ń€ŠµŠ°Š³ŠøŃ€Ń�ŠµŃ‚ Š½Š° rowBg
            local hdrBgR = math.max(rr2*0.22, 0.06)
            local hdrBgG = math.max(rg2*0.22, 0.06)
            local hdrBgB = math.max(rb2*0.22, 0.06)
            dl2:AddRectFilled(
                imgui.ImVec2(ph.x,    ph.y),
                imgui.ImVec2(ph.x+aw, ph.y+hdrH),
                imgui.ColorConvertFloat4ToU32(iv4(hdrBgR,hdrBgG,hdrBgB,0.97)), 12)
            dl2:AddRectFilled(
                imgui.ImVec2(ph.x,    ph.y),
                imgui.ImVec2(ph.x+aw*0.6, ph.y+hdrH),
                imgui.ColorConvertFloat4ToU32(iv4(rr2*0.10,rg2*0.10,rb2*0.10,0.40)), 12)
            dl2:AddRect(
                imgui.ImVec2(ph.x,    ph.y),
                imgui.ImVec2(ph.x+aw, ph.y+hdrH),
                imgui.ColorConvertFloat4ToU32(iv4(r2*0.60,g2*0.60,b2*0.60,0.80)), 12, 0, 1.4)
            -- Š»ŠµŠ²Š°Ń¸ Š°ŠŗŃ†ŠµŠ½Ń‚Š½Š°Ń¸ ŠæŠ¾Š»Š¾Ń�Š°
            dl2:AddRectFilled(
                imgui.ImVec2(ph.x,   ph.y+6),
                imgui.ImVec2(ph.x+4, ph.y+hdrH-6),
                imgui.ColorConvertFloat4ToU32(iv4(r2,g2,b2,1.0)), 2)
            -- Š²ŠµŃ€Ń…Š½Ń¸Ń¸ Ń‚Š¾Š½ŠŗŠ°Ń¸ ŠæŠ¾Š»Š¾Ń�ŠŗŠ°
            dl2:AddRectFilled(
                imgui.ImVec2(ph.x+12,    ph.y),
                imgui.ImVec2(ph.x+aw-12, ph.y+2),
                imgui.ColorConvertFloat4ToU32(iv4(r2,g2,b2,0.85)), 2)
            -- Ń¸Ń€ŠŗŠ¾Ń�Ń‚Ń� Ń„Š¾Š½Š° Ń�Š°ŠæŠŗŠø Š´Š»Ń¸ Š°Š´Š°ŠæŃ‚Š°Ń†ŠøŠø Ń†Š²ŠµŃ‚Š° Ń‚ŠµŠŗŃ�Ń‚Š°
            local hdrBright = hdrBgR*0.299 + hdrBgG*0.587 + hdrBgB*0.114
            local hdrLabelCol = hdrBright > 0.35 and iv4(0.10,0.10,0.15,1.0) or thDim()
            local hdrTextCol  = hdrBright > 0.35 and iv4(0.05,0.05,0.10,1.0) or iv4(0.48,0.48,0.55,1.0)
            imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
            imgui.BeginChild("##hdr", imgui.ImVec2(aw, hdrH), false,
                imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
                -- Š�Ń‚Ń€Š¾ŠŗŠ° 1: Š�Š•Š Š�Š˛Š¯Š�Š– + ŠøŠ¼Ń¸ + Š½Š¾Š¼ŠµŃ€ Š°ŠŗŠŗŠ°Ń�Š½Ń‚Š°
                imgui.SetCursorPos(imgui.ImVec2(S(14), S(6)))
                imgui.TextColored(hdrLabelCol, u8"\xcf\xc5\xd0\xd1\xce\xcd\xc0\xc6")
                imgui.SameLine(0,7)
                imgui.TextColored(thAccBright(), u8(St.statsData.name))
                if St.statsData.accountNumber~="" then
                    imgui.SameLine(0,7)
                    imgui.TextColored(hdrTextCol, "["..St.statsData.accountNumber.."]")
                end
                -- Š�Ń‚Ń€Š¾ŠŗŠ° 2: Š£Ń€. + EXP + HP
                imgui.SetCursorPos(imgui.ImVec2(S(14), S(28)))
                if St.statsData.level~="" then
                    imgui.TextColored(iv4(0.55,0.58,0.68,1.0), u8"\xd3\xf0.")
                    imgui.SameLine(0,4)
                    imgui.TextColored(thGold(), u8(St.statsData.level))
                    imgui.SameLine(0,14)
                end
                if St.statsData.respect~="" then
                    imgui.TextColored(iv4(0.55,0.58,0.68,1.0), "EXP:")
                    imgui.SameLine(0,4)
                    imgui.TextColored(thAcc(), u8(St.statsData.respect))
                    imgui.SameLine(0,14)
                end
                if St.statsData.health~="" then
                    local hp    = tonumber((St.statsData.health or ""):match("%d+")) or 100
                    local maxhp = tonumber((St.statsData.health or ""):match("/(%d+)")) or 100
                    local hcol  = hp>=80 and thGreen() or hp>=40 and thGold() or thRed()
                    imgui.TextColored(iv4(0.55,0.58,0.68,1.0), "HP:")
                    imgui.SameLine(0,4)
                    imgui.TextColored(hcol, u8(St.statsData.health))
                    -- Š¼ŠøŠ½Šø HP-Š±Š°Ń€
                    imgui.SameLine(0,S(10))
                    local bw2 = S(80)
                    local bp  = imgui.GetCursorScreenPos()
                    local dl3 = imgui.GetWindowDrawList()
                    local bh2 = S(10)
                    imgui.SetCursorPos(imgui.ImVec2(imgui.GetCursorPosX(), imgui.GetCursorPosY()+3))
                    dl3:AddRectFilled(
                        imgui.ImVec2(bp.x,        bp.y+3),
                        imgui.ImVec2(bp.x+bw2,    bp.y+3+bh2),
                        imgui.ColorConvertFloat4ToU32(iv4(0.12,0.12,0.14,0.90)), 5)
                    local pct = math.max(0, math.min(1, hp / math.max(1, maxhp)))
                    local fc  = pct>=0.8 and iv4(0.20,0.88,0.40,0.95) or pct>=0.4 and iv4(0.95,0.75,0.10,0.95) or iv4(0.95,0.22,0.22,0.95)
                    if pct > 0 then
                        dl3:AddRectFilled(
                            imgui.ImVec2(bp.x,           bp.y+3),
                            imgui.ImVec2(bp.x+bw2*pct,   bp.y+3+bh2),
                            imgui.ColorConvertFloat4ToU32(fc), 5)
                    end
                    imgui.Dummy(imgui.ImVec2(bw2, bh2))
                end

                -- Строка 3: дата/время авторизации на сервере (только
                -- ДД.ММ.ГГГГ ЧЧ:ММ, без подписи "Авторизация:", белым
                -- цветом) + таймер "в игре" с момента спавна в этой
                -- сессии — выводится прямо в шапке рядом с ником/HP,
                -- по просьбе игрока (заменяет прежнюю строку "Статус:") ──
                if hasVal(St.statsData.authDate) or _sessionStartTime then
                    imgui.SetCursorPos(imgui.ImVec2(S(14), S(50)))
                    if hasVal(St.statsData.authDate) then
                        imgui.TextColored(iv4(1,1,1,1), u8(St.statsData.authDate))
                    end
                    if _sessionStartTime then
                        if hasVal(St.statsData.authDate) then imgui.SameLine(0,10) end
                        imgui.TextColored(iv4(0.55,0.58,0.68,1.0), u8"\xc2\x20\xe8\xe3\xf0\xe5:")
                        imgui.SameLine(0,4)
                        imgui.TextColored(thGold(), fmtSessionDuration(os.time() - _sessionStartTime))
                    end
                end

            imgui.EndChild()
            imgui.PopStyleColor()
            imgui.Spacing()

        end

        -- Ń�Ń‚Š°Ń‚Ń�Ń� Š·Š°Š³Ń€Ń�Š·ŠŗŠø
        if St.waitingStats then
            imgui.TextColored(thGold(), u8"  \xe7\xe0\xe3\xf0\xf3\xe7\xea\xe0...")
            imgui.Spacing()
        elseif St.statusMsg ~= "" and St.statusMsg ~= u8"\xc3\xee\xf2\xee\xe2\xee" then
            imgui.TextColored(thGold(), "  "..St.statusMsg)
            imgui.Spacing()
        end

        -- ā”€ā”€ Š�Š•Š¢Š Š�Š�Š� (Ń‚Š¾Š»Ń�ŠŗŠ¾ Š²ŠŗŠ»Š°Š´ŠŗŠø 1-2) ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€
        if St.statsData and St.activeTab <= 2 then
            local s    = St.statsData
            local av   = imgui.GetContentRegionAvail().x
            local hasAZ = hasVal(s.azCoins) or hasVal(s.accountState)
            local nTiles = hasAZ and 4 or 3
            local mw   = (av - (nTiles-1)*4) / nTiles
            local cashVal  = s.cashSas~="" and fmtMoney(s.cashSas) or "-"
            local bankVal  = s.bank~="" and fmtMoney(s.bank) or "-"
            local depVal   = s.moneyDay~="" and fmtMoney(s.moneyDay) or "-"
            local azVal    = hasVal(s.accountState) and u8(s.accountState) or (hasVal(s.azCoins) and u8(s.azCoins) or "-")
            metricTile(u8"\xcd\xe0\xeb. SA$", cashVal, thGreen(), mw, function()
                pcall(sampAddChatMessage, "{00FF88}[MSW] \xf0\x9f\x92\xb5 \xcd\xe0\xeb. SA$: " .. cashVal, -1)
            end)
            imgui.SameLine(0,4)
            metricTile(u8"\xc1\xe0\xed\xea", bankVal, thAcc(), mw, function()
                pcall(sampAddChatMessage, "{00AAFF}[MSW] \xf0\x9f\x8f\xa6 \xc1\xe0\xed\xea: " .. bankVal, -1)
            end)
            imgui.SameLine(0,4)
            metricTile(u8"\xc4\xe5\xef\xee\xe7\xe8\xf2", depVal, thGold(), mw, function()
                pcall(sampAddChatMessage, "{FFD700}[MSW] \xf0\x9f\x92\xb3 \xc4\xe5\xef\xee\xe7\xe8\xf2: " .. depVal, -1)
            end)
            if hasAZ then
                imgui.SameLine(0,4)
                metricTile("AZ-Coins", azVal, thGold(), mw, function()
                    pcall(sampAddChatMessage, "{FFD700}[MSW] \xf0\x9f\xaa\x99 AZ-Coins: " .. azVal, -1)
                end)
            end
            imgui.Spacing()
        end

        -- ── НИЖНЯЯ ПАНЕЛЬ ───────────────────────────────────────────
        -- вкладка "О скрипте" теперь занимает две строки кнопок снизу
        -- (3 "опасные" + "Перезагрузить") — резервируем под неё больше
        -- места, чем под обычную нижнюю панель в одну строку
        local bottomBarH = (St.activeTab == 5) and (46 + S(50)) or 46
        local contentH = imgui.GetContentRegionAvail().y - bottomBarH - 20

        if St.activeTab == 4 then
            drawSettings(contentH, sw, sh)
        elseif St.activeTab == 5 then
            drawAbout(contentH)
        elseif St.activeTab == 6 then
            drawTaxes(contentH)
        elseif St.activeTab == 3 and St.statsData then
            drawTotal(St.statsData, contentH)
        elseif not St.statsData then
            imgui.Spacing()
            if St.waitingStats then
                imgui.TextColored(thGold(), u8"  \xc7\xe0\xe3\xf0\xf3\xe7\xea\xe0...")
            elseif St.statusMsg ~= "" then
                imgui.TextColored(thGold(), "  "..St.statusMsg)
            else
                imgui.TextColored(thDim(), u8"  \xcd\xe0\xe6\xec\xe8\xf2\xe5 \"\xce\xe1\xed\xee\xe2\xe8\xf2\xfc\" \xe4\xeb\xff \xe7\xe0\xe3\xf0\xf3\xe7\xea\xe8 \xf1\xf2\xe0\xf2\xe8\xf1\xf2\xe8\xea\xe8")
            end
        else
            local s = St.statsData
            PCS_GUARD.mark("frame: content tab " .. tostring(St.activeTab))
            if     St.activeTab == 1 then drawChar(s, contentH)
            elseif St.activeTab == 2 then drawBattle(s, contentH)
            end
        end

        imgui.Spacing()
        if St.activeTab == 4 then
            imgui.Dummy(imgui.ImVec2(0, S(10)))
        end

        -- ā”€ā”€ Š¯Š�Š–Š¯Š�Š• Š�Š¯Š˛Š�Š�Š� ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€
        local r4,g4,b4 = getAcc()
        do
            if St.activeTab == 5 then
                -- Вкладка "О скрипте": по просьбе кнопка "Закрыть" заменена
                -- на три "опасные" кнопки (Выключить/Сброс данных/Удалить) —
                -- см. drawDangerButtonsRow() выше
                local awDanger = imgui.GetContentRegionAvail().x
                drawDangerButtonsRow(awDanger, r4, g4, b4)
            else
                local bw = (imgui.GetContentRegionAvail().x - 6) * 0.5
                if St.activeTab == 6 then
                    -- вкладка "Налоги": кнопка "Сброс" возвращает к дефолту
                    -- тумблеры автооплаты налогов
                    imgui.PushStyleColor(imgui.Col.Button,        iv4(0.55,0.12,0.12,1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(0.78,0.18,0.18,1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(1.0, 0.25,0.25,1.0))
                    if imgui.Button(u8"  \xd1\xe1\xf0\xee\xf1  ##taxReset", imgui.ImVec2(bw, S(40))) then
                        cfg.taxAutoEnabled       = false
                        cfg.taxAutoIntervalHours = 1
                        cfg.taxPayOnLogin        = false
                        St.taxAutoBuf[0]         = false
                        St.taxIntervalBuf[0]     = 1
                        St.taxPayOnLoginBuf[0]   = false
                        saveCfg()
                    end
                    if imgui.IsItemHovered and imgui.IsItemHovered() then
                        pcall(function()
                            imgui.BeginTooltip()
                            imgui.TextColored(iv4(0.75,0.80,0.90,1.0), u8"\xd1\xe1\xf0\xe0\xf1\xfb\xe2\xe0\xe5\xf2\x20\xe2\xf1\xe5\x20\xf2\xf3\xec\xe1\xeb\xe5\xf0\xfb\x20\xe8\x20\xed\xe0\xf1\xf2\xf0\xee\xe9\xea\xe8\x20\xe2\xea\xeb\xe0\xe4\xea\xe8\x20\xab\xce\xef\xeb\xe0\xf2\xe0\xbb\x20\xea\x20\xe7\xed\xe0\xf7\xe5\xed\xe8\xff\xec\x20\xef\xee\x20\xf3\xec\xee\xeb\xf7\xe0\xed\xe8\xfe")
                            imgui.EndTooltip()
                        end)
                    end
                    imgui.PopStyleColor(3)
                elseif St.activeTab == 4 then
                    -- Š’ŠŗŠ»Š°Š´ŠŗŠ° Š½Š°Ń�Ń‚Ń€Š¾ŠµŠŗ: ŠŗŠ½Š¾ŠæŠŗŠ° Š�Š±Ń€Š¾Ń� + Š—Š°ŠŗŃ€Ń‹Ń‚Ń�
                    imgui.PushStyleColor(imgui.Col.Button,        iv4(0.55,0.12,0.12,1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(0.78,0.18,0.18,1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(1.0, 0.25,0.25,1.0))
                    if imgui.Button(u8"  \xd1\xe1\xf0\xee\xf1\xe8\xf2\xfc \xe2\xf1\xb8  ", imgui.ImVec2(bw, S(40))) then
                        cfg.winWPct    = 0.60; cfg.winHPct   = 0.76
                        cfg.custR      = -1;   cfg.custG      = -1;   cfg.custB = -1
                        cfg.rowBgR     = -1;   cfg.rowBgG     = -1;   cfg.rowBgB= -1
                        cfg.fontSize   = 1.25
                        St.winWbuf[0]=0.60; St.winHbuf[0]=0.76
                        St.fontSizeBuf[0] = 1.25
                        local a = getTheme().acc
                        St.custRbuf[0]=a[1]; St.custGbuf[0]=a[2]; St.custBbuf[0]=a[3]
                        St.rowBgRbuf[0]=a[1]; St.rowBgGbuf[0]=a[2]; St.rowBgBbuf[0]=a[3]
                        _sw_win_init=nil

                        -- по просьбе: сюда же влит сброс бывшей отдельной
                        -- вкладки "Уведомления" (теперь просто раздел внутри
                        -- "Настроек" — см. drawNotificationsSection)
                        cfg.toastEnabled = true
                        cfg.notifyWelcomeEnabled = true
                        cfg.notifyPaydayReminderEnabled = true
                        cfg.notifyCryptoUpdateEnabled = true
                        cfg.toastPosH = "right"; cfg.toastPosV = "bottom"
                        cfg.toastWidth = 320; cfg.toastCornerRadius = 8
                        cfg.toastDuration = 6.0; cfg.toastAnimSpeed = 10.0
                        cfg.toastMaxVisible = 5
                        cfg.toastBgR, cfg.toastBgG, cfg.toastBgB = 0.08, 0.08, 0.10
                        cfg.toastTextR, cfg.toastTextG, cfg.toastTextB = 0.94, 0.94, 0.96
                        St.toastWidthBuf, St.toastRoundBuf, St.toastDurBuf = nil, nil, nil
                        St.toastAnimBuf, St.toastMaxvBuf, St.toastBgBuf, St.toastTextBuf = nil, nil, nil, nil

                        saveCfg(); pcs_apply_toast_settings()
                    end
                    imgui.PopStyleColor(3)
                elseif St.activeTab == 3 then
                    -- Š’ŠŗŠ»Š°Š´ŠŗŠ° Š¤ŠøŠ½Š°Š½Ń�Ń‹: ŠŗŠ½Š¾ŠæŠŗŠ° Š�Š±Ń€Š¾Ń� ŠŗŃ�Ń€Ń�Š° Š²Š°Š»Ń�Ń‚ (Š²Š¼ŠµŃ�Ń‚Š¾ Š�Š±Š½Š¾Š²ŠøŃ‚Ń�)
                    imgui.PushStyleColor(imgui.Col.Button,        iv4(0.55,0.35,0.05,1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(0.75,0.50,0.08,1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(0.95,0.65,0.12,1.0))
                    if imgui.Button(u8"  \xd1\xe1\xf0\xee\xf1 \xea\xf3\xf0\xf1 \xe2\xe0\xeb\xfe\xf2  ", imgui.ImVec2(bw, S(40))) then
                        cfg.rateAZ = 35000.0; cfg.rateBTC = 0.0; cfg.rateEUR = 0.0
                        cfg.rateVC = 0.0;     cfg.rateASC = 0.0
                        St.rateAZBuf[0]  = 35000; St.rateBTCBuf[0] = 0; St.rateEURBuf[0] = 0
                        St.rateVCBuf[0]  = 0;     St.rateASCBuf[0] = 0
                        St._cefLastResult = ""
                        saveCfg()
                        pcall(sampAddChatMessage, "{FFAA00}[Stats] \xe2\x9a\xa0\xef\xb8\x8f \xea\xf3\xf0\xf1\xfb \xe2\xe0\xeb\xfe\xf2 \xf1\xe1\xf0\xee\xf8\xe5\xed\xfb \xea \xe7\xed\xe0\xf7\xe5\xed\xe8\xff\xec \xef\xee \xf3\xec\xee\xeb\xf7\xe0\xed\xe8\xfe", -1)
                    end
                    imgui.PopStyleColor(3)
                else
                    -- ŠŸŠµŃ€Ń�Š¾Š½Š°Š¶/Š‘Š¾Ń¹: ŠŗŠ½Š¾ŠæŠŗŠ° Š˛Š±Š½Š¾Š²ŠøŃ‚Ń�
                    imgui.PushStyleColor(imgui.Col.Button,        iv4(r4*0.18,g4*0.18,b4*0.18,1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(r4*0.40,g4*0.40,b4*0.40,1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(r4*0.62,g4*0.62,b4*0.62,1.0))
                    if imgui.Button(u8"  \xce\xe1\xed\xee\xe2\xe8\xf2\xfc  ", imgui.ImVec2(bw, S(40))) then
                        requestStats()
                    end
                    imgui.PopStyleColor(3)
                end
                imgui.SameLine(0,6)
                imgui.PushStyleColor(imgui.Col.Button,        iv4(0.35,0.06,0.06,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(0.58,0.12,0.12,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(0.80,0.22,0.22,1.0))
                if imgui.Button(u8"  \xc7\xe0\xea\xf0\xfb\xf2\xfc  ", imgui.ImVec2(bw, S(40))) then
                    requestCloseMenu()
                end
                imgui.PopStyleColor(3)
            end
        end

end) -- конец pcall для "##sectionContent"
        PCS_GUARD.unwind(St._gSC, "sectionContent")
        imgui.EndChild() -- ##sectionContent
        if not _okSC then
            pcall(sampAddChatMessage, "{FF6666}[PC Stats] " ..
                "\xee\xf8\xe8\xe1\xea\xe0\x20\xee\xf2\xf0\xe8\xf1\xee\xe2\xea\xe8\x20\xe2\xea\xeb\xe0\xe4\xea\xe8: " .. tostring(_errSC), -1)
        end
        imgui.PopStyleColor()

        do
            local okP, p = pcall(imgui.GetWindowPos)
            local okS, s = pcall(imgui.GetWindowSize)
            if okP and okS then St._mainWinPos, St._mainWinSize = p, s end
        end
        imgui.End()
        _mainWinBegan = false

        PCS_GUARD.callr(drawFinanceSettingsPanel)
        PCS_GUARD.callr(drawGlobalSettingsPanel)
        PCS_GUARD.callr(drawProfilePopup) -- п.6/14: тонкая карточка ник/ЗП/сервер/итого
        PCS_GUARD.callr(drawCloseConfirmPopup) -- п.12: подтверждение закрытия при изменённых настройках
        -- ФИКС КРАША "оплатил налог → сразу другая вкладка" (усилено):
        -- popup'ы календаря/журнала оплат теперь всегда навещаются здесь,
        -- вне зависимости от того, активна ли сейчас вкладка "Налоги" —
        -- см. подробный комментарий у объявления drawTaxPopupsGlobal()
        PCS_GUARD.callr(drawTaxPopupsGlobal)
        end -- konec if St.winOpen
        end) -- konec pcall _okFrame
        PCS_GUARD.unwind(St._gMain, "main frame")
        PCS_GUARD.mark("frame: end ok")

        if not _okFrame then
            -- если imgui.Begin() успел выполниться, но кадр упал раньше
            -- imgui.End() — обязательно закрываем окно, иначе imgui
            -- останется в неверном состоянии и следующий кадр крашнет игру
            if _mainWinBegan then
                pcall(imgui.End)
                _mainWinBegan = false
            end
            -- сбрасываем состояние окна и пересчёт размеров, чтобы при
            -- следующем открытии окно не унаследовало сломанное состояние
            St.winOpen = false
            _sw_win_init = nil
            pcall(sampAddChatMessage,
                "{FF6666}[PC Stats] \xe2\x9a\xa0\xef\xb8\x8f " ..
                "\xee\xf8\xe8\xe1\xea\xe0\x20\xee\xf2\xf0\xe8\xf1\xee\xe2\xea\xe8\x20\xee\xea\xed\xe0\x2c\x20\xee\xea\xed\xee\x20\xe7\xe0\xea\xf0\xfb\xf2\xee: " .. tostring(_errFrame), -1)
        end
    end
)



-- ============================================================
--  Š—Š�Š�Š Š˛Š� Š�Š¢Š�Š¢Š�Š�Š¢Š�Š�Š�
-- ============================================================
function requestStats()
    if St.waitingStats then return end
    if not isSampAvailable() then
        St.statusMsg = u8"\xd1\xe0\xec\xef \xed\xe5 \xe4\xee\xf1\xf2\xf3\xef\xe5\xed"
        return
    end
    St.waitingStats    = true
    captureStarted  = false
    lastReqTime     = now()
    lastTdTime      = now()
    tdCollector     = {}
    tdCollectorSize = 0
    -- St.statsData Š¯Š• Ń�Š±Ń€Š°Ń�Ń‹Š²Š°ŠµŠ¼ ā€” Ń�Ń‚Š°Ń€Ń‹Šµ Š´Š°Š½Š½Ń‹Šµ Š²ŠøŠ´Š½Ń‹ ŠæŠ¾ŠŗŠ° Š½Šµ ŠæŠ¾Š»Ń�Ń‡ŠøŠ¼ Š½Š¾Š²Ń‹Šµ
    St.statusMsg       = u8"\xce\xe1\xed\xee\xe2\xeb\xe5\xed\xe8\xe5..."
    lua_thread.create(function()
        wait(300)
        local ok, err = pcall(sampSendChat, "/stats")
        if not ok then
            St.waitingStats = false
            St.statusMsg = u8"\xce\xf8\xe8\xe1\xea\xe0 \xea\xee\xec\xe0\xed\xe4\xfb: " .. tostring(err)
            pcall(pcs_notify, St.statusMsg, "error")
        end
    end)
end

local function finalize()
    if not St.waitingStats or finalizing then return end
    finalizing = true
    -- Š·Š°Ń‰ŠøŃ‚Š° Š¾Ń‚ ŠæŃ�Ń�Ń‚Š¾Š³Š¾ ŠŗŠ¾Š»Š»ŠµŠŗŃ‚Š¾Ń€Š°
    if next(tdCollector) == nil then
        St.waitingStats = false
        finalizing = false  -- Š˛Š‘ŠÆŠ—Š�Š¢Š•Š›Š¬Š¯Š˛ Ń�Š±Ń€Š°Ń�Ń‹Š²Š°ŠµŠ¼ Ń„Š»Š°Š³!
        return
    end
    local rows={}
    for _,td in pairs(tdCollector) do table.insert(rows,td) end
    table.sort(rows, function(a,b)
        local ay = tonumber(a.y) or 0
        local by2 = tonumber(b.y) or 0
        local ax = tonumber(a.x) or 0
        local bx = tonumber(b.x) or 0
        if math.abs(ay - by2) < 5 then return ax < bx end
        return ay < by2
    end)
    local lines,seen={},{}
    for _,td in ipairs(rows) do
        local t=trim(td.text)
        if t~="" and not seen[t]
            and t~="\xcf\xf0\xe5\xe4\xec\xe5\xf2\xfb"
            and t~="\xc7\xe0\xea\xf0\xfb\xf2\xfc" then
            seen[t]=true; table.insert(lines,t)
        end
    end
    local raw=table.concat(lines,"\n")
    if raw~="" then
        St.statsData=parseStats(raw)
        St.statusMsg=u8"\xc3\xee\xf2\xee\xe2\xee"
    else
        St.statusMsg=u8"\xcd\xe5\xf2 \xe4\xe0\xed\xed\xfb\xf5"
    end
    St.waitingStats=false; captureStarted=false; tdCollector={}; tdCollectorSize=0
    finalizing = false
end

-- ============================================================
--  ОБРАБОТЧИКИ SAMP
-- ============================================================

function sampev.onShowDialog(id, style, title, btn1, btn2, text)
    PCS_GUARD.mark("onShowDialog id=" .. tostring(id))
    -- ── автоматизация оплаты налогов (см. payTaxesNow) ──
    -- ФИКС (по жалобе "открывает телефон и диалог, но не жмёт Оплатить"):
    -- раньше здесь была проверка "id == _taxExpectedDialogId" (см. историю
    -- в комментариях ниже, п.19) — сервер, однако, очень часто открывает
    -- КАЖДЫЙ следующий экран телефона (домашний экран → раздел → само
    -- приложение "Налоги" → экран "Оплатить") с НОВЫМ id диалога, отличным
    -- от того, что скрипт запомнил на предыдущем шаге. Из-за этого именно
    -- нужный диалог ("Оплатить"/"нет налогов") постоянно отбрасывался этой
    -- проверкой и просто висел на экране до TAX_TIMEOUT_SEC (18 секунд),
    -- после чего скрипт сдавался — снаружи это выглядело как "открыл
    -- телефон и диалог, а дальше ничего не делает". Ограничение по id
    -- убрано: пока _taxState ~= 0, обрабатываем ЛЮБОЙ пришедший диалог —
    -- это безопасно, т.к. вся логика ниже реагирует только на очень
    -- специфичный игровой текст (названия пунктов меню/кнопок налогов),
    -- который не может случайно совпасть с диалогом другого скрипта.
    if _taxState ~= 0 then
        local handledTax = false

        pcall(function()
            local lines = splitTaxLines(text)

            if _taxState == 1 then
                for i, line in ipairs(lines) do
                    if line:find(TAX_NEEDLE_PAY_ALL, 1, true) then
                        _taxState = 2
                        _taxExpectedDialogId = id
                        _taxAnsweredThisDialog = false
                        local curDialog, curIndex = id, i - 1
                        lua_thread.create(function()
                            wait(TAX_STEP_DELAY)
                            pcall(sampSendDialogResponse, curDialog, 1, curIndex, "")
                        end)
                        handledTax = true
                        return
                    end
                end
                -- ── пункт "Оплата всех налогов" не нашёлся — значит пришедший
                -- диалог это домашний экран телефона (или другое приложение),
                -- а не сами "Налоги". Ищем иконку "Налоги" прямо в этом
                -- диалоге и нажимаем на неё, как это делает игрок вручную —
                -- так же, только через несколько попыток. ФИКС (по жалобе
                -- "скрипт открывает оплату штрафов на авто вместо налогов"):
                -- никогда не нажимаем на строку, где встречается слово
                -- "Штраф" (TAX_NEEDLE_FINE), даже если в ней же случайно
                -- нашлось и "Налог"/"Банк" — цель автоматики только оплата
                -- налогов, ничего больше ──
                if _taxNavAttempts < TAX_NAV_MAX_ATTEMPTS then
                    for i, line in ipairs(lines) do
                        if line:find(TAX_NEEDLE_APP_ICON, 1, true)
                            and not line:find(TAX_NEEDLE_FINE, 1, true) then
                            _taxNavAttempts = _taxNavAttempts + 1
                            local curDialog, curIndex = id, i - 1
                            lua_thread.create(function()
                                wait(TAX_STEP_DELAY)
                                pcall(sampSendDialogResponse, curDialog, 1, curIndex, "")
                            end)
                            handledTax = true
                            return
                        end
                    end
                    -- ФИКС (по жалобе "открывает телефон, а дальше сам иди в
                    -- Банк"): если прямой пункт "Налог..." на этом экране не
                    -- нашёлся, возможно сервер перенёс "Налоги" ВНУТРЬ папки
                    -- "Банк" — пробуем зайти в неё, а на следующем пришедшем
                    -- диалоге (уже внутри Банка) поиск "Налог" выше повторится
                    -- заново автоматически, т.к. _taxState всё ещё = 1. Та же
                    -- защита от "Штраф" применяется и здесь.
                    for i, line in ipairs(lines) do
                        if line:find(BANK_NEEDLE_APP_ICON, 1, true)
                            and not line:find(TAX_NEEDLE_FINE, 1, true) then
                            _taxNavAttempts = _taxNavAttempts + 1
                            local curDialog, curIndex = id, i - 1
                            lua_thread.create(function()
                                wait(TAX_STEP_DELAY)
                                pcall(sampSendDialogResponse, curDialog, 1, curIndex, "")
                            end)
                            handledTax = true
                            return
                        end
                    end
                end
                -- ФИКС (по жалобе "если налогов к оплате нет, скрипт вместо
                -- понятного сообщения лезет куда-то ещё"): совсем ничего
                -- похожего на пункт "Оплата всех налогов" не нашли (и
                -- резервная навигация по иконкам тоже ничего не нашла, или
                -- лимит попыток исчерпан) — с учётом защиты от "Штраф" выше
                -- это почти наверняка означает, что оплачивать просто
                -- нечего (все налоги уже оплачены), а не реальную ошибку.
                -- Раньше здесь всегда показывалось техническое сообщение
                -- об ошибке ("не нашёл пункт... откройте консоль") — теперь
                -- вместо него по умолчанию считаем налоги уже оплаченными.
                _taxState = 0
                _taxExpectedDialogId = nil
                TX.addEntry(_taxIsAuto, 0, true) -- ФИКС (по просьбе): "нет налогов" тоже пишем в лог/календарь
                pcall(sampAddChatMessage, "{FFD700}[PC Stats] " ..
                    "\xcd\xe0\xeb\xee\xe3\xe8\x20\xf3\xe6\xe5\x20\xee\xef\xeb\xe0\xf7\xe5\xed\xfb", -1)
                pcall(pcs_notify, u8"\xcd\xe0\xeb\xee\xe3\xe8\x20\xf3\xe6\xe5\x20\xee\xef\xeb\xe0\xf7\xe5\xed\xfb", "info")
                -- ФИКС: не снимаем блокировку телефона мгновенно — сначала
                -- пробуем закрыть зависший диалог и только потом, с
                -- небольшой паузой, отпускаем замок (тот же приём, что и в
                -- onTaxPaymentSuccess) — иначе следующая попытка (крипта
                -- или повторная оплата) могла столкнуться с ещё открытым
                -- окном телефона и уронить игру
                lua_thread.create(function()
                    pcall(sampCloseCurrentDialog, -1)
                    wait(150)
                    pcall(sampCloseCurrentDialog, -1)
                    wait(250)
                    _phoneOpBusy = false
                end)
                handledTax = true
                return
            end

            if _taxState == 2 then
                if _taxAnsweredThisDialog then
                    -- ФИКС (п.19): ответ в этот диалог уже отправлен — не дублируем
                    handledTax = true
                    return
                end
                local curDialog = id
                local wasAuto = _taxIsAuto
                -- ФИКС (по просьбе): сам диалог "Оплата всех налогов"
                -- открылся, но сервер пишет в нём "У вас нет налогов,
                -- которые требуется оплатить" — печатаем то же самое в
                -- чат (а не только показываем в меню игры), чтобы это
                -- было видно и тем, кто не смотрит на телефон
                for _, line in ipairs(lines) do
                    if line:find(TAX_NEEDLE_NO_TAX, 1, true) then
                        _taxState = 0
                        _taxExpectedDialogId = nil
                        TX.addEntry(wasAuto, 0, true) -- ФИКС (по просьбе): "нет налогов" тоже пишем в лог/календарь
                        pcall(sampAddChatMessage, "{FFD700}[PC Stats] " .. line, -1)
                        pcall(pcs_notify, u8"\xf3\x20\xe2\xe0\xf1\x20\xed\xe5\xf2\x20\xed\xe0\xeb\xee\xe3\xee\xe2\x2c\x20\xea\xee\xf2\xee\xf0\xfb\xe5\x20\xf2\xf0\xe5\xe1\xf3\xe5\xf2\xf1\xff\x20\xee\xef\xeb\xe0\xf2\xe8\xf2\xfc", "info")
                        lua_thread.create(function()
                            pcall(sampCloseCurrentDialog, -1)
                            wait(150)
                            pcall(sampCloseCurrentDialog, -1)
                            wait(250)
                            _phoneOpBusy = false
                        end)
                        handledTax = true
                        return
                    end
                end
                -- ФИКС "в логах не показывается сумма оплаты": сумма видна прямо
                -- в тексте этого диалога (полностью, а не только в строке с
                -- кнопкой) — вытаскиваем её сейчас, пока текст ещё под рукой
                _taxPendingAmount = extractTaxAmount(text)
                for i, line in ipairs(lines) do
                    if line:find(TAX_NEEDLE_PAY_BTN, 1, true) then
                        _taxAnsweredThisDialog = true
                        lua_thread.create(function()
                            wait(TAX_STEP_DELAY)
                            pcall(sampSendDialogResponse, curDialog, 1, i - 1, "")
                            -- ФИКС (п.19): вместо немедленного onTaxPaymentSuccess —
                            -- переходим в state=3 и ждём возможный доп. диалог-
                            -- подтверждение ("Успешно"/OK), см. блок _taxState==3
                            -- ниже и комментарий у объявления _taxState выше
                            _taxState = 3
                            _taxExpectedDialogId = nil
                            wait(_TAX_POST_PAY_WAIT_MS)
                            if _taxState == 3 then
                                -- ФИКС: onTaxPaymentSuccess вызывалась без pcall — любая
                                -- ошибка внутри неё убивала поток и оставляла телефон
                                -- "залипшим" (_phoneOpBusy=true навсегда) — из-за чего
                                -- следующая попытка оплатить налоги молча ничего не
                                -- делала (не открывала меню). Теперь при сбое сами
                                -- сбрасываем состояние вместо тихого зависания.
                                local okSucc = pcall(onTaxPaymentSuccess, wasAuto, _taxPendingAmount)
                                if not okSucc then
                                    _taxState = 0
                                    _taxExpectedDialogId = nil
                                    _phoneOpBusy = false
                                    pcall(sampCloseCurrentDialog, -1)
                                end
                            end
                        end)
                        handledTax = true
                        return
                    end
                end
                if (btn1 or ""):find(TAX_NEEDLE_PAY_BTN, 1, true) then
                    _taxAnsweredThisDialog = true
                    lua_thread.create(function()
                        wait(TAX_STEP_DELAY)
                        pcall(sampSendDialogResponse, curDialog, 1, 0, "")
                        _taxState = 3
                        _taxExpectedDialogId = nil
                        wait(_TAX_POST_PAY_WAIT_MS)
                        if _taxState == 3 then
                            local okSucc = pcall(onTaxPaymentSuccess, wasAuto, _taxPendingAmount)
                            if not okSucc then
                                _taxState = 0
                                _taxExpectedDialogId = nil
                                _phoneOpBusy = false
                                pcall(sampCloseCurrentDialog, -1)
                            end
                        end
                    end)
                    handledTax = true
                    return
                end
                -- не нашли кнопку "Оплатить" — сдаёмся
                _taxState = 0
                _taxExpectedDialogId = nil
                pcall(sampAddChatMessage, "{FF6666}[PC Stats] " ..
                    "\xed\xe5\x20\xed\xe0\xf8\xb8\xeb\x20\xea\xed\xee\xef\xea\xf3\x20\x22\xce\xef\xeb\xe0\xf2\xe8\xf2\xfc\x22\x20\xe4\xeb\xff\x20\xed\xe0\xeb\xee\xe3\xee\xe2", -1)
                -- ФИКС: та же задержанная отпускалка замка, что и выше
                lua_thread.create(function()
                    pcall(sampCloseCurrentDialog, -1)
                    wait(150)
                    pcall(sampCloseCurrentDialog, -1)
                    wait(250)
                    _phoneOpBusy = false
                end)
                handledTax = true
            end

            -- ФИКС (по жалобе "после оплаты налогов надо ещё раз нажать
            -- Enter, чтобы закрыть телефон"): сервер иногда присылает ещё
            -- один диалог-подтверждение ("Успешно"/OK) уже ПОСЛЕ клика по
            -- "Оплатить" (см. переход в _taxState=3 в блоке _taxState==2
            -- выше). Раньше этот диалог ничем не обрабатывался (state уже
            -- был сброшен в 0), и игроку приходилось нажимать Enter
            -- вручную. Теперь сами нажимаем первую кнопку такого диалога и
            -- сразу завершаем оплату (без ожидания таймаута) —
            -- _taxFinalizeDone гарантирует, что это не задвоится с
            -- параллельным таймаутом ожидания в потоке выше.
            if _taxState == 3 then
                pcall(sampSendDialogResponse, id, 1, 0, "")
                local wasAuto = _taxIsAuto
                -- на случай, если сумму не удалось вытащить из первого диалога —
                -- пробуем ещё раз из этого (доп. диалог-подтверждение иногда тоже
                -- содержит сумму)
                if not (_taxPendingAmount and _taxPendingAmount > 0) then
                    _taxPendingAmount = extractTaxAmount(text)
                end
                local okSucc = pcall(onTaxPaymentSuccess, wasAuto, _taxPendingAmount)
                if not okSucc then
                    _taxState = 0
                    _taxExpectedDialogId = nil
                    _phoneOpBusy = false
                    pcall(sampCloseCurrentDialog, -1)
                end
                handledTax = true
            end
        end)
        if handledTax then return false end
    end

    -- ── автообновление курса валют через телефон (см. fetchRatesViaCEF):
    -- приложение "Криптовалюта" открывается напрямую по ID через RakNet
    -- (openCryptoAppDirect), поэтому здесь просто ждём диалог, который
    -- реально похож на экран "Курс валют" (проверяем и заголовок, и текст),
    -- разбираем его и закрываем — остальные диалоги не трогаем ──
    if _phoneFetchState == "waiting" then
        local handled = false
        pcall(function()
            if isCryptoRatesDialog(title, text) then
                local got = parsePhoneRatesText(tostring(text or ""))
                _phoneFetchState = false
                if got then
                    St._cefLastResult = "\xea\xf3\xf0\xf1\xfb \xee\xe1\xed\xee\xe2\xeb\xe5\xed\xfb \xe8\xe7 \xf2\xe5\xeb\xe5\xf4\xee\xed\xe0"
                    pcall(sampAddChatMessage, "{00FF88}[Stats] \xf0\x9f\x92\xb1 " .. "\xea\xf3\xf0\xf1\xfb \xee\xe1\xed\xee\xe2\xeb\xe5\xed\xfb \xe8\xe7 \xf2\xe5\xeb\xe5\xf4\xee\xed\xe0", -1)
                else
                    St._cefLastResult = "\xed\xe5 \xf3\xe4\xe0\xeb\xee\xf1\xfc \xf0\xe0\xe7\xee\xe1\xf0\xe0\xf2\xfc \xea\xf3\xf0\xf1\xfb \xe2 \xee\xf2\xea\xf0\xfb\xf2\xee\xec \xf0\xe0\xe7\xe4\xe5\xeb\xe5"
                    pcall(sampAddChatMessage, "{FF6666}[Stats] " .. tostring(St._cefLastResult), -1)
                end
                -- закрываем меню курсов и саму вкладку телефона, чтобы не
                -- оставлять телефон открытым поверх интерфейса игрока
                pcall(sampCloseCurrentDialog, -1)
                lua_thread.create(function()
                    wait(150)
                    pcall(sampCloseCurrentDialog, -1)
                end)
                handled = true
            end
        end)
        if handled then
            -- ФИКС "крашит игру, если сразу после проверки курса делать
            -- что-то ещё с телефоном (в т.ч. платить налоги)": раньше
            -- _cefFetching/_phoneOpBusy сбрасывались ЗДЕСЬ немедленно, хотя
            -- реальное закрытие диалога телефона идёт чуть выше отдельным
            -- потоком (ещё +150мс). Собственный поток fetchRatesViaCEF()
            -- (см. выше по файлу) и сам корректно снимет оба флага, но уже
            -- ПОСЛЕ своей закрывающей паузы, как только увидит, что
            -- _phoneFetchState стал false. Снимать их второй раз здесь, да
            -- ещё и раньше времени, только открывало окно гонки, из-за
            -- которого игра падала при быстрых действиях с телефоном сразу
            -- после проверки курса.
            return false
        end
    end

    local isStatsDialog = false
    pcall(function()
        local tT  = tostring(title or "")
        local tX  = tostring(text or "")
        local tTl = tT:lower()
        local isStatsTitle = tTl:find("\xf1\xf2\xe0\xf2") or tTl:find("stat")
                          or tTl:find("\xce\xf1\xed\xee\xe2\xed\xe0\xff \xf1\xf2\xe0\xf2")
        if isStatsTitle or isStatsPiece(tX) then
            local cleaned = stripColor(tX)
            if isStatsPiece(cleaned) or (isStatsTitle and cleaned~="") then
                -- Ń�ŠŗŃ€Ń‹Š²Š°ŠµŠ¼ Š´ŠøŠ°Š»Š¾Š³ ŠµŃ�Š»Šø Ń�ŠŗŃ€ŠøŠæŃ‚ Ń�Š°Š¼ ŠµŠ³Š¾ Š·Š°ŠæŃ€Š¾Ń�ŠøŠ»
                if St.waitingStats then isStatsDialog = true end
                St.statsData       = parseStats(cleaned)
                St.statusMsg       = u8"\xc3\xee\xf2\xee\xe2\xee"
                St.waitingStats    = false
                tdCollector     = {}
                tdCollectorSize = 0
            end
        end
    end)
    if isStatsDialog and cfg.hideNativeStats then
        -- zakryvaem rodnoy dialog srazu, chtoby igrok ego ne uvidel na ekrane
        pcall(sampCloseCurrentDialog, -1)
        return false
    end
end

-- ── слежка за чатом: ловим подтверждение "Вы оплатили все налоги на
-- сумму..." (своя оплата) — нужно, чтобы знать точное время/сумму
-- последней оплаты налогов, даже если игрок оплатил вручную из игры,
-- а не через кнопку/автооплату скрипта ──
function sampev.onServerMessage(color, text)
    -- ── учёт дохода PayDay: копим строки блока в буфер, флашим через 600мс
    -- тишины (см. PD.onLine/PD.flush выше). Работает независимо от
    -- блока оплаты налогов ниже, поэтому вынесено в отдельный pcall ──
    pcall(function()
        local cleanPd = stripColor(text or "")
        -- ФИКС "ДОХОД ДВУМЯ СТРОКАМИ" (часть 2): раньше при совпадении
        -- onStandaloneLine функция сразу делала return и НЕ запускала
        -- общий дебаунс-флаш — теперь она тоже пишет в общий буфер (см.
        -- выше), поэтому должна доходить до той же логики "подождать
        -- 600мс тишины и сохранить одной строкой", что и обычные строки
        -- банковского чека.
        local pdHandled = PD.onStandaloneLine(cleanPd) or PD.onLine(cleanPd)
        if pdHandled then
            St._paydayLastLineT = os.clock()
            lua_thread.create(function()
                local myT = St._paydayLastLineT
                wait(600)
                if St._paydayLastLineT == myT then
                    pcall(PD.flush)
                end
            end)
        end
    end)

    pcall(function()
        local clean = stripColor(text or "")
        local low   = cp1251Lower(clean)
        if not low:find(TAX_WORD, 1, true) then return end
        if not low:find(PAID_WORD, 1, true) then return end

        -- своя оплата — если ждали подтверждение диалогом, оно уже
        -- зафиксировано в onTaxPaymentSuccess, но сумму отсюда всё же
        -- пробуем уточнить (диалог не всегда содержит точную сумму)
        local sumStr = clean:match("%$%s*([%d%s%.,]+)")
        local amount = sumStr and parseGameNumber(sumStr) or 0
        if low:find("\xe2\xfb\x20\xee\xef\xeb\xe0\xf2\xe8\xeb", 1, true) then -- "вы оплатил"
            if amount > 0 then cfg.taxLastPayAmount = amount end
            if cfg.taxLastPayTime == 0 or os.time() - cfg.taxLastPayTime > 10 then
                -- игрок оплатил вручную ИЗ ИГРЫ (не через кнопку скрипта) —
                -- всё равно фиксируем время последней оплаты
                onTaxPaymentSuccess(false, amount)
            else
                cfg.taxLastPayTime = os.time()
                saveCfg()
            end
            return
        end
    end)
end

function sampev.onShowTextDraw(id, data)
    -- Š¾Š±Ń€Š°Š±Š°Ń‚Ń‹Š²Š°ŠµŠ¼ Š¢Š˛Š›Š¬Š�Š˛ ŠŗŠ¾Š³Š´Š° Š°ŠŗŃ‚ŠøŠ²Š½Š¾ Š¶Š´Ń‘Š¼ Š¾Ń‚Š²ŠµŃ‚ /stats
    if not St.waitingStats then return end
    local hidden = false
    pcall(function()
        local raw = tostring((data and data.text) or "")
        local cl  = trim(stripColor(raw))
        if cl=="" or looksTexture(cl) then return end
        local x,y = 0,0
        if data then
            if type(data.position)=="table" then
                x=tonumber(data.position.x) or 0; y=tonumber(data.position.y) or 0
            elseif tonumber(data.x) then
                x=tonumber(data.x) or 0; y=tonumber(data.y) or 0
            end
        end
        if x > 550 then return end
        local matched = isStatsPiece(cl)
        if matched then captureStarted=true end
        local inZone  = x>=-10 and x<=550 and y>=-10 and y<=1200
        if matched or (captureStarted and inZone) then
            -- Š·Š°Ń‰ŠøŃ‚Š° Š¾Ń‚ ŠæŠµŃ€ŠµŠæŠ¾Š»Š½ŠµŠ½ŠøŃ¸: ŠøŃ�ŠæŠ¾Š»Ń�Š·Ń�ŠµŠ¼ Ń�Ń‡Ń‘Ń‚Ń‡ŠøŠŗ Š²Š¼ŠµŃ�Ń‚Š¾ pairs()
            if tdCollectorSize == nil then tdCollectorSize = 0 end
            if tdCollectorSize < 300 then
                if not tdCollector[id] then tdCollectorSize = tdCollectorSize + 1 end
                tdCollector[id]={id=id,x=x,y=y,text=cl}; lastTdTime=now()
            end
            if cfg.hideNativeStats then
                -- pryachem realnyy tekst textdrawa, chtoby on ne migal na ekrane
                -- (убрано) sampTextdrawSetString внутри хука: текстдрав ещё не создан, return false его и так скрывает
                hidden = true
            end
        end
    end)
    if hidden then return false end
end

function sampev.onSetTextDraw(id, data)
    -- Š¢Š˛Š›Š¬Š�Š˛ Š²Š¾ Š²Ń€ŠµŠ¼Ń¸ Š°ŠŗŃ‚ŠøŠ²Š½Š¾Š³Š¾ Š·Š°ŠæŃ€Š¾Ń�Š°
    if not St.waitingStats then return end
    local hidden = false
    pcall(function()
        if not tdCollector[id] then return end
        if not data or not data.text then return end
        local raw = tostring((data and data.text) or "")
        local cl  = trim(stripColor(raw))
        if cl=="" or looksTexture(cl) then return end
        tdCollector[id].text=cl; lastTdTime=now()
        if cfg.hideNativeStats then
            -- (убрано) sampTextdrawSetString внутри хука: текстдрав ещё не создан, return false его и так скрывает
            hidden = true
        end
    end)
    if hidden then return false end
end

-- ============================================================
--  MAIN
-- ============================================================
function main()
    -- 1. Š�Š½Š°Ń‡Š°Š»Š° Š³Ń€Ń�Š·ŠøŠ¼ ŠŗŠ¾Š½Ń„ŠøŠ³
    loadCfg()
    if saveCfgLater then saveCfg(); saveCfgLater = false end
    -- ── по требованию: скрипт всегда открывается на вкладке "Персонаж" (1)
    -- при каждом запуске, независимо от того, какая вкладка была активна
    -- в прошлый раз (cfg.lastTab по-прежнему сохраняется и используется
    -- только для того, чтобы переключение вкладок МЕЖДУ окрытиями окна в
    -- пределах одной сессии не сбрасывалось — см. St.activeTab==i ниже) ──
    St.activeTab = 1

    -- 2. Š�ŠøŠ½Ń…Ń€Š¾Š½ŠøŠ·ŠøŃ€Ń�ŠµŠ¼ Š²Ń�Šµ Š±Ń�Ń„ŠµŃ€Ń‹
    St.winWbuf[0] = cfg.winWPct > 0 and cfg.winWPct or 0.60
    St.winHbuf[0] = cfg.winHPct > 0 and cfg.winHPct or 0.76
    if cfg.custR >= 0 then
        St.custRbuf[0] = cfg.custR
        St.custGbuf[0] = cfg.custG
        St.custBbuf[0] = cfg.custB
    else
        local a = getTheme().acc
        St.custRbuf[0] = a[1]; St.custGbuf[0] = a[2]; St.custBbuf[0] = a[3]
    end
    -- Ń�ŠøŠ½Ń…Ń€Š¾Š½ŠøŠ·Š°Ń†ŠøŃ¸ Ń†Š²ŠµŃ‚Š° Ń„Š¾Š½Š° Ń�Ń‚Ń€Š¾Šŗ
    if cfg.rowBgR >= 0 then
        St.rowBgRbuf[0] = cfg.rowBgR
        St.rowBgGbuf[0] = cfg.rowBgG
        St.rowBgBbuf[0] = cfg.rowBgB
    else
        local a = getTheme().acc
        St.rowBgRbuf[0] = a[1]; St.rowBgGbuf[0] = a[2]; St.rowBgBbuf[0] = a[3]
    end
    -- синхронизация цвета текста / фона окна / обводки
    if cfg.textR >= 0 then
        St.textRbuf[0] = cfg.textR; St.textGbuf[0] = cfg.textG; St.textBbuf[0] = cfg.textB
    else
        St.textRbuf[0] = 1.0; St.textGbuf[0] = 1.0; St.textBbuf[0] = 1.0
    end
    if cfg.winBgR >= 0 then
        St.winBgRbuf[0] = cfg.winBgR; St.winBgGbuf[0] = cfg.winBgG; St.winBgBbuf[0] = cfg.winBgB
    else
        St.winBgRbuf[0] = 0.0; St.winBgGbuf[0] = 0.0; St.winBgBbuf[0] = 0.0
    end
    if cfg.outlineR >= 0 then
        St.outlineRbuf[0] = cfg.outlineR; St.outlineGbuf[0] = cfg.outlineG; St.outlineBbuf[0] = cfg.outlineB
    else
        local a2 = getTheme().acc
        St.outlineRbuf[0] = a2[1]*0.45; St.outlineGbuf[0] = a2[2]*0.45; St.outlineBbuf[0] = a2[3]*0.45
    end
    if cfg.chatR and cfg.chatR >= 0 then
        St.chatRbuf[0] = cfg.chatR; St.chatGbuf[0] = cfg.chatG; St.chatBbuf[0] = cfg.chatB
    else
        St.chatRbuf[0] = 0.0; St.chatGbuf[0] = 1.0; St.chatBbuf[0] = 0.53
    end
    chkBuf[0] = cfg.autoRefresh
    chkBuf2[0] = cfg.hideNativeStats
    aBuf[0]   = cfg.autoInterval
    St.fontSizeBuf[0] = cfg.fontSize > 0 and cfg.fontSize or 1.25
    -- ФИКС (п.16): St.menuCmdBuf уже создан один раз при загрузке скрипта
    -- (см. "St.menuCmdBuf = imgui.new(...)" выше, вне pcall — если бы это
    -- упало, скрипт не загрузился бы вообще, и это было бы видно в
    -- консоли MoonLoader). Поэтому здесь pcall может провалиться только
    -- из-за cfg.menuOpenCmd, а не оставить St.menuCmdBuf = nil — но на
    -- всякий случай подстраховываемся явной проверкой: если буфер всё же
    -- стал nil, не даём imgui.InputText ниже упасть на nil-буфере.
    pcall(function() St.menuCmdBuf = imgui.new("char[16]", cfg.menuOpenCmd or "sw") end)
    if not St.menuCmdBuf then
        St.menuCmdBuf = imgui.new("char[16]", "sw")
    end

    -- ── синхронизация буферов вкладки "Налоги" ──
    St.taxAutoBuf[0]         = cfg.taxAutoEnabled
    St.taxIntervalBuf[0]     = cfg.taxAutoIntervalHours
    St.taxPayOnLoginBuf[0]   = cfg.taxPayOnLogin

    -- 3. Š–Š´Ń‘Š¼ SAMP ā€” Š±ŠµŠ· Š»ŠøŃ�Š½ŠøŃ… Š·Š°Š´ŠµŃ€Š¶ŠµŠŗ
    repeat wait(100) until isSampAvailable()

    -- 4. Š ŠµŠ³ŠøŃ�Ń‚Ń€ŠøŃ€Ń�ŠµŠ¼ ŠŗŠ¾Š¼Š°Š½Š´Ń�
    -- 4. Регистрируем команду открытия меню (имя команды настраивается
    -- в "Настройках"; registerMenuCommand() умеет перерегистрировать её
    -- на лету при смене без перезапуска скрипта)
    -- ФИКС "открывается на секунду и пропадает": физическое нажатие
    -- хотхея иногда попадает СРАЗУ в два обработчика подряд — сначала в
    -- глобальный onKeyDown() (пока меню было закрыто, он его открывает),
    -- а затем на первом же кадре после открытия mimgui ЕЩЁ РАЗ видит то
    -- же самое нажатие через imgui.IsKeyPressed (см. комментарий выше про
    -- то, как mimgui успевает записать состояние клавиши в свой буфер) —
    -- и тут же закрывает окно обратно, из-за чего меню мелькает и гаснет.
    -- Короткий анти-дребезг (150мс — хватает на пару кадров даже при
    -- низком FPS, но не заметен как задержка при обычном повторном
    -- нажатии) между переключениями решает это: если toggleMenuWindow()
    -- уже сработал только что, повторный вызов (от кого бы он ни пришёл —
    -- хотхей, ещё раз хотхей, Esc, команда) просто игнорируется. Раньше
    -- было 350мс — этого хватало, ЧТОБЫ ЗАЩИТИТЬ от дребезга, но при
    -- быстрой последовательности "открыл хотхеем → тут же Esc → тут же
    -- снова хотхеем/командой" (обычное поведение при тестировании) этого
    -- же окна хватало, ЧТОБЫ СЛУЧАЙНО заблокировать и следующую, уже
    -- совершенно осознанную попытку игрока — меню выглядело "намертво
    -- зависшим". 150мс — тот же эффект против дребезга, но почти не
    -- ощущается как помеха при обычном использовании ──
    local _lastToggleClock = 0
    function toggleMenuWindow()
        local nowC = os.clock()
        if nowC - _lastToggleClock < 0.15 then return end
        _lastToggleClock = nowC
        if not isSampAvailable() then return end
        if St.winOpen then
            -- закрытие (ESC/хотхей/команда): п.12 — если настройки
            -- менялись в этой сессии меню, не закрываем молча, а
            -- спрашиваем подтверждение (см. requestCloseMenu выше)
            requestCloseMenu()
            return
        end
        St.winOpen = true
        -- по просьбе: с этого момента (первое открытие меню в сессии)
        -- уведомления включаются и остаются включёнными до перезапуска
        -- скрипта, даже после закрытия меню
        St._toastSessionActive = true
        _sw_win_init = nil
        do
            local okW, wd = pcall(getWorkingDirectory)
            local dir = (okW and type(wd) == "string" and wd ~= "") and (wd .. "/config/PCStats") or CFG_DIR
            pcall(createDirectory, wd and (wd .. "/config") or "moonloader/config")
            pcall(createDirectory, dir)
            PCS_TRACE_PATH = dir .. "/crashtrace.txt"
            pcall(PCS_GUARD.traceOpen, PCS_TRACE_PATH)
            if not PCS_TRACE_SHOWN then
                PCS_TRACE_SHOWN = true
                -- только в moonloader.log, НЕ в игровой чат
                print("[PC Stats] trace file: " .. tostring(PCS_TRACE_PATH))
            end
        end
        PCS_GUARD.mark("toggleMenuWindow: open")
        requestStats()
        PCS_GUARD.mark("toggleMenuWindow: requestStats returned")
    end

    function registerMenuCommand(cmdName)
        cmdName = tostring(cmdName or "sw"):gsub("^/+", ""):gsub("%s+", "")
        if cmdName == "" then cmdName = "sw" end
        if _registeredMenuCmd then
            pcall(sampUnregisterChatCommand, _registeredMenuCmd)
        end
        local ok = pcall(sampRegisterChatCommand, cmdName, toggleMenuWindow)
        if ok then _registeredMenuCmd = cmdName end
        return ok, cmdName
    end

    registerMenuCommand(cfg.menuOpenCmd)

    -- ── команда чата для ручной оплаты налогов (по просьбе) ──
    pcall(sampRegisterChatCommand, "paytax", function() payTaxesThenHotel(false) end)

    -- ── команда самообновления: "/pcsupdate" — проверить версию на
    -- GitHub, "/pcsupdate install" — скачать актуальную версию и
    -- перезаписать ею этот же файл (см. pcsCheckForUpdate /
    -- pcsInstallUpdate выше) ──
    pcall(sampRegisterChatCommand, "pcsupdate", function(arg)
        arg = tostring(arg or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
        if arg == "install" or arg == "update" then
            pcsInstallUpdate()
        else
            pcsCheckForUpdate(false)
        end
    end)

    -- ── тихая проверка обновлений раз за сессию, через несколько
    -- секунд после старта (чтобы не мешать загрузке остального) —
    -- уведомление в чат придёт, только если реально нашлась более
    -- новая версия на GitHub ──
    if PCS_UPDATE.cfg.autoCheck then
        lua_thread.create(function()
            wait(5000)
            pcall(pcsCheckForUpdate, true)
            local mins = tonumber(PCS_UPDATE_AUTO_MINUTES) or 5
            if mins < 1 then mins = 1 end
            if mins > 60 then mins = 60 end
            while true do
                wait(mins * 60 * 1000)
                if PCS_UPDATE and PCS_UPDATE.cfg and PCS_UPDATE.cfg.autoCheck then
                    pcall(pcsCheckForUpdate, true)
                end
            end
        end)
    end

    -- уведомляем игрока в чат, что подхватилась ранее сохранённая
    -- (не дефолтная) команда открытия меню — по просьбе: "если игрок
    -- сменил команду и перезашёл, чтобы приходило уведомление в чат"
    if _restoredMenuCmd then
        pcall(sampAddChatMessage, "{00FF88}[PC Stats] \xf0\x9f\x94\x93 " ..
            "\xc2\xee\xf1\xf1\xf2\xe0\xed\xee\xe2\xeb\xe5\xed\xe0\x20\xea\xee\xec\xe0\xed\xe4\xe0\x20\xee\xf2\xea\xf0\xfb\xf2\xe8\xff\x20\xec\xe5\xed\xfe: /" .. tostring(_registeredMenuCmd or cfg.menuOpenCmd), -1)
    end

    -- 5. Š�Š¾Š¾Š±Ń‰ŠµŠ½ŠøŠµ Š² Ń‡Š°Ń‚ ā€” Š¶Š´Ń‘Š¼ Š Š•Š�Š›Š¬Š¯Š«Š™ Ń�ŠæŠ°Š²Š½ ŠøŠ³Ń€Š¾ŠŗŠ°

    lua_thread.create(function()
        for _i = 1, 120 do
            wait(500)
            local spawned = false
            pcall(function()
                local ok, res = pcall(function()
                    return sampIsLocalPlayerSpawned and sampIsLocalPlayerSpawned()
                end)
                if ok and res then spawned = true end
            end)
            if spawned then break end
        end
        -- фиксируем момент старта игровой сессии для таймера "В игре"
        -- на вкладке "Персонаж" (даже если явный спавн не поймали за 60с —
        -- всё равно даём отсчёт от этого момента, чтобы таймер не завис)
        _sessionStartTime = os.time()
        wait(2000)
        -- avtomaticheski podstavlyaem kursy valyut po opredelyonnomu serveru
        -- (tolko esli oni eshchyo ne byli poluchenih ranee cherez telefon
        -- ili vruchnuyu, chtoby ne zatirat' uzhe aktualnie dannie)
        pcall(function()
            if cfg.rateVC <= 0 and cfg.rateBTC <= 0 then
                fetchArzWikiRates(true)
            end
        end)
        pcall(sampAddChatMessage,
            "{00FF88}[MSW v" .. SCRIPT_VER .. "] \xe2\x9c\x85 {FFFFFF}PC Stats | Cmd: {00FF88}/sw", -1)
        -- ── п.7: всплывающее уведомление при входе с той же командой,
        -- что и в чате выше (по просьбе — не только текст в чат) ──
        if cfg.notifyWelcomeEnabled ~= false then
            pcall(function()
                -- ФИКС "нет тоста при входе": pcs_notify() ничего не рисует,
                -- пока St._toastSessionActive не true — раньше это выставлялось
                -- только при первом открытии меню игроком, а приветственный
                -- тост при входе срабатывал ДО этого момента и всегда молча
                -- пропускался. Включаем тосты явно уже здесь.
                St._toastSessionActive = true
                pcs_notify(u8"\xd2\xf3\xea\xed\xe8\xf2\xe5\x20/" .. tostring(_registeredMenuCmd or cfg.menuOpenCmd or "sw") ..
                    u8"\x20\xe4\xeb\xff\x20\xee\xf2\xea\xf0\xfb\xf2\xe8\xff\x20\xec\xe5\xed\xfe", "info")
            end)
        end
    end)

    -- ── оплата при входе: ждём ровно 1 минуту после спавна и сами
    -- оплачиваем налоги, если тумблер "Оплата при входе" включён
    -- (стандартизировано на 1 минуту, по просьбе — раньше была
    -- случайная задержка 1-2 минуты). _taxLoginWaitEndTime хранит
    -- время (os.time()), когда сработает автооплата — используется
    -- вкладкой "Налоги" для живого обратного отсчёта в секундах.
    -- ФИКС "??? не пропадает": раньше поток проверял тумблер ОДИН РАЗ
    -- в самом начале и, если он тогда был выключен, сразу завершался —
    -- если игрок включал тумблер уже ПОСЛЕ этой проверки (в той же
    -- сессии), отсчёт больше никогда не запускался, и вкладка "Налоги"
    -- бесконечно показывала "??". Теперь это постоянный цикл: он сам
    -- дожидается момента, когда тумблер станет включён (когда бы это ни
    -- произошло), и срабатывает один раз за сессию.
    -- ФИКС "крашит игру, если висеть на экране логина/регистрации": раньше
    -- цикл ожидания спавна пытался максимум 240*0.5=120 секунд, а потом
    -- ВСЁ РАВНО продолжал работу дальше, как будто игрок уже в игре — если
    -- регистрация нового аккаунта / выбор персонажа занимали дольше двух
    -- минут, скрипт лез открывать телефон и слать диалоговые пакеты, пока
    -- персонаж ещё даже не заспавнен, что и роняло игру. Теперь ожидание
    -- НЕ имеет лимита по попыткам — ждём столько, сколько нужно, пока
    -- sampIsLocalPlayerSpawned() не подтвердит реальный спавн, и только
    -- после этого входим в основной цикл. Плюс добавлена повторная живая
    -- проверка спавна прямо перед каждой попыткой оплаты (на случай
    -- дисконнекта/повторного захода в аккаунт посреди сессии) ──
    lua_thread.create(function()
        while not isPlayerActuallySpawned() do
            wait(500)
        end
        while true do
            if cfg.taxPayOnLogin and not _taxLoginFired and _taxState == 0 and isPlayerActuallySpawned() then
                -- ── ФИКС "платит повторно при быстром перезаходе": скрипт
                -- уже знает время последней оплаты (cfg.taxLastPayTime) —
                -- обновляется и при собственной оплате скрипта (см.
                -- onTaxPaymentSuccess), и при оплате вручную игроком (см.
                -- sampev.onServerMessage), и при автооплате по таймеру.
                -- Если с последней оплаты прошло меньше интервала
                -- автооплаты (cfg.taxAutoIntervalHours, тот же интервал,
                -- что и у "Автооплата"), значит налоги уже точно оплачены
                -- за этот период — не платим ещё раз просто потому, что
                -- игрок зашёл/перезашёл в игру ──
                local intervalSec = math.max(TAX_MIN_REPAY_SEC, (tonumber(cfg.taxAutoIntervalHours) or 1) * 3600)
                local recentlyPaid = cfg.taxLastPayTime ~= 0
                    and (os.time() - cfg.taxLastPayTime) < intervalSec
                if recentlyPaid then
                    -- уже оплачено недавно (скриптом ранее, вручную игроком
                    -- или это быстрый повторный вход) — пропускаем оплату
                    -- при входе в этой сессии, но не блокируем автооплату
                    -- по таймеру (у неё своя такая же проверка) навсегда —
                    -- _taxLoginFired нужен только чтобы "Оплата при входе"
                    -- не пыталась сработать снова и снова каждую секунду
                    _taxLoginFired = true
                    _taxLoginSkippedRecent = true
                    wait(1000)
                else
                    local delaySec = 60
                    _taxLoginWaitEndTime = os.time() + delaySec
                    wait(delaySec * 1000)
                    _taxLoginWaitEndTime = nil
                    -- перепроверяем ПОСЛЕ ожидания: за эту минуту игрок мог
                    -- успеть оплатить налоги сам (или другим способом), а
                    -- также мог отключиться/перезайти в аккаунт — поэтому
                    -- живой спавн-чек здесь обязателен, а не только в
                    -- самом начале потока
                    local stillNeeded = cfg.taxLastPayTime == 0
                        or (os.time() - cfg.taxLastPayTime) >= intervalSec
                    if cfg.taxPayOnLogin and _taxState == 0 and stillNeeded and isPlayerActuallySpawned() then
                        _taxLoginFired = true
                        pcall(payTaxesNow, true)
                    elseif cfg.taxPayOnLogin and _taxState == 0 and stillNeeded then
                        -- всё ещё нужно платить, но игрок за эту минуту
                        -- почему-то оказался не заспавнен (дисконнект/
                        -- реконнект) — не сдаёмся, пробуем снова со
                        -- следующего витка цикла вместо того, чтобы
                        -- бить попытку об стену прямо сейчас
                    elseif cfg.taxPayOnLogin and _taxState == 0 then
                        _taxLoginFired = true
                        _taxLoginSkippedRecent = true
                    end
                end
            else
                wait(1000)
            end
        end
    end)

    -- 6. Š“Š»Š°Š²Š½Ń‹Š¹ Ń†ŠøŠŗŠ» ā€” Š² Š¾Ń‚Š´ŠµŠ»Ń�Š½Š¾Š¼ ŠæŠ¾Ń‚Š¾ŠŗŠµ, main() Š·Š°Š²ŠµŃ€Ń�Š°ŠµŃ‚Ń�Ń¸
    lastAutoTime = now()
    while true do
        wait(100)

        -- ── весь цикл обёрнут в pcall: ошибка в любой из веток ниже
        -- (парсинг статов, автообновление курсов и т.п.) не должна
        -- убивать главный поток скрипта целиком ──
        local okLoop, errLoop = pcall(function()
            if St.waitingStats then
                local dt = now() - lastTdTime
                local dr = now() - lastReqTime
                if next(tdCollector) ~= nil and captureStarted and dt >= TD_DELAY then
                    local ok2, err2 = pcall(finalize)
                    if not ok2 then
                        St.waitingStats    = false
                        tdCollector     = {}
                        tdCollectorSize = 0
                        St.statusMsg = u8"\xce\xf8\xe8\xe1\xea\xe0 \xef\xe0\xf0\xf1\xe8\xed\xe3\xe0"
                        pcall(sampAddChatMessage, "{FF6666}[MSW] \xe2\x9a\xa0\xef\xb8\x8f finalize err: " .. tostring(err2), -1)
                        pcall(pcs_notify, St.statusMsg, "error")
                    end
                elseif dr >= REQ_TIMEOUT then
                    St.waitingStats    = false
                    tdCollector     = {}
                    tdCollectorSize = 0
                    if not St.statsData then
                        St.statusMsg = u8"\xcd\xe5 \xf3\xe4\xe0\xeb\xee\xf1\xfc"
                    end
                end
            end

            if cfg.autoRefresh and St.winOpen and St.statsData then
                if now() - lastAutoTime >= cfg.autoInterval then
                    lastAutoTime = now()
                    requestStats()
                end
            end

            -- ФИКС (п.17): страховочный watchdog — если _phoneOpBusy "залип"
            -- дольше 30 секунд (оба уже существующих собственных таймаута —
            -- 8с у обновления курса и TAX_TIMEOUT_SEC у оплаты налогов —
            -- по какой-то причине не сработали, например поток упал ДО
            -- своего блока сброса флагов), принудительно освобождаем
            -- телефон и сбрасываем связанные состояния, чтобы налоги и
            -- курс валют не оставались заблокированными до перезапуска
            -- скрипта
            if _phoneOpBusy and St._phoneOpBusySince and (os.time() - St._phoneOpBusySince) > 30 then
                _phoneOpBusy         = false
                _taxState            = 0
                _cefFetching         = false
                _phoneFetchState     = false
                St._phoneOpBusySince = nil
                pcall(sampAddChatMessage, "{FFAA00}[PC Stats] " ..
                    "\xf2\xe5\xeb\xe5\xf4\xee\xed\x20\xef\xf0\xe8\xed\xf3\xe4\xe8\xf2\xe5\xeb\xfc\xed\xee\x20\xee\xf1\xe2\xee\xe1\xee\xe6\xe4\xb8\xed\x20\x28watchdog\x29", -1)
            end

        end)

        if not okLoop then
            -- сбрасываем состояние ожидания статов, чтобы сломанные
            -- данные не зацикливали ошибку каждые 100мс
            St.waitingStats = false
            tdCollector = {}
            tdCollectorSize = 0
            -- ФИКС (п.20): выводим повторяющуюся ошибку не чаще раза в 10
            -- секунд, либо сразу — если текст ошибки изменился. Раньше при
            -- ошибке, повторяющейся каждые 100мс, чат заспамливался
            -- десятками одинаковых сообщений в секунду.
            local errText = tostring(errLoop)
            local nowT = os.time()
            if errText ~= St._lastLoopErrMsg or not St._lastLoopErrTime or (nowT - St._lastLoopErrTime) > 10 then
                St._lastLoopErrMsg  = errText
                St._lastLoopErrTime = nowT
                pcall(sampAddChatMessage, "{FF6666}[PC Stats] \xe2\x9a\xa0\xef\xb8\x8f loop err: " .. errText, -1)
            end
        end
    end
end

function onScriptTerminate(s, q)
    if s == thisScript() then pcall(saveCfg) end
end

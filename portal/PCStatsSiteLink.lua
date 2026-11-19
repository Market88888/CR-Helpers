script_name('PC Stats Site Link')
script_author('PC Stats')
script_version('1.0')

local API_BASE = 'https://pcstats-portal.YOUR-SUBDOMAIN.workers.dev'
local STATE_FILE = 'moonloader/config/PCStats/site_share.json'
local state = { enabled = false, clientId = '' }
local http = nil
local lastSend = 0
local busy = false

local function say(text, color)
    if type(sampAddChatMessage) == 'function' then
        pcall(sampAddChatMessage, '{9B8CFF}[PC Stats] {FFFFFF}' .. text, color or -1)
    end
end

local function ensureDir()
    if type(createDirectory) == 'function' then
        pcall(createDirectory, 'moonloader/config')
        pcall(createDirectory, 'moonloader/config/PCStats')
    end
end

local function encode(value)
    if type(encodeJson) == 'function' then
        local ok, result = pcall(encodeJson, value)
        if ok and type(result) == 'string' then return result end
    end
    return nil
end

local function newClientId()
    math.randomseed(os.time() + math.floor(os.clock() * 100000))
    local out = {}
    for i = 1, 32 do out[i] = string.format('%x', math.random(0, 15)) end
    return table.concat(out)
end

local function saveState()
    ensureDir()
    local body = encode({ enabled = state.enabled == true, clientId = state.clientId })
    if not body then return false end
    local f = io.open(STATE_FILE, 'wb')
    if not f then return false end
    f:write(body)
    f:close()
    return true
end

local function loadState()
    local f = io.open(STATE_FILE, 'rb')
    if not f then return end
    local body = f:read('*a') or ''
    f:close()
    if type(decodeJson) ~= 'function' then return end
    local ok, parsed = pcall(decodeJson, body)
    if ok and type(parsed) == 'table' then
        state.enabled = parsed.enabled == true
        state.clientId = tostring(parsed.clientId or '')
    end
end

local function request(method, path, payload)
    if not http then return false, 'requests module unavailable' end
    if type(http[method]) ~= 'function' then return false, 'HTTP method unavailable: ' .. method end
    local body = encode(payload or {})
    if not body then return false, 'JSON encoder unavailable' end
    local ok, response = pcall(http[method], API_BASE .. path, {
        data = body,
        headers = { ['Content-Type'] = 'application/json', ['Accept'] = 'application/json' },
        timeout = 6,
    })
    if not ok then return false, tostring(response) end
    local code = tonumber(response and (response.status_code or response.status)) or 0
    if code < 200 or code >= 300 then return false, 'HTTP ' .. tostring(code) end
    return true
end

local function playerInfo()
    if not sampIsAvailable or not sampIsAvailable() then return nil end
    local okId, a, b = pcall(sampGetPlayerIdByCharHandle, PLAYER_PED)
    if not okId then return nil end
    local id = (type(a) == 'number' and a) or ((a == true and type(b) == 'number') and b) or nil
    if not id or type(sampGetPlayerNickname) ~= 'function' then return nil end
    local okNick, nickname = pcall(sampGetPlayerNickname, id)
    if not okNick or type(nickname) ~= 'string' or nickname == '' then return nil end

    local server = ''
    if type(sampGetCurrentServerName) == 'function' then
        local okName, name = pcall(sampGetCurrentServerName)
        if okName and type(name) == 'string' then server = name end
    end
    if server == '' and type(sampGetCurrentServerAddress) == 'function' then
        local okAddr, address, port = pcall(sampGetCurrentServerAddress)
        if okAddr and address then server = tostring(address) .. ':' .. tostring(port or '') end
    end
    if server == '' then return nil end
    return nickname, server
end

local function heartbeat()
    if not state.enabled or busy then return end
    local nickname, server = playerInfo()
    if not nickname then return end
    busy = true
    local ok, err = request('post', '/api/heartbeat', {
        consent = true,
        clientId = state.clientId,
        nickname = nickname,
        server = server,
    })
    busy = false
    lastSend = os.clock()
    if not ok and (not state.lastErrorAt or os.clock() - state.lastErrorAt > 60) then
        state.lastErrorAt = os.clock()
        print('[PC Stats Site Link] status send failed: ' .. tostring(err))
    end
end

local function setSharing(enabled)
    if enabled then
        if state.clientId == '' or #state.clientId < 24 then state.clientId = newClientId() end
        state.enabled = true
        saveState()
        say('Публикация включена: сайт получает ваш ник и сервер, пока вы в игре. Логи и история входов не отправляются. Отключить: /pcstatsshare off')
        heartbeat()
        return
    end

    local clientId = state.clientId
    state.enabled = false
    saveState()
    if clientId ~= '' then
        lua_thread.create(function()
            local ok, err = request('post', '/api/optout', { clientId = clientId })
            if not ok then print('[PC Stats Site Link] opt-out cleanup failed: ' .. tostring(err)) end
        end)
    end
    say('Публикация выключена; запись удаляется с сайта. Для повторного включения: /pcstatsshare on')
end

function main()
    repeat wait(100) until isSampLoaded()
    local okReq, mod = pcall(require, 'requests')
    if not okReq or type(mod) ~= 'table' then pcall(function() mod = require('lib.requests') end) end
    if type(mod) == 'table' then http = mod end
    loadState()

    sampRegisterChatCommand('pcstatsshare', function(arg)
        local action = tostring(arg or ''):lower():match('^%s*(.-)%s*$')
        if action == 'on' then
            setSharing(true)
        elseif action == 'off' then
            setSharing(false)
        elseif action == 'status' then
            say(state.enabled and 'Публикация включена.' or 'Публикация выключена.')
        else
            say('Команды: /pcstatsshare on, /pcstatsshare off, /pcstatsshare status')
        end
    end)

    if state.enabled then
        say('Публикация статуса включена ранее. /pcstatsshare off отключает её и удаляет запись.')
    else
        say('Показ ника и сервера на сайте выключен. Включение: /pcstatsshare on')
    end

    while true do
        wait(15000)
        if state.enabled and os.clock() - lastSend >= 45 then heartbeat() end
    end
end


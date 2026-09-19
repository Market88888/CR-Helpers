script_name("PC Stats")
script_author("Marco_Santiago")
script_version("1.8.4")
local SCRIPT_VER = "1.8.4"

-- Bootstrap: скачивает полный PCStats.lua по частям с GitHub и устанавливает.
pcall(require, "lib.moonloader")

local N = 11
local SHA = "b07d6d929bb993bf9ee883fd80dfe8b99ca16a105f989e56a871b9fba2359c89"
local PREFIX = "pcs_raw_"
local BASE = "https://raw.githubusercontent.com/Market88888/CR-Helpers/main/"
local got = {}
local bodies = {}
local done = 0

local function notify(msg, color)
  pcall(sampAddChatMessage, (color or "{66CCFF}") .. "[PC Stats] " .. msg, -1)
end

local function finish()
  local full = table.concat(bodies, "")
  if #full < 30000 then
    notify("assemble size fail", "{FF6666}")
    return
  end
  local dest = thisScript().path
  pcall(function()
    local f = io.open(dest, "rb")
    if f then
      local d = f:read("*a"); f:close()
      local b = io.open(dest .. ".bak", "wb")
      if b then b:write(d); b:close() end
    end
  end)
  local out = io.open(dest, "wb")
  if not out then
    notify("write fail", "{FF6666}")
    return
  end
  out:write(full); out:close()
  for i = 0, N - 1 do
    pcall(os.remove, getWorkingDirectory() .. string.format("/%s%02d.tmp", PREFIX, i))
  end
  notify("v1.8.4 OK, reloading...", "{00FF88}")
  wait(600)
  pcall(function() thisScript():reload() end)
end

function main()
  while not isSampAvailable() do wait(100) end
  local dir = getWorkingDirectory()
  notify("Downloading v1.8.4 (" .. tostring(N) .. " parts)...", "{66CCFF}")
  for i = 0, N - 1 do
    local url = BASE .. string.format("%s%02d.lua", PREFIX, i) .. "?t=" .. tostring(os.time())
    local tmp = dir .. string.format("/%s%02d.tmp", PREFIX, i)
    downloadUrlToFile(url, tmp, function(id, status)
      status = tonumber(status) or -1
      if status == 6 or status == 58 or status == 2 or status == 3 then
        if not got[i] then
          got[i] = true
          local f = io.open(tmp, "rb")
          if f then bodies[i+1] = f:read("*a"); f:close() end
          done = done + 1
          if done >= N then
            local ordered = {}
            for j = 1, N do ordered[j] = bodies[j] or "" end
            bodies = ordered
            lua_thread.create(finish)
          end
        end
      end
    end)
  end
  while true do wait(1000) end
end

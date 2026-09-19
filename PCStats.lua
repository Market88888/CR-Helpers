script_name("PC Stats")
script_author("Marco_Santiago")
script_version("1.8.3")
local SCRIPT_VER = "1.8.3"

pcall(require, "lib.moonloader")

local N = 20
local BASE = "https://raw.githubusercontent.com/Market88888/CR-Helpers/main/pcs_p"
local got = {}
local done = 0

local function isDone(status)
  local dlstatus = nil
  pcall(function() dlstatus = require("moonloader").download_status end)
  if status == 6 or status == 58 then return true end
  if dlstatus and (status == dlstatus.STATUS_ENDDOWNLOADDATA or status == dlstatus.STATUSEX_ENDDOWNLOAD) then return true end
  return false
end

local function finish()
  local dir = getWorkingDirectory()
  local parts = {}
  for i = 0, N - 1 do
    local f = io.open(dir .. string.format("/pcs_p%02d.tmp", i), "rb")
    if not f then
      sampAddChatMessage("{FF6666}[PC Stats] missing part " .. tostring(i), -1)
      return
    end
    parts[#parts + 1] = f:read("*a"); f:close()
  end
  local body = table.concat(parts)
  if #body < 30000 then
    sampAddChatMessage("{FF6666}[PC Stats] assemble size fail", -1)
    return
  end
  local dest = thisScript().path
  local out = io.open(dest, "wb")
  if not out then
    sampAddChatMessage("{FF6666}[PC Stats] write fail", -1)
    return
  end
  out:write(body); out:close()
  for i = 0, N - 1 do
    pcall(os.remove, dir .. string.format("/pcs_p%02d.tmp", i))
  end
  sampAddChatMessage("{00FF88}[PC Stats] v1.8.3 OK, reloading...", -1)
  wait(600)
  pcall(function() thisScript():reload() end)
end

function main()
  while not isSampAvailable() do wait(100) end
  local dir = getWorkingDirectory()
  sampAddChatMessage("{66CCFF}[PC Stats] Downloading v1.8.3...", -1)
  for i = 0, N - 1 do
    local url = BASE .. string.format("%02d.txt", i)
    local tmp = dir .. string.format("/pcs_p%02d.tmp", i)
    downloadUrlToFile(url, tmp, function(id, status)
      if isDone(status) then
        if not got[i] then
          got[i] = true
          done = done + 1
          if done >= N then
            lua_thread.create(finish)
          end
        end
      end
    end)
  end
  while true do wait(1000) end
end

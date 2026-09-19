script_name("PC Stats")
script_author("Marco_Santiago")
script_version("1.8.3")
local SCRIPT_VER = "1.8.3"

pcall(require, "lib.moonloader")

function main()
  while not isSampAvailable() do wait(100) end
  local dlstatus = require("moonloader").download_status
  local dir = getWorkingDirectory()
  local tp1 = dir .. "/PCStats_part1.tmp"
  local tp2 = dir .. "/PCStats_part2.tmp"
  local dest = thisScript().path
  local url1 = "https://raw.githubusercontent.com/Market88888/CR-Helpers/main/PCStats_part1.lua"
  local url2 = "https://raw.githubusercontent.com/Market88888/CR-Helpers/main/PCStats_part2.lua"
  local done1, done2 = false, false
  local function isDone(status)
    if status == 6 or status == 58 then return true end
    if dlstatus and (status == dlstatus.STATUS_ENDDOWNLOADDATA or status == dlstatus.STATUSEX_ENDDOWNLOAD) then return true end
    return false
  end
  local function tryCombine()
    if not (done1 and done2) then return end
    local f1 = io.open(tp1, "rb"); local f2 = io.open(tp2, "rb")
    if not f1 or not f2 then sampAddChatMessage("{FF6666}[PC Stats] Assemble failed (open)", -1); return end
    local a = f1:read("*a"); f1:close()
    local b = f2:read("*a"); f2:close()
    if not a or not b or #a < 1000 or #b < 1000 then
      sampAddChatMessage("{FF6666}[PC Stats] Assemble failed (size)", -1)
      return
    end
    local out = io.open(dest, "wb")
    if out then out:write(a); out:write(b); out:close() end
    pcall(os.remove, tp1); pcall(os.remove, tp2)
    sampAddChatMessage("{00FF88}[PC Stats] v1.8.3 OK, reloading...", -1)
    wait(500)
    pcall(function() thisScript():reload() end)
  end
  sampAddChatMessage("{66CCFF}[PC Stats] Downloading update parts...", -1)
  downloadUrlToFile(url1, tp1, function(id, status)
    if isDone(status) then done1 = true; tryCombine() end
  end)
  downloadUrlToFile(url2, tp2, function(id, status)
    if isDone(status) then done2 = true; tryCombine() end
  end)
  while true do wait(1000) end
end

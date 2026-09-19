script_name("PC Stats")
script_author("Marco_Santiago")
script_version("1.8.3")

pcall(require, "lib.moonloader")

function main()
  while not isSampAvailable() do wait(100) end
  local dlstatus = require("moonloader").download_status
  local path = thisScript().path
  local url = "https://cdn.jsdelivr.net/gh/Market88888/CR-Helpers@main/PCStats.lua"
  -- temporary: if placeholder loop, use commit with last full file
  url = "https://raw.githubusercontent.com/Market88888/CR-Helpers/d5b5bf097ff50a7773f9a8302dddb14a9a394284/PCStats.lua"
  sampAddChatMessage("{66CCFF}[PC Stats] Restoring full script...", -1)
  downloadUrlToFile(url, path, function(id, status, p1, p2)
    if status == dlstatus.STATUS_ENDDOWNLOADDATA or status == dlstatus.STATUSEX_ENDDOWNLOAD or status == 6 or status == 58 then
      sampAddChatMessage("{00FF88}[PC Stats] Restored. Reload (F10).", -1)
      pcall(function() thisScript():reload() end)
    end
  end)
  while true do wait(1000) end
end

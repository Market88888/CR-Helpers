script_name("PC Stats")
script_description("Statistika personazha | Arizona PC | by Marco_Santiago (PC port)")
script_author("Marco_Santiago")
local SCRIPT_VER = "1.8.3"
script_version(SCRIPT_VER)

-- FULL FILE: if you see this short stub, re-upload PCStats_github_1.8.3.lua from the chat as PCStats.lua
-- This stub does NOT crash and points to the fixed local file workflow.

pcall(require, "lib.moonloader")

function main()
  while not isSampAvailable() do wait(200) end
  sampAddChatMessage("{FF6666}[PC Stats] Upload full PCStats.lua (1.8.3) to GitHub CR-Helpers - current file is a stub.", -1)
  while true do wait(5000) end
end

local wezterm = require('wezterm')
local mux = wezterm.mux

local M = {}

M.setup = function()
   wezterm.on('gui-startup', function(cmd)
      local _, _, window = mux.spawn_window(cmd or {})
      window:gui_window():maximize()
      -- 状态栏不再切 pane：已改由 tab bar 承载（events/left-status.lua +
      -- events/right-status.lua 用 set_left_status / set_right_status 绘制）。
      -- 早期那套「1 行 pane 跑 scripts/status-bar.ps1」仍可用 LEADER+b 手动切出。
   end)
end

return M

local wezterm = require('wezterm')
local act = wezterm.action

local M = {}

---Layout: 左大右小 (右侧上下分)
M.left_large_right_small = function(window, pane)
   window:perform_action(act.SplitHorizontal({ domain = 'CurrentPaneDomain' }), pane)
   wezterm.sleep_ms(200)
   window:perform_action(act.ActivatePaneDirection('Right'), pane)
   wezterm.sleep_ms(100)
   window:perform_action(act.SplitVertical({ domain = 'CurrentPaneDomain' }), pane)
   wezterm.sleep_ms(200)
   window:perform_action(act.ActivatePaneDirection('Left'), pane)
   wezterm.sleep_ms(100)
   window:perform_action(act.AdjustPaneSize({ 'Right', 20 }), pane)
end

---Layout: 田字格 (2x2)
M.grid_2x2 = function(window, pane)
   window:perform_action(act.SplitHorizontal({ domain = 'CurrentPaneDomain' }), pane)
   wezterm.sleep_ms(200)
   window:perform_action(act.SplitVertical({ domain = 'CurrentPaneDomain' }), pane)
   wezterm.sleep_ms(200)
   window:perform_action(act.ActivatePaneDirection('Left'), pane)
   wezterm.sleep_ms(100)
   window:perform_action(act.SplitVertical({ domain = 'CurrentPaneDomain' }), pane)
end

return M

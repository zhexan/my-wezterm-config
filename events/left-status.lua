local wezterm = require('wezterm')

local nf = wezterm.nerdfonts

---tab bar **左端** —— 只放「LEADER / key table」这一个**瞬态**指示器，平时为空。
---
---为什么状态信息全在右端、左端只留这一个（2026-09-27 实测后定的）：
---`window:set_left_status` 的内容画在 tab bar 的 **x = 0**，tabs 排在它后面
---（源码 wezterm-gui/src/tabbar.rs：先 `x += left_status_line.len()`，再排各 tab）。
---所以**左端一有内容，tabs 就不在最左边** —— 实测三个药丸会把 tabs 推到屏幕中间，
---观感是「tabs 悬在中间、与状态块糊成一团」（用户原话：还是很别扭）。
---⇒ 常驻信息一律走右端；左端只留给「按键瞬间才出现、松开就消失」的模式指示器。
---它的代价是：按 LEADER 期间 tabs 会右移几格、松手弹回 —— 这正是 vim 那种模式提示。
---
---⚠️ 那能不能做「两行 tab bar」来绕开？**不能** —— tab bar 架构上恒为 1 格高：
---  · `tabbar.rs::compute_ui_items(&self, y, cell_height, cell_width)`
---    → 每项 `height: cell_height`，所有条目**共用同一个 y**，没有 row 维度；
---  · 溢出时 `available_cells / number_of_tabs`（**压缩**）与
---    `while right_status_line.len() > status_space_available`（**截断**），都不折行；
---  · 配置项只有 tab_bar_at_bottom / tab_bar_style / tab_max_width，**无行数选项**。
---⇒ 想要「tabs 一行 + 状态一行」，只能把其中一行交给 **pane**（代价：多 1 整格空白带）。
local M = {}

-- 图标名经探针核实（wezterm.nerdfonts 是 userdata，不能遍历，只能逐个 pcall 探）：
--   md_table_key = U+F13C5、md_key = U+F0306
local GLYPH_KEY_TABLE = nf.md_table_key
local GLYPH_KEY = nf.md_key

---warp.yellow_br（colors/warp.lua 的实测色）。瞬态提示要够醒目。
local FG = '#e09c18'

M.setup = function()
   -- ① 必须**每个 update-status 都显式 set**，不能「什么都不做」就完事。
   --    实测踩过：把本文件改成空实现（不注册 update-status、根本不调 set_left_status）后，
   --   左端那两个药丸**依然挂在屏幕上** —— wezterm 把上一次 set 进去的字串存在窗口里，
   --    没有「未设置 = 回退到空」这种语义，热重载也不会帮你清。
   -- ② `local wezterm = require('wezterm')` 这行不能漏。实测踩过：重写本文件时漏了它，
   --    下一行 `wezterm.on(...)` 直接抛
   --    `attempt to index a nil value (global 'wezterm')` → wezterm 弹出
   --    「Configuration Error」窗口，整个配置被放弃加载。
   wezterm.on('update-status', function(window)
      local text = ''
      local name = window:active_key_table()
      if name then
         text = ' ' .. GLYPH_KEY_TABLE .. ' ' .. string.upper(name) .. ' '
      elseif window:leader_is_active() then
         text = ' ' .. GLYPH_KEY .. ' '
      end

      if text == '' then
         window:set_left_status('')
      else
         window:set_left_status(wezterm.format({
            { Attribute = { Intensity = 'Bold' } },
            { Foreground = { Color = FG } },
            { Text = text },
         }))
      end
   end)
end

return M

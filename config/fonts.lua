local wezterm = require('wezterm')
local platform = require('utils.platform')

-- local font_family = 'Maple Mono NF'
local font_family = 'JetBrainsMono NFM' -- was 'JetBrainsMono Nerd Font Mono' (family name no longer registered)
-- local font_family = 'CartographCF Nerd Font'

local font_size = platform.is_mac and 12 or 14

---@type Config
return {
   -- 坑：这里**不能**用 font_with_fallback 传单个 map。
   -- wezterm 只在「表是数组」时才把它当字体列表，{ family = ..., weight = ... } 的 #t == 0，
   -- 会被当成*空*字体列表 → 静默回退到内置字体，整个字体配置等于没写。
   -- 实测确认方式：`wezterm ls-fonts --text M` 看解析到的是磁盘字体（DirectWrite）还是内置（BuiltIn）。
   font = wezterm.font({
      family = font_family,
      weight = 'Medium',
   }),
   font_size = font_size,

   -- 行高倍数：1.2 = 在算出来的默认行高上多留 20% 间距（也接受 '120%' / '20px' 这类带单位写法）
   line_height = 1,

   freetype_load_target = 'Normal',
   freetype_render_target = 'Normal',
}

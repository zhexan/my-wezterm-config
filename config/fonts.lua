local wezterm = require('wezterm')
local platform = require('utils.platform')

-- local font_family = 'Maple Mono NF'
local font_family = 'JetBrainsMono Nerd Font Mono'
-- local font_family = 'CartographCF Nerd Font'

local font_size = platform.is_mac and 12 or 9.75

---@type Config
return {
   font = wezterm.font_with_fallback({
       family = font_family,
       weight = 'Medium',
   }),
   font_size = font_size,

   freetype_load_target = 'Normal',
   freetype_render_target = 'Normal',
}

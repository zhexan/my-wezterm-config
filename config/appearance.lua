local gpu_adapters = require('utils.gpu-adapter')
local backdrops = require('utils.backdrops')
local colors = require('colors.warp')

---@type Config
return {
   max_fps = 120,
   front_end = 'WebGpu', ---@type 'WebGpu' | 'OpenGL' | 'Software'
   webgpu_power_preference = 'HighPerformance',
   webgpu_preferred_adapter = gpu_adapters:pick_best(),
   -- webgpu_preferred_adapter = gpu_adapters:pick_manual('Dx12', 'IntegratedGpu'),
   -- webgpu_preferred_adapter = gpu_adapters:pick_manual('Gl', 'Other'),
   underline_thickness = '1.5pt',

   -- cursor
   animation_fps = 120,
   cursor_blink_ease_in = 'EaseOut',
   cursor_blink_ease_out = 'EaseOut',
   default_cursor_style = 'BlinkingBlock',
   cursor_blink_rate = 650,

   -- color scheme
   colors = colors,

   -- background: pass in `true` if you want wezterm to start with focus mode on (no bg images)
   background = backdrops:initial_options({ no_img = false }),

   -- scrollbar
   enable_scroll_bar = true,

   -- tab bar
   -- 用 retro（字符网格）样式。这不是审美选择，是功能前提：
   -- WezTerm 只有这组「行内状态」API ——  window:set_left_status / set_right_status，
   -- 而它们的落点就是 tab bar 那一行（官方原文：displayed in the tab bar, to the
   -- left of the tabs）。产品里**没有独立的「状态栏」区域**，所以这才是把状态信息
   -- 放进 UI 的官方路径；早先用 1 行 pane 模拟是绕路，代价是分隔格 17px 缝
   -- 与窗口底部 24px 网格余数两处空白。
   -- ⚠️ fancy 模式下这一行由原生渲染接管，上述两个 status API 的内容**不会显示**。
   -- 代价：失去原生圆角药丸与比例字体，改由 events/tab-title.lua 用字符绘制。
   enable_tab_bar = true,
   hide_tab_bar_if_only_one_tab = false,
   use_fancy_tab_bar = false,
   tab_max_width = 23,
   show_tab_index_in_tab_bar = false,
   switch_to_last_active_tab_when_closing_tab = true,

   -- command palette
   command_palette_fg_color = '#b4befe',
   command_palette_bg_color = '#11111b',
   command_palette_font_size = 12,
   command_palette_rows = 25,

   -- window
   -- bottom = 0：状态信息现在画在 tab bar 那一行（set_left_status / set_right_status），
   -- pane 区域下方只剩窗口自身的网格余数，再留 padding 只会让那圈空白更厚。
   -- （早期留 7.5 是为了迁就「1 行 pane 状态栏」的贴边效果，那套现在只在 LEADER+b
   --   手动切出时才会用到。）
   -- 而且文字在 38px 里偏上，看着就"太高"。
   window_padding = {
      left = 0,
      right = 0,
      top = 10,
      bottom = 0,
   },
   adjust_window_size_when_changing_font_size = false,
   window_close_confirmation = 'NeverPrompt',
   window_frame = {
      active_titlebar_bg = '#090909',
      -- font = fonts.font,
      -- font_size = fonts.font_size,
   },
   -- inactive_pane_hsb = {
   --    saturation = 0.9,
   --    brightness = 0.65,
   -- },
   inactive_pane_hsb = {
      saturation = 1,
      brightness = 1,
   },

   visual_bell = {
      fade_in_function = 'EaseIn',
      fade_in_duration_ms = 250,
      fade_out_function = 'EaseOut',
      fade_out_duration_ms = 250,
      target = 'CursorColor',
   },
}

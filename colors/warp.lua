--[[
  Warp UI 配色（feat/warp-ui 分支）

  来源说明 —— 本文件所有色值都不是"凭感觉调的"，而是从用户提供的
  Warp 截图里逐像素采样得到的，采样方法与原始数据：

    脚本  C:\Users\<user>\WorkBuddy\<session>\_warp_pick.py / _warp_pick2.py / _warp_text.py
    数据  _warp_colors.txt / _warp_colors2.txt / _warp_text_colors.txt

  采样要点（2040x1044 的 2x 截图）：
    · 底部 agent 输入区（不透明面板）      #101010
    · 命令参数 / 正文（最亮像素众数）      #f8f8f4
    · 提示符里的路径                      #aca4a0（偏暖）/ #a4a8ac（偏冷，随底色浮动）
    · 底部 "Run commands" 提示文字        #6c6c6c
    · 失败块左竖条 / 错误标记             #d02c1c
    · 错误正文                            #d84c40
    · alias / cmdlet（PSReadLine 语法高亮）#bc9c64
    · 高饱和黄（错误行里出现）            #e09c18
    · 块与块之间的分隔线                  #3d3d3b

  ⚠️ 截图里没出现 green / blue / magenta / cyan —— 这四个沿用 Warp 官方
     内置主题 warp.yaml 的值（github.com/warpdotdev/themes → warp_bundled/warp.yaml），
     因为它们与实测色同属一套视觉体系，比凭空猜更可靠。
]]

local warp = {
   -- 实测值
   bg_ui      = '#101010', -- 底部面板 / 窗口底色
   fg         = '#f8f8f4', -- 正文
   fg_dim     = '#aca4a0', -- 提示符路径
   fg_mute    = '#6c6c6c', -- 次要提示
   red        = '#d02c1c', -- 失败 / 错误
   red_bright = '#d84c40', -- 错误正文
   yellow     = '#bc9c64', -- 命令名
   yellow_br  = '#e09c18', -- 高亮黄
   sep        = '#3d3d3b', -- 分隔线

   -- 取自 Warp 官方 warp.yaml（截图未覆盖的色相）
   green      = '#99bf52',
   blue       = '#5299bf',
   magenta    = '#9989cc',
   cyan       = '#72b9bf',
   green_br   = '#b4fa72',
   blue_br    = '#a5d5fe',
   magenta_br = '#ff8ffd',
   cyan_br    = '#d0d1fe',
}

local colorscheme = {
   foreground = warp.fg,
   background = warp.bg_ui,
   cursor_bg = warp.fg,
   cursor_fg = warp.bg_ui,
   cursor_border = warp.fg,
   selection_bg = warp.sep,
   selection_fg = warp.fg,

   ansi = {
      warp.bg_ui,    -- 0 black   （用窗口底色，侧栏/滚动条轨道融入背景）
      warp.red,      -- 1 red
      warp.green,    -- 2 green
      warp.yellow,   -- 3 yellow  ← PSReadLine 的 alias/cmdlet 走这一格
      warp.blue,     -- 4 blue
      warp.magenta,  -- 5 magenta
      warp.cyan,     -- 6 cyan
      warp.fg_dim,   -- 7 white
   },
   brights = {
      warp.fg_mute,    -- 8  bright black（PSReadLine 注释/dim 文本）
      warp.red_bright, -- 9  bright red
      warp.green_br,   -- 10 bright green
      warp.yellow_br,  -- 11 bright yellow
      warp.blue_br,    -- 12 bright blue
      warp.magenta_br, -- 13 bright magenta
      warp.cyan_br,    -- 14 bright cyan
      warp.fg,         -- 15 bright white
   },

   -- 标签栏：Warp 的标签是贴在窗口上沿的扁平色块，没有明显边框
   tab_bar = {
      background = 'rgba(0, 0, 0, 0)', -- 透明，直接吃窗口背景 / 壁纸
      active_tab = {
         bg_color = 'rgba(255, 255, 255, 0.10)',
         fg_color = warp.fg,
         intensity = 'Bold',
      },
      inactive_tab = {
         bg_color = 'rgba(0, 0, 0, 0)',
         fg_color = warp.fg_mute,
      },
      inactive_tab_hover = {
         bg_color = 'rgba(255, 255, 255, 0.05)',
         fg_color = warp.fg_dim,
      },
      new_tab = {
         bg_color = 'rgba(0, 0, 0, 0)',
         fg_color = warp.fg_mute,
      },
      new_tab_hover = {
         bg_color = 'rgba(255, 255, 255, 0.05)',
         fg_color = warp.fg,
      },
   },

   visual_bell = warp.red,
   scrollbar_thumb = warp.sep,
   -- 2026-09-27：这是底部状态栏「上面那条横线」的颜色。
   -- 实测（1:1 物理像素抓屏 + 逐行扫描）：线本身 3px 厚、**不透明**（采样值 #3c3c3a），
   -- 而分隔格其余部分是「半透明 pane 底色 + 壁纸」，任何固定色都匹配不上故无法融掉它。
   -- 唯一能让它消失的办法就是全透明 —— 露出下面的底色，视觉上等于没画。
   -- 副作用：那条 37px 的分隔格仍在（wezterm 的结构固定吃掉整 1 格），只是不再有断头线。
   split = 'rgba(0, 0, 0, 0)',
   compose_cursor = warp.yellow,
}

return colorscheme

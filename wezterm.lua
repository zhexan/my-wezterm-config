local Config = require('config')

require('utils.backdrops')
   -- :set_images_dir(require('wezterm').home_dir .. '/Pictures/Wallpapers/')
   :scan_images_dir()
   :random()

require('events.left-status').setup()
-- date_format 决定右端块里「时钟」那一格的宽度，而 tab bar 是**单行有限宽**：
-- 149 列 + 4 个 tab 时右端只剩 ≈62 格，`%a %H:%M:%S`（12 格：Sun 21:31:13）会被
-- 从左端裁掉首字符。`%H:%M:%S`（8 格）留出余量，星期几在系统任务栏本就有。
require('events.right-status').setup({ date_format = '%H:%M:%S' })
require('events.tab-title').setup({
   hide_active_tab_unseen = true,
   unseen_icon = 'numbered_box',
   show_progress = true,
})
require('events.new-tab-button').setup()
require('events.gui-startup').setup()

return Config:init()
   :append(require('config.appearance'))
   :append(require('config.bindings'))
   :append(require('config.domains'))
   :append(require('config.fonts'))
   :append(require('config.general'))
   :append(require('config.launch')).options

local wezterm = require('wezterm')
local Cells = require('utils.cells')
local OptsValidator = require('utils.opts-validator')

local nf = wezterm.nerdfonts
local attr = Cells.attr

---@alias Event.RightStatusOptionsInput { date_format?: string }

---@alias Event.RightStatusOptions { date_format: string }

---Setup options for the tab bar right status segment
---@type OptsValidator
local EVENT_OPTS = OptsValidator:new({
   {
      name = 'date_format',
      type = 'string',
      default = '%a %H:%M:%S',
   },
})

---tab bar **右端**的状态段 —— 本配置**全部**状态信息的落点。
---
---为什么全在右端（2026-09-27 实测后定的）：
---`window:set_left_status` 的内容画在 tab bar 的 **x=0**，tabs 排在它后面
---（源码 wezterm-gui/src/tabbar.rs：先 `x += left_status_line.len()`，再排 tabs）。
---所以左端一旦有内容，**tabs 就不在最左边** —— 实测三个药丸会把 tabs 挤到屏幕中间，
---观感是「tabs 悬在中间、与状态块糊在一起」。⇒ 左端留空，一切走右端。
---
---为什么画成「彩字 + 竖线」，不是药丸（同上，用户当场否决过药丸画法）：
---药丸（半圆 + 色底）与 tab 药丸是同一套视觉语言，并排时分不清哪个可点。
---
---排序依据（重要，别随手改）：源码在空间不足时执行
---`while right_status_line.len() > status_space_available { right_status_line.remove_cell(0, …) }`
---—— **从左端按「格」吃，不是按段吃**（所以被截断的那一段会显示成半截：实测
---`21:31:13` 被啃掉首字符变成了 `1:31:13`）。据此**越次要越靠左**，顺序（左 → 右）是：
---  编码 → 时钟 → 计时器 → git
---为什么是这个序：① 编码一致时只有 5 格、信息量最低 → 最先牺牲且能吃干净；
---② 时钟最冗余（任务栏就有）→ 次之；③ 计时器是明确需求；④ git 最不可替代，钉最右。
---**实测空间账**（149 列 + 4 个 tab，1 格 = 17px）：块起点在 x≈88、内容区到 149，
---右端可用 ≈ 62 格 → 本文件的块必须 ≤ 62 格，超出的部分从左边被砍。
---（用 `_m1_cells.py` 按 17px 网格扫 tab bar 行即可复核这个数。）
---
---数据来源分工（别混）：
---  · 时钟   = wezterm.strftime（内置）—— **真正每秒都在动**，本帧现算。
---  · Git    = pane cwd → 向上找 .git → 读 .git/HEAD（**纯文件**，≈1 ms）
---             只取分支名，对齐 oh-my-posh 默认主题的 ` 分支名` 形态。
---  · 编码   = **只能由 shell 上报**（Lua 读不到 pwsh 的控制台代码页）：走
---             OSC 1337 SetUserVar，Lua 侧用 pane:get_user_vars() 读；上报端在 pwsh profile 里。
---  · 内存   = **主通道**：后台采样文件 `~/.wezterm-mem/<pid>.txt` —— shell 的后台线程
---             每秒覆盖写它，**长任务期间照常更新**；路径靠 shell 上报的 term_pid 拼出。
---             **降级通道**：shell 上报的 term_mem（MB，整数），只在命令结束时刷新一次。
---
---⚠️ **「每秒重绘」与「每秒重新采样」是两件事** —— 分属不同进程，**而且每段各不相同**：
---
---  · Lua 侧（本文件）：`update-status` 由 wezterm 每 **1000 ms** 触发一次
---    （config/general.lua 的 status_update_interval = 1000）。各段都**无缓存**，
---    每帧都重新取一次数据。
---  · shell 侧（pwsh profile）：决定**值本身多久变一次**。
---
---于是逐段的真实节奏是：
---
---  | 段   | 值多久变一次        | 说明 |
---  | ---- | ------------------- | ---- |
---  | 时钟 | **每秒**            | `wezterm.strftime` 在 Lua 侧现算，不经过 shell |
---  | 内存 | **每秒**            | 主通道读后台采样文件（shell 的后台线程每秒覆盖写） |
---  | git  | 每秒重读，值少变     | 纯文件读 `.git/HEAD` |
---  | 编码 | **每条命令一次**     | `term_chcp`/`term_enc` 只在 prompt 里上报；值本就几乎不变 |
---
---⇒ 只剩「编码」还受 prompt 的节奏约束，而它恰好是四段里最不需要实时性的一个。
---（非 pwsh 会话没有 `term_pid`/`term_mem`，内存段直接消失。）
---
---历史：内存段在 2026-09-29 之前是「每条命令一次」—— 长任务挂着时数字冻住，用户
---指出这个缺陷后改成现在的后台采样。详见 mem_text 的注释。
---
---⚠️ Git 与编码都**绝不跑子进程**：本机起任何子进程 ≈ 190–600 ms（实测，
---bash 空跑 285ms、git rev-list 600ms、python 900ms），而 update-status 默认
---每秒触发一次（config/general.lua 的 status_update_interval = 1000），
---跑一次就阻塞 GUI 半秒。
---
---⚠️ 由此**放弃**了 oh-my-posh 那套 ↑↓ 提交计数与「+2 ~1」文件统计：
---  算 ahead/behind 必须 `git rev-list --left-right --count HEAD...@{u}`（600ms），
---  算文件数必须 `git status --porcelain`（更慢）。两者都塞不进每秒一帧，
---  除非改成异步 + 缓存（可做，但用户 2026-09-27 明确选了「只显示分支」）。
---  另：WezTerm 内嵌 Lua **没有** lfs / file_stat / mtime 接口（探针实测
---  `require('lfs')` 报 module not found、`wezterm.stat` 为 nil），所以连
---  「靠时间戳猜有无改动」这种纯文件近似都做不了。
local M = {}

---内存段图标。经 `wezterm ls-fonts --text 󰍛` 实测（2026-09-28）：字形 md-memory
---存在，由 JetBrainsMono Nerd Font Mono 提供。
---⚠️ 别照 Nerd Fonts 码位表填 —— 本机字体里有串位（详见下面 GLYPH_GIT 的注释）。
local GLYPH_MEM = nf.md_memory --[[ 󰍛 U+F035B ]]

---git 段图标（对齐 oh-my-posh 默认主题：` 分支图标 + 分支名`）。
---经 `wezterm ls-fonts --text <字>` 实测字形存在（2026-09-27）：
---  · U+E0A0  pl-branch      —— 当前采用（旧 pane 版脚本用的同一个字形）
---  · U+F126  fa-code_fork   —— 备选，fork 造型
---  · U+F418  oct-git_branch —— 备选
---⚠️ **别照 Nerd Fonts 官方码位表填**：本机字体里已有多处串位 —— 实测
---   `md_source_branch`(U+F062C) 正常，但 `md_git`(U+F124F) 解析出来是 md-gold、
---   `md_circle_small`(U+F09DE) 是 md-circle_medium、`md_check_circle`(U+F05E1)
---   是 md-check_circle_outline。⇒ **换图标前必须 ls-fonts 逐字验**，
---   否则会渲染成毫不相干的字形。
local GLYPH_GIT = nf.pl_branch --[[  U+E0A0 ]]

-- LEADER / key table 指示器**不在这里**：它是瞬态提示，放右端会继续挤占右端预算，
-- 所以留在左端（events/left-status.lua）。

---分隔符：`│`（U+2502）。custom_block_glyphs 默认开启 → 这个 Box Drawing 字符由
---WezTerm 按格子尺寸自绘、占满整格高度，正是状态栏分隔符该有的样子。
---颜色用 warp.fg_mute（最不抢眼），让分隔符退到内容后面 —— 旧版用浅青 #74c7ec 太扎眼。
---
---⚠️ **两侧不留空格**（用户 2026-09-29：「把状态栏的全部空格去掉，靠分割线间隔功能」）。
---原写法 `' │ '` 每处白吃 2 格，而分隔符本身已经把两段分开了，空格纯属冗余。
---⇒ 全部布局空格一律去掉，间距**只由分隔符承担**。
---（唯一保留空格的地方是 `chcp 936 / utf-8` 这类**文本内部**的语义空格 ——
--- 去掉会变成 `chcp936/utf-8`，可读性反而更差；那不是布局空格。且该段平时不显示。）
local ICON_SEPARATOR = '│'
local SEP_TEXT = ICON_SEPARATOR

---shell 上报编码用的 user var 名（pwsh profile 里必须同名）
local VAR_CHCP = 'term_chcp' -- 控制台代码页（`chcp` 命令的那个）
local VAR_ENC = 'term_enc' -- [Console]::OutputEncoding.CodePage
local VAR_MEM = 'term_mem' -- 本 pwsh 进程的工作集（MB，纯数字）——**降级通道**，见 mem_text
local VAR_PID = 'term_pid' -- 本 pwsh 的 PID（纯数字），用来定位后台采样文件

---编码段是否「只在异常时出现」。
---true（默认）= 告警灯：一致时整段消失，只有 chcp 与输出编码不一致才跳出来。
---false        = 仪表盘：一致时恒显编码名（旧行为）。
---为什么默认 true：用户 2026-09-27 明确说「utf-8 就这么放在状态栏确实没什么用」——
---一个永远不变的 5 格纯属噪音，而它真正该被看见的是**不一致的那一刻**。
local ALARM_ONLY = true

---完全透明。
---⚠️ 别用 `rgba(0, 0, 0, 0.4)`：tab bar 本身是「半透明壁纸」，垫一块不透明暗底会出现
---肉眼可见的色差，看着像「叠了一层」（这一条在左右两端都踩过）。
local TRANSPARENT = 'rgba(0, 0, 0, 0)'

---色值全部取自 colors/warp.lua 的实测色（改色请回那里对照，别在这里新造色）。
---@type table<string, Cells.SegmentColors>
-- stylua: ignore
local colors = {
   mem       = { fg = '#a5d5fe', bg = TRANSPARENT }, -- warp.blue_br
   enc_ok    = { fg = '#72b9bf', bg = TRANSPARENT }, -- warp.cyan
   enc_warn  = { fg = '#e09c18', bg = TRANSPARENT }, -- warp.yellow_br（chcp 与输出编码不一致 = GBK 老坑）
   git       = { fg = '#99bf52', bg = TRANSPARENT }, -- warp.green
   date      = { fg = '#aca4a0', bg = TRANSPARENT }, -- warp.fg_dim（次要信息，退到后面）
   separator = { fg = '#6c6c6c', bg = TRANSPARENT }, -- warp.fg_mute
}

---粗体只给「内容」，不给分隔符 —— 分隔符加粗会变成一道实心竖条。
local BOLD = attr(attr.intensity('Bold'))

local cells = Cells:new()

---段的定义顺序 = 屏幕上的出现顺序（下面 SEGMENT_ORDER 再显式钉死一次，因为
---render_all() 内部走 pairs，字符串 id 的顺序不保证）。
---分隔符（sep_*）单独占一段：它的颜色必须独立（muted），不能跟着相邻内容染色。
cells
   :add_segment('enc', '', colors.enc_ok, BOLD)
   :add_segment('sep_e', '', colors.separator)
   :add_segment('date', '', colors.date)
   :add_segment('sep_d', '', colors.separator)
   :add_segment('mem', '', colors.mem, BOLD)
   :add_segment('sep_t', '', colors.separator)
   :add_segment('git', '', colors.git, BOLD)

---@type string[]
local SEGMENT_ORDER = {
   'enc',
   'sep_e',
   'date',
   'sep_d',
   'mem',
   'sep_t',
   'git',
}

---每个「内容段」之后跟的分隔符。分隔符只在**它两侧的段都存在**时出现，
---否则会留下一个孤零零的 `│`（例如不在 git 仓库里时）。
---@type table<string, string>
local SEP_AFTER = {
   enc = 'sep_e',
   date = 'sep_d',
   mem = 'sep_t',
}

---@type string[]
local SEPARATOR_IDS = { 'sep_e', 'sep_d', 'sep_t' }

---@type string[]
local BODY_IDS = { 'enc', 'date', 'mem', 'git' }

---代码页 → 常见编码名，用于把 65001 显示成 utf-8。
---@type table<number, string>
local CP_NAME = {
   [437] = 'cp437',
   [932] = 'shift-jis',
   [936] = 'gbk',
   [950] = 'big5',
   [1252] = 'cp1252',
   [54936] = 'gb18030',
   [65001] = 'utf-8',
}

local B64_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

---base64 → 明文字符串。
---WezTerm 的 SetUserVar 值走 base64 传输，Lua 侧需要还原。
---@param str string
---@return string
local function b64_decode(str)
   local out, buf, bits = {}, 0, 0
   for i = 1, #str do
      local c = str:sub(i, i)
      if c == '=' then
         break
      end
      local idx = B64_ALPHABET:find(c, 1, true)
      if idx then
         buf = buf * 64 + (idx - 1)
         bits = bits + 6
         if bits >= 8 then
            bits = bits - 8
            out[#out + 1] = string.char(math.floor(buf / 2 ^ bits) % 256)
         end
      end
   end
   return table.concat(out)
end

---读 shell 上报的 user var。
---
---两种形态都收：wezterm 可能自行 base64 解码后再放进 user_vars，也可能原样保留。
---判据用「是否纯数字」—— 本模块上报的两个值**约定为纯数字代码页**，
---所以纯数字就是已解码，否则按 base64 再解一次（解不出来就退回原值）。
---之所以不做通用判据：base64 的字母表是 [A-Za-z0-9+/]，与短标识串无法区分
---（"OTM2" 与 "936" 都是合法形态），只有靠「约定纯数字」这条才行得通。
---@param pane Pane
---@param name string
---@return string|nil
local function read_user_var(pane, name)
   local vars = pane:get_user_vars()
   local raw = vars and vars[name]
   if not raw or raw == '' then
      return nil
   end
   if raw:match('^%d+$') then
      return raw
   end
   local decoded = b64_decode(raw)
   if decoded:match('^%d+$') then
      return decoded
   end
   return nil
end

---数值 → 显示文本。数值与单位**不留空格**（`171MB` / `1.5GB`）——
---用户 2026-09-28 明确要求：「数字和MB之间不需要空格」，空间宝贵且单位无歧义。
---@param mb number
---@return string
local function fmt_mb(mb)
   if mb >= 1024 then
      return string.format('%.1fGB', mb / 1024)
   end
   return mb .. 'MB'
end

---上一次成功读到的 (pid, 文本)，只用于「恰好读到写入中的文件」时兜底。
---⚠️ 键用 pid 而不是 pane_id：pid 天然 per-pane 且唯一，pid 一变缓存自动失效，
---省掉一张要自己维护的 map。
local mem_last_pid, mem_last_text = nil, nil

---从后台采样文件读内存值（MB）。读不到返回 nil。
---@param pid string
---@return number|nil
local function read_mem_file(pid)
   -- 路径必须与 pwsh profile 里写的完全一致：$HOME\.wezterm-mem\<pid>.txt
   -- 本机 home_dir 含中文，实测 io.open 正常（探针 _probe_io.lua：读回内容一致）。
   local path = wezterm.home_dir .. '/.wezterm-mem/' .. pid .. '.txt'
   local ok, f = pcall(io.open, path, 'r')
   if not ok or not f then
      return nil
   end
   local raw = f:read('*a')
   f:close()
   return tonumber(raw or '')
end

---内存文本：本 pwsh 进程的工作集。
---
---**两个数据源，按优先级取**：
---  ① 后台采样文件 `~/.wezterm-mem/<pid>.txt` —— 由 pwsh 的后台线程
---     （profile 里的 Start-ThreadJob）**每秒**覆盖写入。**主通道**。
---  ② `term_mem` user var —— shell 每次 prompt 上报一次。**降级通道**，
---     只在后台 job 起不来时兜底。
---
---为什么必须有 ①（用户 2026-09-29 指出的缺陷）：只用 ② 的话，值只在**命令跑完**时
---刷新一次 —— 跑 10 分钟的任务，这 10 分钟里状态栏显示的都是「命令开始之前」的旧值，
---恰恰看不到最该看的那段过程。而 ① 的后台线程在**主 runspace 被长命令占住期间照常跑**
---（探针实测：阻塞 6 s 期间 job 仍为 Running，采样推进 8 个点）。
---
---为什么是「shell 上报」而不是 WezTerm 自己读：WezTerm 内嵌 Lua **没有**任何
---系统状态接口 —— 探针实测 `global.sys` / `global.psutil` / `global.proc` 全为 nil，
---只有 battery_info / hostname / target_triple 这类零散能力。所以动态数值一律
---得由 shell 推过来，编码段也是同一个套路。
---
---⚠️ 读文件（io.open）**不违反**「回调里不跑子进程」那条铁律：几微秒的文件 IO，
---不像起子进程要 190–600 ms。但**别**在这里加 `run_child_process`。
---
---未上报时返回 nil（整段消失）—— 非 pwsh 会话（bash、SSH）本来就没有这个值，
---显示一个编造的 0 比不显示更糟。
---@param pane Pane
---@return string|nil
local function mem_text(pane)
   local pid = read_user_var(pane, VAR_PID)
   if pid then
      local mb = read_mem_file(pid)
      if mb then
         local txt = fmt_mb(mb)
         mem_last_pid, mem_last_text = pid, txt
         return txt
      end
      -- 极少数情况：恰好读到写入中的文件。profile 侧已经用 write-then-rename
      -- 保证原子性，这里是二重保险 —— 沿用上一帧的值，免得段闪一下。
      if mem_last_pid == pid then
         return mem_last_text
      end
   end

   -- 降级：shell 每次 prompt 上报的那个值
   local mb = tonumber(read_user_var(pane, VAR_MEM))
   if mb then
      return fmt_mb(mb)
   end
   return nil
end

---编码文本 —— **只在出问题时才返回内容**（2026-09-27 用户反馈「utf-8 放状态栏没什么用」后改）。
---
---设计依据：编码一致是**常态**，此时恒显 `utf-8` 等于零信息量，白占 5–8 格。
---它真正有价值的那一刻是**两个编码不一致**（= 本机 GBK 老坑的根源）——那时必须看见。
---⇒ 做成「告警灯」而不是「仪表盘」：
---     一致 / 无上报  → 返回 nil，整段消失（右端立省 8 格）
---     不一致（隐患）  → 橙色 `chcp 936 / utf-8`
---想回到「常显编码名」的旧行为：把 ALARM_ONLY 设成 false。
---@param pane Pane
---@return string|nil text
---@return boolean warn
local function encoding_text(pane)
   local chcp = read_user_var(pane, VAR_CHCP)
   local enc = read_user_var(pane, VAR_ENC)

   if not chcp and not enc then
      return nil, false
   end

   -- 一致（正常情况）：默认整段消失；ALARM_ONLY=false 时退回「只说编码名」
   if chcp and enc and chcp == enc then
      if ALARM_ONLY then
         return nil, false
      end
      return CP_NAME[tonumber(enc)] or ('cp' .. enc), false
   end

   -- 不一致（隐患）：两个值都摊开
   local enc_name = enc and (CP_NAME[tonumber(enc)] or ('cp' .. enc)) or '?'
   return string.format('chcp %s / %s', chcp or '?', enc_name), true
end

---把 pane 的 cwd 转成本机 Windows 路径。
---
---pane:get_current_working_dir() 返回一个 Url 对象，其 file_path 通常已解码；
---拿不到时退回解析 tostring(url)（形如 file://HOST/C:/Users/…）。OSC 7 的路径段是
---percent-encoded UTF-8（本机用户名含中文，必现 %E9%A9%AC 之类），所以要做解码，
---并且必须**逐字节**还原 —— 用 %XX 拼成字节序列才是合法 UTF-8 字符串。
---@param pane Pane
---@return string|nil
local function pane_cwd(pane)
   local ok, uri = pcall(function()
      return pane:get_current_working_dir()
   end)
   if not ok or not uri then
      return nil
   end

   local path = uri.file_path
   if type(path) ~= 'string' or path == '' then
      local s = tostring(uri)
      path = s:match('^file://[^/]*(/.*)$')
      if not path then
         return nil
      end
      path = path:gsub('%%(%x%x)', function(h)
         return string.char(tonumber(h, 16))
      end)
   end

   path = path:gsub('^\\\\%?\\', '') -- 去掉 \\?\ 长路径前缀（若 Url 已带）
   path = path:gsub('^/([A-Za-z]:)', '%1') -- /C:/x -> C:/x
   path = path:gsub('/', '\\') -- C:/x -> C:\x
   return path
end

---读 .git/HEAD，返回分支名（detached 时给短 hash）。
---@param head_path string
---@return string|nil
local function read_head(head_path)
   local f = io.open(head_path, 'r')
   if not f then
      return nil
   end
   local content = f:read('*a')
   f:close()
   content = content:gsub('[\r\n]+$', '')

   local branch = content:match('^ref:%s*refs/heads/(.+)$')
   if branch then
      return branch
   end
   local hash = content:match('^(%x%x%x%x%x%x%x)')
   if hash then
      return hash .. ' detached'
   end
   return nil
end

---从 start 目录向上找 git 仓库，返回当前分支。
---.git 有两种形态，都要处理（技能里踩过）：
---  · 目录 → 普通仓库，读 <root>/.git/HEAD
---  · 文件 → worktree / submodule，内容是 `gitdir: <实际路径>`，去那里读 HEAD
---
---⚠️ 只返回**分支名**，不返回仓库名、也不返回路径 —— 用户明确要 oh-my-posh
---那种「只有分支」的样式（2026-09-27：「Git仓库只显示分支」「这个不做了，
---只显示分支」）。宽度上也更省。
---@param start string|nil
---@return string|nil branch
local function git_branch(start)
   if not start or start == '' then
      return nil
   end

   local dir = start
   for _ = 1, 40 do
      local git = dir .. '\\.git'

      local head = read_head(git .. '\\HEAD') -- ① .git 是目录
      if head then
         return head
      end

      local g = io.open(git, 'r') -- ② .git 是文件（worktree / submodule）
      if g then
         local content = g:read('*a')
         g:close()
         local gitdir = content:match('gitdir:%s*(.-)%s*$')
         if gitdir then
            -- gitdir 可能是相对 worktree 的路径（形如 ../.git/worktrees/foo）
            if not gitdir:match('^%a:') and not gitdir:match('^%\\') then
               gitdir = dir .. '\\' .. gitdir
            end
            head = read_head(gitdir .. '\\HEAD')
            if head then
               return head
            end
         end
         break
      end

      local parent = dir:match('^(.*)\\[^\\]+$')
      if not parent or parent == dir then
         break
      end
      dir = parent
   end

   return nil
end

---按窗口缓存的 git 信息。
---缓存 key 是 cwd：只有 cwd 变了才重新做「向上找 .git + 读 HEAD」这一步。
---按 window_id 分开存 —— 多窗口 cwd 不同，共用一个槽位会每次都被冲刷、缓存失效。
---@type table<number, { cwd: string|nil, repo: string|nil, branch: string|nil, gitdir: string|nil }>
local git_cache = {}

---@param window Window
---@param pane Pane
---@return string|nil branch
local function cached_git(window, pane)
   local id = window:window_id()
   local slot = git_cache[id]
   local cwd = pane_cwd(pane)

   if not slot or slot.cwd ~= cwd then
      local branch = git_branch(cwd)
      slot = { cwd = cwd, branch = branch }
      git_cache[id] = slot
   end

   return slot.branch
end

---@param opts? Event.RightStatusOptionsInput Default: {date_format = '%a %H:%M:%S'}
M.setup = function(opts)
   local valid_opts, err = EVENT_OPTS:validate(opts or {})

   if err then
      wezterm.log_error(err)
   end

   ---@cast valid_opts Event.RightStatusOptions

   wezterm.on('update-status', function(window, pane)
      ---@type { id: string, text: string, colors: Cells.SegmentColors }[]
      local shown = {}

      -- ⚠️ 收集顺序必须 = SEGMENT_ORDER（屏幕顺序），因为下面用
      -- `shown[i + 1]` 判断「分隔符两侧是否都存在」。顺序 = 左 → 右 = 次要 → 重要：
      -- 空间不足时源码从左端按格吃，故最先被牺牲的是编码、最后是 git。

      -- ① 字符集编码（shell 上报；未上报时整段消失）
      local enc_text, enc_warn = encoding_text(pane)
      if enc_text then
         shown[#shown + 1] = {
            id = 'enc',
            text = enc_text,
            colors = enc_warn and colors.enc_warn or colors.enc_ok,
         }
      end

      -- ② 时钟
      shown[#shown + 1] = {
         id = 'date',
         text = wezterm.strftime(valid_opts.date_format),
         colors = colors.date,
      }

      -- ③ 内存（shell 上报；未上报时整段消失 —— 和编码段同一个套路，
      --    非 pwsh 会话不该显示一个编造出来的数字）
      -- 图标与数字之间**不留空格**：用户 2026-09-29 要求「把状态栏的全部空格去掉，
      -- 靠分割线间隔功能」。MDI 图标（U+F035B）字形本身在字框内左右留白，视觉上已隔开。
      local mem = mem_text(pane)
      if mem then
         shown[#shown + 1] = { id = 'mem', text = GLYPH_MEM .. mem, colors = colors.mem }
      end

      -- ④ Git 分支（非仓库目录时整段消失；钉在最右端 —— 最不该丢的一条）
      -- 样式对齐 oh-my-posh 默认主题：` 分支图标 分支名`。不带仓库名、不带计数 ——
      -- 用户明确要求（2026-09-27：「Git仓库只显示分支」「只显示分支」）；
      -- 计数做不了也不做：算 ahead/behind 必须跑 `git rev-list`，而本机起子进程
      -- 要 190–600ms，塞进每秒一次的 update-status 会直接卡住界面。
      local branch = cached_git(window, pane)
      if branch then
         shown[#shown + 1] = {
            id = 'git',
            text = GLYPH_GIT .. branch, -- 图标与分支名之间不留空格（同上）
            colors = colors.git,
         }
      end

      -- ⚠️ 这里**曾经**给两端各留 1 格（头部与左侧内容隔开、尾部不贴窗口右沿）。
      -- 用户 2026-09-29 明确要求去掉：「把状态栏的全部空格去掉，靠分割线间隔功能」。
      -- ⇒ 现在块内**一个填充空格都没有**，间距全部由 `│` 承担，块紧贴窗口右沿。
      --   （保留的只有 chcp 那段的文本内部空格，且那段平时不显示。）

      -- 清场：分隔符全清，内容段里本帧未出现的也清（否则会残留上一帧的文本）。
      for _, id in ipairs(SEPARATOR_IDS) do
         cells:update_segment_text(id, '')
      end

      local seen = {}
      for i, part in ipairs(shown) do
         cells:update_segment_text(part.id, part.text)
         cells:update_segment_colors(part.id, part.colors)
         seen[part.id] = true

         local sep = SEP_AFTER[part.id]
         if sep and shown[i + 1] then
            cells:update_segment_text(sep, SEP_TEXT)
         end
      end

      for _, id in ipairs(BODY_IDS) do
         if not seen[id] then
            cells:update_segment_text(id, '')
         end
      end

      -- 必须用 render(ids) 而不是 render_all()：段 id 是字符串，
      -- render_all 内部走 pairs，顺序不确定，段会被打乱。
      window:set_right_status(wezterm.format(cells:render(SEGMENT_ORDER)))
   end)
end

return M

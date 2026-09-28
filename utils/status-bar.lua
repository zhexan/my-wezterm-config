local wezterm = require('wezterm')
local act = wezterm.action

---底部状态栏（1 行高 pane，跑 scripts/status-bar.ps1）的共享启动/开关逻辑。
---供 config/bindings.lua（键位）与 events/gui-startup.lua（启动自动挂载）复用，
---避免 SplitPane 的构造参数与挂载时序散落多份。
local M = {}

---状态栏底条色（VSCode 式实心色带）。
---为什么颜色放在这里而不是 colors/warp.lua：colorscheme 是 wezterm 的固定 schema，
---往里塞自定义键不保证被忽略（可能整份配色被拒）。所以由本模块持有，
---再作为命令行参数交给渲染脚本 —— 只有这一处定义，不存在两处硬编码漂移。
---想换状态栏配色就改这一行；改成空串则回落成"无底色"的旧样式。
M.BG = '#26262b'

---@return string 状态栏脚本的绝对路径
function M.script_path()
   return wezterm.config_dir .. '/scripts/status-bar.ps1'
end

---状态栏 pane 的身份标记。scripts/status-bar.ps1 启动时会发
---`OSC 1337 SetUserVar=term_statusbar=1`，Lua 侧靠它认出「哪个 pane 是状态栏」。
---
---为什么用标记而不是「1 行高的那个」：mux 的 pane 对象**不暴露尺寸**（探针实测
---`get_dimensions` 在 mux pane 上是 nil），尺寸判据在 Lua 里根本用不了。
---user_vars 是脚本能自报、Lua 又能读到的唯一字段。
local MARKER = 'term_statusbar'

---已知的状态栏 pane：tab_id -> pane_id。
---
---为什么有了 user_vars 标记还要在 Lua 侧再记一份：脚本要等 pwsh 起来（约 0.5–1s）
---才发出标记。在这段空窗期里，标记扫描找不到「刚切出来、还没自报」的状态栏，
---于是再按一次 LEADER+b 会**又切一条**（2026-09-27 自测复现：t0 时 pane 已存在
---但 find() 返回 nil，第 1 次 toggle 就多切了一条，tab 里出现两条状态栏）。
---Lua 侧在「切分的那一刻」就把新 pane 记下来，就没有这个空窗期。
---
---记账只活在本进程的 Lua 状态里；配置重载会清空它 —— 所以 find() 里保留了
---标记扫描作为兜底，两种途径互补。
local tracked = {}

---取 window 的 MuxWindow（兼容传入 gui Window 的场合）。
---@param window Window|MuxWindow
---@return MuxWindow|nil
local function mux_window_of(window)
   if window.mux_window then
      local ok, mw = pcall(function()
         return window:mux_window()
      end)
      if ok and mw then
         return mw
      end
   end
   return window -- MuxWindow 本身也有 active_tab()
end

---@param window Window|MuxWindow
---@return MuxTab|nil
local function current_tab(window)
   local mw = mux_window_of(window)
   return mw and mw:active_tab()
end

---在 tab 里按 pane_id 找 pane。
---@param tab MuxTab
---@param id number
---@return MuxPane|nil
local function pane_by_id(tab, id)
   for _, p in ipairs(tab:panes()) do
      if p:pane_id() == id then
         return p
      end
   end
   return nil
end

---找当前 tab 里的状态栏 pane（没有则 nil）。
---@param window Window|MuxWindow
---@return MuxPane|nil
local function find_status_bar(window)
   local tab = current_tab(window)
   if not tab then
      return nil
   end
   local key = tab:tab_id()

   -- ① Lua 侧记账（无空窗期，优先）
   local id = tracked[key]
   if id then
      local p = pane_by_id(tab, id)
      if p then
         return p
      end
      -- 记账的 pane 已不在（被手工关掉、或切到别的 tab 了）：清账，落到 ②
      tracked[key] = nil
   end

   -- ② 脚本自报的标记（兜底：配置重载清空了 Lua 记账，但 pane 还活着）
   for _, p in ipairs(tab:panes()) do
      local uv = p:get_user_vars()
      local v = uv and uv[MARKER]
      -- 值可能是解码后的 '1'，也可能是原始 base64（看 wezterm 是否自行解码），两种都收
      if v == '1' or v == 'MQ==' then
         tracked[key] = p:pane_id()
         return p
      end
   end
   return nil
end

---找当前 tab 里的状态栏 pane，没有则返回 nil。
---toggle 用它判断「开还是关」；自测脚本也用它核对每一阶段的实际结果。
---@param window Window|MuxWindow
---@return MuxPane|nil
function M.find(window)
   return find_status_bar(window)
end

---在当前 tab 切出状态栏，并在 Lua 侧记账，最后把焦点还给切分前的活动 pane。
---
---认领新 pane 用「切分前后 diff」而不是「看谁变成活动 pane」：不依赖活动 pane 语义，
---只依赖一点 —— SplitPane 对 mux 是同步生效的（自测确认 perform_action 返回后
---tab:panes() 立刻包含新 pane）。
---@param window Window|MuxWindow
---@param pane Pane 切分目标/参考 pane
local function open_status_bar(window, pane)
   local tab = current_tab(window)
   local before = {}
   local prev_active = tab and tab:active_pane()
   if tab then
      for _, p in ipairs(tab:panes()) do
         before[p:pane_id()] = true
      end
   end

   window:perform_action(M.split_action(), pane)

   local tab2 = current_tab(window)
   if not tab2 then
      return
   end
   for _, p in ipairs(tab2:panes()) do
      local pid = p:pane_id()
      if not before[pid] then
         tracked[tab2:tab_id()] = pid
         break
      end
   end

   -- 状态栏是纯展示 pane（脚本不读 stdin、光标也藏着），不该抢焦点：
   -- SplitPane 默认会把新 pane 设为活动 pane，不还回去的话，启动后敲键盘是敲给
   -- 状态栏的 —— 什么都不显示，像是键盘坏了。所以把焦点还给切分前的活动 pane。
   if prev_active and pane_by_id(tab2, prev_active:pane_id()) then
      pcall(function()
         prev_active:activate()
      end)
   end
end

---公开入口，自测脚本用。
---@param window Window|MuxWindow
---@param pane Pane
function M.open(window, pane)
   open_status_bar(window, pane)
end

---wezterm 主程序（支持 cli 子命令的那个）的绝对路径，拿不到则 nil。
---`executable_dir` 是字符串常量（不是函数），本机实测 = `C:\Program Files\WezTerm`。
---@return string|nil
local function wezterm_exe()
   local dir = wezterm.executable_dir
   if type(dir) == 'function' then
      local ok, v = pcall(dir)
      dir = ok and v or nil
   end
   if type(dir) ~= 'string' or dir == '' then
      return nil
   end
   if wezterm.target_triple:find('windows') then
      return dir .. '\\wezterm.exe'
   end
   return dir .. '/wezterm'
end

---关掉指定的状态栏 pane。
---
---实现走 `wezterm cli kill-pane --pane-id N`，而不是 Lua 侧的动作。原因（都是实测，别再踩）：
---
---1) 给状态栏发 Ctrl+C（`pane:send_text(string.char(3))`）在本机**关不掉**。
---   原因在配置里：`exit_behavior = 'CloseOnCleanExit'`（见 config/general.lua）——
---   只有**干净退出（exit code 0）**才回收 pane。Ctrl+C 打断 pwsh 是非零退出，
---   pane 会被原地留一具"尸体"（自测：发完 Ctrl+C，2s 后 tab 仍是 [0,1,2]，pane 1 还在）。
---
---2) `window:perform_action(act.CloseCurrentPane, 目标pane)` **根本传不进去**：
---   perform_action 的第 2 个参数只接受「事件回调给你的那个 pane 对象」，
---   而 mux 的 pane（tab:panes() 拿到的）转不过去，直接报
---   `bad argument #2 to GuiWin.perform_action: error converting Lua userdata to
---   config::keyassignment::KeyAssignment`。
---   早先那版之所以"没报错"，是因为它干脆只作用于「当前活动 pane」——
---   实测传状态栏 pane 1 进去，被关掉的却是主 pane 0（t1 panes=[0,1,2] -> t2 panes=[1,2]）。
---
---   也就是说 CloseCurrentPane 认的是「活动 pane」而非传入的 pane，作为开关是危险的。
---
---3) CLI 方案为什么可靠：`kill-pane --pane-id N` 的语义就是「关掉这个 pane」，
---   不碰焦点、不看谁是活动 pane；而且它连的是 GUI 自己的 mux（WEZTERM_UNIX_SOCKET
---   实测在 GUI 进程环境里有值，子进程会继承），所以不会连错实例。
---   `--no-auto-start` 保证连不上时直接报错，而不是偷偷拉起一个 mux server。
---@param window Window|MuxWindow
---@param target MuxPane
local function close_status_bar(window, target)
   local tab = current_tab(window)
   if tab then
      tracked[tab:tab_id()] = nil
   end

   local exe = wezterm_exe()
   if not exe then
      wezterm.log_error('status-bar: 找不到 wezterm 主程序，无法关闭状态栏 pane')
      return
   end

   local ok, err = pcall(wezterm.background_child_process, {
      exe,
      'cli',
      '--no-auto-start',
      'kill-pane',
      '--pane-id',
      tostring(target:pane_id()),
   })
   if not ok then
      wezterm.log_error('status-bar: kill-pane 启动失败: ' .. tostring(err))
   end
end

---LEADER+b 的开关语义：已经有状态栏就关掉，没有就开一条。
---@param window Window
---@param pane Pane
function M.toggle(window, pane)
   local existing = find_status_bar(window)
   if existing then
      close_status_bar(window, existing)
      return
   end
   open_status_bar(window, pane)
end

---构造「在 tab 底部切出 1 行高状态栏 pane」的动作。
---注意：当前 wezterm（20260716-195552）的 SplitPane 不接受 domain 字段
---（只认 command/direction/size/top_level），新 pane 跟随被切分 pane 所在的域。
---因此状态栏（Windows 侧 pwsh 脚本）只在 DefaultDomain 的 tab 里可用；
---WSL 域 tab 不挂状态栏（见 config/bindings.lua 对应键位的注释）。
---@return Action
function M.split_action()
   return act.SplitPane({
      direction = 'Down',
      size = { Cells = 1 },
      top_level = true,
      command = {
         args = {
            'pwsh',
            '-NoLogo',
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            M.script_path(),
            -- 状态栏底条色。脚本收到后铺满整行（VSCode 式实心带）。
            '-BgRgb',
            M.BG,
         },
      },
   })
end

---新 tab 自动挂载：在 SpawnTab 之后立刻调用。
---先 sleep 让 SpawnTab 的 mux 往返完成（与 utils/layouts.lua 同一套时序模式），
---再显式取「当前活动 tab 的活动 pane」作为切分目标 —— 避免 SplitPane 对
---「传入 pane 还是活动 pane」的解释差异把状态栏切进旧 tab。
---@param window Window
---@param pane Pane
function M.attach_to_new_tab(window, pane)
   wezterm.sleep_ms(200)

   local tab = current_tab(window)
   local target = tab and tab:active_pane()
   if not target or target:pane_id() == pane:pane_id() then
      -- 新 tab 还没就绪（罕见）：放弃本次自动挂载，用 LEADER+b 手动补
      return
   end

   open_status_bar(window, target)
end

---首个窗口自动挂载：gui-startup 里调用。
---延迟一小段再切：等窗口首次 resize/maximize 落定，否则 1 行 pane 会被
---那次 resize 按比例放大（上游 wez/wezterm#6378，脚本内有自愈兜底）。
---@param window MuxWindow
---@param pane MuxPane
function M.attach_to_window(window, pane)
   local gui_window = window:gui_window()
   wezterm.time.call_after(0.2, function()
      open_status_bar(gui_window, pane)
   end)
end

return M

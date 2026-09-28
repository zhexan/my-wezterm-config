#Requires -Version 7.0
<#
.SYNOPSIS
    WezTerm 底部状态栏 —— 跑在 1 行高的 pane 里。

.DESCRIPTION
    由 wezterm 键位拉起，命令形如（见 config/bindings.lua）：

        SplitPane { direction='Down', size={Cells=1}, top_level=true,
                    command={ args={'pwsh','-NoLogo','-NoProfile','-File','...\status-bar.ps1'} } }

    pane 内常驻循环，每秒重绘第一行，显示：

      · Git 仓库    同 tab 内「活动 pane」的工作目录所属仓库与分支
      · 字符集编码  控制台代码页(chcp) + 本进程输出编码，两者不一致时标黄
      · 会话计时器  本状态栏进程已存活的时长（右侧，仅此一项）

    八个设计要点：

    1. 配色不硬编码 RGB，使用 256 色索引（38;5;N / 48;5;N）。
       索引 0-7 映射到配色方案的 ansi[]，8-15 映射到 brights[]，
       所以换主题时状态栏自动跟随，不需要改脚本。

    2. 编码显示的是「本 pane 启动时的代码页」，它等于系统默认代码页
       （中文 Windows 通常是 936），也是主 pane 默认的编码。
       跨 conpty 读另一个会话的代码页没有通道，故不做假装。

    3. 【Git 那段的前提】仓库信息来自「同 tab 活动 pane 的 cwd」，而这个 cwd
       只有在目标壳发过 OSC 7 时才可信 —— WezTerm 不跟踪进程目录，只认 OSC 7
       （2026-09-27 实测：壳里 `Set-Location C:\Windows` 后 pane 的 cwd 5 秒内
       纹丝不动；发一条 OSC 7 指向 C:/Program Files，pane 的 cwd 立刻变成它）。
       pwsh 侧已在 profile 的 prompt 包装层里发（Get-Osc7Url），
       其它壳（bash/wsl…）不发就仍会显示 no repo —— 这是已知边界，不是 bug。
       另：**已经在跑的旧会话**不会补发，得新开一个 pane 才生效。

    4. 【身份标记】启动时发一条 OSC 1337 SetUserVar=term_statusbar=1，
       让 Lua 能认出这个 pane。LEADER+b 的「再按一次关掉」靠它定位目标
       （mux 的 pane 对象没有尺寸字段，无法用「1 行高」来认）。
       见 utils/status-bar.lua 的 MARKER 与 find_status_bar。

    5. 本 pane 只占 1 行，且这就是 pane 的物理下限 —— pane 高度只能是 cell 的整数倍。
       实测本机 cell 为 17 × 37 px（font_size 14，dpi 144 = 150% 缩放），
       所以状态栏高度恒为 37px。想更矮只能动 font_size / line_height（全局字号，不划算）。
       另注意 config/appearance.lua 里 window_padding.bottom 必须是 0：
       留 7.5px 会在本行下面垫一圈同色空白，把状态栏连同留白一起撑厚。

    6. 【上下两处空白，来源完全不同，别混为一谈】
       2026-09-27 用 1:1 物理像素抓屏（Python + ctypes 声明 DPI 感知）+ 逐行平均色扫描实测：

       · 上方 17px —— 来自 wezterm 给 split 预留的**整 1 格分隔格**（37px）。
         分隔线画在这格正中（线上 18px / 线下 16px），线下那 16px + 本格顶的 1px = 17px。
         这格没有配置项能去掉。缩 font_size / line_height 只会连带等比缩小
         （缝 ≈ 格高 × 46%），永远不为 0 —— 因为分隔格的格数不变，缩的只是格高。
         想让它"消失"只有一条路：把那条线设成全透明（见 colors/warp.lua 的 split）。
       · 下方 ≈25px —— 是**网格余数**：客户区高度减去 tabbar / 内边距后不是 cell 的整数倍，
         余数落在网格下方。它随窗口高度在 0..36px 之间浮动（这正是"小窗口小、大窗口大"的原因）。
         window_padding.bottom 是固定像素，管不到余数。

    7. 底色：由 utils/status-bar.lua 的 M.BG 经 -BgRgb 传进来，铺满整行，做出 VSCode 那种实心色带。
       关键一步是"先设底色再清行"：ESC[2K 是用**当前**背景色清整行的，顺序反了就白铺。
       另一个坑：分段**不能**用 ESC[0m 结尾 —— 那会把底色一并清掉，只剩第一段有色。
       所以段尾一律用 ESC[39m（只重置前景色），ESC[0m 只留在整帧收尾。

    8. 【重要】WezTerm 会在窗口 resize 时按比例重算 pane 尺寸，SplitPane 的
       size = { Cells = 1 } 只保证创建那一刻是 1 行，之后会累积漂移
       （实测 1 → 6 → 1 → 6 → 3 行；上游已知问题 wez/wezterm#6378，官方判为不修）。
       多出来的行是空白，视觉上就是「底部一块大空区域」。
       本脚本因此自带高度自愈：发现行数 > 1 就调 wezterm cli adjust-pane-size 缩回去，
       方向猜反时会自动翻转一次（见 Repair-PaneHeight）。

.NOTES
    作者: zhexan
#>
[CmdletBinding()]
param(
    # 重绘间隔（毫秒）。计时器走秒，1000 足够。
    [int]$IntervalMs = 1000,

    # 查询活动 pane 工作目录的间隔（毫秒）。
    # 这一步要起一个 wezterm 子进程（本机实测约 200ms），别设太小。
    [int]$ProbeIntervalMs = 2000,

    # 只渲染一帧然后退出。自测用，正常运行时不要加。
    [switch]$Once,

    # 状态栏底条色，形如 #rrggbb。由 utils/status-bar.lua 的 M.BG 传入
    # （单一来源，脚本不硬编码配色）。传空串 = 不铺底色。
    [string]$BgRgb = '#26262b'
)

# 由 utils/status-bar.lua 的 M.BG 传入（单一来源，脚本不硬编码配色）。
# 解析失败或传空串 = 不铺底色，回落成"浮在背景上的一行字"。

# 状态栏不该因为一次读文件/调命令失败就整个挂掉，用宽松模式。
$ErrorActionPreference = 'Continue'

# ── 终端原生调用 ────────────────────────────────────────────────
# 用 P/Invoke 读写控制台代码页，避免每次起 chcp.exe 子进程（本机实测约 200ms）。
if (-not ('Wb.K32' -as [type])) {
    Add-Type -Namespace Wb -Name K32 -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern uint GetConsoleOutputCP();
[DllImport("kernel32.dll")] public static extern bool SetConsoleOutputCP(uint wCodePageID);
'@
}

# 必须在切成 UTF-8 之前读 —— 这个值就是本终端实例的启动代码页。
$script:OrigCodePage = [Wb.K32]::GetConsoleOutputCP()

# 本 pane 自己强制 UTF-8。否则 Nerd Font 图标和中文会乱码，
# 这一点与本机 pwsh profile 的做法一致（$OutputEncoding = utf-8）。
[void][Wb.K32]::SetConsoleOutputCP(65001)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

# ── ANSI 片段（全部走 256 色索引，跟随主题）─────────────────────
$ESC = [char]27
$script:C = @{
    # 全重置：底色 + 前景 + 属性一起清。**只用于整帧收尾**。
    Reset   = "$ESC[0m"
    # 只重置前景色、保住底色 —— 段尾一律用这个（理由见文件头第 6 条）。
    FgReset = "$ESC[39m"
    Mute   = "$ESC[38;5;8m"    # bright black -> warp.fg_mute   #6c6c6c
    Text   = "$ESC[38;5;7m"    # white        -> warp.fg_dim    #aca4a0
    Bright = "$ESC[38;5;15m"   # bright white -> warp.fg        #f8f8f4
    Blue   = "$ESC[38;5;12m"   # bright blue  -> warp.blue_br   #a5d5fe
    Green  = "$ESC[38;5;10m"   # bright green -> warp.green_br  #b4fa72
    Warn   = "$ESC[38;5;11m"   # bright yellow-> warp.yellow_br #e09c18
    Red    = "$ESC[38;5;9m"    # bright red   -> warp.red_bright #d84c40
    # 底条色（truecolor）。空串 = 不铺。
    Bg     = ''
}
$C = $script:C

# #rrggbb -> ESC[48;2;r;g;bm
# 用真彩色而非 256 索引：底条色是"非主题"的 UI 色 ——
# 索引 0-15 会被配色方案的 ansi/brights 改写，16-255 又固定在 xterm 色板上、
# 与 warp 色系对不齐，两头都不合适。
if ($BgRgb -match '^#?([0-9a-fA-F]{6})$') {
    $hx = $Matches[1]
    $r = [Convert]::ToInt32($hx.Substring(0, 2), 16)
    $g = [Convert]::ToInt32($hx.Substring(2, 2), 16)
    $b = [Convert]::ToInt32($hx.Substring(4, 2), 16)
    # 坑：写成 "$b m" 里的 $bm 会被 PowerShell 当成变量名 $bm（未定义→空串），
    # 结果是 ESC[48;2;38;38; 直接断掉、底色彻底失效。必须用 ${b} 界定变量边界。
    $script:C.Bg = "$ESC[48;2;${r};${g};${b}m"
    $C = $script:C
}

# ── Nerd Font 图标（字体 JetBrainsMono NFM，已确认支持）──────────
$ICON_TIMER = [char]0xf017   # 秒表
$ICON_GIT   = [char]0xe0a0   # git 分支
# 分段分隔：VSCode 状态栏不用竖线，靠「留白 + 前景色变化」区分。
# 这里用 3 个空格 —— 既回避了「竖线接不上下方那根分隔线」这个结构上无解的死结
# （见文件头第 5 条），也不会自造新的断头感。
$script:SEP = '   '

# ── 会话起点 ────────────────────────────────────────────────────
$script:StartedAt = Get-Date

# ── 定位 wezterm 可执行文件 ─────────────────────────────────────
$script:WezExe = 'wezterm'
if (-not (Get-Command 'wezterm' -ErrorAction SilentlyContinue)) {
    foreach ($p in @(
            'C:\Program Files\WezTerm\wezterm.exe',
            "$env:LOCALAPPDATA\Programs\WezTerm\wezterm.exe"
        )) {
        if (Test-Path -LiteralPath $p) { $script:WezExe = $p; break }
    }
}

# ── 自报家门：本 pane 的 id ─────────────────────────────────────
# WezTerm 为每个 pane 注入 WEZTERM_PANE（wezterm cli 的 --pane-id 默认也走它）。
$script:SelfPaneId = $env:WEZTERM_PANE

# ── 身份标记：让 Lua 认得出「这个 pane 是状态栏」────────────────
# LEADER+b 要能「再按一次就关掉」，就得先找到这条状态栏。mux 的 pane 对象
# 不暴露尺寸（实测 get_dimensions 在 mux pane 上是 nil），所以不能靠「1 行高」
# 去认；能自报又被 Lua 读到的字段只有 user_vars，因此在这里上报一个。
# 走 OSC 1337 SetUserVar（iterm2 协议，WezTerm 会消费、不会打印乱码），
# 值按协议要求做 base64。Lua 侧读 pane:get_user_vars().term_statusbar
# （见 utils/status-bar.lua 的 MARKER）。
$script:MarkerSent = $false
function Send-IdentityMarker {
    if ($script:MarkerSent) { return }
    try {
        $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('1'))
        [Console]::Write("$ESC]1337;SetUserVar=term_statusbar=$b64$([char]7)")
        [Console]::Out.Flush()
        $script:MarkerSent = $true
    }
    catch {
        # 没有真实控制台（管道/重定向自测）时会抛，忽略即可
    }
}
Send-IdentityMarker

# ── 工具函数 ────────────────────────────────────────────────────

<#
把 wezterm cli list 给出的 cwd 转成文件系统路径。
该字段来自 Rust 侧的 Url::as_str()，Windows 上形如 file://HOST/C:/Users/x，
必须自己剥协议头，不能直接当路径用。
#>
function ConvertFrom-CwdUrl([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    if ($s -match '^file://([^/]*)(/.*)$') {
        $p = [uri]::UnescapeDataString($Matches[2]).TrimStart('/')
        return ($p -replace '/', '\')
    }
    return $s
}

<#
诊断落盘：把一行记录追加到 %TEMP%\wezterm-statusbar-rows.txt。
只在「首次读到行数」「行数发生变化」「发起高度纠正」这几个时刻写，不进热循环。
这个文件是排查本 pane 尺寸问题的唯一窗口 —— 本机无 GUI 时探不到 pane 尺寸，
只能靠 pane 自己上报。
#>
function Write-Diag([string]$text) {
    try {
        $path = Join-Path $env:TEMP 'wezterm-statusbar-rows.txt'
        Add-Content -LiteralPath $path -Encoding utf8 -ErrorAction Stop `
            -Value ('{0}  {1:o}' -f $text, (Get-Date))
    }
    catch {
        # 诊断失败不能影响状态栏本身
    }
}

function Write-RowsDiag([string]$kind, [int]$rows, $cols, [int]$conH = -1) {
    Write-Diag ('{0}  rows={1} cols={2} conH={3}' -f $kind, $rows, $cols, $conH)
}

function Write-RepairDiag([string]$text) {
    Write-Diag $text
}

<#
取「同一 tab 内活动 pane」的工作目录 —— 也就是用户正在敲命令那一格。
wezterm cli list 的 is_active 是 pane 级（每个 tab 各有一个活动 pane），
不是全局焦点，所以不能直接取第一个 is_active，必须先锚定自己所在的 tab。
#>
$script:CwdCache = @{ At = [datetime]::MinValue; Value = $null }
$script:DiagRows = $null   # 本 pane 上次观测到的行数（用于诊断，见 Write-RowsDiag）
function Get-ActivePaneCwd {
    $now = Get-Date
    if (($now - $script:CwdCache.At).TotalMilliseconds -lt $script:ProbeIntervalMs) {
        return $script:CwdCache.Value
    }
    $script:CwdCache.At = $now

    $result = $null
    try {
        $raw = & $script:WezExe cli --no-auto-start list --format json 2>$null | Out-String
        if ($raw -and $raw.TrimStart().StartsWith('[')) {
            $panes = @($raw | ConvertFrom-Json)
            $self = $panes |
                Where-Object { "$($_.pane_id)" -eq "$($script:SelfPaneId)" } |
                Select-Object -First 1
            if ($self) {
                # 本 pane 的行数。数据源是 cli list 的 size.rows —— 这是权威值
                # （实测能如实反映 resize 后的漂移：1 → 6 → 1 → 6 → 3），
                # 所以高度自愈挂在这里，见 Repair-PaneHeight。
                if ($null -ne $self.size -and $null -ne $self.size.rows) {
                    $rows = [int]$self.size.rows
                    $cols = $self.size.cols

                    # 顺带记下 [Console]::WindowHeight，用来核对它是否等于 pane 行数 ——
                    # 若相等，将来可拿它做零成本的触发信号，不必等这个 2s 一次的子进程。
                    $conH = -1
                    try { $conH = [Console]::WindowHeight } catch { $conH = -1 }

                    $rowsChanged = ($rows -ne $script:LastSeenRows)
                    $script:LastSeenRows = $rows

                    if ($null -eq $script:DiagRows) {
                        $script:DiagRows = $rows
                        Write-RowsDiag 'first' $rows $cols $conH
                    }
                    elseif ($rows -ne $script:DiagRows) {
                        Write-RowsDiag 'changed' $rows $cols $conH
                        $script:DiagRows = $rows
                    }

                    # 验证上一轮纠正：行数不降反增 = 方向猜反了，翻转一次并记住。
                    if ($script:RepairBusy) {
                        if ($rows -gt $script:RepairFromRows) {
                            $script:RepairDir = if ($script:RepairDir -eq 'Down') { 'Up' } else { 'Down' }
                            Write-RepairDiag ('flip  dir={0}' -f $script:RepairDir)
                        }
                        $script:RepairBusy = $false
                    }

                    # 自愈：resize 把本 pane 撑高了就缩回去。
                    # 只在行数「变化」时动手 —— 这样即便纠正无效（例如被 clamp 住）也不会
                    # 每 2 秒刷一个子进程。
                    if (-not $Once -and $rows -gt 1 -and $rowsChanged) {
                        $script:RepairFromRows = $rows
                        $script:RepairBusy     = $true
                        Repair-PaneHeight $rows
                    }
                }

                $target = $panes |
                    Where-Object {
                        $_.tab_id -eq $self.tab_id -and
                        $_.pane_id -ne $self.pane_id -and
                        $_.is_active
                    } | Select-Object -First 1
                if (-not $target) {
                    # 兜底：焦点可能正落在状态栏自己身上，退而取同 tab 的其它 pane。
                    $target = $panes |
                        Where-Object { $_.tab_id -eq $self.tab_id -and $_.pane_id -ne $self.pane_id } |
                        Select-Object -First 1
                }
                if ($target) { $result = ConvertFrom-CwdUrl $target.cwd }
            }
            elseif ($panes.Count -gt 0) {
                # 拿不到自身 id（例如手动在普通 pane 里跑本脚本）→ 退回第一个 pane。
                $result = ConvertFrom-CwdUrl $panes[0].cwd
            }
        }
    }
    catch {
        $result = $null
    }
    $script:CwdCache.Value = $result
    return $result
}

<#
从给定目录向上找 .git，读出当前分支。
纯文件读取，不起 git 子进程 —— 本机实测 git 命令约 200ms，每秒跑一次不可接受；
读 .git/HEAD 约 1ms。
三种形态都要处理：.git 目录、.git 文件（worktree/submodule）、detached HEAD。
#>
$script:GitCache = @{ Dir = $null; Value = $null }
function Get-GitInfo([string]$Dir) {
    if ([string]::IsNullOrWhiteSpace($Dir)) { return $null }
    if ($script:GitCache.Dir -eq $Dir) { return $script:GitCache.Value }

    $value = $null
    $d = $Dir
    for ($i = 0; $i -lt 64 -and $d; $i++) {
        $dotGit = Join-Path $d '.git'
        if (Test-Path -LiteralPath $dotGit) {
            $gitDir = $null
            $item = Get-Item -LiteralPath $dotGit -Force -ErrorAction SilentlyContinue
            if ($item -and $item.PSIsContainer) {
                $gitDir = $dotGit
            }
            elseif ($item) {
                # .git 是文件：内容为 "gitdir: <path>"，相对路径要基于所在目录解析。
                $txt = Get-Content -LiteralPath $dotGit -Raw -ErrorAction SilentlyContinue
                if ($txt -match 'gitdir:\s*(.+?)\s*$') {
                    $gitDir = $Matches[1].Trim()
                    if (-not [IO.Path]::IsPathRooted($gitDir)) { $gitDir = Join-Path $d $gitDir }
                }
            }
            if ($gitDir) {
                $headFile = Join-Path $gitDir 'HEAD'
                if (Test-Path -LiteralPath $headFile) {
                    $head = (Get-Content -LiteralPath $headFile -Raw -ErrorAction SilentlyContinue).Trim()
                    $branch = 'unknown'
                    if ($head -match '^ref:\s*refs/heads/(.+)$') { $branch = $Matches[1] }
                    elseif ($head -match '^ref:\s*refs/(.+)$') { $branch = $Matches[1] }
                    elseif ($head) {
                        $short = $head.Substring(0, [Math]::Min(7, $head.Length))
                        $branch = "$short detached"
                    }
                    # 取仓库名用 .NET 而不是 Split-Path：Split-Path 的 -Leaf/-Parent
                    # 只属于 Path 参数集，传 -LiteralPath 会报「无法解析参数集」。
                    $repoName = [IO.Path]::GetFileName($d)
                    if ([string]::IsNullOrWhiteSpace($repoName)) { $repoName = $d }
                    $value = [pscustomobject]@{
                        Name   = $repoName
                        Branch = $branch
                    }
                }
            }
            break   # 找到最近的 .git 就停，不再往上找（不跨仓库嵌套）
        }
        # 同上，向上找父目录也不走 Split-Path。
        $parent = $null
        try { $parent = [IO.Path]::GetDirectoryName($d) } catch { $parent = $null }
        if (-not $parent -or $parent -eq $d) { break }
        $d = $parent
    }

    $script:GitCache = @{ Dir = $Dir; Value = $value }
    return $value
}

<#
把本 pane 的高度缩回 1 行 —— 这是本脚本存在的最重要的一个补丁。

为什么需要：
    WezTerm 在窗口 resize 时按**比例**重算 pane 尺寸，
    而 SplitPane 的 size = { Cells = 1 } 只在**创建那一刻**解析成 1 行，
    之后那条分隔线记住的是比例。于是：
        全屏开状态栏 → 1 行
        缩小窗口     → 1 行被 clamp 住（1 行是下限），比例反而变大
        放大窗口     → 按放大后的比例算 = 6 行
    反复几次会累积漂移（实测 1 → 6 → 1 → 6 → 3）。
    多出来的行是空的，视觉上就是「底部一块大空区域」，文字只在最上面一行。

    上游已知问题：wez/wezterm#6378「Split panes improperly scale on window resize」
    → 被判为 #6052 的重复，状态 closed as not planned（官方不修）。

所以本脚本自己守住高度：发现行数 > 1 就调 wezterm cli adjust-pane-size 缩回去。

方向语义（官方文档 + 多个配置来源交叉验证）：
    AdjustPaneSize 的 direction 指的是**分隔线的移动方向**，效果取决于本 pane
    落在分隔线的哪一侧。官方原文举例：右侧 pane「向左调整 1」→ 该 pane 变大
    （分隔线左移，右侧区域扩大）。本 pane 在分隔线**下方**，所以：
        分隔线上移(Up) → 下方区域扩大 → 本 pane 变高
        分隔线下移(Down) → 下方区域缩小 → 本 pane 变矮   ← 用这个
    这个推断若与实际相反，主循环里的自适应逻辑会自动翻转一次并记住。
#>
$script:RepairDir      = 'Down'   # 分隔线移动方向
$script:RepairFromRows = 0        # 发起纠正时的行数（用于判断方向是否反了）
$script:RepairBusy     = $false   # 已发起纠正、等下次探测验证效果
$script:LastSeenRows   = -1       # 上次探测到的行数；只在「行数变化」时纠正，防止无效时狂刷子进程

function Repair-PaneHeight([int]$rows) {
    if (-not $script:SelfPaneId -or $rows -le 1) { return }
    try {
        # 与探测 cwd 时一致地加 --no-auto-start：本脚本本来就跑在 wezterm 的 pane 里，
        # mux 一定可达；万一不可达也不该顺手拉起一个后台 mux server。
        & $script:WezExe cli --no-auto-start adjust-pane-size $script:RepairDir --amount ($rows - 1) `
            --pane-id $script:SelfPaneId 2>$null | Out-Null
        Write-RepairDiag ('repair rows={0} dir={1} amount={2}' -f $rows, $script:RepairDir, ($rows - 1))
    }
    catch {
        # 纠正失败不影响状态栏显示
    }
}

<#
算可见宽度：先剥掉 ANSI 转义序列，再按东亚宽度累加（宽字符占 2 列）。
Nerd Font 图标落在 PUA(0xE000-0xF8FF)，按 1 列算。
#>
function Get-VisibleWidth([string]$s) {
    if (-not $s) { return 0 }
    $clean = $s -replace "$ESC\[[0-9;:?]*[a-zA-Z]", ''
    $w = 0
    foreach ($ch in $clean.ToCharArray()) {
        $c = [int]$ch
        if (($c -ge 0x1100 -and $c -le 0x115F) -or
            ($c -ge 0x2E80 -and $c -le 0xA4CF) -or
            ($c -ge 0xAC00 -and $c -le 0xD7A3) -or
            ($c -ge 0xF900 -and $c -le 0xFAFF) -or
            ($c -ge 0xFE30 -and $c -le 0xFE6F) -or
            ($c -ge 0xFF00 -and $c -le 0xFF60) -or
            ($c -ge 0xFFE0 -and $c -le 0xFFE6)) { $w += 2 }
        else { $w += 1 }
    }
    return $w
}

<#
组装一帧，返回左右两段（VSCode 状态栏的惯例分组）：

   左 = 工作上下文（仓库/分支、编码）
   右 = 会话自身（计时器）

右边**只留计时器**：原来的时钟（HH:mm:ss）已按用户要求去掉 ——
tab bar 右侧的 update-status 已经在显示 `%a %H:%M:%S`（见 wezterm.lua 里
`events.right-status` 的 date_format），两处并排出现同一个时间是纯噪音。

不在这里拼整行，是因为「中间空档」要等渲染循环拿到 [Console]::WindowWidth 才算得出。
#>
function Format-StatusLine {
    $now = Get-Date

    # 计时器：本状态栏进程存活时长
    $el = $now - $script:StartedAt
    $timer = '{0:00}:{1:00}:{2:00}' -f [int]$el.TotalHours, $el.Minutes, $el.Seconds

    # 编码：启动代码页 vs 本进程输出编码，不一致就是老坑（936 vs utf-8）
    $outCp = [Console]::OutputEncoding.CodePage
    if ($script:OrigCodePage -eq $outCp) { $encColor = $C.Green } else { $encColor = $C.Warn }
    $enc = "$encColor$($script:OrigCodePage)$($C.Mute) / $($C.Text)utf-8$($C.FgReset)"

    # Git：取同 tab 活动 pane 的 cwd。
    # 注意 cwd 的**可信前提**：目标 pane 的壳必须发过 OSC 7（pwsh profile 里已加，
    # 见 Microsoft.PowerShell_profile.ps1 的 Get-Osc7Url）。WezTerm 只认 OSC 7 ——
    # 实测壳里 `Set-Location` 之后 panel cwd 纹丝不动，一条 OSC 7 才立刻生效。
    # 缺了它这里拿到的永远是启动目录，于是「在有仓库的目录里显示 no repo」。
    $cwd = Get-ActivePaneCwd
    $git = Get-GitInfo $cwd
    if ($git) {
        $repo = "$($C.Green)$ICON_GIT  $($C.Text)$($git.Name)$($C.Mute) @ $($C.Bright)$($git.Branch)$($C.FgReset)"
    }
    else {
        $repo = "$($C.Mute)$ICON_GIT  no repo$($C.FgReset)"
    }

    $left = @(
        $repo,
        "$($C.Mute)chcp $enc"
    ) -join $script:SEP

    $right = "$($C.Blue)$ICON_TIMER  $($C.Bright)$timer$($C.FgReset)"

    return [pscustomobject]@{ Left = $left; Right = $right }
}

# 被 dot-source 时只加载上面的函数、不进入主循环 —— 便于单独测 Get-GitInfo 等：
#   . .\scripts\status-bar.ps1 ; Get-GitInfo $HOME
if ($MyInvocation.InvocationName -eq '.') { return }

# ── 渲染 ────────────────────────────────────────────────────────
# 隐藏光标：本 pane 只有显示职责，不需要光标。
# 刻意**不**设置 TreatControlCAsInput —— 让 Ctrl+C 能直接结束本进程。
# wezterm 的 exit_behavior 默认是 "Close"（20220624 版本起就是），进程一退 pane 就关，
# 所以 Ctrl+C 是关掉这条状态栏最顺手的办法。
# 另两条路：焦点在它上面时按 SUPER+w（CloseCurrentPane），
# 或先 SUPER_REV+j 把焦点往下移再到它身上。
try { [Console]::Write("$ESC[?25l") }
catch {
    # 无真实控制台时（管道/重定向环境）会抛，忽略即可。
}

try {
    while ($true) {
        $frame = Format-StatusLine

        $width = 0
        try { $width = [Console]::WindowWidth } catch { $width = 0 }

        # 左端 1 列、右端 1 列内边距，中间空档顶满 —— 右侧那组信息才算真正右对齐。
        $gap = ' '
        if ($width -gt 0) {
            $need = $width - (Get-VisibleWidth $frame.Left) - (Get-VisibleWidth $frame.Right) - 2
            if ($need -gt 0) { $gap = ' ' * $need }
        }

        # 顺序不能换：先设底色 -> 归位 -> 清整行（ESC[2K 是拿**当前**背景色填满整行的）
        # -> 最后写内容。先清后写顺带解决上一帧更长时的拖尾。
        [Console]::Write(
            "$($C.Bg)$ESC[H$ESC[2K $($frame.Left)$gap$($frame.Right) $($C.Reset)")
        [Console]::Out.Flush()

        if ($Once) { break }

        # 对齐到整秒唤醒，否则时钟会有可见漂移（每次循环还要花几十毫秒）。
        $sleep = $IntervalMs - ((Get-Date).Millisecond % $IntervalMs)
        if ($sleep -lt 50) { $sleep += $IntervalMs }
        Start-Sleep -Milliseconds $sleep
    }
}
finally {
    [Console]::Write("$ESC[0m$ESC[?25h")
    [Console]::Out.Flush()
}

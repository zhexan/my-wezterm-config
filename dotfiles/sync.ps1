<#
.SYNOPSIS
    把本仓库 dotfiles/ 下的文件同步到系统里的真实位置。

.DESCRIPTION
    仓库里的 dotfiles/ 是**副本**（版本控制的对象），系统里的才是生效的那份。
    改完仓库里的副本后跑这个脚本落地，或者反过来用 -Pull 把系统上的改动收回仓库。

    为什么不做成 symlink：
      pwsh 的 profile 是 pwsh 启动时按 `$PROFILE` 路径读的，符号链接本身没问题，
      但 Windows 上创建符号链接要开发者模式或管理员权限，而且一旦用户在
      `$PROFILE` 上直接编辑，改的是 link 目标还是 link 本身会取决于编辑器行为 ——
      对"偶尔改一改"的个人配置，复制 + 显式同步比 symlink 少一类说不清的故障。

.PARAMETER Pull
    反向同步：系统 -> 仓库。用于在真机上调完配置后把改动收进版本控制。

.PARAMETER WhatIf
    只打印将要做什么，不落盘（标准 PowerShell 开关）。

.EXAMPLE
    pwsh -File dotfiles\sync.ps1              # 仓库 -> 系统（落地）
    pwsh -File dotfiles\sync.ps1 -Pull        # 系统 -> 仓库（收回改动）
    pwsh -File dotfiles\sync.ps1 -WhatIf      # 只看会做什么，不落盘
#>
# SupportsShouldProcess 是 -WhatIf 的前提：没有它，PowerShell **不会**把 -WhatIf
# 绑进 $WhatIfPreference，而是直接报「找不到与参数名称 'WhatIf' 匹配的参数」。
# 实测踩过（2026-09-28）。
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Pull
)

$ErrorActionPreference = 'Stop'

# 仓库根 = 本脚本所在目录的上一级
$repoRoot = Split-Path -Parent $PSScriptRoot

# 映射表：仓库内相对路径 -> 系统绝对路径
# 加新文件时在这里补一行即可，同步逻辑不用动。
$MAP = @(
    @{
        Name = 'pwsh profile'
        Repo = 'dotfiles/pwsh/Microsoft.PowerShell_profile.ps1'
        Live = Join-Path $env:USERPROFILE 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1'
    }
)

$direction = if ($Pull) { '系统 -> 仓库' } else { '仓库 -> 系统' }
Write-Host "同步方向：$direction" -ForegroundColor Cyan
Write-Host ""

$fail = 0
foreach ($item in $MAP) {
    $repoPath = Join-Path $repoRoot ($item.Repo -replace '/', '\')
    $livePath = $item.Live

    $src = if ($Pull) { $livePath } else { $repoPath }
    $dst = if ($Pull) { $repoPath } else { $livePath }

    if (-not (Test-Path -LiteralPath $src)) {
        Write-Host ("  [跳过] {0} —— 源不存在：{1}" -f $item.Name, $src) -ForegroundColor Yellow
        $fail++
        continue
    }

    $srcHash = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash
    $dstHash = if (Test-Path -LiteralPath $dst) {
        (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash
    } else {
        ''
    }

    if ($srcHash -eq $dstHash) {
        Write-Host ("  [一致] {0}" -f $item.Name) -ForegroundColor DarkGray
        continue
    }

    if ($WhatIfPreference) {
        Write-Host ("  [将写入] {0}`n           {1}" -f $item.Name, $dst)
        continue
    }

    # 落地前先给目标留一份 .bak（和用户"旧配置用 .bak 备份而非删除"的习惯一致）
    if ($dstHash -ne '') {
        $bak = "$dst.bak"
        Copy-Item -LiteralPath $dst -Destination $bak -Force
        Write-Host ("  [备份] {0}" -f (Split-Path -Leaf $bak)) -ForegroundColor DarkGray
    }

    $dstDir = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $dstDir)) {
        New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
    }

    Copy-Item -LiteralPath $src -Destination $dst -Force

    $newHash = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash
    if ($newHash -eq $srcHash) {
        Write-Host ("  [完成] {0}`n           {1}" -f $item.Name, $dst) -ForegroundColor Green
    } else {
        Write-Host ("  [校验失败] {0} —— 写入后哈希不符" -f $item.Name) -ForegroundColor Red
        $fail++
    }
}

Write-Host ""
if ($fail -eq 0) {
    Write-Host "全部完成。" -ForegroundColor Green
} else {
    Write-Host "有 $fail 项未成功，请看上面的输出。" -ForegroundColor Yellow
    exit 1
}

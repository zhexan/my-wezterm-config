# dotfiles

放在系统各处、但需要版本控制的配置文件。仓库里的这份是**副本**，系统里的那份才生效。

## 为什么要放这里

`Microsoft.PowerShell_profile.ps1` 里那段命令耗时回写逻辑（`ESC[{n}A` + `ICH` 的落点算术、
`Test-WarpRowBlank` 的空行判定、`term_mem` 上报）和 WezTerm 的 `events/right-status.lua`
是**咬牙配套**的 —— 状态栏显示的内存值就靠 profile 用 OSC 1337 推过去。
两边改动必须能一起回溯，所以放在同一个仓库里。

## 同步

仓库里的副本不会自动生效，改完要落地：

```powershell
pwsh -File dotfiles/sync.ps1            # 仓库 -> 系统（落地；会先留 .bak）
pwsh -File dotfiles/sync.ps1 -Pull      # 系统 -> 仓库（把真机上的改动收回来）
pwsh -File dotfiles/sync.ps1 -WhatIf    # 只看会做什么，不落盘
```

脚本按 SHA256 判断是否需要动，已经一致的文件会标 `[一致]` 跳过。

## 当前纳入的文件

| 仓库内 | 系统路径 |
| --- | --- |
| `pwsh/Microsoft.PowerShell_profile.ps1` | `%USERPROFILE%\Documents\PowerShell\Microsoft.PowerShell_profile.ps1` |

## 关于 profile 里的中文用户名

profile 的注释里出现了 `C:\Users\马文坤\...`，那是**技术说明的一部分**，不是笔误：
这份配置里好几个地方（`Get-WarpVisualWidth` 的宽度计算、开头强制 UTF-8 的那一行）
存在的理由就是「用户名含中文会导致 GBK 解码错位 / 宽度算错」。把路径改成占位符，
注释就讲不清在防什么。这个仓库是私有的，保留原样。

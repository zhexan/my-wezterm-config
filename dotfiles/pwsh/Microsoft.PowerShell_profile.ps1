# ============================================================
# PowerShell 7 (pwsh) profile
# WezTerm launches `pwsh -NoLogo`, which auto-loads this file.
# This is where oh-my-posh is initialized 鈥?WezTerm itself does
# NOT configure the prompt; it only renders the output font.
# ============================================================

# Force UTF-8 output encoding BEFORE initializing oh-my-posh.
# Without this, the temp init script path (which contains the Chinese
# username in C:\Users\椹枃鍧...) is decoded as GBK and turns into
# mojibake like "妞规瀮閸?, so the `&` call can't find the file.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# ---------------------------------------------------------------
# oh-my-posh -- Warp-style minimal prompt:   E:\Path
#
# All themes live in ~/.oh-my-posh/. To switch, change the --config path:
#   warp-ui.omp.json                <- current: path only. The duration is
#                                      drawn by the wrapper below, not here.
#   warp-style.omp.json             (previous: two-line box + status tick)
#   powerlevel10k_rainbow.omp.json  (original)
# ---------------------------------------------------------------
oh-my-posh init pwsh --config "$env:USERPROFILE\.oh-my-posh\warp-ui.omp.json" | Invoke-Expression

# ---------------------------------------------------------------
# helpers / tunables
# ---------------------------------------------------------------

# Visible width of a string that may carry ANSI colour codes: strip OSC and CSI
# sequences, then count CJK / fullwidth characters as two columns. The Chinese
# username in C:\Users\椹枃鍧... makes this necessary -- counting by .Length
# would place the duration in the middle of the path.
function Get-WarpVisualWidth {
   param([string]$Text)
   if (-not $Text) { return 0 }
   $plain = [regex]::Replace($Text, "\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)?", '')
   $plain = [regex]::Replace($plain, "\x1b\[[0-9;?]*[A-Za-z]", '')
   $sum = 0
   foreach ($ch in $plain.ToCharArray()) {
      $c = [int]$ch
      if (($c -ge 0x1100 -and $c -le 0x115F) -or ($c -ge 0x2E80 -and $c -le 0xA4CF) -or
          ($c -ge 0xAC00 -and $c -le 0xD7A3) -or ($c -ge 0xF900 -and $c -le 0xFAFF) -or
          ($c -ge 0xFE30 -and $c -le 0xFE6F) -or ($c -ge 0xFF00 -and $c -le 0xFF60) -or
          ($c -ge 0xFFE0 -and $c -le 0xFFE6)) { $sum += 2 }
      else { $sum += 1 }
   }
   return $sum
}

# Locate the block rule above the cursor by reading the console buffer: the
# rule row is nothing but U+2500 dashes starting at column 0, and the block's
# directory line is by construction the row right below it. Scans upward from
# the cursor and returns the FIRST (closest) match, or -1 when there is none --
# a taller block simply has its rule further up than the scan window, and then
# the caller falls back to the bottom placement, which is what it should do.
#
# Reading only the left 24 columns keeps this cheap; a real rule starts at
# column 0 with 100+ dashes, so 24 is plenty to recognise it.
function Get-WarpRuleRow {
   param([int]$CursorRow, [int]$Width, [int]$ScanRows)
   $top = $CursorRow - $ScanRows
   if ($top -lt 0) { $top = 0 }
   if ($CursorRow - $top -lt 2) { return -1 }
   $probeW = [Math]::Min(24, $Width)
   if ($probeW -lt 8) { return -1 }
   try {
      $rect = New-Object System.Management.Automation.Host.Rectangle(0, $top, ($probeW - 1), ($CursorRow - 1))
      $cells = $Host.UI.RawUI.GetBufferContents($rect)
   }
   catch { return -1 }
   $dash = [string][char]0x2500
   for ($r = $CursorRow - 1; $r -ge $top; $r--) {
      $isRule = $true
      for ($c = 0; $c -lt $probeW; $c++) {
         if ($cells[($r - $top), $c].Character -ne $dash) { $isRule = $false; break }
      }
      if ($isRule) { return $r }
   }
   return -1
}

# Is the given buffer row entirely blank? The bottom placement uses this to
# tell "the output ended with a spare blank row" apart from "the cursor sits
# directly below the last line of output".
#
# Why that distinction is the whole bug -- measured 2026-09-28 by dumping a real
# console buffer (_r1_screen.py) instead of guessing:
#
#     ls <long dir>   last output row -> ONE blank row -> cursor below it
#                     step up lands on the blank row   -> "0.128s" alone  OK
#     node <6 lines>  cursor directly below "line5"
#                     step up lands INSIDE line5       -> "0.227s line5"  BAD
#
# Both are the same bottom placement doing the same ESC[1A; the spare blank row
# is Format-Table's doing (it ends \r\n\r\n) and cannot be relied on. So the
# placement asks this function before deciding whether to step up at all.
#
# Scans the full width rather than the first few cells on purpose: a row that is
# all spaces on the left but carries text further right (indented output, a
# right-aligned column) is NOT blank, and a narrow probe would call it blank and
# walk straight back into the misplaced write this exists to prevent.
function Test-WarpRowBlank {
   param([int]$Row, [int]$Width)
   if ($Row -lt 0) { return $false }
   if ($Width -lt 1) { return $false }
   try {
      $rect = New-Object System.Management.Automation.Host.Rectangle(0, $Row, ($Width - 1), $Row)
      $cells = $Host.UI.RawUI.GetBufferContents($rect)
      for ($c = 0; $c -lt $Width; $c++) {
         $ch = $cells[0, $c].Character
         if ($null -eq $ch) { continue }
         if ([int][char]$ch -eq 0) { continue }
         if ($ch -ne ' ') { return $false }
      }
      return $true
   }
   catch { return $false }
}

# How tall a block may still be (counted as the command line PLUS its output
# rows) and get the duration up on the directory line. Taller blocks keep the
# duration at the block's bottom, left aligned. This is the single number to
# tune: 4 means "1-4 rows -> next to the directory, 5+ -> bottom", i.e. a
# command with 0-3 rows of output gets the directory placement.
$global:__WarpUIShortBlockRows = 4

# How far above the cursor the buffer scan looks for the block rule. Only needs
# to cover a short block (a rule one row above the directory line, so
# ShortBlockRows + 2), with headroom for a wrapped prompt line.
$global:__WarpUIRuleScanRows = $global:__WarpUIShortBlockRows + 6

# ---------------------------------------------------------------
# OSC 7 -- tell the terminal where the shell actually is.
#
# WezTerm can ONLY learn a pane's real working directory from an OSC 7
# sequence. Measured 2026-09-27: `Set-Location C:\Windows` left the pane's
# reported cwd at its old value for the whole 5s of observation, while a
# single OSC 7 sequence moved it immediately (file:///C:/Program%20Files).
#
# Without this, anything that reads the pane cwd is wrong, and that includes
# the bottom status bar in WezTerm (scripts/status-bar.ps1): it walked up from
# a stale directory and therefore always printed "no repo".
#
# oh-my-posh does NOT do this for pwsh -- its generated init script contains
# no `]7;file://` (grepped all of AppData\Local\oh-my-posh\init.*.ps1), even
# though the binary's template has the sequence for other shells. So the
# wrapper below emits it.
#
# The path must be percent-encoded UTF-8: it contains a CJK username, and a
# raw 椹?is not valid inside a URL. Everything outside [A-Za-z0-9-._~/] is
# escaped byte by byte.
# ---------------------------------------------------------------
function Get-Osc7Url {
   $p = $PWD.ProviderPath
   if (-not $p) { return $null }
   $slashed = $p -replace '\\', '/'
   $sb = [System.Text.StringBuilder]::new()
   foreach ($b in [System.Text.Encoding]::UTF8.GetBytes($slashed)) {
      if (($b -ge 0x30 -and $b -le 0x39) -or    # 0-9
         ($b -ge 0x41 -and $b -le 0x5A) -or    # A-Z
         ($b -ge 0x61 -and $b -le 0x7A) -or    # a-z
         $b -eq 0x2D -or $b -eq 0x2E -or $b -eq 0x5F -or $b -eq 0x7E -or   # - . _ ~
         $b -eq 0x2F -or $b -eq 0x3A) {        # / :
         [void]$sb.Append([char]$b)
      }
      else {
         [void]$sb.Append(('%{0:X2}' -f $b))
      }
   }
   return "file://$env:COMPUTERNAME/$($sb.ToString())"
}

# ---------------------------------------------------------------
# Console code pages -- reported to WezTerm for the tab-bar status.
#
# GetConsoleOutputCP() returns the same value `chcp` prints, but calling the
# API costs microseconds whereas spawning chcp.com costs ~190 ms on this
# machine (measured) -- and this runs on EVERY prompt, so the subprocess is
# not an option.
#
# Add-Type compiles once per session; the guard keeps a re-dot-source (or a
# reloaded profile) from throwing "type already exists". Wrapped in try/catch
# because a locked-down session may refuse Add-Type -- the callers below test
# for the type before using it.
# ---------------------------------------------------------------
if (-not ('Wz.ConsoleCp' -as [type])) {
   try {
      Add-Type -Namespace Wz -Name ConsoleCp -ErrorAction Stop -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern uint GetConsoleOutputCP();
[DllImport("kernel32.dll")] public static extern uint GetConsoleCP();
'@
   }
   catch { }
}

# ---------------------------------------------------------------
# Wrap the oh-my-posh prompt: Warp's block rule + duration placement.
#
# Warp puts every command in its own block: a 1px rule between blocks, plus a
# coloured status stripe down the left edge of a failed block. The rule is
# reproducible; the stripe is NOT -- it needs terminal-level knowledge of
# command boundaries, and WezTerm's Lua API cannot touch the scrollback.
# So status is carried by the rule colour instead: failed -> #d02c1c red.
# Both colours are pixel-sampled from the Warp screenshot (see colors/warp.lua).
#
# DURATION PLACEMENT -- depends on how tall the block turned out to be
#
#   short block (<= __WarpUIShortBlockRows)   -> up on the directory line,
#       right after the path:      E:\dir 0.001s
#
#   tall block                                -> bottom of the block, left
#       aligned, so it reads next to the command's last output line.
#
# Both are RELATIVE cursor moves, which keep working however far the screen has
# scrolled. (Absolute row numbers would not: past one screenful the cursor
# coordinate saturates and the arithmetic silently lands on the wrong row.)
#
#   ESC[{up}A       up to the target row (up = rows + 1)
#                   the target is $rows + 1 up because the block is laid out as
#                   directory / command / output..., i.e. rows = 1 + output rows
#   ESC[?7l         autowrap OFF -- nothing written here may spill onto a new row
#   ESC[0m          reset the pen, so an ICH insert makes plain blanks
#   ESC[{col}G      to the column just past the path on that row, or ESC[G (col 1)
#   ESC[{n}@        ICH on the bottom placement: insert n blanks and push the
#                   row's text right instead of overwriting it. Left aligned
#                   means column 1, which for an output-less command (cd ..) is
#                   the command itself -- an overwrite would erase it, an insert
#                   turns `cd ..` into `0.001s cd ..`.
#   <duration>      dim grey #6c6c6c
#   ESC[?7h / ESC[G / ESC[{up}B   restore, come back down
#
# ICH was verified against wezterm's own source rather than assumed:
#   '@' -> Edit::InsertCharacter        (wezterm-escape-parser/src/csi.rs)
#   implemented as screen.insert_cell() n times, "text between the cursor and
#   right margin moves to the right"    (term/src/terminalstate/mod.rs)
#
# Falls back to gluing the duration onto the path when the terminal is too
# narrow for either placement, and stays quiet when no command actually ran.
# ---------------------------------------------------------------
$global:__OmpPrompt = $function:prompt
$global:__WarpUILastHistId = $null
$global:__WarpUILastCode = $null

# Cursor row read at the start of the previous prompt, and how wide the
# directory line drawn back then turned out to be. Together they are what lets
# this prompt measure the previous block and find the path's end on its
# directory row.
$global:__WarpUIPrevY = $null
$global:__WarpUIDirCols = 0
$global:__WarpUIDirFits = $false            # was that row a single row?

# Diagnostics for troubleshooting: which branch ran, the block height it saw,
# and whether that height came from the row arithmetic or the buffer scan.
$global:__WarpUIPlacement = ''
$global:__WarpUIRows = -1
$global:__WarpUIRowSource = ''

function global:prompt {
   # These two MUST be the first statements: $? and $LASTEXITCODE describe the
   # PREVIOUS command, and anything after them would clobber that reading.
   $ok = $?
   $lastExit = $LASTEXITCODE

   $esc = [char]27

   # $? is the ONLY reliable signal: it is False both for a failed cmdlet AND
   # for a native command that exited non-zero. $LASTEXITCODE is NOT enough on
   # its own -- cmdlets never touch it, so it keeps whatever an earlier native
   # command left behind. (Caught in testing: a successful Write-Output right
   # after `cmd /c exit 7` still painted the rule red.)
   $failed = -not $ok

   # Only surface the exit code if it changed since the previous prompt,
   # otherwise a failed cmdlet would print a stale number.
   $showCode = ($null -ne $lastExit) -and ($lastExit -ne 0) -and ($lastExit -ne $global:__WarpUILastCode)
   $global:__WarpUILastCode = $lastExit

   $rgb = if ($failed) { '208;44;28' } else { '61;61;59' }

   # ---- ROW ARITHMETIC FIX: force a newline when the output didn't end with one
   #
   # The whole duration placement depends on one invariant:  "when this prompt is
   # called, the cursor sits on a FRESH row below the command's last output row."
   # Everything downstream (rows = nowY - prevY - 2, and $up = rows + 1) is
   # derived from that, so if it is violated the duration lands one row too low.
   #
   # It IS violated by any command whose output does not end in a newline --
   # measured 2026-09-27 in a real ConPTY:
   #     node -e "process.stdout.write('a\nb\nc')"  ->  3 rows, NO trailing \n
   #     groovy -e "print 'x\ny\nz'"                ->  same
   #     cat <file with no final newline>           ->  same
   # Symptom the user reported: the duration is pushed INTO the last output row
   # ("time and output rendered on one line"), while `ls` looked fine -- `ls` is
   # Format-Table output, which ends \r\n\r\n, so it happens to leave a blank row
   # for the write-back to land on. The bug was invisible exactly because the
   # commands that expose it (cat / groovy / node) are the ones you time.
   #
   # Measured write-back sequences (3-row, no trailing newline vs 2-row with):
   #     node print  (no \n)  ->  ESC[5A ... ESC[32G   <- one row too low
   #     node log    (with \n)->  ESC[4A ... ESC[32G
   # Confirms rows came out 1 short, and $up = rows + 1 propagated the error.
   #
   # Fix: if the cursor is not in column 1, the last output line has no newline,
   # so emit one before any of the arithmetic runs. CursorPosition.X is 0-based;
   # X -eq 0 means already at the start of a fresh row. Wrapped in try/catch and
   # defaulted to "no output" so a redirected stdout (no console) still works.
   $midLine = $false
   try {
      $midLine = ($Host.UI.RawUI.CursorPosition.X -ne 0)
   }
   catch { $midLine = $false }
   if ($midLine) {
      # A literal newline: the console translates LF to CRLF itself, and this
      # goes out before the rule/dirLine so it cannot disturb them.
      [Console]::Write("`n")
   }

   # ---- duration of the command that just finished -------------------------
   # Sourced the same way oh-my-posh sources it internally (see its generated
   # init script, Update-PoshErrorCode): PowerShell's own history timestamps.
   # Those exclude the time you spent typing, which is what we want here.
   $dur = ''
   try {
      $hist = Get-History -ErrorAction Ignore -Count 1
      # A new history id means a non-empty command actually ran. Pressing Enter
      # on an empty line adds no history -> no duration, no write-back.
      if ($null -ne $hist -and $hist.Id -ne $global:__WarpUILastHistId) {
         $global:__WarpUILastHistId = $hist.Id
         if ($null -ne $hist.StartExecutionTime -and $null -ne $hist.EndExecutionTime) {
            $ms = ($hist.EndExecutionTime - $hist.StartExecutionTime).TotalMilliseconds
            if ($ms -ge 0) {
               $dur = if ($ms -ge 60000) { '{0}m {1:0.00}s' -f [int][math]::Floor($ms / 60000), (($ms % 60000) / 1000) }
               elseif ($ms -ge 1000) { '{0:0.00}s' -f ($ms / 1000) }
               else { '{0:0.000}s' -f ($ms / 1000) }
            }
         }
      }
   }
   catch { $dur = '' }

   # Terminal geometry. NOT [Console]::WindowWidth -- that throws when stdout is
   # redirected (no console attached), which would kill prompt and make pwsh
   # silently fall back to the default "PS>" prompt.
   $w = 0
   $termH = 0
   try {
      $size = $Host.UI.RawUI.WindowSize
      $w = $size.Width
      $termH = $size.Height
   }
   catch { $w = 0; $termH = 0 }
   if ($w -lt 2) { $w = 80 }
   $rule = [string]::new([char]0x2500, $w - 1)

   # ---- how tall was the previous command's block? -------------------------
   # $Host.UI.RawUI.CursorPosition is the same API oh-my-posh itself uses (its
   # generated init script does `$env:POSH_CURSOR_LINE = ...CursorPosition.Y`),
   # and it is read here while the cursor still sits one row below the previous
   # command's output. The previous prompt left it on the row it drew its
   # directory line on, so:
   #
   #    directory row   <- prevY + 1
   #    command line    <- prevY + 2
   #    output          <- prevY + 3 ..
   #    cursor now      <- prevY + 3 + outputRows
   #
   #    rows = nowY - prevY - 2   =  1 (command) + outputRows
   #
   # 鈿狅笍 This block reads `cursor now = prevY + 3 + outputRows`, i.e. it ASSUMES
   #   the cursor is on a fresh row below the output. That assumption is what the
   #   "force a newline" fix above exists to guarantee -- without it, output that
   #   ends mid-line makes nowY (and therefore rows, and therefore $up) 1 short,
   #   and the duration lands inside the last output row. Do not remove that fix
   #   without re-deriving this arithmetic.
   #
   # rows is left at -1 (unusable) when the cursor row cannot be read at all,
   # when the previous directory line wrapped onto a second row (which would
   # make the subtraction off by one), or when nowY is pinned to the last row
   # -- that means the screen scrolled while the command ran, the coordinate
   # saturated, and the subtraction would under-report.
   $rows = -1
   $rowSource = 'none'
   $nowY = -1
   try {
      $nowY = $Host.UI.RawUI.CursorPosition.Y
      if ($global:__WarpUIDirFits -and $null -ne $global:__WarpUIPrevY -and $nowY -lt ($termH - 1)) {
         $rows = $nowY - $global:__WarpUIPrevY - 2
         $rowSource = 'arith'
      }
      $global:__WarpUIPrevY = $nowY
   }
   catch {
      $global:__WarpUIPrevY = $null
      $rows = -1
   }

   # Fallback for a full screen, which is the normal state after a while and
   # exactly where the arithmetic above gives up: saturating at the last row
   # erases the difference between a two-row block and a fifty-row one. Read
   # the console buffer and find the block rule instead.
   if ($rows -lt 1 -and $nowY -ge 0) {
      $ruleRow = Get-WarpRuleRow -CursorRow $nowY -Width $w -ScanRows $global:__WarpUIRuleScanRows
      if ($ruleRow -ge 0) {
         $rows = $nowY - $ruleRow - 2
         $rowSource = 'scan'
      }
   }
   $global:__WarpUIRows = $rows
   $global:__WarpUIRowSource = $rowSource

   $mark = ''
   if ($failed) {
      $suffix = if ($showCode) { " $lastExit" } else { '' }
      $mark = "$esc[38;2;208;44;28m$([char]0x2717)$suffix$esc[0m  "
   }

   # ---- report the cwd to the terminal (OSC 7) -----------------------------
   # Emitted on every prompt so a `cd` is visible to the terminal before the
   # next one is drawn. $ok / $lastExit were captured above, so nothing here
   # can disturb the exit-status reading. See Get-Osc7Url for why this exists.
   try {
      $osc7 = Get-Osc7Url
      if ($osc7) { [Console]::Write("$esc]7;$osc7$([char]7)") }
   }
   catch { }

   # ---- report console code pages + memory (OSC 1337 SetUserVar) -----------
   # WezTerm cannot read the shell's code page -- it is shell-private state --
   # so the tab-bar status (events/left-status.lua) gets it from user vars via
   # pane:get_user_vars(). The Lua reader tells "wezterm already decoded it"
   # from "still base64" by an all-digits test, so these values MUST be bare
   # digits (they are code pages, so they naturally are).
   #
   # Two code pages on purpose: the console output CP and .NET's OutputEncoding
   # CP can disagree, and that disagreement is exactly the GBK mojibake trap the
   # status line is there to surface. Same pattern as the OSC 7 above -- cheap
   # API calls only, no subprocess.
   #
   # Plus a third, non-code-page value: this process's working set in MB, which
   # the right-hand status (events/right-status.lua) shows in its memory
   # segment. Process::GetCurrentProcess() rather than Get-Process -Id $PID --
   # the latter runs a full process query and prompt runs after every single
   # command, so it has to be the cheap one. On failure we simply omit the var
   # instead of sending a bogus 0, so the segment disappears rather than lying.
   try {
      $encCp = [int][Console]::OutputEncoding.CodePage
      $consoleCp = $encCp
      if ('Wz.ConsoleCp' -as [type]) { $consoleCp = [int][Wz.ConsoleCp]::GetConsoleOutputCP() }

      $vals = @(@('term_chcp', $consoleCp), @('term_enc', $encCp))
      try {
         $proc = [System.Diagnostics.Process]::GetCurrentProcess()
         $memMB = [int]($proc.WorkingSet64 / 1MB)
         $proc.Dispose()
         $vals += , @('term_mem', $memMB)
      }
      catch { }

      foreach ($pair in $vals) {
         $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([string]$pair[1]))
         [Console]::Write("$esc]1337;SetUserVar=$($pair[0])=$b64$([char]7)")
      }
   }
   catch { }

   $dirLine = "$mark$(& $global:__OmpPrompt)"

   # ---- place the duration ------------------------------------------------
   $writeback = ''
   $inline = ''
   $placement = ''
   if ($dur) {
      $need = $dur.Length + 1                  # duration + one leading space
      $white = $w - $need - 1                  # columns still free on the row
      $col = $global:__WarpUIDirCols + 1       # just past the path, 1-based
      if (($rows -ge 1) -and ($rows -le $global:__WarpUIShortBlockRows) -and ($col + $need - 1 -le $w)) {
         # Short block: go up to the directory line and append after the path.
         # ICH as well, for the same reason as below -- it shifts instead of
         # overwriting, so even a misjudged target row cannot lose text.
         $up = $rows + 1
         $writeback = "$esc[${up}A$esc[?7l$esc[0m$esc[${col}G$esc[${need}@$esc[38;2;108;108;108m $dur$esc[0m$esc[?7h$esc[G$esc[${up}B"
         $placement = 'dir'
      }
      elseif ($white -ge 20) {
         # Tall block: one dedicated line UNDER the output, left aligned.
         #
         # "Under the output" is NOT the same thing as "one row up from the
         # cursor", and the difference is the bug the user hit:
         #
         #   ls (Format-Table)  output ends \r\n\r\n, so there is a spare blank
         #                      row and stepping up lands on it -> the duration
         #                      gets a line of its own.            <- looks right
         #   cat / node / groovy / bun
         #                      output ends flush, the cursor sits directly below
         #                      the last line, and stepping up lands INSIDE that
         #                      line -> "0.227s line5".            <- the symptom
         #
         # Both cases ran the same ESC[1A, which is why the bug looked like it
         # depended on the command -- and why `ls` "worked" while everything the
         # user actually wanted to time did not. Verified both ways by dumping a
         # real console buffer on 2026-09-28 (_r1_screen.py).
         #
         # So: only step up when there is a blank row to step up into. Otherwise
         # write on the row the cursor already occupies -- the fresh row right
         # below the output, which is exactly "under the output".
         #
         # ICH either way, so the row's own text survives: an overwrite at
         # column 1 would erase it, an insert turns `cd ..` into `0.001s cd ..`.
         #
         # Getting DOWN off the last row: CUD (ESC[nB) on the bottom row may or
         # may not scroll depending on the terminal, and when it does not, the
         # rule that follows overwrites the duration we just wrote -- which is
         # exactly what a fill-the-screen command did before this guard. A
         # literal newline cannot be a no-op, so use it when we are on the last
         # row and there is no blank row above to escape into.
         $blankAbove = $false
         if ($nowY -ge 1) { $blankAbove = Test-WarpRowBlank -Row ($nowY - 1) -Width $w }
         $stepUp = if ($blankAbove) { "$esc[1A" } else { '' }
         $atBottom = ($termH -gt 0) -and ($nowY -ge $termH - 1)
         $down = if ($atBottom -and (-not $blankAbove)) { "`n" } else { "$esc[1B" }
         $writeback = "$stepUp$esc[?7l$esc[0m$esc[G$esc[${need}@$esc[38;2;108;108;108m$dur $esc[0m$esc[?7h$esc[G$down"
         $placement = 'bottom'
      }
      else {
         $inline = " $esc[38;2;108;108;108m$dur$esc[0m"
         $placement = 'inline'
      }
   }
   $global:__WarpUIPlacement = $placement

   # Remember the directory line we are about to draw: its width is where the
   # next prompt will append ITS duration.
   $global:__WarpUIDirCols = Get-WarpVisualWidth $dirLine
   $global:__WarpUIDirFits = ($inline -eq '') -and ($global:__WarpUIDirCols -lt $w)

   $body = "$esc[38;2;${rgb}m$rule$esc[0m`n$dirLine$inline"
   return "$writeback$body`n"
}

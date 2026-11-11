# Live chat view of the Claude <-> Antigravity conversation.
# Usage (from a project folder):  powershell -File "$HOME\.claude\skills\antigravity-team\watch.ps1" [-History]
#   -History   replay everything already in the log before following new messages
param([string]$Log = ".agy\live.log", [switch]$History)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
if (-not (Test-Path $Log)) {
    New-Item -ItemType Directory -Force (Split-Path $Log) | Out-Null
    New-Item -ItemType File $Log | Out-Null
}
$root = (Resolve-Path (Join-Path (Split-Path $Log) "..")).Path.TrimEnd('\') + '\'
Write-Host "Antigravity chat - $((Resolve-Path $Log).Path)  (Ctrl+C to stop)" -ForegroundColor DarkGray

$script:inReply = $false     # currently streaming Antigravity's reply text
$script:replyStarted = $false

function Short([string]$s) {
    if (-not $s) { return "" }
    $s = $s.Replace($root, "").Replace($root.Replace('\', '/'), "")
    if ($s.Length -gt 140) { $s = $s.Substring(0, 140) + "..." }
    return $s
}

function EndReplyLine {
    if ($script:inReply) { Write-Host ""; $script:inReply = $false }
}

function Header([string]$who, [string]$color, [string]$extra, [string]$time) {
    if (-not $time) { $time = Get-Date -Format "HH:mm" }
    Write-Host ""
    Write-Host -NoNewline " $who " -ForegroundColor Black -BackgroundColor $color
    Write-Host "  $time  $extra" -ForegroundColor DarkGray
}

$toolLabels = @{
    write_to_file = "write"; replace_file_content = "edit"; multi_replace_file_content = "edit";
    view_file = "read"; list_dir = "list"; find_by_name = "find"; grep_search = "search";
    run_command = "run"; search_web = "web"; read_url_content = "fetch"
}

$tail = if ($History) { 100000 } else { 0 }
Get-Content $Log -Wait -Tail $tail -Encoding UTF8 | ForEach-Object {
    try { $e = $_ | ConvertFrom-Json } catch { return }

    switch ($e.event) {
        "prompt" {
            EndReplyLine
            $color = if ($e.from -eq "You") { "Magenta" } else { "DarkYellow" }
            Header "$($e.from) -> Antigravity" $color "task  ($($e.model))" $e.time
            $lines = $e.text -split "`n"
            $max = 25
            foreach ($l in ($lines | Select-Object -First $max)) { Write-Host "  $l" }
            if ($lines.Count -gt $max) { Write-Host "  ... ($($lines.Count - $max) more lines)" -ForegroundColor DarkGray }
            $script:replyStarted = $false
            $script:resumed = $false
        }
        "question" {
            EndReplyLine
            $color = if ($e.from -eq "You") { "Magenta" } else { "DarkYellow" }
            Header "$($e.from) asks" $color "side question - task keeps running" $e.time
            foreach ($l in ($e.text -split "`n")) { Write-Host "  $l" }
            if ($script:replyStarted) { $script:replyStarted = $false; $script:resumed = $true }
        }
        "answer" {
            EndReplyLine
            Header "Antigravity answers $($e.to)" "Blue" "($($e.model))" $e.time
            foreach ($l in ($e.text -split "`n")) { Write-Host "  $l" -ForegroundColor White }
            if ($script:replyStarted) { $script:replyStarted = $false; $script:resumed = $true }
        }
        "queued" {
            EndReplyLine
            $color = if ($e.from -eq "You") { "Magenta" } else { "DarkYellow" }
            Header "$($e.from) -> task (queued)" $color "delivered when the current step ends" $e.time
            foreach ($l in ($e.text -split "`n")) { Write-Host "  $l" }
            if ($script:replyStarted) { $script:replyStarted = $false; $script:resumed = $true }
        }
        "notice" {
            EndReplyLine
            Write-Host "`n  ! $($e.text)" -ForegroundColor Yellow
        }
        "step_update" {
            $s = $e.step_update
            if (-not $script:replyStarted -and ($s.step_type -eq "agent_response" -or $s.step_type -eq "tool")) {
                $label = if ($script:resumed) { "working on task (continued)" } else { "working on task" }
                Header "Antigravity" "Cyan" $label
                $script:replyStarted = $true
            }
            if ($s.step_type -eq "tool" -and $s.state -eq "ACTIVE") {
                EndReplyLine
                $p = $s.tool_info.parameters
                $detail = if ($p.CommandLine) { $p.CommandLine }
                          elseif ($p.TargetFile) { $p.TargetFile }
                          elseif ($p.AbsolutePath) { $p.AbsolutePath }
                          elseif ($p.DirectoryPath) { $p.DirectoryPath }
                          elseif ($p.Query) { $p.Query }
                          else { ($p | ConvertTo-Json -Compress -Depth 3) }
                $label = $toolLabels[$s.tool_name]; if (-not $label) { $label = $s.tool_name }
                Write-Host ("  * {0,-7}{1}" -f $label, (Short $detail)) -ForegroundColor DarkCyan
            }
            elseif ($s.step_type -eq "agent_response" -and $s.text_delta) {
                if (-not $script:inReply) { Write-Host -NoNewline "  "; $script:inReply = $true }
                Write-Host -NoNewline ($s.text_delta -replace "`n", "`n  ")
            }
        }
        "result" {
            EndReplyLine
            $r = $e.result
            $ok = $r.status -eq "SUCCESS" -and -not $r.denied_actions
            $color = if ($ok) { "Green" } else { "Red" }
            $mark = if ($ok) { "done" } else { "problem" }
            $msg = "  -- ${mark}: $($r.status), $([math]::Round($r.duration_seconds))s"
            if ($r.denied_actions) { $msg += ", BLOCKED: " + (($r.denied_actions | ForEach-Object { $_.display_name }) -join ", ") }
            Write-Host $msg -ForegroundColor $color
            $script:replyStarted = $false
        }
    }
}

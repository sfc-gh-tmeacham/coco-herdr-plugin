# Report Cortex Code lifecycle state to Herdr (Windows port of herdr-coco-state.sh).
# Does nothing outside a Herdr pane. Never fails the CoCo turn.
# Shipped by the "herdr" CoCo plugin. Invoked via ${CLAUDE_PLUGIN_ROOT}.
$ErrorActionPreference = 'SilentlyContinue'

# Guard: act only inside a Herdr-managed pane.
if ($env:HERDR_ENV -ne '1') { exit 0 }
if ([string]::IsNullOrEmpty($env:HERDR_PANE_ID)) { exit 0 }
if ([string]::IsNullOrEmpty($env:HERDR_BIN_PATH)) { exit 0 }
if (-not (Test-Path -LiteralPath $env:HERDR_BIN_PATH -PathType Leaf)) { exit 0 }

$Source = 'custom:coco'
$Agent = 'coco'
$Pane = $env:HERDR_PANE_ID
$HerdrBin = $env:HERDR_BIN_PATH

# Pane IDs such as "w1:p1" contain ":", which is illegal in Windows file names.
$PaneFile = $Pane -replace ':', '_'

# Monotonic sequence per pane. Herdr keeps the highest accepted --seq per pane
# for the life of the server, so a counter that restarts per session is ignored.
# Use a millisecond timestamp, bumped past the stored value if needed.
$SeqDir = Join-Path ([IO.Path]::GetTempPath()) 'herdr-coco'
try { New-Item -ItemType Directory -Path $SeqDir -Force | Out-Null } catch {}
$SeqFile = Join-Path $SeqDir "seq.$PaneFile"
[long]$Last = 0
try { [long]::TryParse((Get-Content -LiteralPath $SeqFile -Raw).Trim(), [ref]$Last) | Out-Null } catch {}
[long]$Now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
if ($Now -gt $Last) { $Seq = $Now } else { $Seq = $Last + 1 }
try { [IO.File]::WriteAllText($SeqFile, "$Seq") } catch {}

# Hook payload arrives as JSON on stdin.
$Payload = ''
try { $Payload = [Console]::In.ReadToEnd() } catch {}
$Data = $null
try { if ($Payload) { $Data = $Payload | ConvertFrom-Json } } catch { $Data = $null }

function Get-Field {
    # $Name = field name. Returns '' when missing. Nested values are JSON-encoded.
    param([string]$Name)
    if ($null -eq $Data) { return '' }
    $v = $Data.PSObject.Properties[$Name]
    if ($null -eq $v -or $null -eq $v.Value) { return '' }
    $val = $v.Value
    if ($val -is [System.Management.Automation.PSCustomObject] -or $val -is [array]) {
        return ($val | ConvertTo-Json -Compress -Depth 10)
    }
    return [string]$val
}

$Event = Get-Field 'hook_event_name'
if (-not $Event -and $args.Count -gt 0) { $Event = $args[0] }
$SessionId = Get-Field 'session_id'

# Per-pane event log for troubleshooting ($herdr:doctor reads it).
$LogFile = Join-Path $SeqDir "events.$PaneFile.log"
$Stamp = Get-Date -Format 'HH:mm:ss'
try { Add-Content -LiteralPath $LogFile -Value "$Stamp $Event tool=$(Get-Field 'tool_name') [plugin]" } catch {}
try {
    $lines = @(Get-Content -LiteralPath $LogFile)
    if ($lines.Count -gt 400) { Set-Content -LiteralPath $LogFile -Value ($lines | Select-Object -Last 200) }
} catch {}

function Send-Report {
    # $State = Herdr state, $Message = optional text (may contain tool output).
    param([string]$State, [string]$Message = '')
    $a = @('pane', 'report-agent', $Pane,
           '--source', $Source, '--agent', $Agent,
           '--state', $State, '--seq', "$Seq")
    if ($SessionId) { $a += @('--agent-session-id', $SessionId) }
    # $Message is always one argv element. PowerShell never re-parses it.
    if ($Message) { $a += @('--message', $Message) }
    try { & $HerdrBin @a *> $null } catch {}
}

switch ($Event) {
    'SessionStart' { Send-Report 'idle' }
    { $_ -in 'UserPromptSubmit', 'PreToolUse', 'PostToolUse' } { Send-Report 'working' }
    'PermissionRequest' {
        # Fires when CoCo asks permission to run a tool.
        $m = Get-Field 'tool_name'
        if (-not $m) { $m = 'awaiting approval' }
        Send-Report 'blocked' $m
    }
    'Notification' {
        # Fires when CoCo asks the user a question (ask_user_question), which
        # PermissionRequest does not cover. Log the payload for later review.
        try { Add-Content -LiteralPath $LogFile -Value "$Stamp   Notification payload: $Payload" } catch {}
        $m = Get-Field 'message'
        if (-not $m) { $m = 'awaiting input' }
        Send-Report 'blocked' $m
    }
    'Stop' { Send-Report 'idle' }
    'SessionEnd' {
        $a = @('pane', 'release-agent', $Pane, '--source', $Source, '--agent', $Agent, '--seq', "$Seq")
        try { & $HerdrBin @a *> $null } catch {}
    }
    default { }
}

exit 0   # never block a CoCo turn

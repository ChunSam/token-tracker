# Token Tracker status-line bridge (Windows).
#
# The Windows port of scripts/claude-statusline-bridge.sh — same file format,
# same rules. Claude Code hands its status-line command the account's 5-hour and
# 7-day usage percentages on stdin. Token Tracker cannot ask for those itself
# once the access token Claude Code stored has lapsed, because only the CLI
# refreshes it. This script records just those numbers where Token Tracker reads
# them, then runs whatever status-line command you already had, with the same
# stdin, so your status line keeps printing exactly what it printed before.
#
# Install by pointing statusLine.command in %USERPROFILE%\.claude\settings.json
# at this script, with your existing command after `--`:
#
#   "statusLine": {
#     "type": "command",
#     "command": "powershell -NoProfile -ExecutionPolicy Bypass -File C:\\path\\claude-statusline-bridge.ps1 -- node C:\\your\\statusline.js"
#   }
#
# What is written (and nothing else): the two usage percentages, the instant each
# window resets, and two timestamps. No token, no session id, no transcript path,
# no prompt text — the rest of the payload is read and dropped.
#
# Override the destination with TOKEN_TRACKER_STATUSLINE_FILE (used by the tests).
# Set TOKEN_TRACKER_STATUSLINE_DEBUG=1 to have recording failures explain
# themselves on stderr instead of staying silent. The status line reads stdout,
# so this never changes what it shows.

$ErrorActionPreference = 'Continue'

$bridgeVersion = 1
$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

# Everything after the first `--` is the command to run; without a `--`, every
# argument is. Supporting both means a pasted command works either way.
$inner = @($args)
if ($inner.Count -gt 0 -and $inner[0] -eq '--') {
    $inner = @($inner[1..($inner.Count - 1)])
}

$payload = [Console]::In.ReadToEnd()

$outPath = $env:TOKEN_TRACKER_STATUSLINE_FILE
if ([string]::IsNullOrWhiteSpace($outPath)) {
    $outPath = Join-Path (Join-Path $env:APPDATA 'Token Tracker') 'claude-statusline.json'
}

function Get-Field($object, [string]$name) {
    if ($null -eq $object) { return $null }
    $property = $object.PSObject.Properties[$name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

# used_percentage + resets_at, or $null. Both are required: without the reset
# instant there is no way to tell a live window from one that has rolled over,
# and Claude Code drops a window once its reset passes.
function Read-Window($raw, [long]$now) {
    $used = Get-Field $raw 'used_percentage'
    $resets = Get-Field $raw 'resets_at'
    if ($null -eq $used -or $null -eq $resets) { return $null }
    try {
        $usedValue = [double]$used
        $resetsValue = [long]$resets
    } catch {
        return $null
    }
    if ([double]::IsNaN($usedValue) -or [double]::IsInfinity($usedValue)) { return $null }
    if ($resetsValue -le $now) { return $null }
    # A PSCustomObject, not a hashtable: PowerShell enumerates an ordered
    # dictionary on the way out of a function, which would scatter it.
    return [pscustomobject]@{
        used_percentage = $usedValue
        resets_at       = $resetsValue
    }
}

# Recording must never break the status line: no output, and no failure escapes.
# Worst case the file is left as it was.
try {
    $limits = Get-Field ($payload | ConvertFrom-Json -ErrorAction Stop) 'rate_limits'

    $stored = $null
    try {
        if (Test-Path -LiteralPath $outPath) {
            $record = Get-Content -LiteralPath $outPath -Raw -ErrorAction Stop |
                ConvertFrom-Json -ErrorAction Stop
            if ((Get-Field $record 'version') -eq $bridgeVersion) { $stored = $record }
        }
    } catch {
        $stored = $null
    }
    $storedLimits = Get-Field $stored 'rate_limits'

    $merged = New-Object psobject
    $advanced = $false
    foreach ($name in @('five_hour', 'seven_day')) {
        $old = Read-Window (Get-Field $storedLimits $name) $now
        $new = Read-Window (Get-Field $limits $name) $now
        $keep = $old

        # A status-line command re-runs on the CLI's own schedule, so an identical
        # payload is a replay, not a new measurement — the whole point of this file
        # is that a replay must not look fresh. Within one window instance
        # used_percentage only climbs, so a lower value is an older reading (a
        # second session rendering its own slightly staler copy) and must not
        # overwrite a newer one. A different resets_at is a different window
        # instance: always new.
        if ($null -ne $new) {
            if ($null -eq $old `
                -or $old.resets_at -ne $new.resets_at `
                -or $new.used_percentage -gt $old.used_percentage) {
                $keep = $new
                $advanced = $true
            }
        }

        if ($null -ne $keep) {
            Add-Member -InputObject $merged -MemberType NoteProperty -Name $name -Value $keep
        }
    }

    if (@($merged.PSObject.Properties).Count -gt 0) {
        $measured = Get-Field $stored 'measured_at'
        if ($advanced -or $null -eq $measured) {
            $measured = $now
        } else {
            $measured = [long]$measured
        }

        # Nothing moved. The only field left to refresh is written_at, which
        # exists for diagnostics ("the bridge is running, the data is just old")
        # and never for freshness, so once a minute is plenty — a status line can
        # re-render several times a second, and this is not worth that many writes.
        $written = Get-Field $stored 'written_at'
        $skip = $false
        if (-not $advanced -and $null -ne $written) {
            $age = $now - [long]$written
            if ($age -ge 0 -and $age -lt 60) { $skip = $true }
        }

        $out = [pscustomobject]@{
            version     = $bridgeVersion
            provider    = 'claude'
            measured_at = [long]$measured
            written_at  = $now
            rate_limits = $merged
        }

        if (-not $skip) {
            $directory = Split-Path -Parent $outPath
            if (-not (Test-Path -LiteralPath $directory)) {
                New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
            }
            $temp = Join-Path $directory ('.claude-statusline-' + [System.Guid]::NewGuid().ToString('N') + '.tmp')
            [System.IO.File]::WriteAllText(
                $temp,
                (ConvertTo-Json $out -Depth 5),
                (New-Object System.Text.UTF8Encoding $false))
            # Replace in one step, so a reader never sees a half-written file and
            # two sessions finishing at once cannot interleave. The loser loses
            # its update.
            Move-Item -LiteralPath $temp -Destination $outPath -Force -ErrorAction Stop
        }
    }
} catch {
    if ($env:TOKEN_TRACKER_STATUSLINE_DEBUG) {
        [Console]::Error.WriteLine("claude-statusline-bridge: " + $_.Exception.Message)
    }
}

# Your status line, unchanged: same stdin, its stdout, its exit status.
if ($inner.Count -gt 0) {
    $command = $inner[0]
    $rest = @()
    if ($inner.Count -gt 1) { $rest = @($inner[1..($inner.Count - 1)]) }
    $payload | & $command @rest
    if ($null -ne $LASTEXITCODE) { exit $LASTEXITCODE }
}

#!/bin/zsh
# Runs a PowerShell script, read from stdin, inside a UTM Windows VM through the
# guest agent, and prints what it wrote. See docs/windows-vm-testing.md.
#
#   scripts/utm-windows-ps.sh [--user] [timeout-seconds] < script.ps1
#
# --user runs the script as the signed-in Windows user, in their session. The
# guest agent itself runs as SYSTEM with an x64 environment
# (PROCESSOR_ARCHITECTURE=AMD64 on an ARM64 guest), which is the wrong profile
# and the wrong architecture for an installer, so user mode goes through a
# one-shot scheduled task instead.
#
# UTM_VM names the VM (default: Windows).

vm=${UTM_VM:-Windows}
mode=system
if [[ "$1" == "--user" ]]; then
  mode=user
  shift
fi
timeout=${1:-300}
id=$RANDOM$RANDOM
dir='C:\Users\Public'
script="$dir\\tt-$id.ps1"
wrapper="$dir\\tt-$id-run.ps1"
out="$dir\\tt-$id.out"

# Windows PowerShell 5.1 reads a script without a byte-order mark in the system
# code page, which garbles anything outside ASCII.
{ printf '\xef\xbb\xbf'; cat; } | utmctl file push $vm "$script" || exit 1
# `utmctl exec` returns once the process has started, not when it ends, so the
# wrapper leaves a marker with content when the script is done.
printf '%s\r\n' "\$ErrorActionPreference = 'Continue'" \
  "try { & '$script' *> '$out' } catch { \$_ | Out-File -Append '$out' }" \
  "Set-Content -Path '$out.done' -Value \"done \$LASTEXITCODE\"" | utmctl file push $vm "$wrapper"
run="powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $wrapper"

if [[ $mode == user ]]; then
  utmctl exec $vm --cmd powershell.exe -NoProfile -Command \
    "(Get-CimInstance Win32_ComputerSystem).UserName | Set-Content -Encoding ascii '$dir\\tt-$id.user'" >/dev/null
  user=""
  for i in {1..30}; do
    sleep 1
    user=$(utmctl file pull $vm "$dir\\tt-$id.user" 2>/dev/null | tr -d '\r\n')
    [[ -n "$user" ]] && break
  done
  if [[ -z "$user" ]]; then
    echo "no signed-in Windows user found" >&2
    exit 1
  fi
  # A start time in the past makes schtasks warn; the task only ever runs by /run.
  utmctl exec $vm --cmd schtasks.exe /create /f /tn "tt-$id" /sc once /st 00:00 /it /ru "$user" /tr "$run" >/dev/null 2>&1
  sleep 2
  utmctl exec $vm --cmd schtasks.exe /run /tn "tt-$id" >/dev/null
else
  utmctl exec $vm --cmd ${=run} >/dev/null
fi

for i in $(seq 1 $timeout); do
  sleep 1
  # Pulling a file that does not exist still exits 0, so look for content.
  [[ -n "$(utmctl file pull $vm "$out.done" 2>/dev/null)" ]] && break
  [[ $i == $timeout ]] && echo "(timed out after ${timeout}s)" >&2
done

[[ $mode == user ]] && utmctl exec $vm --cmd schtasks.exe /delete /f /tn "tt-$id" >/dev/null
# Windows PowerShell 5.1 writes UTF-16LE with a byte-order mark.
utmctl file pull $vm "$out" 2>/dev/null | iconv -f UTF-16LE -t UTF-8 2>/dev/null | tr -d '\r' \
  | LC_ALL=C sed $'1s/^\xef\xbb\xbf//'
utmctl exec $vm --cmd cmd.exe /c "del /q $dir\\tt-$id*" >/dev/null

# qoder-win-mihomo-pipe-watch.ps1
# Watch live mihomo connections through the Clash Verge named-pipe controller
# (TCP external-controller is often NOT listening in service mode).
# Logs any connection whose host contains 'qoder', whose destination is AWS,
# or that was routed by the fallback (Match) rule - deduplicated.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File qoder-win-mihomo-pipe-watch.ps1 [-Seconds 140] [-LogFile path]
#
# Why HTTP/1.0: over the pipe, mihomo answers HTTP/1.1 with chunked transfer encoding,
# which PowerShell 5.1 ConvertFrom-Json cannot parse. HTTP/1.0 responses are un-chunked.
# ASCII-only on purpose: PowerShell 5.1 mis-parses UTF-8 .ps1 with Chinese comments (no BOM).

param(
    [int]$Seconds = 140,
    [string]$LogFile = (Join-Path $env:TEMP 'qoder_conn.log'),
    [string]$ProxyHost = '127.0.0.1:7897'
)

$ErrorActionPreference = 'SilentlyContinue'

# --- discover the live mihomo pipe (name in verge config files may be stale) ---
$pipeName = [System.IO.Directory]::GetFiles('\\.\pipe\') |
    Where-Object { $_ -match 'verge-mihomo' } | Select-Object -First 1
if (-not $pipeName) { Write-Error 'no verge-mihomo named pipe found; is Clash Verge running?'; exit 1 }
$pipeName = $pipeName.TrimStart('\\.\pipe\')
Write-Host ("[i] using pipe: {0}" -f $pipeName)

# --- read the controller secret from the runtime config (never printed to output) ---
$secret = ''
$cfg = Join-Path $env:APPDATA 'io.github.clash-verge-rev.clash-verge-rev\clash-verge.yaml'
if (Test-Path $cfg) {
    $m = Select-String -Path $cfg -Pattern '(?m)^secret:\s*"?([^"\r\n]+)"?' | Select-Object -First 1
    if ($m) { $secret = $m.Matches[0].Groups[1].Value }
}

function Invoke-PipeHttp([string]$path) {
    $pipe = New-Object System.IO.Pipes.NamedPipeClientStream('.', $pipeName, [System.IO.Pipes.PipeDirection]::InOut)
    $pipe.Connect(2000)
    $auth = if ($secret) { "Authorization: Bearer $secret`r`n" } else { '' }
    $req = "GET $path HTTP/1.0`r`nHost: localhost`r`n$auth`r`n"
    $bytes = [Text.Encoding]::UTF8.GetBytes($req)
    $pipe.Write($bytes, 0, $bytes.Length)
    $pipe.Flush()
    $ms = New-Object System.IO.MemoryStream
    $buf = New-Object byte[] 65536
    try {
        while (($n = $pipe.Read($buf, 0, $buf.Length)) -gt 0) { $ms.Write($buf, 0, $n); if ($ms.Length -gt 8MB) { break } }
    } catch {}
    $pipe.Close()
    [Text.Encoding]::UTF8.GetString($ms.ToArray())
}

Write-Host ("[i] watching {0}s, log: {1}" -f $Seconds, $LogFile)
"watch start $(Get-Date -Format HH:mm:ss)" | Out-File $LogFile -Encoding utf8
$seen = @{}
$deadline = (Get-Date).AddSeconds($Seconds)
while ((Get-Date) -lt $deadline) {
    try {
        $resp = Invoke-PipeHttp '/connections'
        $idx = $resp.IndexOf("`r`n`r`n")
        if ($idx -ge 0) {
            $json = $resp.Substring($idx + 4) | ConvertFrom-Json
            foreach ($c in $json.connections) {
                $m = $c.metadata
                $proc = if ($m.processPath) { $m.processPath.Split('\')[-1] } else { '' }
                $hit = $false
                if ($m.host -match 'qoder') { $hit = $true }                                  # qoder domains
                if ($proc -match 'Qoder') { $hit = $true }                                    # qoder processes
                if ($m.destinationIP -match '^(16\.|18\.|13\.|52\.|54\.|3\.|35\.|43\.20)') { $hit = $true }  # AWS ranges
                if ($c.rule -eq 'Match') { $hit = $true }                                     # fallback group
                if (-not $hit) { continue }
                $key = "$($m.host)|$($m.destinationIP)|$proc|$($c.chains -join '/')"
                if (-not $seen.ContainsKey($key)) {
                    $seen[$key] = $true
                    "$(Get-Date -Format HH:mm:ss.fff) host=$($m.host) dest=$($m.destinationIP):$($m.destinationPort) proc=$proc chains=$($c.chains -join '/') rule=$($c.rule) payload=$($c.rulePayload)" |
                        Out-File $LogFile -Append -Encoding utf8
                }
            }
        }
    } catch {}
    Start-Sleep -Milliseconds 100
}
"DONE $(Get-Date -Format HH:mm:ss)" | Out-File $LogFile -Append -Encoding utf8
Write-Host ("[done] {0} unique hits logged to {1}" -f $seen.Count, $LogFile)

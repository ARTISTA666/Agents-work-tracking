# qoder-win-clash-verge-direct.ps1
# Fix Qoder connectivity on Windows Clash Verge: prepend DOMAIN-SUFFIX DIRECT rules
# for qoder.com / qoder.sh into the CURRENT subscription's rules-override file.
# (Round 5 of the Qoder routing saga; macOS FlClash rounds 1-4 are in records/2026-10-22-*.md)
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File qoder-win-clash-verge-direct.ps1 check
#   powershell -ExecutionPolicy Bypass -File qoder-win-clash-verge-direct.ps1 apply
#   powershell -ExecutionPolicy Bypass -File qoder-win-clash-verge-direct.ps1 rollback
#
# Notes:
# - The override file survives subscription auto-updates (runtime clash-verge.yaml does NOT).
# - apply restarts the Clash Verge GUI to regenerate the runtime config; the mihomo core
#   is managed by clash-verge-service, so existing proxied connections survive.
# - ASCII-only on purpose: PowerShell 5.1 mis-parses UTF-8 .ps1 with Chinese comments (no BOM).

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('check', 'apply', 'rollback')]
    [string]$Action
)

$ErrorActionPreference = 'Stop'
$vergeDir = Join-Path $env:APPDATA 'io.github.clash-verge-rev.clash-verge-rev'
$profilesYaml = Join-Path $vergeDir 'profiles.yaml'
$rules = @('DOMAIN-SUFFIX,qoder.com,DIRECT', 'DOMAIN-SUFFIX,qoder.sh,DIRECT')

function Get-RulesOverrideFile {
    if (-not (Test-Path $profilesYaml)) { throw "profiles.yaml not found: $profilesYaml" }
    $text = Get-Content $profilesYaml -Raw -Encoding UTF8
    $current = [regex]::Match($text, '(?m)^current:\s*(\S+)').Groups[1].Value
    if (-not $current) { throw 'cannot resolve current profile uid' }
    # locate the "- uid: <current>" item block, then its "rules: <uid>" line inside it
    $itemRx = [regex]::Escape($current)
    $block = [regex]::Match($text, "(?ms)- uid:\s*$itemRx.*?(?=^- uid:|\z)").Value
    $rulesUid = [regex]::Match($block, '(?m)^\s*rules:\s*(\S+)').Groups[1].Value
    if (-not $rulesUid) { throw "current profile $current has no rules-override file" }
    return Join-Path $vergeDir "profiles\$rulesUid.yaml"
}

function Test-RulesPresent([string]$content) {
    $missing = @($rules | Where-Object { $content -notmatch [regex]::Escape($_) })
    return ($missing.Count -eq 0), $missing
}

function Restart-Verge {
    Write-Host '[i] restarting Clash Verge GUI to regenerate runtime config ...'
    Stop-Process -Name clash-verge -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-Process (Join-Path ${env:ProgramFiles} 'Clash Verge\clash-verge.exe')
    Start-Sleep -Seconds 9
    $core = Get-Process verge-mihomo -ErrorAction SilentlyContinue
    if ($core) { Write-Host ("[ok] mihomo core running, pid {0}" -f $core.Id) } else { Write-Warning 'mihomo core not detected yet' }
}

function Verify-Proxy {
    foreach ($t in @('https://qoder.com', 'https://center.qoder.sh')) {
        $code = & curl.exe -s -o NUL -w '%{http_code}' -x http://127.0.0.1:7897 --max-time 8 $t
        Write-Host ("[verify] {0} via proxy -> HTTP {1}" -f $t, $code)
    }
}

$file = Get-RulesOverrideFile
$content = Get-Content $file -Raw -Encoding UTF8
$present, $missing = Test-RulesPresent $content
Write-Host ("[i] rules override file: {0}" -f $file)

switch ($Action) {
    'check' {
        if ($present) { Write-Host '[ok] all qoder DIRECT rules present' }
        else { Write-Host ("[!!] missing rules: {0}" -f ($missing -join ', ')); exit 1 }
    }
    'apply' {
        if ($present) { Write-Host '[ok] nothing to do, rules already present'; Verify-Proxy; break }
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $bak = "$file.bak-$stamp"
        Copy-Item $file $bak -Force
        Write-Host "[ok] backup saved: $bak"
        $lines = ($rules | ForEach-Object { "  - $_" }) -join "`r`n"
        if ($content -match '(?m)^prepend:\s*\[\]\s*$') {
            $content = $content -replace '(?m)^prepend:\s*\[\]\s*', "prepend:`r`n$lines"
        }
        elseif ($content -match '(?m)^prepend:\s*$') {
            $content = $content -replace '(?m)^prepend:\s*$', "prepend:`r`n$lines"
        }
        else { throw 'unexpected prepend format; edit the override file manually' }
        Set-Content -Path $file -Value $content -Encoding UTF8
        Write-Host '[ok] rules written'
        Restart-Verge
        Verify-Proxy
    }
    'rollback' {
        $new = $content
        foreach ($r in $rules) { $new = $new -replace ("(?m)^\s*- " + [regex]::Escape($r) + "\s*\r?\n?"), '' }
        if ($new -eq $content) { Write-Host '[ok] nothing to roll back'; break }
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        Copy-Item $file "$file.bak-rollback-$stamp" -Force
        Set-Content -Path $file -Value $new -Encoding UTF8
        Write-Host '[ok] qoder rules removed (backup saved)'
        Restart-Verge
    }
}

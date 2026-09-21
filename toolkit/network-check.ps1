<#
Reports how this machine reaches the internet, and how uv does. Changes
nothing, downloads nothing of consequence, and touches no settings.

Run it as:  .\toolkit\network-check.ps1

Setup reaches the network two different ways, and they can disagree. The tool
downloads go through Windows, which knows this network's proxy settings and can
run an automatic configuration script. uv reads proxy environment variables and
nothing else. When one works and the other does not, this says which.
#>

$Root = Split-Path -Parent $PSScriptRoot
$targets = @(
    'https://github.com',
    'https://objects.githubusercontent.com',
    'https://astral.sh',
    'https://pypi.org'
)

function Show($label, $value) { Write-Host ("  {0,-26} {1}" -f $label, $value) }

Write-Host "`nWindows proxy settings" -ForegroundColor Cyan
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$ie = Get-ItemProperty $key -ErrorAction SilentlyContinue
Show 'ProxyEnable' $(if ($ie.ProxyEnable) { $ie.ProxyEnable } else { '0 (no manual proxy)' })
Show 'ProxyServer' $(if ($ie.ProxyServer) { $ie.ProxyServer } else { '(none)' })
Show 'AutoConfigURL' $(if ($ie.AutoConfigURL) { $ie.AutoConfigURL } else { '(none)' })
Show 'ProxyOverride' $(if ($ie.ProxyOverride) { $ie.ProxyOverride } else { '(none)' })

Write-Host "`nProxy environment variables" -ForegroundColor Cyan
foreach ($n in 'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY') {
    $v = (Get-Item "env:$n" -ErrorAction SilentlyContinue).Value
    Show $n $(if ($v) { $v } else { '(not set)' })
}

Write-Host "`nWhat Windows would use for each address" -ForegroundColor Cyan
$proxies = @{}
foreach ($t in $targets) {
    $answer = '(direct)'
    try {
        $r = [System.Net.WebRequest]::GetSystemWebProxy().GetProxy($t)
        if ($r -and $r.AbsoluteUri -ne ([Uri] $t).AbsoluteUri) {
            $answer = $r.Scheme + '://' + $r.Authority
            $proxies[$answer] = $true
        }
    } catch { $answer = "lookup failed: $($_.Exception.Message)" }
    Show ([Uri]$t).Host $answer
}

Write-Host "`nAre those proxies reachable" -ForegroundColor Cyan
if (-not $proxies.Count) { Show '(none to test)' 'every address resolves direct' }
foreach ($p in $proxies.Keys) {
    $ok = $false
    try {
        $u = [Uri] $p
        $c = New-Object System.Net.Sockets.TcpClient
        $ok = $c.ConnectAsync($u.Host, $u.Port).Wait(3000)
        $c.Close()
    } catch { }
    Show $p $(if ($ok) { 'answers' } else { 'NO ANSWER' })
}

Write-Host "`nCan Windows fetch these (this is how the tools download)" -ForegroundColor Cyan
foreach ($t in $targets) {
    try {
        $null = Invoke-WebRequest -Uri $t -UseBasicParsing -TimeoutSec 20 -Method Head
        Show ([Uri]$t).Host 'reached'
    } catch {
        # Any HTTP status means the server answered, which is the question here.
        # A 404 on a bare hostname is normal and says nothing about reachability.
        $status = $null
        try { $status = [int]$_.Exception.Response.StatusCode } catch { }
        if ($status) { Show ([Uri]$t).Host "reached (HTTP $status)" }
        else { Show ([Uri]$t).Host "COULD NOT CONNECT: $(($_.Exception.Message -split "`n")[0])" }
    }
}

Write-Host "`nCan uv reach the internet (this is what installs Python)" -ForegroundColor Cyan
$uv = Join-Path $Root 'uv\uv.exe'
if (-not (Test-Path $uv)) {
    Show 'uv' 'not installed yet'
} else {
    foreach ($case in @(
        @{ name = 'as configured now'; proxy = $env:HTTPS_PROXY },
        @{ name = 'forced direct';     proxy = '' }
    )) {
        $saved = $env:HTTPS_PROXY, $env:HTTP_PROXY
        if ($case.proxy) { $env:HTTPS_PROXY = $case.proxy; $env:HTTP_PROXY = $case.proxy }
        else { Remove-Item env:HTTPS_PROXY, env:HTTP_PROXY -ErrorAction SilentlyContinue }
        $out = & $uv python list --all-versions 2>&1 | Select-Object -Last 1
        $verdict = if ($LASTEXITCODE -eq 0) { 'ok' } else { "FAILED: $out" }
        Show "$($case.name)" $verdict
        $env:HTTPS_PROXY = $saved[0]; $env:HTTP_PROXY = $saved[1]
    }
}

Write-Host "`nPx" -ForegroundColor Cyan
$px = Join-Path $Root 'px\px.exe'
Show 'installed' (Test-Path $px)
Show 'process running' ([bool](Get-Process px -ErrorAction SilentlyContinue))
$listening = $false
try { $c = New-Object System.Net.Sockets.TcpClient; $listening = $c.ConnectAsync('127.0.0.1', 3128).Wait(1500); $c.Close() } catch { }
Show 'answering on 3128' $listening
if (Test-Path (Join-Path $Root 'px\px.ini')) {
    $server = (Select-String -Path (Join-Path $Root 'px\px.ini') -Pattern '^\s*server\s*=\s*(.*)$').Matches.Groups[1].Value
    Show 'upstream configured' $(if ($server.Trim()) { $server.Trim() } else { '(none - Px will not stay running)' })
}

Write-Host "`nSend this whole output when reporting a network problem.`n" -ForegroundColor Cyan

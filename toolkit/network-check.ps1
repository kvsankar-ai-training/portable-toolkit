<#
Reports how this machine reaches the internet, and how uv does. Changes
nothing, downloads nothing of consequence, and touches no settings.

Run it as:  .\toolkit\network-check.ps1

Setup reaches the network two different ways, and they can disagree. The tool
downloads go through Windows, which knows this network's proxy settings and can
run an automatic configuration script. uv reads proxy environment variables and
nothing else. When one works and the other does not, this says which.
#>
param([string] $StatusLog)
. (Join-Path $PSScriptRoot 'proxy-display.ps1')

if ($StatusLog) {
    # gui.ps1 runs this hidden and reads LOG| lines out of a file, so that the
    # report lands in its log pane next to the Copy button - which is how it
    # reaches whoever can act on it. Shadowing Write-Host sends every line
    # below to both places without the report itself having to know.
    function Write-Host {
        param(
            [Parameter(ValueFromPipeline = $true, Position = 0)] $Object,
            [System.ConsoleColor] $ForegroundColor,
            [switch] $NoNewline
        )
        Microsoft.PowerShell.Utility\Write-Host @PSBoundParameters
        # Split rather than flatten, so the blank line before each heading survives
        try { foreach ($part in (("$Object") -split ("`r?`n"))) { Add-Content -Path $StatusLog -Value ("LOG|" + $part) -ErrorAction Stop } } catch { }
    }
}

# Report on the installed toolkit, not on whichever copy of this script is being
# run. The window runs the copy in the extracted folder, where nothing is
# installed, and the uv checks below would then say "not installed yet".
$Root = Split-Path -Parent $PSScriptRoot
try {
    $manifest = Get-Content (Join-Path $PSScriptRoot 'tools.json') -Raw | ConvertFrom-Json
    foreach ($candidate in @($manifest.install.root, $manifest.install.fallback_root)) {
        if (-not $candidate) { continue }
        $expanded = [Environment]::ExpandEnvironmentVariables(($candidate -replace '/', '\\'))
        if (Test-Path (Join-Path $expanded 'uv\uv.exe')) { $Root = $expanded; break }
    }
} catch { }
$targets = @(
    'https://github.com',
    'https://objects.githubusercontent.com',
    'https://astral.sh',
    'https://pypi.org'
)

function Show($label, $value) { Write-Host ("  {0,-26} {1}" -f $label, (Protect-ProxyText $value)) }

Write-Host "`nWindows proxy settings" -ForegroundColor Cyan
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$ie = Get-ItemProperty $key -ErrorAction SilentlyContinue
Show 'ProxyEnable' $(if ($ie.ProxyEnable) { $ie.ProxyEnable } else { '0 (no manual proxy)' })
Show 'ProxyServer' $(if ($ie.ProxyServer) { Format-ProxyAddress $ie.ProxyServer } else { '(none)' })
Show 'AutoConfigURL' $(if ($ie.AutoConfigURL) { Format-ProxyAddress $ie.AutoConfigURL } else { '(none)' })
Show 'ProxyOverride' $(if ($ie.ProxyOverride) { $ie.ProxyOverride } else { '(none)' })

Write-Host "`nProxy environment variables" -ForegroundColor Cyan
foreach ($n in 'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY') {
    $v = (Get-Item "env:$n" -ErrorAction SilentlyContinue).Value
    Show $n $(if ($v -and $n -ne 'NO_PROXY') { Format-ProxyAddress $v } elseif ($v) { $v } else { '(not set)' })
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

Write-Host "`nWho signed the connection (a company name here means TLS is inspected)" -ForegroundColor Cyan
foreach ($t in $targets) {
    $target = ([Uri] $t).Host
    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        if (-not $client.ConnectAsync($target, 443).Wait(5000)) { Show $target 'no answer on 443'; continue }
        # Accept whatever is presented. The question is who signed it, not
        # whether to trust it, and refusing here would report nothing.
        $ssl = New-Object System.Net.Security.SslStream($client.GetStream(), $false, { $true })
        $ssl.AuthenticateAsClient($target)
        $issuer = $ssl.RemoteCertificate.Issuer
        $ssl.Dispose()
        Show $target ((($issuer -split ',') | Where-Object { $_ -match 'CN=|^\s*O=' }) -join ' ').Trim()
    } catch {
        Show $target "could not look: $(($_.Exception.Message -split "`n")[0])"
    } finally {
        if ($client) { $client.Close() }
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
    $match = Select-String -Path (Join-Path $Root 'px\px.ini') -Pattern '^\s*server\s*=\s*(.*)$' | Select-Object -First 1
    $server = if ($match) { $match.Matches[0].Groups[1].Value } else { '' }
    Show 'upstream configured' $(if ($server.Trim()) { Format-ProxyAddress $server.Trim() } else { '(none - Px will not stay running)' })
}

Write-Host "`nSend this whole output when reporting a network problem.`n" -ForegroundColor Cyan

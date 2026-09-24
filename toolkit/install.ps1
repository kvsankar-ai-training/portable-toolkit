#Requires -Version 5.1
<#
Installs Git, Node, uv and Python into a tools folder of their own, then adds
that folder to your user PATH so the tools work by name in any window.

It does not install into the folder you extracted. That folder is only the
installer, and you can delete it afterwards.

Running it again only installs what is missing.
#>

param(
    # Overrides install.root from tools.json. Exists so the shipped manifest can
    # be tested without editing it, which is how a bad default slipped through.
    [string] $Root,

    # Skips the "Add them? [Y/n]" prompt and proceeds as if Enter was pressed,
    # so this can be run from something other than an interactive console, such
    # as gui.ps1. Everything else behaves exactly the same.
    [switch] $Unattended
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # without this, downloads are very slow
. (Join-Path $PSScriptRoot 'proxy-display.ps1')

# A proxy that demands NTLM or Kerberos answers 407 to anything that does not
# offer credentials, and by default .NET offers none. A browser passes because
# it uses your logged-in session; this makes the downloads below do the same.
# Without it the very first download fails on a corporate network, which is a
# chicken-and-egg problem, because px - the tool that would solve it - is one
# of the things being downloaded.
try {
    [System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
} catch { }

function Test-ProxyReachable($ProxyUri) {
    # Is anything actually accepting connections there? A proxy address that
    # nothing answers on turns a download that would have worked into a
    # connection error, so it is worth one second to find out.
    try {
        $uri = [Uri] $ProxyUri
        $client = New-Object System.Net.Sockets.TcpClient
        $ok = $client.ConnectAsync($uri.Host, $uri.Port).Wait(1500)
        $client.Close()
        return $ok
    } catch { return $false }
}

# A proxy variable left pointing at something that is not running takes the
# whole install down with it: uv reads these for itself, and so does
# Invoke-WebRequest on PowerShell 7, so neither can be talked out of it by
# argument. They are commonly set to a local relay such as Px that is needed
# for some other program and is not running at the moment.
#
# Clearing them here affects this process only. Windows still knows how to
# reach the internet - directly, through a configured proxy, or through an
# automatic configuration script - and that is what gets used instead.
foreach ($name in 'HTTPS_PROXY', 'HTTP_PROXY', 'ALL_PROXY') {
    $value = (Get-Item "env:$name" -ErrorAction SilentlyContinue).Value
    if (-not $value) { continue }
    if (Test-ProxyReachable $value) { continue }
    Write-Host "  $name is set to $(Format-ProxyAddress $value), which is not answering - ignoring it for this install" -ForegroundColor Yellow
    Remove-Item "env:$name" -ErrorAction SilentlyContinue
}

$Source = $PSScriptRoot
$config = Get-Content (Join-Path $Source 'tools.json') -Raw | ConvertFrom-Json
. (Join-Path $Source 'paths.ps1')

# A parseable line per step, beside install.ps1 itself so it exists regardless
# of where the install root ends up. A caller that wants granular progress
# (gui.ps1) tails this file; a console run ignores it and reads Write-Host as
# always. Reset on every run so a caller never reads a previous run's lines.
# Progress reporting must never be the reason an install fails, so a folder that
# cannot be written to costs the granular progress and nothing else.
$StatusLog = Join-Path $Source 'install.status.log'
try { Set-Content -Path $StatusLog -Value $null -ErrorAction Stop } catch { $StatusLog = $null }
function Write-Status {
    param([string] $Name, [string] $State, [string] $Detail = '')
    if (-not $StatusLog) { return }
    try { Add-Content -Path $StatusLog -Value "STATUS|name=$Name|state=$State|detail=$(Protect-ProxyText $Detail)" -ErrorAction Stop } catch { }
}

function Write-LogLine {
    # Anything a console user would read as it scrolls past. A caller showing a
    # window (gui.ps1) has no other way to see it, because it runs this script
    # hidden - so the long steps would otherwise look like nothing happening.
    param([string] $Text)
    if (-not $StatusLog) { return }
    $clean = (Protect-ProxyText ($Text -replace '[\r\n]', ' ')).Trim()
    if (-not $clean) { return }
    try { Add-Content -Path $StatusLog -Value "LOG|$clean" -ErrorAction Stop } catch { }
}

# A zip downloaded from the internet marks every file it extracts, and the mark
# can stop scripts running. Clear it on our own files before doing anything else.
Get-ChildItem (Split-Path -Parent $Source) -Recurse -File | Unblock-File -ErrorAction SilentlyContinue

function Select-InstallRoot {
    # C:\tools if the machine allows it, the user profile if it does not.
    $candidates = if ($Root) { @($Root) } else { @($config.install.root, $config.install.fallback_root) }
    foreach ($candidate in $candidates) {
        # A tab or a newline here means a single backslash in tools.json, where
        # JSON reads \t as a tab. Name that cause rather than letting Windows
        # report a puzzling "Illegal characters in path" from deeper down.
        if ($candidate -match '[\x00-\x1f]') {
            throw ("Install path in tools.json contains a control character: '$($candidate -replace '[\x00-\x1f]', '?')'. " +
                   "A Windows path in JSON needs doubled backslashes, or forward slashes instead.")
        }
        $path = [Environment]::ExpandEnvironmentVariables($candidate)
        try {
            if (-not (Test-Path $path)) { New-Item -ItemType Directory $path -ErrorAction Stop | Out-Null }
            $probe = Join-Path $path '.write-probe'
            Set-Content $probe 'x' -ErrorAction Stop
            Remove-Item $probe -Force
            return (Get-Item $path).FullName
        } catch {
            Write-Host "  $path is not usable: $($_.Exception.Message)" -ForegroundColor DarkGray
        }
    }
    throw "No writable install location. Tried $($config.install.root) and $($config.install.fallback_root)."
}

function Test-ToolRuns($tool) {
    # Actually run it. Only meaningful straight after installing, when nothing
    # else is holding the folder - see Test-Tool for why this is not the check
    # used to decide whether a tool needs installing.
    $exe = Join-Path $InstallRoot ($tool.verify[0] -replace '/', '\')
    if (-not (Test-Path $exe)) { return $false }
    try { & $exe $tool.verify[1] *> $null; return ($LASTEXITCODE -eq 0) } catch { return $false }
}

function Get-VersionStampPath($tool) {
    Join-Path (Join-Path $InstallRoot $tool.target) '.installed-version'
}

function Test-Tool($tool) {
    # Is this tool already installed at the version the manifest asks for?
    #
    # Deciding that by running the tool looks obvious and is wrong. px exits
    # non-zero when another copy of itself is already running, so asking px
    # whether it is installed says no precisely when it is installed and in
    # use - and setup would then try to replace files that running copy holds
    # open, which Windows refuses. A version recorded at install time answers
    # the question without launching anything.
    $exe = Join-Path $InstallRoot ($tool.verify[0] -replace '/', '\')
    if (-not (Test-Path $exe)) { return $false }

    $stamp = Get-VersionStampPath $tool
    if (Test-Path $stamp) {
        $recorded = (Get-Content $stamp -Raw -ErrorAction SilentlyContinue)
        return (($recorded -replace '\s', '') -eq $tool.version)
    }

    # No stamp: installed before stamps existed, so fall back to asking it.
    Test-ToolRuns $tool
}


function Start-PxRelay($Root, $Upstream) {
    # Px answers the proxy's authentication challenge using your Windows session
    # and presents a plain, unauthenticated proxy on 127.0.0.1:3128. uv cannot
    # answer such a challenge itself, so on a proxy that demands one this is the
    # difference between uv working and not.
    #
    # Returns the address to use, or nothing if Px cannot be made to serve.
    $px = Join-Path $Root 'px\px.exe'
    if (-not (Test-Path $px)) { return $null }

    $local = 'http://127.0.0.1:3128'
    if (-not $Upstream) { return $null }
    $hostPort = ([Uri] $Upstream).Authority
    $ini = Join-Path $Root 'px\px.ini'
    $saved = $null
    if (Test-Path $ini) {
        $line = Get-Content $ini -ErrorAction SilentlyContinue | Where-Object { $_ -match '^\s*server\s*=\s*(\S+)' } | Select-Object -First 1
        if ($line) { $saved = ($line -replace '^\s*server\s*=\s*', '').Trim() }
    }

    # A listening port alone does not prove that it is this Px. Restart our Px
    # even when the file looks right: it may still be running with older
    # settings loaded before the file was changed.
    $owned = @(Get-Process px -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -eq $px } catch { $false }
    })
    $listening = Test-ProxyReachable $local
    if ($listening -and -not $owned.Count) { return $null }

    if ($owned.Count) {
        Write-Host "  restarting px for this network's proxy"
        & $px --quit *> $null
        for ($i = 0; $i -lt 10; $i++) {
            if (-not (Test-ProxyReachable $local)) { break }
            Start-Sleep -Milliseconds 200
        }
        if (Test-ProxyReachable $local) { return $null }
    }

    if ($saved -ne $hostPort) {
        Write-Host "  configuring px for this network's proxy: $hostPort"
        & $px --save --proxy=$hostPort *> $null
        if ($LASTEXITCODE -ne 0) { return $null }
    }

    Write-Host "  starting px so uv can get through the proxy"
    try { Start-Process -FilePath $px -WorkingDirectory (Split-Path $px) -WindowStyle Hidden } catch { return $null }

    # It binds a port; that is not instant.
    for ($i = 0; $i -lt 10; $i++) {
        Start-Sleep -Milliseconds 700
        if (Test-ProxyReachable $local) { return $local }
    }
    $null
}

function Get-SystemProxyFor($Uri) {
    # What Windows itself would use to reach this address, including working
    # through an automatic configuration script. Returns nothing when the
    # answer is to go direct.
    try {
        $resolved = [System.Net.WebRequest]::GetSystemWebProxy().GetProxy($Uri)
        if ($resolved -and $resolved.AbsoluteUri -ne ([Uri] $Uri).AbsoluteUri) {
            return ($resolved.Scheme + '://' + $resolved.Authority)
        }
    } catch { }
    $null
}

function Get-DownloadArgs($Uri, $OutFile) {
    # Windows already knows how to reach the internet here - directly, through a
    # configured proxy, or through whatever a PAC script decides per address -
    # so the normal case is to let it decide and simply offer the logged-in
    # session's credentials in case the proxy asks for them.
    #
    # HTTPS_PROXY is honoured only if something is listening on it. It is often
    # set to a local relay like Px that is needed for some other program, and a
    # relay that is not running would otherwise take downloads down with it.
    # -ProxyUseDefaultCredentials is rejected unless -Proxy is given too, which
    # is why this is built per download rather than set once.
    $splat = @{ Uri = $Uri; OutFile = $OutFile; UseBasicParsing = $true }

    # Which of those picked it matters when it then misbehaves: a stale
    # HTTPS_PROXY is yours to fix, a proxy an automatic configuration script
    # chose is not, and the two need different answers. Record it here, where
    # it is known, so a failure can say so.
    $proxy = $null
    $script:ProxyOrigin = ''
    if ($env:HTTPS_PROXY -and (Test-ProxyReachable $env:HTTPS_PROXY)) {
        $proxy = $env:HTTPS_PROXY
        $script:ProxyOrigin = 'from the HTTPS_PROXY setting'
    } else {
        try {
            $resolved = [System.Net.WebRequest]::GetSystemWebProxy().GetProxy($Uri)
            if ($resolved -and $resolved.AbsoluteUri -ne $Uri) {
                $proxy = $resolved.AbsoluteUri
                $ie = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
                $script:ProxyOrigin = if ($ie.AutoConfigURL) { "chosen by the automatic configuration script at $(Format-ProxyAddress $ie.AutoConfigURL)" }
                                      else { 'from this machine''s Windows proxy setting' }
            }
        } catch { }
    }

    if ($proxy) {
        $splat.Proxy = $proxy
        $splat.ProxyUseDefaultCredentials = $true
    }
    $splat
}

function Stop-RunningFrom($Folder) {
    # A program that is running holds its own files open, and Windows refuses to
    # replace or delete them - reinstalling px over a running px fails on the
    # .pyd inside its bundled Python. Returns what was stopped so the caller can
    # start it again afterwards; px in particular is how this machine reaches
    # the internet, so leaving it stopped would break the rest of the install.
    $stopped = @()
    if (-not (Test-Path $Folder)) { return $stopped }
    $full = (Get-Item $Folder).FullName.TrimEnd('\')

    foreach ($proc in (Get-Process -ErrorAction SilentlyContinue)) {
        $path = try { $proc.Path } catch { $null }
        if (-not $path) { continue }
        if (-not $path.StartsWith("$full\", [System.StringComparison]::OrdinalIgnoreCase)) { continue }

        Write-Host "  stopping $($proc.ProcessName), which is running from this folder"
        $stopped += $path
        if ($proc.ProcessName -eq 'px') { & $path --quit *> $null }   # px shuts down cleanly and frees its port
        Start-Sleep -Milliseconds 500
        try { if (-not $proc.HasExited) { $proc | Stop-Process -Force -ErrorAction Stop } } catch { }
    }
    if ($stopped.Count) { Start-Sleep -Milliseconds 800 }
    $stopped
}

function Restart-Stopped($tool, $wasRunning) {
    # Only the tool itself: the others were its children - px runs its own
    # bundled python - and starting one of those alone leaves a stray process.
    $main = Join-Path $InstallRoot ($tool.verify[0] -replace '/', '\')
    if (($wasRunning -contains $main) -and (Test-Path $main)) {
        Write-Host "  restarting $($tool.name)"
        try { Start-Process -FilePath $main -WorkingDirectory (Split-Path $main) -WindowStyle Hidden } catch { }
    }
}

function Get-HttpStatus($ErrorRecord) {
    # What the other end answered, if it answered at all. Normally the response
    # object carries it; when it does not, the message still spells it out, as
    # in "The remote server returned an error: (502) Bad Gateway."
    try {
        $code = [int] $ErrorRecord.Exception.Response.StatusCode
        if ($code) { return $code }
    } catch { }
    if ("$($ErrorRecord.Exception.Message)" -match '\((?<code>[1-5]\d\d)\)') { return [int] $Matches.code }
    return $null
}

function Install-Tool($tool) {
    Write-Status $tool.name 'downloading'
    $zip = Join-Path $env:TEMP "portable-toolkit-$($tool.name).zip"
    Write-Host "  downloading $($tool.url)"
    $download = Get-DownloadArgs $tool.url $zip
    $hadProxy = $download.ContainsKey('Proxy')
    $via = if ($hadProxy) { "$(Format-ProxyAddress $download.Proxy) ($script:ProxyOrigin)" } else { 'no proxy - straight out' }
    Write-Host "  via $via"

    try {
        Invoke-WebRequest @download
    } catch {
        $status = Get-HttpStatus $_
        $detail = (Protect-ProxyText (($_.Exception.Message -split "`n")[0])).Trim().TrimEnd('.')

        # A 5xx comes from the proxy, not from the site: it took the request and
        # could not complete it. Whatever the reason - the site blocked by
        # policy, the proxy unable to reach it, or the proxy simply wrong for
        # this address - going straight out is worth one attempt before giving
        # up, and costs a second when it fails too.
        $recovered = $false
        if ($status -ge 500 -and $hadProxy) {
            Write-Host "  $via returned $status; trying without it" -ForegroundColor Yellow
            Write-LogLine "$via returned $status for $($tool.name); retrying without a proxy."
            try {
                Invoke-WebRequest -Uri $tool.url -OutFile $zip -UseBasicParsing -TimeoutSec 30
                Write-Host "  that worked - the proxy was the problem, not the network" -ForegroundColor Green
                Write-LogLine "Downloading without the proxy worked."
                $recovered = $true
            } catch {
                $status = Get-HttpStatus $_
                $detail = (Protect-ProxyText (($_.Exception.Message -split "`n")[0])).Trim().TrimEnd('.')
            }
        }

        if (-not $recovered) {
            # Say who refused, and only blame a proxy when one was actually used.
            $refuser = if ($hadProxy) { "The proxy" } else { "That address" }
            $advice =
                if ($status -eq 407) {
                    "A proxy is asking for credentials this script cannot supply. Px exists for that: set it up in the GUI, or with run.cmd px --save --proxy=host:port, then run setup again."
                } elseif ($status -eq 403) {
                    "$refuser refused the request. That is usually policy rather than a fault, and a question for whoever runs the network."
                } elseif ($status -ge 500 -and $hadProxy) {
                    "The proxy took the request and could not complete it, and going straight out failed too. That points at the proxy or at what it is allowed to reach, not at this script."
                } elseif ($status -ge 500) {
                    "The site itself answered with a server error, which is usually temporary. Try again in a few minutes."
                } elseif (-not $status) {
                    "Nothing answered at all, so this never got as far as an HTTP reply."
                } else { "" }

            throw ("$($tool.name): could not download $($tool.url)" +
                   $(if ($status) { " - HTTP $status" } else { " - $detail" }) +
                   ". Tried via $via. $advice Run toolkit\network-check.ps1 and send its output.")
        }
    }

    # Refuse to install anything whose contents do not match the published hash.
    $actual = (Get-FileHash $zip -Algorithm SHA256).Hash
    if ($actual -ne $tool.sha256.ToUpper()) {
        Remove-Item $zip -Force
        throw "$($tool.name): checksum mismatch. Expected $($tool.sha256), got $actual."
    }
    Write-Host "  checksum matches the one published at $($tool.sha256_source)"
    Write-Status $tool.name 'verified'

    $dest = Join-Path $InstallRoot $tool.target
    $wasRunning = Stop-RunningFrom $dest
    if (Test-Path $dest) {
        try {
            Remove-Item $dest -Recurse -Force -ErrorAction Stop
        } catch {
            # Something in there is still open and would not let go. If a usable
            # copy is already installed, that is not worth failing the whole run
            # for - keep it and carry on, so the rest of the toolkit still gets
            # set up. Only a folder with nothing usable in it is fatal.
            $exe = Join-Path $InstallRoot ($tool.verify[0] -replace '/', '\')
            if (Test-Path $exe) {
                Write-Host "  in use and cannot be replaced - keeping the copy already installed" -ForegroundColor Yellow
                Write-LogLine "$($tool.name) is in use, so the installed copy was kept rather than replaced."
                Write-Status $tool.name 'kept' 'in use, existing copy kept'
                if (Test-Path $zip) { Remove-Item $zip -Force }
                Restart-Stopped $tool $wasRunning
                return
            }
            throw ("$($tool.name): cannot replace $dest because something has files there open. " +
                   "Close it and run setup again. " + $_.Exception.Message)
        }
    }

    if ($tool.archive -eq 'none') {
        # Not an archive at all, just the executable. jq is published this way.
        New-Item -ItemType Directory $dest -Force | Out-Null
        Move-Item $zip (Join-Path $dest $tool.file_name) -Force
    } elseif ($tool.strip_root) {
        # This archive wraps everything in one folder; unwrap it so paths stay short.
        $stage = Join-Path $env:TEMP "portable-toolkit-$($tool.name)-stage"
        if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
        Expand-Archive -Path $zip -DestinationPath $stage -Force
        Move-Item (Get-ChildItem $stage -Directory | Select-Object -First 1).FullName $dest
        Remove-Item $stage -Recurse -Force
    } else {
        Expand-Archive -Path $zip -DestinationPath $dest -Force
    }

    # Already gone when the download was the executable itself and was moved.
    if (Test-Path $zip) { Remove-Item $zip -Force }

    if (-not (Test-ToolRuns $tool)) { throw "$($tool.name): installed, but it does not run." }
    Set-Content -Path (Get-VersionStampPath $tool) -Value $tool.version -Encoding ASCII
    Write-Host "  installed and runs" -ForegroundColor Green
    Write-Status $tool.name 'installed'

    # Started last, so the verification above ran with nothing of this tool's
    # already up - which is the state px needs to report success.
    Restart-Stopped $tool $wasRunning
}

function Write-UvEvents($SourceId, $Output) {
    # DataReceived events are queued in this PowerShell runspace. Drain them
    # while uv is running so the GUI receives each completed line promptly.
    foreach ($event in @(Get-Event -SourceIdentifier $SourceId -ErrorAction SilentlyContinue)) {
        $line = $event.SourceEventArgs.Data
        if ($null -ne $line -and $line -ne '') {
            Write-Host "  $(Protect-ProxyText $line)" -ForegroundColor DarkGray
            Write-LogLine $line
            $Output.Add($line)
        }
        Remove-Event -EventIdentifier $event.EventIdentifier
    }
}

function Invoke-Uv {
    # Stream uv's completed lines through PowerShell's event queue. A normal
    # pipe forwards lines but cannot show anything when uv is silent for
    # minutes; the heartbeat below makes that wait visible in the GUI.
    $uv = Join-Path $InstallRoot 'uv\uv.exe'
    $uvArgs = @($args)
    if ($uvArgs.Count -ge 2 -and $uvArgs[0] -eq 'pip' -and $uvArgs[1] -eq 'install') {
        $uvArgs = @('-v') + $uvArgs
    }
    $arguments = ($uvArgs | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ' '
    $output = New-Object System.Collections.Generic.List[string]
    $started = Get-Date
    $lastHeartbeat = $started
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $uv
    $psi.Arguments = $arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    $outId = 'portable-toolkit-uv-out-' + [guid]::NewGuid().ToString('N')
    $errId = 'portable-toolkit-uv-err-' + [guid]::NewGuid().ToString('N')
    try {
        Register-ObjectEvent -InputObject $process -EventName OutputDataReceived -SourceIdentifier $outId | Out-Null
        Register-ObjectEvent -InputObject $process -EventName ErrorDataReceived -SourceIdentifier $errId | Out-Null
        [void] $process.Start()
        $process.BeginOutputReadLine()
        $process.BeginErrorReadLine()
        while (-not $process.HasExited) {
            Write-UvEvents $outId $output
            Write-UvEvents $errId $output
            if (((Get-Date) - $lastHeartbeat).TotalSeconds -ge 15) {
                $elapsed = [int] ((Get-Date) - $started).TotalSeconds
                $message = "uv is still working ($elapsed seconds elapsed)."
                Write-Host "  $message" -ForegroundColor DarkGray
                Write-LogLine $message
                $lastHeartbeat = Get-Date
            }
            Start-Sleep -Milliseconds 500
        }
        $process.WaitForExit()
        Write-UvEvents $outId $output
        Write-UvEvents $errId $output
        $code = $process.ExitCode
    } finally {
        Unregister-Event -SourceIdentifier $outId -ErrorAction SilentlyContinue
        Unregister-Event -SourceIdentifier $errId -ErrorAction SilentlyContinue
        $process.Dispose()
    }
    if ($code -ne 0) {
        $hint = ''
        $outputText = $output -join "`n"
        if ($outputText -match 'Timeout \(\d+s\) when waiting for lock') {
            $hint = " Another uv process is holding the Python install folder. Close any other toolkit setup or uv operation, check for a remaining uv.exe process, then run setup again. Do not delete the .lock file."
        } elseif ($outputText -match 'UnknownIssuer|invalid peer certificate|certificate verify failed') {
            $hint = " That is a certificate uv does not recognise, which is what a network that inspects TLS looks like. " +
                    "uv is already told to use this machine's certificate store; if it still fails, the company authority " +
                    "is missing from your user store. Run toolkit\network-check.ps1 - it names who signed the connection."
        } elseif ($outputText -match 'operation timed out|timed out') {
            $hint = " A uv download timed out. Retry setup once; uv keeps successful downloads in its cache. " +
                    "If the same host times out again, ask the network team to check that download through Px."
        } elseif ($outputText -match 'HTTP 407|Proxy Authentication Required|proxy authorization') {
            $hint = " The proxy asked uv to authenticate. Check that Px is configured and running for this network, then run setup again."
        } elseif (-not $env:HTTPS_PROXY) {
            $hint = " If this is a DNS or connection error, uv may need the proxy address for this network: " +
                    "set HTTPS_PROXY and run setup again."
        } elseif ($code -ne 0) {
            $hint = " Run toolkit\network-check.ps1 and send the full error so the failed address can be diagnosed."
        }
        throw ("uv $($args -join ' ') failed with exit code $code." + $hint)
    }
}

function Get-CompatiblePython {
    # Reuse a working Python already on PATH before downloading another one.
    # uv will still create the toolkit's isolated environment from it.
    $minimum = [version] $config.python.minimum_version
    $maximum = [version] $config.python.maximum_version_exclusive
    foreach ($command in @(Get-Command python -All -CommandType Application -ErrorAction SilentlyContinue)) {
        $exe = $command.Source
        if (-not $exe -or -not (Test-Path $exe)) { continue }
        # env.ps1 puts every toolkit tool on PATH. Px bundles a private
        # python.exe, which is not the participant's Python to build from.
        if ($exe.StartsWith($InstallRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { continue }
        try {
            $version = & $exe --version 2>&1 | Select-Object -First 1
            if ("$version" -match '^Python (?<minor>3\.\d+)\.\d+') {
                $minor = [version] $Matches.minor
                if ($minor -ge $minimum -and $minor -lt $maximum) { return $exe }
            }
        } catch { }
    }
    return $null
}

function Test-OfflinePython($Python) {
    # The release's offline wheels target CPython 3.13 on Windows x64.
    try {
        $tag = & $Python -c 'import sys; print(sys.implementation.name, sys.version_info.major, sys.version_info.minor, int(sys.maxsize > 2**32))' 2>$null
        return ("$tag".Trim() -eq 'cpython 3 13 1')
    } catch { return $false }
}

function Export-WindowsRootCertificates($Path) {
    # The same TLS inspection that stops uv stops pip, and for the same reason:
    # pip trusts the bundle inside certifi and nothing else. Hand it the
    # authorities this machine already trusts. Nothing is weakened - these are
    # read straight out of the Windows store.
    $folder = Split-Path -Parent $Path
    if (-not (Test-Path $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }

    $lines = @()
    foreach ($store in 'Cert:\LocalMachine\Root', 'Cert:\CurrentUser\Root') {
        foreach ($certificate in (Get-ChildItem $store -ErrorAction SilentlyContinue)) {
            $lines += '-----BEGIN CERTIFICATE-----'
            $lines += [Convert]::ToBase64String($certificate.RawData, 'InsertLineBreaks')
            $lines += '-----END CERTIFICATE-----'
        }
    }
    if (-not $lines) { return $null }
    Set-Content -Path $Path -Value $lines -Encoding ascii
    return $Path
}

function Install-MachinePythonPackages($packages, $offlineWheelhouse = $null, $offlineLock = $null) {
    # A Python installed for all users answers to "python" whatever this install
    # does, because Windows reads the machine PATH first. An assistant types
    # "python", so on those machines the document libraries have to be where
    # that Python looks, or every one of them fails to import.
    #
    # --user puts them under this account's profile: no administrator rights, no
    # change to anything outside the profile, and pip uninstall reverses it. The
    # toolkit's own environment is untouched and still complete.
    $machinePython = Get-MachineWidePython
    if (-not $machinePython) {
        Write-Status 'machine-python' 'not-needed'
        return
    }

    if ($offlineWheelhouse -and -not (Test-OfflinePython $machinePython)) {
        Write-LogLine 'The machine-wide Python is not 64-bit Python 3.13; the offline wheels were not added to it. The toolkit environment remains complete.'
        Write-Status 'machine-python' 'skipped' 'offline wheels do not match the machine-wide Python'
        return
    }

    Write-Host "`nA Python installed for all users answers to 'python' here:" -ForegroundColor Yellow
    Write-Host "  $machinePython" -ForegroundColor Yellow
    Write-Host "  Windows reads the machine PATH before yours, so that one wins by name."
    Write-Host "  Adding the same document libraries to it, under your profile only."
    Write-LogLine "A machine-wide Python wins by name here: $machinePython"
    Write-LogLine "Adding the document libraries to it with pip --user, so a bare 'python' can read documents."
    Write-Status 'machine-python' 'installing' 'adding the libraries to the machine Python'

    $pem = Export-WindowsRootCertificates (Join-Path $InstallRoot 'certs\windows-roots.pem')
    $arguments = @('-m', 'pip', 'install', '--user', '--disable-pip-version-check', '--no-warn-script-location')
    if ($pem) { $arguments += @('--cert', $pem) }
    if ($offlineWheelhouse) {
        $arguments += @('--no-index', '--find-links', $offlineWheelhouse, '-r', $offlineLock)
    } else {
        $arguments += $packages
    }

    # What that Python already had, so a later removal takes out only what
    # this added. Several of these packages are common enough to be there
    # already, and uninstalling someone's existing pandas would be worse than
    # useless.
    $listing = "import importlib.metadata as m; print('|'.join(sorted(set(d.metadata['Name'] for d in m.distributions() if d.metadata['Name']))))"
    $before = @((& $machinePython -c $listing 2>$null) -split '\|' | Where-Object { $_ })

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $machinePython @arguments 2>&1 | ForEach-Object { Write-Host "  $(Protect-ProxyText $_)" -ForegroundColor DarkGray; Write-LogLine $_ }
    $code = $LASTEXITCODE
    $ErrorActionPreference = $previous

    if ($code -ne 0) {
        # Not fatal. The toolkit's own Python is installed and complete; what
        # failed is an addition to someone else's interpreter.
        Write-Host "  that did not work (exit code $code). The toolkit's own Python is unaffected." -ForegroundColor Yellow
        Write-LogLine "Adding the libraries to the machine Python failed with exit code $code. Use run.cmd python instead."
        Write-Status 'machine-python' 'error' "pip exited $code - use run.cmd python instead"
        return
    }

    $after = @((& $machinePython -c $listing 2>$null) -split '\|' | Where-Object { $_ })
    $added = @($after | Where-Object { $before -notcontains $_ })
    if ($added.Count) {
        Write-Host "  added to it: $($added -join ', ')" -ForegroundColor DarkGray
        Write-LogLine "Added to the machine Python: $($added -join ', ')"
    }

    $record = [PSCustomObject]@{
        python    = $machinePython
        packages  = $packages
        added     = $added
        installed = (Get-Date).ToString('s')
    }
    $record | ConvertTo-Json | Set-Content -Path (Get-MachinePythonMarker $InstallRoot) -Encoding utf8
    Write-Host "  done - a bare 'python' can now read documents too" -ForegroundColor Green
    Write-Status 'machine-python' 'installed'
}

function Show-MachineWideTools {
    # Windows reads the system PATH before the user PATH, and setup can only
    # write the user half. Anything already installed for all users will keep
    # winning by name after this install, so say so before downloading 300 MB.
    $machinePaths = ([Environment]::GetEnvironmentVariable('Path', 'Machine') -split ';') |
        Where-Object { $_ } | ForEach-Object { $_.Trim().TrimEnd('\') }

    $found = @()
    foreach ($name in (@($config.tools | ForEach-Object { $_.name }) + 'python')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $cmd -or -not $cmd.Source) { continue }
        if ($machinePaths -contains (Split-Path -Parent $cmd.Source).TrimEnd('\')) {
            $found += "  {0,-6} {1}" -f $name, $cmd.Source
        }
    }
    if (-not $found) { return }

    Write-Host "Already installed for all users on this machine:" -ForegroundColor Yellow
    $found | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
    Write-Host ""
    Write-Host "Windows reads the system PATH before yours, so after this install a plain" -ForegroundColor Yellow
    Write-Host "'python' or 'node' will still reach those, not the toolkit's copy. Only an" -ForegroundColor Yellow
    Write-Host "administrator can change that. The toolkit's copies are still reached with" -ForegroundColor Yellow
    Write-Host "run.cmd, or by their full path, and check.ps1 reports which is which." -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "`nportable-toolkit $($config.version)"
Write-Status 'overall' 'starting'

$InstallRoot = Select-InstallRoot
Write-Host "`nInstalling into $InstallRoot`n"
Show-MachineWideTools

try {

foreach ($tool in $config.tools) {
    Write-Host "$($tool.name) $($tool.version)"
    if (Test-Tool $tool) {
        Write-Host "  already installed" -ForegroundColor DarkGray
        Write-Status $tool.name 'already-installed'
    } else {
        Install-Tool $tool
    }
}

# Also before Python, and for the same reason: this is what makes the install
# folder describe itself. Without it a failure later leaves no check.ps1 or
# uninstall.ps1 beside the tools, and nothing for the GUI to recognise the
# install by.
# Keep the scripts and the manifest beside what they installed, so the folder
# describes itself after the extracted copy is deleted.
$destToolkit = Join-Path $InstallRoot 'toolkit'
if ($Source -ne $destToolkit) {
    # Replace rather than copy into. Copy-Item onto an existing folder would
    # nest a second toolkit inside the first, and the second run would fail.
    if (Test-Path $destToolkit) { Remove-Item $destToolkit -Recurse -Force }
    New-Item -ItemType Directory $destToolkit | Out-Null
    Copy-Item (Join-Path $Source '*') $destToolkit -Recurse -Force
    Move-Item (Join-Path $destToolkit 'run.cmd') (Join-Path $InstallRoot 'run.cmd') -Force
    foreach ($f in 'README.txt', 'SKILL.md', 'GUI.cmd') {
        $from = Join-Path (Split-Path -Parent $Source) $f
        if (Test-Path $from) { Copy-Item $from $InstallRoot -Force }
    }
}

# Done before Python, deliberately. Creating the environment and installing
# its packages can fail, and if PATH were updated after them,
# a failure there would leave the tools installed but reachable by nobody,
# with the GUI reporting everything as not ready. The entries are static
# paths, so they are just as correct now as later.
# The one change outside the install folder. Rebuilt from scratch each run,
# rather than only appending whatever is missing, so re-running this also
# fixes the order if it was ever wrong - which is exactly what happened when
# px was added after everything else: it landed ahead of the toolkit's own
# Python instead of after it. $allKnown is every folder tools.json has ever
# named, including ones like px that are no longer meant to persist, so a
# stale entry from before that changed also gets cleaned up here.
$wanted = Get-PersistentToolkitPaths $InstallRoot $config
$allKnown = Get-KnownToolkitPaths $InstallRoot $config
Write-Host "`nThe tools work by name only if this folder is on your PATH."
Write-Host "Without it, an assistant running 'python' or 'node' will not find them."
Write-Host "These entries would be added to your user PATH, not the system one:"
$wanted | ForEach-Object { Write-Host "  $_" }

$answer = if ($Unattended) { 'y' } else { Read-Host "`nAdd them? [Y/n]" }
Write-Status 'path' 'updating'
if ($answer -eq '' -or $answer -eq 'y') {
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    $kept = ($current -split ';') | Where-Object { $_ -and ($allKnown -notcontains $_) }
    $rebuilt = ($wanted + $kept) -join ';'
    if ($rebuilt -ne $current) {
        [Environment]::SetEnvironmentVariable('Path', $rebuilt, 'User')
        Write-Host "Added." -ForegroundColor Green
    } else { Write-Host "Already there." }
    Write-Host "Close and reopen any terminal or assistant for it to take effect." -ForegroundColor Yellow
    Write-Status 'path' 'updated'
} else {
    Write-Host "Not added. Use $InstallRoot\run.cmd <command> instead, or run toolkit\env.ps1 in a window."
    Write-Status 'path' 'skipped'
}

# Point uv inside the install root, then let it fetch Python.
$ToolkitRootOverride = $InstallRoot
. (Join-Path $Source 'env.ps1')

$offlineWheelhouse = Join-Path (Split-Path -Parent $Source) 'offline-wheels\win_amd64-cp313'
$offlineBundle = Test-Path $offlineWheelhouse

# uv reads proxy environment variables and nothing else. It does not consult
# Windows' proxy settings and cannot run an automatic configuration script, so
# on a network where those decide how traffic leaves - and where external names
# are resolved by the proxy rather than by this machine - uv on its own cannot
# resolve anything and fails with a DNS error. The downloads above are fine
# because they go through Windows, which does all of that for them.
#
# A credential-bearing HTTPS_PROXY points uv at the authenticating proxy
# directly. Start Px for that proxy first and give uv its local address instead.
# The credentials in the URL are neither passed to Px nor printed in the log;
# Px authenticates with the Windows session.
if ($offlineBundle) {
    Write-LogLine 'Offline document bundle detected; package installation will not contact PyPI or need Px.'
}
$credentialedProxy = $false
if (-not $offlineBundle) {
    try { $credentialedProxy = [bool]([Uri] $env:HTTPS_PROXY).UserInfo } catch { }
}
if ($credentialedProxy) {
    $localProxy = Start-PxRelay $InstallRoot $env:HTTPS_PROXY
    if ($localProxy) {
        $env:HTTP_PROXY = $localProxy
        $env:HTTPS_PROXY = $localProxy
        Write-Host "  uv will use Px at $localProxy"
        Write-LogLine "uv routed through Px instead of the credential-bearing HTTPS_PROXY setting."
    } else {
        throw "Px could not start for this network's proxy. In the GUI, click Save & start under Corporate proxy, then Install / Fix."
    }
}

# Otherwise ask Windows what it would use for a representative address and hand
# uv the same answer, for this install only. Where the answer is "go direct" this
# does nothing at all.
if (-not $offlineBundle -and -not $env:HTTPS_PROXY) {
    # Resolve against the address uv actually struggles with. A proxy can let
    # one destination through unauthenticated and challenge the next, so the
    # Python download succeeding says nothing about the packages that follow.
    $systemProxy = Get-SystemProxyFor 'https://pypi.org'
    if (-not $systemProxy) { $systemProxy = Get-SystemProxyFor 'https://github.com' }

    if ($systemProxy) {
        # Prefer Px where it can be made to serve: it answers authentication
        # challenges with your Windows session, which uv cannot do at all.
        $chosen = Start-PxRelay $InstallRoot $systemProxy
        if ($chosen) {
            Write-LogLine "uv routed through px, which authenticates to the proxy on its behalf."
        } elseif (Test-ProxyReachable $systemProxy) {
            $chosen = $systemProxy
            Write-Host "  px is not available, so uv goes straight at the proxy"
            Write-LogLine "uv routed straight at $(Format-ProxyAddress $systemProxy). If it asks uv to authenticate, uv cannot - Px is what answers that."
        }

        if ($chosen) {
            $env:HTTP_PROXY = $chosen
            $env:HTTPS_PROXY = $chosen
            Write-Host "  uv will use $(Format-ProxyAddress $chosen)"
        }
    }
}

$envDir = Join-Path $InstallRoot $config.python.environment
if ($offlineBundle -and -not (Test-Path (Join-Path $envDir 'Scripts\python.exe'))) {
    throw 'The offline bundle requires an existing toolkit Python 3.13 environment. Use the regular toolkit ZIP for the first Python setup.'
}
Write-Host "`nPython environment"
Write-Status 'python' 'installing'
if (Test-Path (Join-Path $envDir 'Scripts\python.exe')) {
    Write-Host "  shared environment already exists" -ForegroundColor DarkGray
} else {
    $basePython = Get-CompatiblePython
    if ($basePython) {
        Write-Host "  using the Python already installed at $basePython"
        Write-LogLine "Creating the toolkit environment from the Python already installed at $basePython."
    } else {
        Write-Host "  no compatible Python found; downloading $($config.python.version)"
        Invoke-Uv python install $config.python.version
        $basePython = $config.python.version
    }
    # --seed puts pip inside the environment. Without it there is no pip here
    # and a bare "pip install" would silently use another Python on the machine.
    Invoke-Uv venv $envDir --python $basePython --seed
}
Write-Host "  one shared environment at $envDir" -ForegroundColor Green
Write-Status 'python' 'installed'

$packages = @($config.python.packages)
if ($packages.Count -gt 0) {
    Write-Host "`nPython packages"
    Write-Host "  this is the longest step - downloading the document libraries"
    Write-Status 'packages' 'installing' "$($packages.Count) packages - the longest step"
    Write-LogLine "Installing $($packages.Count) Python packages: $($packages -join ', ')"
    Write-LogLine "This is the longest step. uv reports each step below as it goes."
    $offlineLock = Join-Path $Source 'offline-win313.lock'
    if ($offlineBundle) {
        if (-not (Test-OfflinePython (Join-Path $envDir 'Scripts\python.exe'))) {
            throw 'This offline package bundle requires 64-bit Python 3.13 in the toolkit environment. Use the regular toolkit ZIP for another Python version.'
        }
        $locked = @(Get-Content $offlineLock | Where-Object { $_ -match '^[A-Za-z0-9_-]+==' })
        $wheels = @(Get-ChildItem $offlineWheelhouse -Filter '*.whl' -File)
        if ($wheels.Count -ne $locked.Count) { throw "Offline package bundle is incomplete: $($wheels.Count) wheels for $($locked.Count) locked packages." }
        $hashes = @(Get-Content (Join-Path $Source 'offline-win313.sha256'))
        if ($hashes.Count -ne $wheels.Count) { throw 'Offline package hash list does not match the wheels.' }
        foreach ($entry in $hashes) {
            if ($entry -notmatch '^(?<hash>[0-9a-fA-F]{64})  (?<file>[^\\/]+\.whl)$') { throw 'Offline package hash list is invalid.' }
            $expectedHash = $Matches.hash
            $file = $Matches.file
            $wheel = Join-Path $offlineWheelhouse $file
            if (-not (Test-Path $wheel)) { throw "Offline package is missing: $file" }
            $actual = (Get-FileHash $wheel -Algorithm SHA256).Hash
            if ($actual -ne $expectedHash) { throw "Offline package checksum mismatch: $file" }
        }
        Write-Host "  using $($wheels.Count) bundled wheels; no PyPI requests" -ForegroundColor Green
        Write-LogLine "Installing $($wheels.Count) bundled wheels without contacting PyPI."
        Invoke-Uv pip install --offline --no-index --find-links $offlineWheelhouse -r $offlineLock
    } else {
        $offlineWheelhouse = $null
        $offlineLock = $null
        Invoke-Uv pip install @packages
    }
    Write-Status 'packages' 'installed'
    Install-MachinePythonPackages $packages $offlineWheelhouse $offlineLock
} else {
    Write-Status 'packages' 'skipped' 'tools.json lists none'
    Write-Status 'machine-python' 'skipped' 'tools.json lists no packages'
}


# The download cache is only needed while installing. The installed files are
# hard links, so they survive it being emptied.
Invoke-Uv cache clean

Write-Host "`nInstalled." -ForegroundColor Green

Write-Host "`nEverything is in $InstallRoot. To check it:  $InstallRoot\toolkit\check.ps1"
Write-Host "To remove it:                              $InstallRoot\toolkit\uninstall.ps1"
Write-Host "The folder you extracted is no longer needed and can be deleted.`n"
Write-Status 'overall' 'done'

} catch {
    # Covers the PATH update and the copy step too, not just the downloads.
    # Without that, a failure here ended the process with no terminal status
    # line and gui.ps1 was left showing a run that never finished.
    Write-Status 'overall' 'error' $_.Exception.Message
    throw
}

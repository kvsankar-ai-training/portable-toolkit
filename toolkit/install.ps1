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
    [switch] $Unattended,

    # Also installs everything tools.json marks as optional: the extra tools and
    # the document libraries. Without it the install is the smaller set that is
    # enough to have a working Python, Node and Git.
    [switch] $IncludeOptional
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # without this, downloads are very slow

# A proxy that demands NTLM or Kerberos answers 407 to anything that does not
# offer credentials, and by default .NET offers none. A browser passes because
# it uses your logged-in session; this makes the downloads below do the same.
# Without it the very first download fails on a corporate network, which is a
# chicken-and-egg problem, because px - the tool that would solve it - is one
# of the things being downloaded.
try {
    [System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
} catch { }

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
    try { Add-Content -Path $StatusLog -Value "STATUS|name=$Name|state=$State|detail=$Detail" -ErrorAction Stop } catch { }
}

function Write-LogLine {
    # Anything a console user would read as it scrolls past. A caller showing a
    # window (gui.ps1) has no other way to see it, because it runs this script
    # hidden - so the long steps would otherwise look like nothing happening.
    param([string] $Text)
    if (-not $StatusLog) { return }
    $clean = ($Text -replace '[\r\n]', ' ').Trim()
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

function Test-Tool($tool) {
    $exe = Join-Path $InstallRoot ($tool.verify[0] -replace '/', '\')
    if (-not (Test-Path $exe)) { return $false }
    try { & $exe $tool.verify[1] *> $null; return ($LASTEXITCODE -eq 0) } catch { return $false }
}

function Get-DownloadArgs($Uri, $OutFile) {
    # Only offer credentials when there is actually a proxy to offer them to:
    # -ProxyUseDefaultCredentials is rejected unless -Proxy is given too. An
    # explicit HTTPS_PROXY wins, because that is how someone points this at a
    # running px; otherwise ask Windows what it would use for this address.
    $splat = @{ Uri = $Uri; OutFile = $OutFile; UseBasicParsing = $true }
    $proxy = $env:HTTPS_PROXY
    if (-not $proxy) {
        try {
            $resolved = [System.Net.WebRequest]::GetSystemWebProxy().GetProxy($Uri)
            if ($resolved -and $resolved.AbsoluteUri -ne $Uri) { $proxy = $resolved.AbsoluteUri }
        } catch { }
    }
    if ($proxy) {
        $splat.Proxy = $proxy
        $splat.ProxyUseDefaultCredentials = $true
    }
    $splat
}

function Install-Tool($tool) {
    Write-Status $tool.name 'downloading'
    $zip = Join-Path $env:TEMP "portable-toolkit-$($tool.name).zip"
    Write-Host "  downloading $($tool.url)"
    try {
        $download = Get-DownloadArgs $tool.url $zip
        Invoke-WebRequest @download
    } catch {
        if ("$($_.Exception.Message)" -match '407|Proxy Authentication') {
            throw ("Proxy authentication failed (407) downloading $($tool.name). Your proxy wants credentials " +
                   "this script cannot supply. If px is installed and configured, start it first and set " +
                   "HTTPS_PROXY to http://127.0.0.1:3128, then run setup again. See toolkit\troubleshooting.md.")
        }
        throw
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
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }

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
    if (-not (Test-Tool $tool)) { throw "$($tool.name): installed, but it does not run." }
    Write-Host "  installed and runs" -ForegroundColor Green
    Write-Status $tool.name 'installed'
}

function Invoke-Uv {
    # uv reports progress on the error stream. PowerShell would treat that as a
    # failure, so judge these calls by their exit code instead.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & uv @args 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray; Write-LogLine $_ }
    $code = $LASTEXITCODE
    $ErrorActionPreference = $previous
    if ($code -ne 0) { throw "uv $($args -join ' ') failed with exit code $code." }
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

$optional = @($config.tools | Where-Object { $_.tier -eq 'optional' })
if ($optional.Count -and -not $IncludeOptional) {
    Write-Host "Skipping the optional extras: $(($optional | ForEach-Object { $_.name }) -join ', '), and the document libraries." -ForegroundColor DarkGray
    Write-Host "Run SETUP.cmd again with the extras, or install.ps1 -IncludeOptional, to add them.`n" -ForegroundColor DarkGray
}

foreach ($tool in $config.tools) {
    if ($tool.tier -eq 'optional' -and -not $IncludeOptional) { continue }
    Write-Host "$($tool.name) $($tool.version)"
    if (Test-Tool $tool) {
        Write-Host "  already installed" -ForegroundColor DarkGray
        Write-Status $tool.name 'already-installed'
    } else {
        Install-Tool $tool
    }
}

# Point uv inside the install root, then let it fetch Python.
$ToolkitRootOverride = $InstallRoot
. (Join-Path $Source 'env.ps1')

# uv has no way to answer an NTLM challenge, so unlike the downloads above it
# cannot use the logged-in session. If px is already running, send uv through
# it for the rest of this install; px answers the challenge on uv's behalf.
if ((Get-Process px -ErrorAction SilentlyContinue) -and -not $env:HTTPS_PROXY) {
    $env:HTTP_PROXY = 'http://127.0.0.1:3128'
    $env:HTTPS_PROXY = 'http://127.0.0.1:3128'
    Write-Host "  routing uv through the running px on 127.0.0.1:3128"
    Write-LogLine "px is running, so uv is routed through it for this install."
}

Write-Host "`nPython $($config.python.version)"
Write-Status 'python' 'installing'
Invoke-Uv python install $config.python.version
$envDir = Join-Path $InstallRoot $config.python.environment
if (Test-Path (Join-Path $envDir 'Scripts\python.exe')) {
    Write-Host "  shared environment already exists" -ForegroundColor DarkGray
} else {
    # --seed puts pip inside the environment. Without it there is no pip here
    # and a bare "pip install" would silently use another Python on the machine.
    Invoke-Uv venv $envDir --python $config.python.version --seed
}
Write-Host "  one shared environment at $envDir" -ForegroundColor Green
Write-Status 'python' 'installed'

$packages = @($config.python.packages)
if ($IncludeOptional) { $packages += @($config.python.optional_packages) }
if ($packages.Count -gt 0) {
    Write-Host "`nPython packages"
    Write-Host "  this is the longest step - several hundred MB for the document libraries"
    Write-Status 'packages' 'installing' "$($packages.Count) packages - the longest step"
    Write-LogLine "Installing $($packages.Count) Python packages: $($packages -join ', ')"
    Write-LogLine "This is the longest step. Several hundred MB, and uv reports below as it goes."
    Invoke-Uv pip install @packages
    Write-Status 'packages' 'installed'
} else {
    Write-Status 'packages' 'skipped' 'run again with the extras to add them'
}

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

# The download cache is only needed while installing. The installed files are
# hard links, so they survive it being emptied.
Invoke-Uv cache clean

Write-Host "`nInstalled." -ForegroundColor Green

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

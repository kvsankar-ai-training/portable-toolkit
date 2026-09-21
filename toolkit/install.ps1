#Requires -Version 5.1
<#
Installs Git, Node, uv and Python into a tools folder of their own, then adds
that folder to your user PATH so the tools work by name in any window.

It does not install into the folder you extracted. That folder is only the
installer, and you can delete it afterwards.

Running it again only installs what is missing.
#>

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # without this, downloads are very slow

$Source = $PSScriptRoot
$config = Get-Content (Join-Path $Source 'tools.json') -Raw | ConvertFrom-Json
. (Join-Path $Source 'paths.ps1')

# A zip downloaded from the internet marks every file it extracts, and the mark
# can stop scripts running. Clear it on our own files before doing anything else.
Get-ChildItem (Split-Path -Parent $Source) -Recurse -File | Unblock-File -ErrorAction SilentlyContinue

function Select-InstallRoot {
    # C:\tools if the machine allows it, the user profile if it does not.
    foreach ($candidate in @($config.install.root, $config.install.fallback_root)) {
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

function Install-Tool($tool) {
    $zip = Join-Path $env:TEMP "portable-toolkit-$($tool.name).zip"
    Write-Host "  downloading $($tool.url)"
    Invoke-WebRequest -Uri $tool.url -OutFile $zip -UseBasicParsing

    # Refuse to install anything whose contents do not match the published hash.
    $actual = (Get-FileHash $zip -Algorithm SHA256).Hash
    if ($actual -ne $tool.sha256.ToUpper()) {
        Remove-Item $zip -Force
        throw "$($tool.name): checksum mismatch. Expected $($tool.sha256), got $actual."
    }
    Write-Host "  checksum matches the one published at $($tool.sha256_source)"

    $dest = Join-Path $InstallRoot $tool.target
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }

    if ($tool.strip_root) {
        # This archive wraps everything in one folder; unwrap it so paths stay short.
        $stage = Join-Path $env:TEMP "portable-toolkit-$($tool.name)-stage"
        if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
        Expand-Archive -Path $zip -DestinationPath $stage -Force
        Move-Item (Get-ChildItem $stage -Directory | Select-Object -First 1).FullName $dest
        Remove-Item $stage -Recurse -Force
    } else {
        Expand-Archive -Path $zip -DestinationPath $dest -Force
    }

    Remove-Item $zip -Force
    if (-not (Test-Tool $tool)) { throw "$($tool.name): installed, but it does not run." }
    Write-Host "  installed and runs" -ForegroundColor Green
}

function Invoke-Uv {
    # uv reports progress on the error stream. PowerShell would treat that as a
    # failure, so judge these calls by their exit code instead.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & uv @args 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
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

$InstallRoot = Select-InstallRoot
Write-Host "`nInstalling into $InstallRoot`n"
Show-MachineWideTools

foreach ($tool in $config.tools) {
    Write-Host "$($tool.name) $($tool.version)"
    if (Test-Tool $tool) { Write-Host "  already installed" -ForegroundColor DarkGray }
    else { Install-Tool $tool }
}

# Point uv inside the install root, then let it fetch Python.
$ToolkitRootOverride = $InstallRoot
. (Join-Path $Source 'env.ps1')

Write-Host "`nPython $($config.python.version)"
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

if ($config.python.packages.Count -gt 0) {
    Write-Host "`nPackages"
    Invoke-Uv pip install @($config.python.packages)
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
    foreach ($f in 'README.txt', 'SKILL.md') {
        $from = Join-Path (Split-Path -Parent $Source) $f
        if (Test-Path $from) { Copy-Item $from $InstallRoot -Force }
    }
}

# The download cache is only needed while installing. The installed files are
# hard links, so they survive it being emptied.
Invoke-Uv cache clean

Write-Host "`nInstalled." -ForegroundColor Green

# The one change outside the install folder.
$wanted = Get-ToolkitPaths $InstallRoot $config
Write-Host "`nThe tools work by name only if this folder is on your PATH."
Write-Host "Without it, an assistant running 'python' or 'node' will not find them."
Write-Host "These entries would be added to your user PATH, not the system one:"
$wanted | ForEach-Object { Write-Host "  $_" }

$answer = Read-Host "`nAdd them? [Y/n]"
if ($answer -eq '' -or $answer -eq 'y') {
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    $missing = $wanted | Where-Object { ($current -split ';') -notcontains $_ }
    if ($missing) {
        [Environment]::SetEnvironmentVariable('Path', (($missing -join ';') + ';' + $current), 'User')
        Write-Host "Added." -ForegroundColor Green
    } else { Write-Host "Already there." }
    Write-Host "Close and reopen any terminal or assistant for it to take effect." -ForegroundColor Yellow
} else {
    Write-Host "Not added. Use $InstallRoot\run.cmd <command> instead, or run toolkit\env.ps1 in a window."
}

Write-Host "`nEverything is in $InstallRoot. To check it:  $InstallRoot\toolkit\check.ps1"
Write-Host "To remove it:                              $InstallRoot\toolkit\uninstall.ps1"
Write-Host "The folder you extracted is no longer needed and can be deleted.`n"

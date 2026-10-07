<#
Chooses the Python the toolkit's environment is built from. install.ps1
dot-sources it; it is a file of its own so the choice can be tested without
installing anything.
#>

function Get-CompatiblePythons($InstallRoot, $config) {
    # Every working Python already on PATH that the toolkit supports, in PATH
    # order. Reusing one saves a download; uv still builds the toolkit's
    # isolated environment from it.
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
                if ($minor -ge $minimum -and $minor -lt $maximum) { $exe }
            }
        } catch { }
    }
}

function Test-OfflinePython($Python) {
    # The release's offline wheels target CPython 3.13 on Windows x64.
    try {
        $tag = & $Python -c 'import sys; print(sys.implementation.name, sys.version_info.major, sys.version_info.minor, int(sys.maxsize > 2**32))' 2>$null
        return ("$tag".Trim() -eq 'cpython 3 13 1')
    } catch { return $false }
}

function Select-BasePython($Candidates, $DefaultVersion, [switch] $Offline) {
    # Python is an installed interpreter to build from; Download is the version
    # uv fetches when there is none. The offline bundle's wheels fit only
    # 64-bit CPython 3.13, so for it any other Python is passed over and 3.13
    # is downloaded instead.
    if ($Offline) {
        $python = @($Candidates | Where-Object { Test-OfflinePython $_ })[0]
        $download = '3.13'
    } else {
        $python = @($Candidates)[0]
        $download = $DefaultVersion
    }
    if ($python) { return [pscustomobject] @{ Python = $python; Download = $null } }
    return [pscustomobject] @{ Python = $null; Download = $download }
}

function Invoke-Ensurepip($EnvDir) {
    # Installs the pip wheel that ships inside the interpreter, so nothing is
    # downloaded.
    & (Join-Path $EnvDir 'Scripts\python.exe') -m ensurepip --default-pip | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    if ($LASTEXITCODE -ne 0) { throw "Could not add pip to the toolkit environment (ensurepip exit code $LASTEXITCODE)." }
}

function New-ToolkitEnvironment($EnvDir, $Base, [switch] $Offline) {
    # Uses Invoke-Uv from install.ps1.
    if (-not $Base.Python) { Invoke-Uv python install $Base.Download }
    $python = if ($Base.Python) { $Base.Python } else { $Base.Download }
    if ($Offline) {
        # --seed would fetch pip from PyPI, which the offline bundle avoids.
        Invoke-Uv venv $EnvDir --python $python
        Invoke-Ensurepip $EnvDir
    } else {
        # --seed puts pip inside the environment. Without it there is no pip here
        # and a bare "pip install" would silently use another Python on the machine.
        Invoke-Uv venv $EnvDir --python $python --seed
    }
}

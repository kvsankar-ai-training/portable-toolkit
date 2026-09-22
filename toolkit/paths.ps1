<#
The one definition of which folders under the install root hold executables.
Everything that touches PATH reads it from here, so adding a tool to tools.json
is enough and no script needs editing.
#>

function Get-ToolkitPaths($Root, $config) {
    $paths = @(
        (Join-Path $Root "$($config.python.environment)\Scripts"),
        (Join-Path $Root 'bin')
    )
    foreach ($tool in $config.tools) {
        $paths += (Join-Path $Root ($tool.path_add -replace '/', '\'))
    }
    $paths
}

function Get-KnownToolkitPaths($Root, $config) {
    # Every folder this toolkit could have put on PATH, at the current root and
    # at either root tools.json names. Without the second part, an install that
    # first landed in %USERPROFILE%\tools and later in C:\tools would leave the
    # earlier entries behind: they point at a folder that may no longer exist,
    # but they do not match the current root so nothing would clean them up.
    $roots = @($Root)
    foreach ($candidate in @($config.install.root, $config.install.fallback_root)) {
        if (-not $candidate) { continue }
        $expanded = [Environment]::ExpandEnvironmentVariables($candidate) -replace '/', '\'
        $expanded = $expanded.TrimEnd('\')
        if ($roots -notcontains $expanded) { $roots += $expanded }
    }

    $paths = @()
    foreach ($r in $roots) { $paths += Get-ToolkitPaths $r $config }
    $paths | Select-Object -Unique
}

function Get-MachineWidePython {
    # The python.exe that answers to a bare "python" in a new window, when it is
    # not the toolkit's. Windows builds PATH as machine entries first and user
    # entries after, so a Python installed for all users always wins and no
    # amount of user PATH editing changes that.
    #
    # It has to be worked out from the registry rather than with Get-Command,
    # because the process asking has usually put the toolkit ahead on its own
    # PATH and would answer the wrong question.
    $machinePaths = ([Environment]::GetEnvironmentVariable('Path', 'Machine') -split ';') |
        Where-Object { $_ } |
        ForEach-Object { [Environment]::ExpandEnvironmentVariables($_).Trim().TrimEnd('\') }

    foreach ($dir in $machinePaths) {
        if (-not $dir) { continue }
        $candidate = Join-Path $dir 'python.exe'
        if (Test-Path $candidate) { return $candidate }
    }
    return $null
}

function Get-MachinePythonMarker($Root) {
    Join-Path $Root '.machine-python-packages.json'
}

function Get-PersistentToolkitPaths($Root, $config) {
    # Same list, minus any tool marked "persistent_path": false. Those still
    # need to be reachable within run.cmd/env.ps1's own short-lived PATH (so
    # Get-ToolkitPaths above is unchanged), just not added to the user's
    # permanent PATH - px is why this exists, see tools.json's comment.
    $persistent = $config.tools | Where-Object {
        -not ($_.PSObject.Properties.Name -contains 'persistent_path' -and $_.persistent_path -eq $false)
    }
    Get-ToolkitPaths $Root ([PSCustomObject]@{ python = $config.python; tools = $persistent })
}

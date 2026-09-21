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

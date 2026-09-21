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

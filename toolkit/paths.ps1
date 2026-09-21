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

<#
Points the toolkit's tools at the install root, for the current process only.
Closing the window undoes it. This file changes nothing on disk.

Run it as:  .\toolkit\env.ps1
#>

# install.ps1 sets $ToolkitRootOverride before dot-sourcing this, because during
# a first install the scripts are still running from the extracted zip rather
# than from the install root.
$Root = if ($ToolkitRootOverride) { $ToolkitRootOverride } else { Split-Path -Parent $PSScriptRoot }
$config = Get-Content (Join-Path $PSScriptRoot 'tools.json') -Raw | ConvertFrom-Json
. (Join-Path $PSScriptRoot 'paths.ps1')
$envDir = Join-Path $Root $config.python.environment

# None of these are persisted to your user profile. They exist so that uv, when
# it is used through this script or run.cmd, writes inside the install root
# instead of under %APPDATA% and %USERPROFILE%.
$env:UV_PYTHON_INSTALL_DIR  = Join-Path $Root 'python'
$env:UV_CACHE_DIR           = Join-Path $Root 'cache'
$env:UV_TOOL_DIR            = Join-Path $Root 'uv-tools'
$env:UV_TOOL_BIN_DIR        = Join-Path $Root 'bin'
$env:UV_PYTHON_BIN_DIR      = Join-Path $Root 'bin'
$env:UV_PROJECT_ENVIRONMENT = $envDir   # stops "uv sync" creating a .venv
$env:VIRTUAL_ENV            = $envDir   # tells "uv pip install" where to install

# Built in one go, in the order Get-ToolkitPaths returns. Prepending them one at
# a time reverses that order, which put px - and so px's own bundled python.exe -
# ahead of the toolkit's real Python, and "run.cmd python" then ran the wrong
# interpreter with none of the toolkit's packages visible.
$toolkitPaths = Get-ToolkitPaths $Root $config
$rest = $env:Path -split ';' | Where-Object { $_ -and ($toolkitPaths -notcontains $_) }
$env:Path = (($toolkitPaths + $rest) -join ';')

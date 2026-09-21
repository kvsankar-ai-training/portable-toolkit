<#
Removes the toolkit's entries from your user PATH and tells you what is left to
delete. Changes nothing else.

Run it as:  .\toolkit\uninstall.ps1
#>

$Root = Split-Path -Parent $PSScriptRoot
$config = Get-Content (Join-Path $PSScriptRoot 'tools.json') -Raw | ConvertFrom-Json
. (Join-Path $PSScriptRoot 'paths.ps1')

# Same parseable-line convention as install.ps1's install.status.log, for a
# caller (gui.ps1) that wants to show progress instead of a bare console.
$StatusLog = Join-Path $PSScriptRoot 'uninstall.status.log'
Set-Content -Path $StatusLog -Value $null
function Write-Status {
    param([string] $Name, [string] $State, [string] $Detail = '')
    Add-Content -Path $StatusLog -Value "STATUS|name=$Name|state=$State|detail=$Detail"
}
Write-Status 'overall' 'starting'

$ours = Get-ToolkitPaths $Root $config
$current = [Environment]::GetEnvironmentVariable('Path', 'User')
$kept = ($current -split ';') | Where-Object { $_ -and ($ours -notcontains $_) }

if (($current -split ';').Count -ne $kept.Count) {
    [Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), 'User')
    Write-Host "Removed the toolkit's entries from your user PATH." -ForegroundColor Green
    Write-Status 'path' 'removed'
} else {
    Write-Host "Your user PATH had no toolkit entries."
    Write-Status 'path' 'clean'
}

Write-Host "`nNothing else was changed. Setup persisted PATH and nothing more."
Write-Host "To finish, delete the folder:  $Root"
Write-Host "This script is inside it, so delete it from outside, or run:"
Write-Host "  Remove-Item -Recurse -Force '$Root'"
Write-Status 'overall' 'done'

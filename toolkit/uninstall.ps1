<#
Removes the toolkit's entries from your user PATH and tells you what is left to
delete. Changes nothing else.

Run it as:  .\toolkit\uninstall.ps1
#>

$Root = Split-Path -Parent $PSScriptRoot
$config = Get-Content (Join-Path $PSScriptRoot 'tools.json') -Raw | ConvertFrom-Json
. (Join-Path $PSScriptRoot 'paths.ps1')

$ours = Get-ToolkitPaths $Root $config
$current = [Environment]::GetEnvironmentVariable('Path', 'User')
$kept = ($current -split ';') | Where-Object { $_ -and ($ours -notcontains $_) }

if (($current -split ';').Count -ne $kept.Count) {
    [Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), 'User')
    Write-Host "Removed the toolkit's entries from your user PATH." -ForegroundColor Green
} else {
    Write-Host "Your user PATH had no toolkit entries."
}

Write-Host "`nNothing else was changed. Setup persisted PATH and nothing more."
Write-Host "To finish, delete the folder:  $Root"
Write-Host "This script is inside it, so delete it from outside, or run:"
Write-Host "  Remove-Item -Recurse -Force '$Root'"

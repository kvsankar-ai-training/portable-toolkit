<#
Reverses everything setup persisted outside the toolkit folder: the user PATH
entries, and Px's logon registration if it was ever set up. Then tells you what
is left to delete.

Run it as:  .\toolkit\uninstall.ps1          undoes the machine changes only
            .\toolkit\uninstall.ps1 -Full    also deletes the installed tools
#>

param(
    # Also deletes every installed tool and the Python environment, which is
    # nearly all of the disk space. The toolkit's own scripts stay, because this
    # script is one of them and cannot delete the folder it is running from -
    # that last step is still yours.
    [switch] $Full
)

$Root = Split-Path -Parent $PSScriptRoot
$config = Get-Content (Join-Path $PSScriptRoot 'tools.json') -Raw | ConvertFrom-Json
. (Join-Path $PSScriptRoot 'paths.ps1')

# Same parseable-line convention as install.ps1's install.status.log, for a
# caller (gui.ps1) that wants to show progress instead of a bare console.
$StatusLog = Join-Path $PSScriptRoot 'uninstall.status.log'
try { Set-Content -Path $StatusLog -Value $null -ErrorAction Stop } catch { $StatusLog = $null }
function Write-Status {
    param([string] $Name, [string] $State, [string] $Detail = '')
    if (-not $StatusLog) { return }
    try { Add-Content -Path $StatusLog -Value "STATUS|name=$Name|state=$State|detail=$Detail" -ErrorAction Stop } catch { }
}
Write-Status 'overall' 'starting'

$ours = Get-KnownToolkitPaths $Root $config
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

# Px, if it was configured, is registered to start at logon and may be running.
# That registration lives outside this folder and survives deleting it, so the
# folder must not be deleted before this has run.
$px = Join-Path $Root 'px\px.exe'
if (Test-Path $px) {
    if (Get-Process px -ErrorAction SilentlyContinue) {
        Write-Host "Stopping Px..."
        & $px --quit *> $null
    }
    # Harmless when it was never registered; px reports nothing to remove.
    & $px --uninstall *> $null
    Write-Host "Deregistered Px from starting at logon." -ForegroundColor Green
    Write-Status 'px' 'deregistered'
} else {
    Write-Status 'px' 'absent'
}

if ($Full) {
    Write-Host "`nDeleting the installed tools..."
    $targets = @($config.tools | ForEach-Object { $_.target }) +
               @($config.python.environment, 'python', 'cache', 'bin', 'uv-tools')
    foreach ($t in $targets) {
        $path = Join-Path $Root $t
        if (-not (Test-Path $path)) { continue }
        try {
            Remove-Item $path -Recurse -Force -ErrorAction Stop
            Write-Host "  removed $t" -ForegroundColor Green
        } catch {
            Write-Host "  could not remove $t : $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    Write-Status 'files' 'removed'
}

Write-Host "`nNothing else was changed."
Write-Host "To finish, delete the folder:  $Root"
Write-Host "This script is inside it, so delete it from outside, or run:"
Write-Host "  Remove-Item -Recurse -Force '$Root'"
Write-Status 'overall' 'done'

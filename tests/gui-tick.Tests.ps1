# Pester 3.4 tests; see python-env.Tests.ps1 for how to run them.
# gui.ps1 opens its window as it loads, so this takes Invoke-Tick out of it
# with the parser and runs it against a finished run that never had a window.

. (Join-Path $PSScriptRoot '..\toolkit\failure.ps1')
$gui = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot '..\toolkit\gui.ps1'), [ref] $null, [ref] $null)
$tick = $gui.FindAll({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-Tick' }, $true)
. ([scriptblock]::Create($tick[0].Extent.Text))

function Write-Log($text) { }
function Start-NetworkCheck { }
function Update-Status { }
function Read-NewStatusLines { }

function Invoke-FinishedRun($ScriptName, $StatusLine) {
    $folder = Join-Path $env:TEMP ('gui-tick-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory $folder | Out-Null
    $script:trackedScript = Join-Path $folder $ScriptName
    Set-Content $script:trackedScript '# stands in for the script that ran'
    $script:activeStatusLog = Join-Path $folder 'status.log'
    Set-Content $script:activeStatusLog "STATUS|name=overall|state=starting|detail=`r`n$StatusLine"
    $script:trackedProcess = [pscustomobject] @{ HasExited = $true; ExitCode = 1 }
    $script:trackedReportsOnly = $false
    foreach ($name in 'btnInstall', 'btnUninstall', 'btnRemoveAll', 'btnNetCheck') {
        Set-Variable -Scope Script -Name $name -Value ([pscustomobject] @{ Enabled = $false })
    }
    try { Invoke-Tick } finally { Remove-Item $folder -Recurse -Force }
}

Describe 'Invoke-Tick after a failed run' {
    Mock Write-Log { }
    Mock Start-NetworkCheck { }

    It 'checks the network after a download failure' {
        Invoke-FinishedRun 'install.ps1' 'STATUS|name=overall|state=error|detail=uv: could not download https://github.com/x.zip'
        Assert-MockCalled Start-NetworkCheck -Exactly 1 -Scope It
    }

    It 'says the cause is local, and skips the check, after an offline bundle error' {
        Invoke-FinishedRun 'install.ps1' 'STATUS|name=overall|state=error|detail=Offline package is missing: pandas.whl'
        Assert-MockCalled Start-NetworkCheck -Exactly 0 -Scope It
        Assert-MockCalled Write-Log -Exactly 1 -Scope It -ParameterFilter { $text -eq 'That did not finish. The error above is about this machine, not the network.' }
    }

    It 'skips the check after an uninstall failure' {
        Invoke-FinishedRun 'uninstall.ps1' 'STATUS|name=overall|state=error|detail=Something unexpected happened.'
        Assert-MockCalled Start-NetworkCheck -Exactly 0 -Scope It
    }
}

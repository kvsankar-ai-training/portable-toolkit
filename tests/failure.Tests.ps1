# Pester 3.4 tests; see python-env.Tests.ps1 for how to run them.

. (Join-Path $PSScriptRoot '..\toolkit\failure.ps1')

function New-FailedLog($Message) {
    "STATUS|name=overall|state=starting|detail=`r`nLOG|working`r`nSTATUS|name=overall|state=error|detail=$Message`r`n"
}

Describe 'Test-NetworkFailure' {
    Context 'install.ps1 failures that happen at the network' {
        It 'reports a download that failed' {
            Test-NetworkFailure 'install.ps1' (New-FailedLog 'uv: could not download https://github.com/astral-sh/uv/releases/x.zip') | Should Be $true
        }
        It 'reports a tool download whose checksum did not match, which a proxy page can cause' {
            Test-NetworkFailure 'install.ps1' (New-FailedLog 'node: checksum mismatch. Expected aa, got bb.') | Should Be $true
        }
        It 'reports a failed uv step' {
            Test-NetworkFailure 'install.ps1' (New-FailedLog 'uv pip install pandas failed with exit code 2. A uv download timed out.') | Should Be $true
        }
        It 'judges by the error line, not by progress lines before it' {
            $log = "LOG|Checking the offline package files.`r`n" + (New-FailedLog 'uv python install 3.13 failed with exit code 2. A uv download timed out.')
            Test-NetworkFailure 'install.ps1' $log | Should Be $true
        }
        It 'reports an error it does not recognise' {
            Test-NetworkFailure 'install.ps1' (New-FailedLog 'Something unexpected happened.') | Should Be $true
        }
        It 'reports a run that stopped without an error line' {
            Test-NetworkFailure 'install.ps1' "STATUS|name=overall|state=starting|detail=`r`n" | Should Be $true
        }
    }

    Context 'install.ps1 failures on this machine alone' {
        $local = @(
            "Install path in tools.json contains a control character: 'C:?tools'.",
            'No writable install location. Tried C:/tools and %USERPROFILE%/tools.',
            'git: cannot replace C:\tools\git because something has files there open. Close it.',
            'gh: installed, but it does not run.',
            'This offline package bundle requires 64-bit Python 3.13 in the toolkit environment. Use the regular toolkit ZIP for another Python version.',
            'Offline package bundle is incomplete: 44 wheels for 45 locked packages.',
            'Offline package hash list does not match the wheels.',
            'Offline package is missing: pandas-3.0.0-cp313-cp313-win_amd64.whl',
            'Offline package checksum mismatch: pandas-3.0.0-cp313-cp313-win_amd64.whl',
            'Could not add pip to the toolkit environment (ensurepip exit code 1).',
            'uv python install 3.13 failed with exit code 2. Another uv process is holding the Python install folder. Close any other toolkit setup or uv operation, check for a remaining uv.exe process, then run setup again. Do not delete the .lock file.'
        )
        foreach ($message in $local) {
            It "does not report: $message" {
                Test-NetworkFailure 'install.ps1' (New-FailedLog $message) | Should Be $false
            }
        }
    }

    Context 'uninstall.ps1, which makes no network calls' {
        It 'does not report its failures' {
            Test-NetworkFailure 'uninstall.ps1' (New-FailedLog 'Something unexpected happened.') | Should Be $false
        }
    }
}

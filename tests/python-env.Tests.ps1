# Pester 3.4 tests, the version Windows PowerShell 5.1 ships with. From the
# repository root:
#   powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests"

. (Join-Path $PSScriptRoot '..\toolkit\python-env.ps1')

Describe 'Select-BasePython' {
    $py312 = 'C:\Python312\python.exe'
    $py313 = 'C:\Python313\python.exe'
    Mock Test-OfflinePython { $Python -eq 'C:\Python313\python.exe' }

    Context 'regular ZIP' {
        It 'builds from the first supported Python on PATH' {
            (Select-BasePython @($py312, $py313) '3.13').Python | Should Be $py312
        }

        It 'downloads the configured version when no Python is installed' {
            $choice = Select-BasePython @() '3.13'
            $choice.Python | Should BeNullOrEmpty
            $choice.Download | Should Be '3.13'
        }
    }

    Context 'offline bundle' {
        It 'skips an installed Python the bundled wheels do not fit' {
            (Select-BasePython @($py312, $py313) '3.12' -Offline).Python | Should Be $py313
        }

        It 'downloads Python 3.13 when no installed Python fits the wheels' {
            $choice = Select-BasePython @($py312) '3.12' -Offline
            $choice.Python | Should BeNullOrEmpty
            $choice.Download | Should Be '3.13'
        }
    }
}

Describe 'New-ToolkitEnvironment' {
    # install.ps1 defines Invoke-Uv; stand-ins here so they can be mocked.
    function Invoke-Uv { }
    function Invoke-Ensurepip($EnvDir) { }
    Mock Invoke-Uv { }
    Mock Invoke-Ensurepip { }
    $envDir = 'C:\tools\env'

    Context 'regular ZIP' {
        It 'lets uv seed pip from the package index' {
            New-ToolkitEnvironment $envDir ([pscustomobject] @{ Python = 'C:\Python312\python.exe'; Download = $null })
            Assert-MockCalled Invoke-Uv -Exactly 1 -ParameterFilter { ($args -join ' ') -eq 'venv C:\tools\env --python C:\Python312\python.exe --seed' }
            Assert-MockCalled Invoke-Ensurepip -Exactly 0
        }
    }

    Context 'offline bundle' {
        It 'downloads Python, then takes pip from its own ensurepip rather than PyPI' {
            New-ToolkitEnvironment $envDir ([pscustomobject] @{ Python = $null; Download = '3.13' }) -Offline
            Assert-MockCalled Invoke-Uv -Exactly 1 -ParameterFilter { ($args -join ' ') -eq 'python install 3.13' }
            Assert-MockCalled Invoke-Uv -Exactly 1 -ParameterFilter { ($args -join ' ') -eq 'venv C:\tools\env --python 3.13' }
            Assert-MockCalled Invoke-Uv -Exactly 0 -ParameterFilter { $args -contains '--seed' }
            Assert-MockCalled Invoke-Ensurepip -Exactly 1 -ParameterFilter { $EnvDir -eq 'C:\tools\env' }
        }
    }
}

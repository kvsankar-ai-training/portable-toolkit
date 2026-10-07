<#
Decides whether a failed run is worth a network report. gui.ps1 dot-sources
it; it is a file of its own so the decision can be tested without a window.
#>

# Failures install.ps1 reports that happen on this machine alone. A network
# report after one of these points the reader at the wrong cause.
$LocalFailurePatterns = @(
    'contains a control character',
    'No writable install location',
    'something has files there open',
    'installed, but it does not run',
    'offline package',
    'Could not add pip to the toolkit environment',
    'Another uv process is holding the Python install folder'
)

function Test-NetworkFailure($ScriptName, $StatusLogText) {
    # Only install.ps1 downloads anything; uninstall.ps1 makes no network calls.
    if ($ScriptName -ne 'install.ps1') { return $false }
    # Judge by the error line alone; progress lines before it can mention
    # anything. Anything not recognised as local keeps the report: most install
    # failures are at the network, and an unneeded report costs less than a
    # missing one.
    $match = [regex]::Match("$StatusLogText", '(?m)^STATUS\|name=overall\|state=error\|detail=(?<detail>[^\r\n]*)')
    if (-not $match.Success) { return $true }
    foreach ($pattern in $LocalFailurePatterns) {
        if ($match.Groups['detail'].Value -match $pattern) { return $false }
    }
    return $true
}

<#
Runs one command with the toolkit's tools available, then exits.
Called by run.cmd in the folder above; there is no need to call this directly.

There is no param block on purpose. Without one, PowerShell passes switches
like -c and --version through to the command instead of trying to interpret
them as arguments to this script.
#>

. (Join-Path $PSScriptRoot 'env.ps1')

if ($args.Count -eq 0) {
    Write-Host "Usage: run.cmd <command> [arguments]"
    Write-Host "  run.cmd uv pip install requests"
    Write-Host "  run.cmd python script.py"
    exit 2
}

# The cast matters. With a single remaining argument the range operator returns
# a string rather than an array, and splatting a string passes its characters
# one at a time, so "--version" would arrive as "-", "-", "v" and so on.
$rest = @()
if ($args.Count -gt 1) { $rest = [object[]]$args[1..($args.Count - 1)] }

& $args[0] @rest
exit $LASTEXITCODE

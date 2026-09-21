<#
Reports what is installed and whether an assistant would find it. Changes nothing.
Run it as:  .\toolkit\check.ps1
#>

$Root = Split-Path -Parent $PSScriptRoot
$config = Get-Content (Join-Path $PSScriptRoot 'tools.json') -Raw | ConvertFrom-Json
. (Join-Path $PSScriptRoot 'paths.ps1')

Write-Host "Install root: $Root`n"

$missing = 0
$expected = @{}
foreach ($tool in $config.tools) {
    $exe = Join-Path $Root ($tool.verify[0] -replace '/', '\')
    $expected[$tool.name] = $exe
    if (Test-Path $exe) {
        Write-Host ("{0,-7} {1}" -f $tool.name, (& $exe $tool.verify[1] 2>&1 | Select-Object -First 1)) -ForegroundColor Green
    } else {
        Write-Host ("{0,-7} not installed" -f $tool.name) -ForegroundColor Red
        $missing++
    }
}

$python = Join-Path $Root "$($config.python.environment)\Scripts\python.exe"
$expected['python'] = $python
if (Test-Path $python) {
    Write-Host ("{0,-7} {1}" -f 'python', (& $python --version)) -ForegroundColor Green
} else {
    Write-Host ("{0,-7} not installed" -f 'python') -ForegroundColor Red
    $missing++
}

# The question that actually matters: does a bare command name reach these files?
# An assistant types "python", not a full path, so this is what decides whether
# it can use the toolkit at all.
#
# Windows builds PATH as machine entries first, then user entries. Setup can
# only write the user part, so a tool already installed machine-wide always
# wins. That is not something the toolkit can fix without administrator rights.
# Entries are written inconsistently: "C:\Python314\" and "C:\Program Files\Git\cmd"
# both occur, so trailing separators have to come off before comparing.
$machinePaths = ([Environment]::GetEnvironmentVariable('Path', 'Machine') -split ';') |
    Where-Object { $_ } | ForEach-Object { $_.Trim().TrimEnd('\') }

Write-Host "`nFound by name, as an assistant would call them:"
$wrong = 0
foreach ($name in 'python', 'pip', 'node', 'npm', 'git', 'uv') {
    $found = (Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if (-not $found) {
        Write-Host ("  {0,-6} not found" -f $name) -ForegroundColor Red
        $wrong++
    } elseif ($found -like "$Root\*") {
        Write-Host ("  {0,-6} {1}" -f $name, $found) -ForegroundColor Green
    } else {
        $dir = (Split-Path -Parent $found).TrimEnd('\')
        Write-Host ("  {0,-6} {1}" -f $name, $found) -ForegroundColor Yellow
        if ($machinePaths -contains $dir) {
            Write-Host ("  {0,-6} ^ installed machine-wide; user PATH cannot override it" -f '') -ForegroundColor Yellow
        } else {
            Write-Host ("  {0,-6} ^ not the toolkit's copy" -f '') -ForegroundColor Yellow
        }
        $wrong++
    }
}

if ($missing -gt 0) {
    Write-Host "`n$missing missing. Run SETUP.cmd." -ForegroundColor Yellow
    exit 1
}
if ($wrong -gt 0) {
    Write-Host "`nInstalled, but $wrong command(s) do not resolve to this folder." -ForegroundColor Yellow
    Write-Host "Usual causes, in order of likelihood:" -ForegroundColor Yellow
    Write-Host "  1. This window was open before setup ran. Open a new one." -ForegroundColor Yellow
    Write-Host "  2. The PATH question was answered no. Run SETUP.cmd again." -ForegroundColor Yellow
    Write-Host "  3. The tool is installed machine-wide and wins on PATH." -ForegroundColor Yellow
    Write-Host "Meanwhile these always work: $Root\run.cmd <command>" -ForegroundColor Yellow
    exit 1
}
Write-Host "`nEverything is installed and reachable by name." -ForegroundColor Green

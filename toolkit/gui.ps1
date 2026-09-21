#Requires -Version 5.1
<#
A WinForms front end for the toolkit: install/check/uninstall, and start, stop
and configure px. Every button here runs the same install.ps1, check.ps1,
uninstall.ps1 or px.exe you could run yourself; this only clicks them for you.
Needs nothing beyond what Windows already has - no Python or Node required to
run it, which is the point.

Run it as:  .\toolkit\gui.ps1   (or double-click GUI.cmd in the folder above)
#>

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$config = Get-Content (Join-Path $PSScriptRoot 'tools.json') -Raw | ConvertFrom-Json

function Resolve-InstallRoot {
    # Where install.ps1 actually put things, which is not necessarily wherever
    # this copy of gui.ps1 happens to be running from - those are the same
    # folder only after install.ps1 has copied the toolkit there. Checking each
    # candidate the same way install.ps1 chooses between them, rather than
    # assuming this script's own location, is what keeps Check/Uninstall
    # pointed at the real install even when gui.ps1 is run from an extracted
    # zip or a cloned repo.
    #
    # Normalising to backslashes matters beyond appearance: Test-ToolReady
    # compares this against Get-Command's .Source with -like, which is a
    # literal string match. tools.json writes "C:/tools" with forward
    # slashes, so without this a real match would silently compare unequal
    # and everything would report "not ready" even once it truly was.
    foreach ($candidate in @($config.install.root, $config.install.fallback_root)) {
        $path = [Environment]::ExpandEnvironmentVariables($candidate) -replace '/', '\'
        if (Test-Path (Join-Path $path 'toolkit\tools.json')) { return $path }
    }
    # Nothing installed yet; this is where Install / Update would put it.
    [Environment]::ExpandEnvironmentVariables($config.install.root) -replace '/', '\'
}

$script:Root = Resolve-InstallRoot

function Get-PxPath { Join-Path $script:Root 'px\px.exe' }

function Get-CopilotAppPath {
    $exe = Join-Path $env:LOCALAPPDATA 'Programs\GitHub Copilot\github.exe'
    if (Test-Path $exe) { $exe }
}

function Get-SiteConfig {
    # Optional and gitignored; see toolkit/site.example.json for the template.
    # This is how site-specific values (a proxy address) reach the GUI without
    # ever being part of the public repo.
    $path = Join-Path $PSScriptRoot 'site.json'
    if (-not (Test-Path $path)) { return $null }
    try { Get-Content $path -Raw | ConvertFrom-Json } catch { $null }
}

function Get-SavedPxProxy {
    # Whatever was last saved with --save, straight from px's own config file -
    # the fallback source for the proxy field so it is remembered between GUI
    # sessions even without a site.json.
    $ini = Join-Path $script:Root 'px\px.ini'
    if (-not (Test-Path $ini)) { return $null }
    $line = Get-Content $ini -ErrorAction SilentlyContinue | Where-Object { $_ -match '^\s*server\s*=\s*(.+)$' } | Select-Object -First 1
    if ($line -and $Matches[1].Trim()) { return $Matches[1].Trim() }
    $null
}

function Invoke-Timeboxed {
    # Runs a px.exe command with a hard timeout. px.exe with no recognised flag
    # starts the proxy server instead of exiting, and a naive synchronous call
    # would freeze this window forever if that ever happened again.
    #
    # Arguments are passed explicitly via -ArgumentList rather than $using:,
    # because $using: only resolves reliably when Start-Job is called directly
    # where the scriptblock is written, not through a helper like this one.
    param([scriptblock]$Script, [object[]]$ArgumentList = @(), [int]$TimeoutSec = 8)
    $job = Start-Job -ScriptBlock $Script -ArgumentList $ArgumentList
    if (-not (Wait-Job $job -Timeout $TimeoutSec)) {
        Stop-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        return "Timed out after ${TimeoutSec}s. Check Task Manager for a stray px.exe and end it if present."
    }
    $out = (Receive-Job $job 2>&1 | Out-String).Trim()
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    if ($out) { $out } else { "Done." }
}

function Test-ToolInstalled($tool) {
    $exe = Join-Path $script:Root ($tool.verify[0] -replace '/', '\')
    Test-Path $exe
}

function Get-ToolCommandName($tool) {
    # tools.json names the tool, which is not always what you type to run it:
    # ripgrep installs rg.exe. Readiness has to ask about the name someone
    # would actually type, or a perfectly good install reports as missing.
    [System.IO.Path]::GetFileNameWithoutExtension((($tool.verify[0] -split '/')[-1]))
}

function Test-ToolReady($name) {
    # Whether Windows would actually find this by typing its bare name right
    # now - the only thing a participant cares about. A file can exist under
    # the install root and still not be "ready" if PATH does not point there,
    # or if something else on PATH answers to the same name first; both look
    # identical to someone who is not a developer, so this is the one signal
    # the GUI shows for it, instead of exposing that distinction at all.
    $cmd = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cmd -or -not $cmd.Source) { return $false }
    $cmd.Source -like "$script:Root\*"
}

function Test-PersistentTool($tool) {
    -not ($tool.PSObject.Properties.Name -contains 'persistent_path' -and $tool.persistent_path -eq $false)
}

# ---- window ---------------------------------------------------------------

$form = New-Object System.Windows.Forms.Form
$form.Text = "Portable Toolkit"
$form.Size = New-Object System.Drawing.Size(560, 736)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

$lblRoot = New-Object System.Windows.Forms.Label
$lblRoot.Location = New-Object System.Drawing.Point(12, 12)
$lblRoot.AutoSize = $true
$form.Controls.Add($lblRoot)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = New-Object System.Drawing.Point(12, 34)
$lblStatus.AutoSize = $true
$lblStatus.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($lblStatus)

# ---- setup group ------------------------------------------------------------

$grpSetup = New-Object System.Windows.Forms.GroupBox
$grpSetup.Text = "Setup"
$grpSetup.Location = New-Object System.Drawing.Point(12, 68)
$grpSetup.Size = New-Object System.Drawing.Size(520, 96)
$form.Controls.Add($grpSetup)

# One choice, used by both buttons below: it decides how much Install puts on
# and how much Uninstall takes off, so there is never a question of which mode
# a given button is in.
$rdoBasic = New-Object System.Windows.Forms.RadioButton
$rdoBasic.Text = "Basic - the tools"
$rdoBasic.Location = New-Object System.Drawing.Point(15, 20)
$rdoBasic.Size = New-Object System.Drawing.Size(140, 20)
$rdoBasic.Checked = $true
$grpSetup.Controls.Add($rdoBasic)

$rdoFull = New-Object System.Windows.Forms.RadioButton
$rdoFull.Text = "Full - also document libraries, ripgrep and jq"
$rdoFull.Location = New-Object System.Drawing.Point(165, 20)
$rdoFull.Size = New-Object System.Drawing.Size(330, 20)
$grpSetup.Controls.Add($rdoFull)

$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text = "Install / Fix"
$btnInstall.Location = New-Object System.Drawing.Point(15, 48)
$btnInstall.Size = New-Object System.Drawing.Size(130, 28)
$grpSetup.Controls.Add($btnInstall)

$btnCheck = New-Object System.Windows.Forms.Button
$btnCheck.Text = "Show details"
$btnCheck.Location = New-Object System.Drawing.Point(155, 48)
$btnCheck.Size = New-Object System.Drawing.Size(110, 28)
$grpSetup.Controls.Add($btnCheck)

$btnUninstall = New-Object System.Windows.Forms.Button
$btnUninstall.Text = "Uninstall"
$btnUninstall.Location = New-Object System.Drawing.Point(275, 48)
$btnUninstall.Size = New-Object System.Drawing.Size(100, 28)
$grpSetup.Controls.Add($btnUninstall)

$lblMode = New-Object System.Windows.Forms.Label
$lblMode.Location = New-Object System.Drawing.Point(385, 54)
$lblMode.AutoSize = $true
$lblMode.ForeColor = [System.Drawing.Color]::Gray
$grpSetup.Controls.Add($lblMode)

$updateMode = {
    $lblMode.Text = if ($rdoFull.Checked) { "Uninstall also deletes files" } else { "Uninstall undoes settings only" }
}
$rdoBasic.Add_CheckedChanged($updateMode)
$rdoFull.Add_CheckedChanged($updateMode)
& $updateMode

# ---- progress panel ----------------------------------------------------------

# One row per tool in tools.json, plus python, so adding a tool there is still
# the only edit needed - this panel does not need to know their names in advance.
$progressNames = @($config.tools | ForEach-Object { $_.name }) + @('python', 'packages')
$script:statusLabels = @{}

$grpProgress = New-Object System.Windows.Forms.GroupBox
$grpProgress.Text = "Progress"
$grpProgress.Location = New-Object System.Drawing.Point(12, ($grpSetup.Bottom + 8))
$grpProgress.Size = New-Object System.Drawing.Size(520, (24 + 20 * $progressNames.Count))
$form.Controls.Add($grpProgress)

$y = 22
foreach ($name in $progressNames) {
    $lblName = New-Object System.Windows.Forms.Label
    $lblName.Text = $name
    $lblName.Location = New-Object System.Drawing.Point(15, $y)
    $lblName.Size = New-Object System.Drawing.Size(80, 18)
    $grpProgress.Controls.Add($lblName)

    $lblState = New-Object System.Windows.Forms.Label
    $lblState.Text = "checking..."
    $lblState.ForeColor = [System.Drawing.Color]::Gray
    $lblState.Location = New-Object System.Drawing.Point(100, $y)
    $lblState.Size = New-Object System.Drawing.Size(400, 18)
    $grpProgress.Controls.Add($lblState)

    $script:statusLabels[$name] = $lblState
    $y += 20
}

# ---- px group ---------------------------------------------------------------

$grpPx = New-Object System.Windows.Forms.GroupBox
$grpPx.Text = "Corporate proxy (px) - only needed if your network requires it"
$grpPx.Location = New-Object System.Drawing.Point(12, ($grpProgress.Bottom + 8))
$grpPx.Size = New-Object System.Drawing.Size(520, 130)
$form.Controls.Add($grpPx)

$lblPxState = New-Object System.Windows.Forms.Label
$lblPxState.Location = New-Object System.Drawing.Point(15, 20)
$lblPxState.AutoSize = $true
$grpPx.Controls.Add($lblPxState)

$lblProxy = New-Object System.Windows.Forms.Label
$lblProxy.Text = "Proxy address (host:port)"
$lblProxy.Location = New-Object System.Drawing.Point(15, 45)
$lblProxy.AutoSize = $true
$grpPx.Controls.Add($lblProxy)

$txtProxy = New-Object System.Windows.Forms.TextBox
$txtProxy.Location = New-Object System.Drawing.Point(15, 65)
$txtProxy.Size = New-Object System.Drawing.Size(300, 24)
$site = Get-SiteConfig
$savedProxy = Get-SavedPxProxy
if ($site -and $site.proxy) { $txtProxy.Text = $site.proxy }
elseif ($savedProxy) { $txtProxy.Text = $savedProxy }
$grpPx.Controls.Add($txtProxy)

$lblSite = New-Object System.Windows.Forms.Label
$lblSite.Location = New-Object System.Drawing.Point(325, 68)
$lblSite.AutoSize = $true
$lblSite.ForeColor = [System.Drawing.Color]::DarkGreen
$lblSite.Text = if ($site -and $site.proxy) { "from site.json" } elseif ($savedProxy) { "from saved settings" } else { "" }
$grpPx.Controls.Add($lblSite)

$chkAutoStart = New-Object System.Windows.Forms.CheckBox
$chkAutoStart.Text = "Start automatically when I log in"
$chkAutoStart.Location = New-Object System.Drawing.Point(15, 95)
$chkAutoStart.AutoSize = $true
$grpPx.Controls.Add($chkAutoStart)

$btnPxSave = New-Object System.Windows.Forms.Button
$btnPxSave.Text = "Save && start"
$btnPxSave.Location = New-Object System.Drawing.Point(325, 93)
$btnPxSave.Size = New-Object System.Drawing.Size(90, 28)
$grpPx.Controls.Add($btnPxSave)

$btnPxStop = New-Object System.Windows.Forms.Button
$btnPxStop.Text = "Stop"
$btnPxStop.Location = New-Object System.Drawing.Point(420, 93)
$btnPxStop.Size = New-Object System.Drawing.Size(80, 28)
$grpPx.Controls.Add($btnPxStop)

# ---- GitHub Copilot launcher --------------------------------------------

$grpCopilot = New-Object System.Windows.Forms.GroupBox
$grpCopilot.Text = "GitHub Copilot desktop app"
$grpCopilot.Location = New-Object System.Drawing.Point(12, ($grpPx.Bottom + 8))
$grpCopilot.Size = New-Object System.Drawing.Size(520, 60)
$form.Controls.Add($grpCopilot)

$btnLaunchCopilot = New-Object System.Windows.Forms.Button
$btnLaunchCopilot.Text = "Launch (fresh settings)"
$btnLaunchCopilot.Location = New-Object System.Drawing.Point(15, 22)
$btnLaunchCopilot.Size = New-Object System.Drawing.Size(170, 28)
$grpCopilot.Controls.Add($btnLaunchCopilot)

$lblCopilotHint = New-Object System.Windows.Forms.Label
$lblCopilotHint.Text = "Closes it if already running, then reopens it with today's proxy settings"
$lblCopilotHint.Location = New-Object System.Drawing.Point(195, 27)
$lblCopilotHint.AutoSize = $true
$lblCopilotHint.ForeColor = [System.Drawing.Color]::Gray
$grpCopilot.Controls.Add($lblCopilotHint)

# ---- log --------------------------------------------------------------------

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(12, ($grpCopilot.Bottom + 8))
$txtLog.Size = New-Object System.Drawing.Size(520, (676 - $grpCopilot.Bottom))
$txtLog.Multiline = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.ReadOnly = $true
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$form.Controls.Add($txtLog)

function Write-Log($text) {
    $txtLog.AppendText("$text`r`n")
}

# ---- status refresh -----------------------------------------------------

function Set-ProgressState {
    param([string]$Name, [string]$State, [string]$Detail = '')
    if (-not $script:statusLabels.ContainsKey($Name)) { return }
    $lbl = $script:statusLabels[$Name]
    $text = switch ($State) {
        'ready'            { 'Ready to use' }
        'needs-setup'       { 'Not ready yet - click Install / Fix' }
        'installed'         { 'Installed' }
        'not installed'     { 'Not installed yet' }
        'already-installed' { 'Already installed' }
        'downloading'       { 'Downloading...' }
        'verified'          { 'Verified, installing...' }
        'installing'        { 'Installing...' }
        'updating'          { 'Updating...' }
        'updated'           { 'Done' }
        'skipped'           { 'Skipped' }
        'done'              { 'Done' }
        'pending'           { 'Waiting...' }
        'error'             { "Something went wrong: $Detail" }
        default             { $State }
    }
    $color = switch -Regex ($State) {
        'error'                                                      { [System.Drawing.Color]::Red; break }
        'ready|installed|already-installed|updated|done'             { [System.Drawing.Color]::DarkGreen; break }
        'not installed|needs-setup'                                  { [System.Drawing.Color]::DarkOrange; break }
        'pending'                                                    { [System.Drawing.Color]::Gray; break }
        default                                                      { [System.Drawing.Color]::SteelBlue }
    }
    # A step that runs for minutes says why, so the row is not just "Installing..."
    # for the whole time with no indication of what or how long.
    if ($Detail -and $State -in 'installing', 'downloading', 'updating') { $text = "$text  $Detail" }
    $lbl.Text = $text
    $lbl.ForeColor = $color
}

function Update-Status {
    # Keeps this window's own view of the environment current with the
    # registry, so nothing it shows or launches is ever working from what
    # things looked like when the window was opened.
    Sync-Environment

    $script:Root = Resolve-InstallRoot
    $lblRoot.Text = "Install root: $script:Root"

    $pxRunning = $null -ne (Get-Process px -ErrorAction SilentlyContinue)
    $btnPxStop.Enabled = $pxRunning
    $lblPxState.Text = if (-not (Test-Path (Get-PxPath))) { "Not installed yet" }
                       elseif ($pxRunning) { "Running" }
                       else { "Stopped" }
    $lblPxState.ForeColor = if ($pxRunning) { [System.Drawing.Color]::DarkGreen } else { [System.Drawing.Color]::Gray }

    # While install/uninstall is actively running, Read-NewStatusLines owns
    # the progress labels; overwriting them here would fight with that.
    if ($script:trackedProcess) { return }

    $allReady = $true
    foreach ($tool in $config.tools) {
        if (Test-PersistentTool $tool) {
            $ready = Test-ToolReady (Get-ToolCommandName $tool)
            Set-ProgressState $tool.name $(if ($ready) { 'ready' } else { 'needs-setup' })
            if (-not $ready) { $allReady = $false }
        } else {
            # px: not something anyone types by name, so "ready" does not apply -
            # its own line above already covers whether it is doing anything.
            Set-ProgressState $tool.name $(if (Test-ToolInstalled $tool) { 'installed' } else { 'not installed' })
        }
    }
    $pythonReady = Test-ToolReady 'python'
    Set-ProgressState 'python' $(if ($pythonReady) { 'ready' } else { 'needs-setup' })
    if (-not $pythonReady) { $allReady = $false }

    if ($allReady) {
        $lblStatus.Text = "Ready to use"
        $lblStatus.ForeColor = [System.Drawing.Color]::DarkGreen
    } else {
        $lblStatus.Text = "Not ready yet - click Install / Fix below"
        $lblStatus.ForeColor = [System.Drawing.Color]::DarkOrange
    }
}

# ---- long-running actions (install / uninstall) --------------------------

$script:trackedProcess = $null
$script:activeStatusLog = $null
$script:statusLogOffset = 0

function Read-NewStatusLines {
    # install.ps1/uninstall.ps1 append "STATUS|name=...|state=...|detail=..."
    # lines as they go; this reads only what has been added since last read.
    if (-not $script:activeStatusLog -or -not (Test-Path $script:activeStatusLog)) { return }
    $content = Get-Content $script:activeStatusLog -Raw -ErrorAction SilentlyContinue
    if (-not $content -or $content.Length -le $script:statusLogOffset) { return }
    $new = $content.Substring($script:statusLogOffset)
    $script:statusLogOffset = $content.Length
    foreach ($line in ($new -split "`r?`n")) {
        # Free text from the installer, so a long step is visibly doing something.
        if ($line -match '^LOG\|(?<text>.*)$') { Write-Log $Matches.text; continue }
        if ($line -notmatch '^STATUS\|name=(?<name>[^|]*)\|state=(?<state>[^|]*)\|detail=(?<detail>.*)$') { continue }
        Set-ProgressState $Matches.name $Matches.state $Matches.detail
        Write-Log $(if ($Matches.detail) { "$($Matches.name): $($Matches.state) - $($Matches.detail)" } else { "$($Matches.name): $($Matches.state)" })
    }
}

function Start-Tracked($scriptPath, $extraArgs, $statusLogPath, $label) {
    $btnInstall.Enabled = $false
    $btnUninstall.Enabled = $false
    foreach ($lbl in $script:statusLabels.Values) { $lbl.Text = 'Waiting...'; $lbl.ForeColor = [System.Drawing.Color]::Gray }
    Remove-Item $statusLogPath -Force -ErrorAction SilentlyContinue
    $script:activeStatusLog = $statusLogPath
    $script:statusLogOffset = 0
    Write-Log "$label ..."
    $script:trackedProcess = Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -PassThru -ArgumentList (
        @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath) + $extraArgs
    )
}

function Sync-Environment {
    # install.ps1/uninstall.ps1/px change PATH and proxy variables via the
    # registry, which an already running process never sees on its own - this
    # window included. Without this, Check status (and anything this window
    # launches, including GitHub Copilot) keeps using whatever the GUI's own
    # environment looked like when it started, even right after fixing them.
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
    foreach ($name in 'HTTP_PROXY', 'HTTPS_PROXY', 'NO_PROXY', 'NODE_EXTRA_CA_CERTS', 'SSL_CERT_FILE') {
        # User scope wins, machine scope is the fallback - the same precedence
        # Windows itself uses, and the same as the PATH line above. Reading only
        # the user scope would delete a proxy that IT had set machine-wide, and
        # anything launched from here would then inherit nothing.
        $value = [Environment]::GetEnvironmentVariable($name, 'User')
        if (-not $value) { $value = [Environment]::GetEnvironmentVariable($name, 'Machine') }
        if ($value) { Set-Item "env:$name" $value } else { Remove-Item "env:$name" -ErrorAction SilentlyContinue }
    }
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
    Read-NewStatusLines
    if ($script:trackedProcess -and $script:trackedProcess.HasExited) {
        Read-NewStatusLines   # catch anything written between the last tick and exit
        Write-Log "Finished (exit code $($script:trackedProcess.ExitCode))."
        $script:trackedProcess = $null
        $script:activeStatusLog = $null
        $btnInstall.Enabled = $true
        $btnUninstall.Enabled = $true
    }
    Update-Status
})
$timer.Start()

# ---- button handlers ----------------------------------------------------

$btnInstall.Add_Click({
    # The only copy guaranteed to exist before a first install is this one.
    $scriptPath = Join-Path $PSScriptRoot 'install.ps1'
    $setupArgs = @('-Unattended')
    if ($rdoFull.Checked) { $setupArgs += '-IncludeOptional' }
    $label = if ($rdoFull.Checked) { 'Setting things up, with the extras' } else { 'Setting things up' }
    Start-Tracked $scriptPath $setupArgs (Join-Path $PSScriptRoot 'install.status.log') $label
})

$btnUninstall.Add_Click({
    $installed = Join-Path $script:Root 'toolkit\uninstall.ps1'
    if (-not (Test-Path $installed)) { Write-Log "Nothing to remove - it is not installed."; return }

    $removeArgs = @()
    $label = 'Undoing the settings'
    if ($rdoFull.Checked) {
        # Deleting files is worth one confirmation; undoing PATH is not.
        $answer = [System.Windows.Forms.MessageBox]::Show(
            "This deletes every installed tool and the Python environment under:`n`n$($script:Root)`n`n" +
            "Anything you installed into that Python goes too. The toolkit's own scripts stay, so you can reinstall.`n`nContinue?",
            "Full uninstall", 'YesNo', 'Warning')
        if ($answer -ne 'Yes') { Write-Log "Full uninstall cancelled."; return }
        $removeArgs += '-Full'
        $label = 'Removing everything'
    }
    Start-Tracked $installed $removeArgs (Join-Path $script:Root 'toolkit\uninstall.status.log') $label
})

$btnCheck.Add_Click({
    $installed = Join-Path $script:Root 'toolkit\check.ps1'
    if (-not (Test-Path $installed)) { Write-Log "Nothing installed yet. Click Install / Fix first."; return }
    Write-Log "Checking ..."
    Write-Log (Invoke-Timeboxed -TimeoutSec 20 -ArgumentList @($installed) -Script {
        param($checkScript)
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $checkScript 2>&1
    })
})

$btnPxSave.Add_Click({
    $value = $txtProxy.Text.Trim()
    if (-not (Test-Path (Get-PxPath))) { Write-Log "px is not installed yet. Click Install / Fix first."; return }
    if (-not $value) { Write-Log "Enter a proxy address first, e.g. proxy.example.com:8080"; return }
    $px = Get-PxPath
    Write-Log "Saving proxy $value ..."
    Write-Log (Invoke-Timeboxed -ArgumentList @($px, $value) -Script {
        param($px, $value)
        & $px --save --proxy=$value 2>&1
    })
    if ($chkAutoStart.Checked) {
        Write-Log "Registering px to start at logon ..."
        Write-Log (Invoke-Timeboxed -ArgumentList @($px) -Script { param($px) & $px --install 2>&1 })
    }
    if (-not (Get-Process px -ErrorAction SilentlyContinue)) {
        Start-Process -FilePath $px -WorkingDirectory (Split-Path $px) -WindowStyle Hidden
        Write-Log "px started."
    }
    Update-Status
})

$btnPxStop.Add_Click({
    $px = Get-PxPath
    if (-not (Get-Process px -ErrorAction SilentlyContinue)) { Write-Log "px is not running."; return }
    Write-Log (Invoke-Timeboxed -ArgumentList @($px) -Script { param($px) & $px --quit 2>&1 })
    Update-Status
})

$btnLaunchCopilot.Add_Click({
    $exe = Get-CopilotAppPath
    if (-not $exe) { Write-Log "GitHub Copilot app not found at the usual install location."; return }

    # A copy already running keeps whatever environment it started with, the
    # same problem this button exists to avoid - so it needs to go first. Ask it
    # to close rather than killing it outright, because a forced exit loses
    # whatever the person had not saved.
    $running = @(Get-Process | Where-Object { $_.ProcessName -in 'github', 'copilot' })
    if ($running.Count) {
        Write-Log "Asking GitHub Copilot to close ..."
        foreach ($p in $running) { [void]$p.CloseMainWindow() }

        $deadline = (Get-Date).AddSeconds(5)
        while ((Get-Date) -lt $deadline) {
            if (-not (Get-Process -Id $running.Id -ErrorAction SilentlyContinue)) { break }
            Start-Sleep -Milliseconds 200
        }

        $stubborn = @(Get-Process -Id $running.Id -ErrorAction SilentlyContinue)
        if ($stubborn.Count) {
            Write-Log "It did not close after 5 seconds. Forcing it - unsaved work there will be lost."
            $stubborn | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
        }
    }

    Sync-Environment
    Start-Process -FilePath $exe
    Write-Log "Launched GitHub Copilot with today's proxy settings."
})

# ---- go ---------------------------------------------------------------------

Update-Status
[System.Windows.Forms.Application]::Run($form)

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
. (Join-Path $PSScriptRoot 'proxy-display.ps1')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$config = Get-Content (Join-Path $PSScriptRoot 'tools.json') -Raw | ConvertFrom-Json
# Get-MachineWidePython and Get-MachinePythonMarker live here, so this window
# and the installer decide the same way what a bare "python" reaches.
. (Join-Path $PSScriptRoot 'paths.ps1')

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

function Test-PxListening {
    # Whether anything is answering on Px's port. A px process existing is not
    # the same thing: it exits by itself when it has no upstream configured.
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $ok = $c.ConnectAsync('127.0.0.1', 3128).Wait(1500)
        $c.Close()
        return $ok
    } catch { return $false }
}

function Test-UpstreamReachable {
    # Whether the proxy Px has been told to relay to can be reached from where
    # this machine is now. A saved proxy is a company address; carry the laptop
    # home and it is simply not there any more.
    $server = Get-SavedPxProxy
    if (-not $server) { return $false }
    try {
        $parts = $server -replace '^\w+://', ''
        $hostName, $port = $parts.Split(':', 2)
        if (-not $port) { $port = 8080 }
        $c = New-Object System.Net.Sockets.TcpClient
        $ok = $c.ConnectAsync($hostName, [int] $port).Wait(2000)
        $c.Close()
        return $ok
    } catch { return $false }
}

function Start-PxForCopilot {
    # Copilot is the reason Px is here: it cannot get through an authenticating
    # proxy on its own. Starting Copilot without Px running, on a network that
    # needs it, reproduces the failure this button exists to avoid.
    #
    # Sets the proxy variables in this process only, so the Copilot started
    # below inherits them. Nothing is written to your account or the machine.
    $px = Get-PxPath
    if (-not (Test-Path $px)) { return $false }

    # Px listening is not the same as Px working. It binds its port wherever it
    # is, so on a network that cannot see the saved proxy it accepts every
    # connection and fails every request - which reads as "tunnel error" in
    # Copilot. Sending the app through it then is worse than not using it.
    $saved = Get-SavedPxProxy
    if ($saved -and -not (Test-UpstreamReachable)) {
        Write-Log "The saved proxy $(Format-ProxyAddress $saved) cannot be reached from this network, so Px was not used."
        Write-Log "Copilot will start without a proxy. Press Stop under Px if it is running and still interfering."
        Remove-Item env:HTTP_PROXY, env:HTTPS_PROXY -ErrorAction SilentlyContinue
        return $false
    }

    if (-not (Test-PxListening)) {
        if (-not $saved) {
            Write-Log "Px has no proxy saved, so it was not started. If Copilot cannot sign in, put the address above and press Save & start."
            return $false
        }
        Write-Log "Starting Px so Copilot can get through the proxy ..."
        try { Start-Process -FilePath $px -WorkingDirectory (Split-Path $px) -WindowStyle Hidden } catch { }
        for ($i = 0; $i -lt 10; $i++) {
            Start-Sleep -Milliseconds 700
            if (Test-PxListening) { break }
        }
    }

    if (Test-PxListening) {
        $env:HTTP_PROXY = 'http://127.0.0.1:3128'
        $env:HTTPS_PROXY = 'http://127.0.0.1:3128'
        Write-Log "Px is serving. Copilot will start pointed at it."
        return $true
    }

    Write-Log "Px did not start. Copilot starts with the proxy settings as they are."
    $false
}

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

function Get-NetworkProxy {
    # What Windows would use to reach the internet from here, including via an
    # automatic configuration script. This is the same answer setup gives uv,
    # so showing it here means the field says what will actually be used rather
    # than asking someone to find out.
    foreach ($probe in 'https://pypi.org', 'https://github.com') {
        try {
            $r = [System.Net.WebRequest]::GetSystemWebProxy().GetProxy($probe)
            if ($r -and $r.AbsoluteUri -ne ([Uri] $probe).AbsoluteUri) { return $r.Authority }
        } catch { }
    }
    $null
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
# Sized at the end, once the left column's height is known - see the bottom of
# this file. Two columns rather than one: the controls stack on the left, the
# log fills the right, which keeps the window a sensible shape on a laptop
# screen instead of growing taller with every addition.
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'Sizable'
$form.MaximizeBox = $true

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

# One install, not a choice. Every lab past reading a document needs the
# document libraries, so an install without them is a state nobody should be
# able to end up in by leaving a box unticked.
$lblSetupHint = New-Object System.Windows.Forms.Label
$lblSetupHint.Text = "Installs the tools, Python, and the libraries that read documents"
$lblSetupHint.Location = New-Object System.Drawing.Point(15, 22)
$lblSetupHint.Size = New-Object System.Drawing.Size(490, 20)
$lblSetupHint.ForeColor = [System.Drawing.Color]::DimGray
$grpSetup.Controls.Add($lblSetupHint)

$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text = "Install / Fix"
$btnInstall.Location = New-Object System.Drawing.Point(15, 48)
$btnInstall.Size = New-Object System.Drawing.Size(120, 28)
$grpSetup.Controls.Add($btnInstall)

$btnCheck = New-Object System.Windows.Forms.Button
$btnCheck.Text = "Show details"
$btnCheck.Location = New-Object System.Drawing.Point(143, 48)
$btnCheck.Size = New-Object System.Drawing.Size(105, 28)
$grpSetup.Controls.Add($btnCheck)

# Two buttons rather than one whose meaning depends on a setting elsewhere on
# the form. What each does is in its own label.
$btnUninstall = New-Object System.Windows.Forms.Button
$btnUninstall.Text = "Uninstall"
$btnUninstall.Location = New-Object System.Drawing.Point(256, 48)
$btnUninstall.Size = New-Object System.Drawing.Size(95, 28)
$grpSetup.Controls.Add($btnUninstall)

$btnRemoveAll = New-Object System.Windows.Forms.Button
$btnRemoveAll.Text = "Remove everything"
$btnRemoveAll.Location = New-Object System.Drawing.Point(359, 48)
$btnRemoveAll.Size = New-Object System.Drawing.Size(145, 28)
$grpSetup.Controls.Add($btnRemoveAll)

# ---- status panel ------------------------------------------------------------

# Named Status rather than Progress because that is what it shows nearly all of
# the time: what is installed right now. It only reports progress while setup is
# running.
#
# Two columns for the shape of the window, not because there are two kinds of
# install. The left is what you type a name to run, the right is Python and what
# it can read. The tool list still comes from tools.json, so adding a tool there
# remains the only edit needed.
$basicNames = @($config.tools | ForEach-Object { $_.name })
$fullNames  = @('python', 'packages', 'machine-python')
$script:statusLabels = @{}

$rows = [Math]::Max($basicNames.Count, $fullNames.Count)

$grpProgress = New-Object System.Windows.Forms.GroupBox
$grpProgress.Text = "Status"
$grpProgress.Location = New-Object System.Drawing.Point(12, ($grpSetup.Bottom + 8))
$grpProgress.Size = New-Object System.Drawing.Size(520, (44 + 20 * $rows))
$form.Controls.Add($grpProgress)

$rowLabels = @{ 'machine-python' = 'machine py'; 'packages' = 'libraries' }

function Add-StatusColumn($Names, $Heading, $X, $Width) {
    $lblHead = New-Object System.Windows.Forms.Label
    $lblHead.Text = $Heading
    $lblHead.Location = New-Object System.Drawing.Point($X, 20)
    $lblHead.Size = New-Object System.Drawing.Size($Width, 16)
    $lblHead.ForeColor = [System.Drawing.Color]::DimGray
    $grpProgress.Controls.Add($lblHead)

    $y = 40
    foreach ($name in $Names) {
        $lblName = New-Object System.Windows.Forms.Label
        # The status key and the word on screen are not always the same:
        # "machine-python" is what the installer reports and does not fit.
        $lblName.Text = if ($rowLabels.ContainsKey($name)) { $rowLabels[$name] } else { $name }
        $lblName.Location = New-Object System.Drawing.Point($X, $y)
        $lblName.Size = New-Object System.Drawing.Size(72, 18)
        $grpProgress.Controls.Add($lblName)

        $lblState = New-Object System.Windows.Forms.Label
        $lblState.Text = "checking..."
        $lblState.ForeColor = [System.Drawing.Color]::Gray
        $lblState.Location = New-Object System.Drawing.Point(($X + 76), $y)
        $lblState.Size = New-Object System.Drawing.Size(($Width - 76), 18)
        $grpProgress.Controls.Add($lblState)

        $script:statusLabels[$name] = $lblState
        $y += 20
    }
}

Add-StatusColumn $basicNames 'Tools' 15 225
Add-StatusColumn $fullNames  'Python' 250 255

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
$lblProxy.Text = "Proxy address (usually filled in for you)"
$lblProxy.Location = New-Object System.Drawing.Point(15, 45)
$lblProxy.AutoSize = $true
$grpPx.Controls.Add($lblProxy)

$txtProxy = New-Object System.Windows.Forms.TextBox
$txtProxy.Location = New-Object System.Drawing.Point(15, 65)
$txtProxy.Size = New-Object System.Drawing.Size(300, 24)
$site = Get-SiteConfig
$savedProxy = Get-SavedPxProxy
# Three places it can come from, most specific first. The last is the point:
# on a network with a proxy, this fills itself in and nobody has to ask what
# the address is.
$networkProxy = Get-NetworkProxy
if ($site -and $site.proxy) { $txtProxy.Text = $site.proxy }
elseif ($savedProxy) { $txtProxy.Text = $savedProxy }
elseif ($networkProxy) { $txtProxy.Text = $networkProxy }
$grpPx.Controls.Add($txtProxy)

$lblSite = New-Object System.Windows.Forms.Label
$lblSite.Location = New-Object System.Drawing.Point(325, 68)
$lblSite.AutoSize = $true
$lblSite.ForeColor = [System.Drawing.Color]::DarkGreen
$lblSite.Text = if ($site -and $site.proxy) { "from site.json" }
                elseif ($savedProxy) { "from saved settings" }
                elseif ($networkProxy) { "found on this network" }
                else { "" }
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
$lblCopilotHint.Text = "Closes it if running, starts Px if needed, then reopens it"
$lblCopilotHint.Location = New-Object System.Drawing.Point(195, 27)
$lblCopilotHint.AutoSize = $true
$lblCopilotHint.ForeColor = [System.Drawing.Color]::Gray
$grpCopilot.Controls.Add($lblCopilotHint)

# ---- log --------------------------------------------------------------------

# The right-hand column. It starts level with the first group on the left and
# runs to the same bottom edge, so the two columns square up whatever the left
# one ends up being - the progress panel grows a row per tool in tools.json.
$logLeft = 12 + 520 + 12
$logWidth = 450
$logTop = $grpSetup.Top
$logBottom = $grpCopilot.Bottom

$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = "Log"
$lblLog.Location = New-Object System.Drawing.Point($logLeft, ($logTop - 20))
$lblLog.AutoSize = $true
$lblLog.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($lblLog)

# Quiet, and out of the way until wanted. Reporting a problem means sending
# this text, and selecting it by hand in a read-only box is awkward.
$btnCopyLog = New-Object System.Windows.Forms.Button
$btnCopyLog.Text = "Copy"
$btnCopyLog.Size = New-Object System.Drawing.Size(62, 22)
$btnCopyLog.Location = New-Object System.Drawing.Point(($logLeft + $logWidth - 62), ($logTop - 24))
$btnCopyLog.FlatStyle = 'Flat'
$btnCopyLog.FlatAppearance.BorderColor = [System.Drawing.Color]::LightGray
$btnCopyLog.ForeColor = [System.Drawing.Color]::DimGray
$btnCopyLog.TabStop = $false
$form.Controls.Add($btnCopyLog)

# Sits with Copy because its answer arrives in the box below them, and the two
# together are the whole of "tell someone what went wrong".
$btnNetCheck = New-Object System.Windows.Forms.Button
$btnNetCheck.Text = "Network check"
$btnNetCheck.Size = New-Object System.Drawing.Size(112, 22)
$btnNetCheck.Location = New-Object System.Drawing.Point(($logLeft + $logWidth - 62 - 6 - 112), ($logTop - 24))
$btnNetCheck.FlatStyle = 'Flat'
$btnNetCheck.FlatAppearance.BorderColor = [System.Drawing.Color]::LightGray
$btnNetCheck.ForeColor = [System.Drawing.Color]::DimGray
$btnNetCheck.TabStop = $false
$form.Controls.Add($btnNetCheck)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point($logLeft, $logTop)
$txtLog.Size = New-Object System.Drawing.Size($logWidth, ($logBottom - $logTop))
$txtLog.Multiline = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.ReadOnly = $true
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$form.Controls.Add($txtLog)

# Now that both columns exist, make the window exactly fit them.
$form.ClientSize = New-Object System.Drawing.Size(($logLeft + $logWidth + 12), ($logBottom + 12))

# Resizable, but never smaller than the controls need. Only the log stretches:
# the left column is a fixed stack, so it anchors top-left and stays put.
$form.MinimumSize = $form.Size
$txtLog.Anchor = 'Top,Bottom,Left,Right'
$btnCopyLog.Anchor = 'Top,Right'
$btnNetCheck.Anchor = 'Top,Right'

# Says "Copied" briefly, then goes back. Without that there is no sign it
# worked, and people press it again.
$copyReset = New-Object System.Windows.Forms.Timer
$copyReset.Interval = 1200
$copyReset.Add_Tick({ $btnCopyLog.Text = "Copy"; $copyReset.Stop() })

function Copy-LogToClipboard {
    # A function rather than the body of the click handler, so it can be
    # exercised without a window on screen.
    if (-not $txtLog.Text) { $btnCopyLog.Text = "Empty"; $copyReset.Start(); return $false }
    $copied = $false
    # Set-Clipboard is the tidy way; the WinForms call is the fallback for a
    # host that does not have it.
    try { Set-Clipboard -Value $txtLog.Text; $copied = $true } catch { }
    if (-not $copied) {
        try { [System.Windows.Forms.Clipboard]::SetText($txtLog.Text); $copied = $true } catch { }
    }
    $btnCopyLog.Text = if ($copied) { "Copied" } else { "Failed" }
    $copyReset.Start()
    $copied
}

$btnCopyLog.Add_Click({ [void](Copy-LogToClipboard) })

function Write-Log($text) {
    $txtLog.AppendText("$(Protect-ProxyText $text)`r`n")
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
        'not-asked-for'     { 'Not installed yet - click Install / Fix' }
        'not-needed'        { 'Not needed - python here is the toolkit''s' }
        'machine-ready'     { 'Ready - this machine''s own Python, libraries added' }
        'libraries-added'   { 'Libraries added to it' }
        'kept'              { 'Already installed, left as it is' }
        'left-running'      { 'Left running - needed to reinstall' }
        'done'              { 'Done' }
        'pending'           { 'Waiting...' }
        'error'             { "Something went wrong: $Detail" }
        default             { $State }
    }
    $color = switch -Regex ($State) {
        'error'                                                      { [System.Drawing.Color]::Red; break }
        'ready|installed|already-installed|updated|done|machine-ready|libraries-added' { [System.Drawing.Color]::DarkGreen; break }
        'not-asked-for|not-needed'                                   { [System.Drawing.Color]::Gray; break }
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
    if ($script:trackedProcess -and -not $script:trackedReportsOnly) { return }

    # "Ready" means every tool answers to its own name and Python can read a
    # document. There is one install, so anything missing is genuinely missing.
    $allReady = $true
    foreach ($tool in $config.tools) {
        $installed = Test-ToolInstalled $tool

        if (-not (Test-PersistentTool $tool)) {
            # px: not something anyone types by name, so "ready" does not apply -
            # its own line above already covers whether it is doing anything.
            Set-ProgressState $tool.name $(if ($installed) { 'installed' } else { 'not installed' })
            continue
        }

        $ready = Test-ToolReady (Get-ToolCommandName $tool)
        Set-ProgressState $tool.name $(if ($ready) { 'ready' } else { 'needs-setup' })
        if (-not $ready) { $allReady = $false }
    }

    # Typing "python" on a machine that has one installed for all users reaches
    # that one, and no user PATH can change it. Setup handles that by putting
    # the document libraries there too, so it is a working state, not a fault -
    # and saying "not ready" about a machine that works is worse than useless.
    $machinePython = Get-MachineWidePython
    $machineHandled = $machinePython -and (Test-Path (Get-MachinePythonMarker $script:Root))

    $pythonReady = Test-ToolReady 'python'
    if ($pythonReady) {
        Set-ProgressState 'python' 'ready'
    } elseif ($machineHandled) {
        Set-ProgressState 'python' 'machine-ready'
    } else {
        Set-ProgressState 'python' 'needs-setup'
        $allReady = $false
    }

    # The document libraries. Looking for one of them on disk rather than asking
    # Python to import them, because this runs on a timer and launching an
    # interpreter every second to answer it would be absurd.
    $marker = Join-Path $script:Root ($config.python.environment + '\Lib\site-packages\markitdown')
    Set-ProgressState 'packages' $(if (Test-Path $marker) { 'installed' } else { 'not-asked-for' })

    # A Python installed for all users answers to "python" whatever is on the
    # user PATH, so the libraries have to be in that one too or an assistant
    # typing "python" finds none of them. Nothing to do where there is no such
    # Python, which is the common case off a corporate image.
    if (-not $machinePython) {
        Set-ProgressState 'machine-python' 'not-needed'
    } elseif ($machineHandled) {
        Set-ProgressState 'machine-python' 'libraries-added'
    } else {
        Set-ProgressState 'machine-python' 'needs-setup'
    }

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
$script:trackedScript = $null
$script:trackedReportsOnly = $false
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

function Start-Tracked {
    # -Reports is for a run that only looks at things. It changes nothing, so
    # the status rows keep saying what is installed instead of going blank.
    param($scriptPath, $extraArgs, $statusLogPath, $label, [switch] $Reports)
    $script:trackedScript = $scriptPath
    $btnInstall.Enabled = $false
    $btnUninstall.Enabled = $false
    $btnRemoveAll.Enabled = $false
    $btnNetCheck.Enabled = $false
    $script:trackedReportsOnly = [bool] $Reports
    if (-not $Reports) {
        foreach ($lbl in $script:statusLabels.Values) { $lbl.Text = 'Waiting...'; $lbl.ForeColor = [System.Drawing.Color]::Gray }
    }
    Remove-Item $statusLogPath -Force -ErrorAction SilentlyContinue
    $script:activeStatusLog = $statusLogPath
    $script:statusLogOffset = 0
    Write-Log "$label ..."
    # Start-Process joins an ArgumentList array into one command line without
    # quoting its elements. The extracted folder and status log can both have
    # spaces in their paths; without quotes, powershell.exe exits before the
    # script starts, with no status lines for the window to show.
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath) + $extraArgs
    $quotedArguments = $arguments | ForEach-Object { '"' + $_ + '"' }
    $script:trackedProcess = Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -PassThru -ArgumentList ($quotedArguments -join ' ')
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

function Start-NetworkCheck {
    # Reports how this machine reaches the internet. Run as a tracked process
    # rather than inline, because it makes several network calls with their own
    # timeouts and doing that on the UI thread would freeze the window for as
    # long as it takes.
    $checkScript = Join-Path $PSScriptRoot 'network-check.ps1'
    if (-not (Test-Path $checkScript)) { Write-Log "network-check.ps1 is missing from $PSScriptRoot."; return }
    $log = Join-Path $PSScriptRoot 'network-check.status.log'
    Start-Tracked $checkScript @('-StatusLog', $log) $log 'Checking how this machine reaches the internet' -Reports
}

function Invoke-Tick {
    # The timer's body as a function, so it can be exercised without a window
    # on screen - the same reason Copy-LogToClipboard is one.
    Read-NewStatusLines
    if ($script:trackedProcess -and $script:trackedProcess.HasExited) {
        Read-NewStatusLines   # catch anything written between the last tick and exit
        $code = $script:trackedProcess.ExitCode
        $wasReport = $script:trackedReportsOnly
        $hadStatusLog = $false
        try {
            $hadStatusLog = $script:activeStatusLog -and (Test-Path $script:activeStatusLog) -and
                ((Get-Item $script:activeStatusLog).Length -gt 0)
        } catch { }
        $wasLockTimeout = $false
        if ($code -ne 0 -and -not $wasReport -and $script:activeStatusLog) {
            try {
                $wasLockTimeout = (Get-Content $script:activeStatusLog -Raw -ErrorAction Stop) -match 'Timeout \(\d+s\) when waiting for lock'
            } catch { }
        }
        Write-Log "Finished (exit code $code)."
        $script:trackedProcess = $null
        $script:trackedReportsOnly = $false
        $script:activeStatusLog = $null
        $btnInstall.Enabled = $true
        $btnUninstall.Enabled = $true
        $btnRemoveAll.Enabled = $true
        $btnNetCheck.Enabled = $true

        # A script that is no longer on disk was taken off it while it ran. That
        # is security software, not a fault in the toolkit, and no amount of
        # network checking will say so. Seen on a machine running Bitdefender:
        # the run stops part way with no error line, and install.ps1 is gone.
        if ($code -ne 0 -and -not $wasReport -and $script:trackedScript -and
            -not (Test-Path $script:trackedScript)) {
            Write-Log ""
            Write-Log "$(Split-Path -Leaf $script:trackedScript) is no longer on disk. It was removed while it ran."
            Write-Log "That is antivirus quarantining it, not a fault here and not a network problem."
            Write-Log "It needs an exclusion for this folder from whoever manages endpoint security."
            Write-Log "See 'Antivirus quarantined the toolkit' in toolkit\troubleshooting.md."
            Update-Status
            return
        }

        if ($code -ne 0 -and -not $wasReport -and -not $hadStatusLog) {
            Write-Log ""
            Write-Log "The action stopped before it could write a log line."
            if ((Split-Path -Leaf $script:trackedScript) -eq 'install.ps1') {
                Write-Log "Run SETUP.cmd from this folder to see the PowerShell error."
            }
            Update-Status
            return
        }

        # Nearly everything else that fails here fails at the network, and the
        # answer is in this report. Running it unasked means the log already
        # holds what is needed to say why - one Copy, no second round trip.
        if ($code -ne 0 -and -not $wasReport -and -not $wasLockTimeout) {
            Write-Log ""
            Write-Log "That did not finish. Checking the network so the log says why:"
            Start-NetworkCheck
        }
    }
    Update-Status
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({ Invoke-Tick })
$timer.Start()

# ---- button handlers ----------------------------------------------------

$btnInstall.Add_Click({
    # The only copy guaranteed to exist before a first install is this one.
    $scriptPath = Join-Path $PSScriptRoot 'install.ps1'
    Start-Tracked $scriptPath @('-Unattended') (Join-Path $PSScriptRoot 'install.status.log') 'Setting things up'
})

$btnUninstall.Add_Click({
    # Undoes what setup changed outside its own folder and leaves the files, so
    # reinstalling is quick and Px keeps serving.
    $installed = Join-Path $script:Root 'toolkit\uninstall.ps1'
    if (-not (Test-Path $installed)) { Write-Log "Nothing to undo - it is not installed."; return }
    Start-Tracked $installed @() (Join-Path $script:Root 'toolkit\uninstall.status.log') 'Undoing the settings'
})

$btnRemoveAll.Add_Click({
    $installed = Join-Path $script:Root 'toolkit\uninstall.ps1'
    if (-not (Test-Path $installed)) { Write-Log "Nothing to remove - it is not installed."; return }

    # Deleting files is worth one confirmation; undoing PATH is not.
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "This deletes every installed tool and the Python environment under:`n`n$($script:Root)`n`n" +
        "Anything you installed into that Python goes too. The toolkit's own scripts stay, so you can reinstall.`n`nContinue?",
        "Remove everything", 'YesNo', 'Warning')
    if ($answer -ne 'Yes') { Write-Log "Cancelled - nothing was removed."; return }

    Start-Tracked $installed @('-Full') (Join-Path $script:Root 'toolkit\uninstall.status.log') 'Removing everything'
})

$btnNetCheck.Add_Click({ Start-NetworkCheck })

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
    Write-Log "Saving proxy $(Format-ProxyAddress $value) ..."
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

    # Order matters. Sync-Environment rebuilds the proxy variables from your
    # account settings, and would undo the next line if it ran after it.
    Sync-Environment
    [void](Start-PxForCopilot)
    Start-Process -FilePath $exe
    Write-Log "Launched GitHub Copilot."
})

# ---- go ---------------------------------------------------------------------

Update-Status
[System.Windows.Forms.Application]::Run($form)

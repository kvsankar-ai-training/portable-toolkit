# Troubleshooting

## SETUP.cmd opens and closes immediately

The window closed before you could read it. Open PowerShell in the toolkit
folder and run the installer directly so the error stays on screen:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

## "cannot be loaded because running scripts is disabled on this system"

Execution policy is set by Group Policy, which overrides the `-ExecutionPolicy
Bypass` switch in `SETUP.cmd`. Nothing in the toolkit can work around this, and
nothing should try.

Check which level set it:

```powershell
Get-ExecutionPolicy -List
```

If `MachinePolicy` or `UserPolicy` is anything other than `Undefined`, the
setting comes from your organisation. Report it rather than looking for a way
round it.

## "is not digitally signed" or "operation did not complete successfully"

The files still carry the marker Windows puts on anything downloaded. Unblock
the whole folder:

```powershell
Get-ChildItem -Recurse -File | Unblock-File
```

Unblocking the zip before extracting avoids this in one step.

## The download fails, or hangs, or reports a certificate error

A proxy is between you and the download. If your proxy needs explicit
configuration:

```powershell
$env:HTTPS_PROXY = 'http://your-proxy:8080'
```

A certificate error usually means the proxy is inspecting traffic and
re-signing it. Do not disable certificate validation. Report it.

## "checksum mismatch"

The file that arrived is not the file that was published. The usual cause is a
proxy returning a login page instead of the download, so the "archive" is HTML.
Stop here and report it. Do not install it.

## AppLocker or WDAC blocks uv.exe, node.exe or git.exe

The message mentions your system administrator and a policy. The tools
installed, but the machine will not run programs from a user-writable folder.

This cannot be worked around from inside the toolkit. Record the exact message
and which executable was blocked.

## Python is installed but `python` still runs a different one

`scripts\env.ps1` only affects the window it was run in. Run it again in the
new window, or re-run `SETUP.cmd` and answer `y` to the PATH question.

Check which one is being found:

```powershell
Get-Command python | Select-Object -ExpandProperty Source
```

## Removing everything

Delete the folder. If you answered `y` to the PATH question, also remove the
entries from your user PATH under Settings, Edit environment variables for
your account.

## `python` runs the wrong Python after installing

Windows builds a process's PATH from the system entries first and the user
entries second. Setup can only write the user part, so a Python, Node or Git
that is installed for all users will always be found first, and no user-level
change can outrank it.

`check.ps1` reports this explicitly when it happens:

```
  python C:\Python314\python.exe
         ^ installed machine-wide; user PATH cannot override it
```

Either use `run.cmd python ...`, or call `<root>\env\Scripts\python.exe`
directly. Both bypass name resolution entirely.

## A terminal or assistant does not see the tools

A running process keeps the environment it was started with, so a PATH change
does not reach anything that was already open. Close the terminal, editor or
assistant and start it again.

## Setup could not create C:\tools

Setup falls back to `%USERPROFILE%\tools` and says which it used. If both
failed, the account cannot write to either location, which is worth reporting.

## Removing everything

```powershell
<root>\toolkit\uninstall.ps1
```

That removes the toolkit's user PATH entries. It then tells you to delete the
folder, which it cannot do while running from inside it.

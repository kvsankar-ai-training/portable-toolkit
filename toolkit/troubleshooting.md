# Troubleshooting

## SETUP.cmd opens and closes immediately

The window closed before you could read it. Open PowerShell in the toolkit
folder and run the installer directly so the error stays on screen:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\toolkit\install.ps1
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

## The proxy answers with 407, and setting HTTPS_PROXY is not enough

Some corporate proxies require NTLM or Kerberos authentication on every
connection, not just a proxy address. Tools that only read `HTTPS_PROXY` have
no way to answer that challenge and fail even though the address is correct.
Windows tools that use the system network stack (a browser, curl, PowerShell's
`Invoke-WebRequest`) can pass this silently using your logged-in credentials;
many command-line tools cannot.

`px`, included in this toolkit, sits between such a tool and the real proxy,
answers the authentication challenge on your behalf using your Windows session,
and presents a plain, unauthenticated proxy on `127.0.0.1:3128`.

Configure it once with your proxy's address:

```powershell
run.cmd px --save --proxy=your-proxy:port
```

Register it to start automatically at logon:

```powershell
run.cmd px --install
```

Then point tools at it instead of the real proxy:

```powershell
$env:HTTPS_PROXY = 'http://127.0.0.1:3128'
```

This relies on your own Windows credentials and changes nothing about what the
proxy allows through; it only lets a tool clear an authentication step your
session would have cleared automatically anyway. If in doubt, ask whoever runs
the proxy before installing it to start automatically.

`GUI.cmd` does all three of the above (save, start, stop) from buttons, and
pre-fills the address if a `toolkit\site.json` is present. See
[`README.md`](../README.md#site-specific-values-proxy-addresses) for where
that file comes from.

## GitHub Copilot fails with "error sending request for url", even with the proxy set correctly

If the direct proxy is configured correctly (confirmed reachable with `curl`)
and GitHub Copilot's desktop app still fails to sign in or create a session
with this error, the cause is usually not authentication but the proxy's TLS
inspection itself: some Rust-based clients do not handle the certificate
swap an inspecting proxy performs the same way a browser or `curl` does.

Routing through `px` instead of the proxy directly has resolved this in
practice, even though `px` was originally added here only for NTLM/Kerberos
authentication:

```powershell
$env:HTTP_PROXY = 'http://127.0.0.1:3128'
$env:HTTPS_PROXY = 'http://127.0.0.1:3128'
```

Then fully close and reopen GitHub Copilot's desktop app so it picks up the
change - `GUI.cmd` has a "Launch (fresh settings)" button under GitHub Copilot
desktop app that does exactly this: closes any running copy and reopens it
with the current proxy settings, rather than whatever it started with.

Do not also set `NODE_EXTRA_CA_CERTS` or `SSL_CERT_FILE` to a custom
certificate file alongside this. Windows already trusts your organisation's
inspection certificate through its own certificate store once IT has deployed
it, and once traffic is routed through `px` that is what actually gets used -
pointing these variables at a manually exported certificate file instead
replaces that working, complete trust chain with whatever got exported, which
is easy to get subtly wrong (for example, a certificate authority is not just
one file - exporting only the root and not the intermediate certificate
authorities underneath it produces exactly this failure). If both a proxy and
a custom certificate were configured at some point while diagnosing a
different problem, remove the certificate variables first and see if the
proxy alone is now enough - it may be the underlying issue px already solved.

## Setup fails with 407, and it worked the last time

A 407 means the proxy wants credentials. Two things can cause it to appear
between one install and the next.

**Px was stopped.** If your network needs Px, it is how everything here
reaches the internet. Older versions of `uninstall.ps1` stopped and
deregistered it even on a plain uninstall, so the next install had nothing to
authenticate through. It is now left alone unless you ask for a full removal.
Start it again:

```powershell
<root>\run.cmd px
```

**The proxy wants NTLM or Kerberos.** Setup now offers your logged-in Windows
session when it downloads, which is what a browser does, so this should pass
without Px. `uv` cannot do that - it has no way to answer the challenge - so
the Python download still needs Px running. Setup detects a running Px and
routes `uv` through it automatically.

If it still fails, configure Px and try again:

```powershell
<root>\run.cmd px --save --proxy=your-proxy:port
<root>\run.cmd px
```

## "checksum mismatch"

The file that arrived is not the file that was published. The usual cause is a
proxy returning a login page instead of the download, so the "archive" is HTML.
Stop here and report it. Do not install it.

## AppLocker or WDAC blocks uv.exe, node.exe or git.exe

The message mentions your system administrator and a policy. The tools
installed, but the machine will not run programs from a user-writable folder.

This cannot be worked around from inside the toolkit. Record the exact message
and which executable was blocked.

## `python` runs the wrong Python after installing

Two causes, and `check.ps1` tells them apart. Start there:

```powershell
<root>\toolkit\check.ps1
```

**Something is installed machine-wide.** Windows builds a process's PATH from
the system entries first and the user entries second. Setup can only write the
user part, so a Python, Node or Git installed for all users is always found
first, and no user-level change can outrank it.

```
  python C:\Python314\python.exe
         ^ installed machine-wide; user PATH cannot override it
```

**Or this window started before setup ran.** A process keeps the environment it
was launched with. Open a new window, or run `toolkit\env.ps1`, which affects
only the window it is run in.

Either way, these bypass name resolution entirely and always reach the
toolkit's copy:

```
<root>\run.cmd python ...
<root>\env\Scripts\python.exe ...
```

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

That removes the toolkit's user PATH entries and leaves the files alone. It
also leaves Px running: on a network that needs it, Px is how the next install
reaches the internet at all, so stopping it here would make reinstalling fail
with a 407.

To delete the installed tools as well, add `-Full`:

```powershell
<root>\toolkit\uninstall.ps1 -Full
```

That removes every tool and the Python environment, which is nearly all of the
disk space, and with it anything you installed into that Python. It also stops
Px and deregisters it from starting at logon, because its files are going too. The toolkit's
own scripts stay, because the script doing the deleting is one of them, so the
last step - deleting the folder - is still yours.

`GUI.cmd` does the same: choose Basic or Full beside the buttons, then press
Uninstall. Full asks for confirmation first.

## Antivirus quarantined the toolkit

Behavioural antivirus engines watch what a program does rather than what it
contains. This installer downloads executables, writes them to a folder, adds
that folder to PATH and runs them, which is also what a malware dropper does.
Some engines act on that pattern.

Observed on Bitdefender, detection name `Atc4.Detection` from Active Threat
Control: sixteen files quarantined across two waves, including the installed
copies of every script, both `.cmd` entry points, and the original `install.ps1`
in the source folder it was run from. Disabling the engine did not release the
files; the quarantine records held a lock on those exact paths until they were
restored or deleted through the antivirus console.

Nothing here is a false claim about the software: the behaviour really is what
the engine describes. There is no way to work around it from inside the toolkit
and no attempt should be made.

What to do:

1. Record the detection name and the list of files. It is evidence that the
   detection is heuristic rather than a signature match.
2. Report it to whoever runs endpoint security, and ask for the install root
   and the download folder to be excluded, including in the behavioural engine,
   which is usually configured separately from the file scanner.
3. Do not re-run setup until that is in place. Each run risks another wave.

On a managed machine a participant can do none of this themselves, so it needs
to be resolved before a session rather than during one.

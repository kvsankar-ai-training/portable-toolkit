# Troubleshooting

## SETUP.cmd opens and closes immediately

The window closed before you could read it. Open PowerShell in the toolkit
folder and run the installer directly so the error stays on screen:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
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

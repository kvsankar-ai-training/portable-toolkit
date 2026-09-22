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

## The first download fails with "(502) Bad Gateway"

The log says something like:

```
uv: downloading
overall: error - The remote server returned an error: (502) Bad Gateway.
```

Nothing is wrong with uv. That is the very first download, and a 502 is a proxy
saying it accepted the request and could not complete it - so this machine
reached a proxy and got an answer, and the proxy did not reach the site. A
proxy that could not be reached at all fails differently, so this is not a
connectivity problem between you and it.

Setup names the proxy it used and says which setting picked it, then tries once
without it, because a proxy that is in the way is not always one you have to go
through. If that second attempt works the install carries on and says so.

If it does not, setup stops and the window runs the network check by itself, so
the log already holds the answer. Press **Copy** above the log and send it.

### On a VPN

This is the common case, and connecting the VPN is not the fix - the proxy
answered, so the VPN was already carrying traffic to it. What changes on a VPN
is which proxy gets picked and whether that proxy serves clients on the VPN's
addresses at all. Some networks run one proxy for the building and another for
remote clients, and an automatic configuration script that is right on site
hands out the wrong one from home.

So compare the two. The network check's "What Windows would use for each
address" names the proxy, and the log line from setup says whether an automatic
configuration script chose it. If that proxy differs from the one a machine in
the office resolves, the configuration script is picking a proxy you cannot
use, which is a question for whoever runs the network rather than something to
work around.

If they name the proxy remote clients should use, setup will take it ahead of
whatever Windows would have picked. Run it from a console rather than the
window, because this sets the address for that console only:

```powershell
$env:HTTPS_PROXY = 'http://the-proxy-they-named:8080'
.\SETUP.cmd
```

Setup ignores the setting if nothing is listening at that address, so a typo
falls back to the normal route rather than breaking the install outright. If
the proxy also wants credentials, it is Px you want, not this - see the 407
section below.

## The proxy answers with 407, and setting HTTPS_PROXY is not enough

This is about programs you run afterwards, not about setup itself. Setup lets
Windows decide how to reach each address - directly, through a configured
proxy, or through whatever an automatic configuration script picks per address
- and offers your logged-in session's credentials if asked, which is what a
browser does. On a network where browsing works, downloading works.

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
desktop app that does this for you: it closes any running copy, starts Px if
Px is configured and not already serving, points the app at it, and reopens
it. A running app keeps the environment it started with, which is why
restarting it is the point.

If Px has no proxy saved, the button says so and starts the app anyway with
the settings as they are.

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

## Setup stops with "access to the path ... is denied"

Something in that folder is running, and Windows will not let a running
program's files be replaced. Px is the usual one, because it stays running in
the background, and the file named is normally inside its bundled Python
rather than `px.exe` itself.

Setup avoids this in two ways. It records the version it installed, so a tool
already at the right version is left alone rather than reinstalled - asking a
tool whether it is installed by running it is unreliable, because px exits
non-zero while another copy of itself is running. And when a folder does have
to be replaced, setup stops whatever is running from it first and starts the
tool again afterwards.

If the files still cannot be replaced, setup keeps the copy already installed,
says so, and carries on with the rest rather than stopping. Nothing is lost:
the tool that was there still works.

To force a genuine reinstall of one tool, close whatever is using it and
delete its folder, then run setup again:

```powershell
<root>\run.cmd px --quit
Remove-Item <root>\px -Recurse -Force
```

## A download fails with "failed to create underlying connection" or a tunnel error

Something is being sent through a proxy that is not answering. The usual cause
is `HTTPS_PROXY` left pointing at a local relay such as Px, which is needed for
other programs but is not running at the moment.

Setup checks that a proxy answers before using it, so its own downloads are not
affected. `uv` reads `HTTPS_PROXY` for itself and does not make that check, so
clear it or point it somewhere alive:

```powershell
$env:HTTPS_PROXY = $null      # this window only
```

If a relay is meant to be running, start it:

```powershell
<root>\run.cmd px
```

Px exits on its own when it has no upstream proxy configured, so if it will not
stay running, give it one:

```powershell
<root>\run.cmd px --save --proxy=your-proxy:port
```

## Any network failure: find out what is actually happening first

Setup reaches the network two ways and they can disagree, so guessing wastes
time. This reports both, changes nothing, and needs no arguments:

```powershell
<root>\toolkit\network-check.ps1
```

It shows this machine's proxy settings, what Windows resolves for several
addresses, whether those proxies answer, whether Windows can reach the sites
the tools come from, whether `uv` can reach them with and without a proxy, and
what state Px is in.

The window has a **Network check** button above its log, and runs the same
check by itself whenever setup fails - so after a failure the log already holds
this. Press **Copy** next to it and send the whole thing when reporting a
problem. The useful distinction it draws
is between Windows reaching a site and `uv` reaching it: the tools download
through Windows, `uv` does not, and a failure in one and not the other points
straight at the proxy handling rather than at the network.

## Python fails with "invalid peer certificate: UnknownIssuer"

The tools install, then Python does not:

```
error: Failed to install cpython-3.13.15-windows-x86_64-none
cause: client error (Connect)
cause: invalid peer certificate: UnknownIssuer
```

The network is inspecting TLS. Every connection is intercepted and re-signed by
a company certificate authority, and this machine trusts it - which is why the
tool downloads, which go through Windows, worked. `uv` carries its own copy of
the public authorities and consults nothing else, so the company signature is
one it has never seen.

Setup tells `uv` to use this machine's certificate store instead. That weakens
nothing: the certificates come from the store Windows already trusts.

Run the network check if it still fails. Its "Who signed the connection" section
names the authority for each address. A company name there confirms inspection;
public names like Sectigo, Let's Encrypt or GlobalSign mean this is not your
problem.

If the company authority is named and `uv` still refuses, hand it the
certificates as a file:

```powershell
$pem = "$env:USERPROFILE\corp-roots.pem"
Get-ChildItem Cert:\LocalMachine\Root | ForEach-Object {
    "-----BEGIN CERTIFICATE-----"
    [Convert]::ToBase64String($_.RawData, 'InsertLineBreaks')
    "-----END CERTIFICATE-----"
} | Set-Content $pem
$env:SSL_CERT_FILE = $pem
.\SETUP.cmd
```

That lasts for that console. `SSL_CERT_FILE` is read by `uv`, and by Python
afterwards.

## The tools download but objects.githubusercontent.com times out

Every GitHub release file is served from that host, not from `github.com`. A
network can allow one and not the other, and then `github.com` looks reachable
while nothing actually downloads. The network check tests both separately for
this reason. If it reports `COULD NOT CONNECT` for
`objects.githubusercontent.com`, that host is what to ask about.

## The Python or package download fails at the proxy

The tools install, then `uv` fails - with a DNS error, a connection timeout,
or "tunnel error: proxy authorization required".

The two halves of setup reach the network differently. The tool downloads go
through Windows, which knows this network's proxy settings and can run an
automatic configuration script to pick one per address. `uv` does neither: it
reads proxy environment variables and nothing else, and it cannot answer a
proxy that asks it to authenticate.

So setup asks Windows what it would use, and puts Px in front of `uv` when
there is a proxy at all - Px answers the authentication with your Windows
session, which `uv` cannot do. Where Windows says to go direct, none of this
happens.

Watch for these lines in the log:

```
configuring px for this network's proxy: ...
starting px so uv can get through the proxy
uv will use http://127.0.0.1:3128
```

If instead it says `px is not available, so uv goes straight at the proxy`,
then Px could not be started, and a proxy that demands authentication will
refuse `uv`. Configure Px by hand and run setup again:

```powershell
<root>
un.cmd px --save --proxy=your-proxy:port
<root>
un.cmd px
```

Note that a proxy can let one destination through and challenge the next, so
Python installing successfully does not mean the packages will. The error that
names `files.pythonhosted.org` with "proxy authorization required" is that
case.

If you would rather point `uv` somewhere yourself, setup leaves an existing
`HTTPS_PROXY` alone, provided something is listening on it.

## Copilot worked at the office and fails at home, with a tunnel error

The proxy Px relays to is a company address. Take the laptop somewhere else and
it is simply not there, so Px accepts every connection on its own port and
fails every request behind it - which reaches Copilot as a connect or tunnel
error. Px running is not the same as Px working.

The Launch button checks this now: where the saved proxy cannot be reached from
the network you are on, Px is not used and Copilot starts without a proxy,
with a line in the log saying so. If Px is already running from an earlier
session, press **Stop** under Px first, or:

```powershell
<root>\run.cmd px --quit
```

If you set `HTTPS_PROXY` permanently on your account at some point, that
survives all of this and will still point at Px. Clear it under Settings, Edit
environment variables for your account, or expect to do this every time the
laptop changes network.

Nothing needs undoing when you go back to the office: the saved proxy becomes
reachable again and Px is used as before.

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

`GUI.cmd` has both as separate buttons: Uninstall undoes the settings, and
Remove everything deletes the files too, asking for confirmation first.

## Antivirus quarantined the toolkit

Files disappear, or a script that was there a moment ago reports as missing.

Behavioural antivirus watches what a program does rather than what it contains.
This installer downloads executables, writes them to a folder, puts that folder
on PATH and runs them - which is also what a malware dropper does. Some engines
act on that pattern. Bitdefender's Active Threat Control reports it as
`Atc4.Detection`.

The engine is describing the behaviour accurately. There is no way around it
from inside the toolkit and no attempt should be made.

Expect it to take more than the obvious files. It can quarantine the installed
copies and the installer you ran them from, and the quarantine record holds a
lock on each path afterwards, so writing the file back fails until the record
is cleared through the antivirus console. Turning the engine off does not
release them.

What to do:

1. Record the detection name and which files went. A heuristic name rather
   than a named piece of malware is the useful detail.
2. Ask whoever runs endpoint security to exclude the install root and the
   folder you extracted to. The behavioural engine is usually configured
   separately from the file scanner, so both need it.
3. Do not re-run setup until that is in place. Each run risks another sweep.

On a managed machine none of this is something you can do yourself, so it has
to be settled before a session rather than during one.

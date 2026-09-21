# portable-toolkit

Installs Git, Node, uv, Python and Px on a Windows machine without
administrator rights and without a software request. Everything lands in one
folder, and one command removes it again.

## Download

Get [**portable-toolkit.zip**](../../releases/latest) from the latest release,
or use the green **Code** button above and choose *Download ZIP*.

## Install

1. Right-click the zip, choose **Properties**, tick **Unblock**, click OK, then
   extract it. Skipping this makes step 2 fail on some machines.
2. Double-click **SETUP.cmd**.
3. Answer the question at the end. Enter accepts yes.

It downloads about 130 MB and uses about 320 MB once installed.

## What it installs

| Tool | Version | Verified against |
| --- | --- | --- |
| uv | 0.12.17 | the `.sha256` published beside the release asset |
| Node | 24.21.0 | `SHASUMS256.txt` on nodejs.org |
| Git (MinGit) | 2.55.0.5 | the SHA-256 table in the Git for Windows release notes |
| Python | 3.13 | fetched by uv |
| Px | 0.11.0 | the `.sha256` published beside the release asset |

Every download is checked against the hash its publisher recorded, and the
install stops rather than continuing if one does not match.

Px is an NTLM/Kerberos proxy relay. It is only useful behind a corporate proxy
that needs authentication a tool cannot supply itself, and it does nothing
until you configure and start it. See
[`toolkit/troubleshooting.md`](toolkit/troubleshooting.md) for how.

## What it changes on your machine

Two things:

- a folder at `C:\tools`, or `%USERPROFILE%\tools` if the machine will not allow
  the first;
- five entries added to your **user** PATH, so the tools work by name.

Setup shows you those entries before adding them, and nothing else on the
machine is touched. To undo both, run `toolkit\uninstall.ps1`.

## Checking it worked

```
C:\tools\toolkit\check.ps1
```

It reports what is installed and, more usefully, whether a plain `python` or
`node` actually reaches this folder.

If your machine already has Python, Node or Git installed for all users, those
win, because Windows reads the system PATH before yours and only an
administrator can change that. `check.ps1` says so when it happens. Use
`C:\tools\run.cmd python ...` or the full path in that case.

## GUI

Double-click **GUI.cmd** instead of using a terminal. It installs, checks
status, uninstalls, and configures, starts and stops `px`, all from one
window, showing per-tool progress (downloading, verified, installed) as it
goes rather than a bare console. It calls the same scripts described below;
nothing it does is unavailable from the command line.

It needs nothing beyond what Windows already provides, so it works before
Python or Node exist on the machine, not just after.

It also has a "Launch (fresh settings)" button for the GitHub Copilot desktop
app: closes it if already running and reopens it with the current proxy
settings, rather than whatever it happened to start with. See
[`toolkit/troubleshooting.md`](toolkit/troubleshooting.md) for why that
matters.

## Site-specific values (proxy addresses)

`toolkit/tools.json` and the rest of this repo are generic on purpose; nothing
here names any specific organisation's proxy. If your network needs `px`
configured with a real address, put it in `toolkit/site.json` (copy
`toolkit/site.example.json` and fill it in), which the GUI reads to pre-fill
the proxy field. `site.json` is git-ignored: distribute it separately from the
public repo, to whoever needs it, through however your organisation shares
internal files.

## Reading it before you run it

Everything is plain text and short enough to read in full:

- `toolkit/tools.json` — what is downloaded, from where, and the expected hash
- `toolkit/install.ps1` — the installer
- `toolkit/env.ps1` — the paths and variables it sets, for one process only
- `toolkit/check.ps1` — diagnostic, changes nothing
- `toolkit/uninstall.ps1` — removes the PATH entries
- `toolkit/gui.ps1` — the GUI; every action in it calls the scripts above
- `toolkit/site.example.json` — the template for a site-specific `site.json`

Adding a tool is an edit to `tools.json`, not to any script.

## Troubleshooting

See [`toolkit/troubleshooting.md`](toolkit/troubleshooting.md), which covers
execution policy, Mark-of-the-Web, proxies, checksum mismatches, AppLocker and
PATH precedence.

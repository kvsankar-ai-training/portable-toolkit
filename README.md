# portable-toolkit

Installs Git, Node, uv, Python and Px on a Windows machine without
administrator rights and without a software request. Everything lands in one
folder, and one command removes it again.

## Download

Get [**portable-toolkit.zip**](../../releases/latest) from the latest release,
or use the green **Code** button above and choose *Download ZIP*.

On a Windows x64 machine whose toolkit environment already uses Python 3.13,
download **portable-toolkit-offline-win313.zip** from the same release if PyPI
downloads time out. It includes the pinned document-library wheels. Extract it
and use **GUI.cmd** the same way; setup verifies the bundled wheels and installs
them without contacting PyPI. It does not support other Python versions.

## Install

1. Right-click the zip, choose **Properties**, tick **Unblock**, click OK, then
   extract it. Skipping this makes step 2 fail on some machines.
2. Double-click **GUI.cmd**.
3. Press **Install / Fix**, and wait. The log on the right shows what is
   happening; downloading and installing the document libraries takes longest.
   During that step, uv's detailed output appears as it arrives, with an
   elapsed-time update every 15 seconds even when uv is quiet.

If a network step fails, the window checks the connection and writes the result
into the log - press **Copy** above the log and send it. There is a **Network
check** button there to run it any time.

That is the whole install: the tools, Python, and the libraries that read Word,
PDF, Excel and PowerPoint. There is nothing to choose and nothing to come back
for.

The document libraries are the largest download. Setup includes only the
MarkItDown extras for Word, Excel, PowerPoint and PDF, so it does not fetch
unrelated Azure, audio or YouTube packages. Do it before you need it rather
than in front of a room.

### Without a window

If you would rather not use the window, or you are scripting it:

```
SETUP.cmd
```

It does exactly what the button does.

### If your machine already has a Python

Setup uses an existing Python 3.10 through 3.14 when one is available, creating
an isolated toolkit environment from it. Otherwise, it downloads Python 3.13.
When a proxy setting contains credentials, setup starts Px and routes uv through
it for the package downloads.

Some corporate images install Python for all users. Windows reads machine PATH
entries before yours, so that Python answers to `python` in every window and
nothing the toolkit writes to your own PATH can change it.

Setup notices, and installs the same document libraries into that Python too,
with `pip install --user`. They land under your profile, need no administrator,
and `uninstall.ps1 -Full` removes them again. The toolkit's environment is
separate. The Status panel has a row for it, and `check.ps1` reports which
libraries that Python can actually import.

## What it installs

| Tool | Version | Verified against |
| --- | --- | --- |
| uv | 0.12.17 | the `.sha256` published beside the release asset |
| Node | 24.21.0 | `SHASUMS256.txt` on nodejs.org |
| Git (MinGit) | 2.55.0.5 | the SHA-256 table in the Git for Windows release notes |
| GitHub CLI | 2.101.0 | `checksums.txt` published with the release |
| Python | existing supported 3.x (currently 3.10 through 3.14), otherwise 3.13 | toolkit environment created by uv |
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

## The window

**GUI.cmd** is the way in. It installs, reports what is installed, removes
things again, configures and starts Px, and launches GitHub Copilot - all from
one window, with a log on the right that you can copy with one button.

It needs nothing beyond what Windows already provides, so it works before
Python or Node exist on the machine, not only after. Everything it does is
available from the command line too; the buttons call the same scripts.

## Launching GitHub Copilot

The **Launch (fresh settings)** button closes GitHub Copilot if it is running,
starts Px if Px is configured and not already serving, points the app at it,
and opens the app again.

Restarting it is the point. A running program keeps the environment it started
with, so an app opened before the proxy was sorted out will keep failing until
it is restarted, however correct the settings have since become.

**Before that button is any use, two things have to be true, and neither is
something this toolkit can do for you:**

1. **The GitHub Copilot desktop app is installed.** Download it from
   [github.com/features/ai/github-app](https://github.com/features/ai/github-app).
   The button reports "not found at the usual install location" if it is
   missing.
2. **Your GitHub account has Copilot enabled** - any plan, including the free
   one. On a work account this is usually something your organisation grants
   rather than something you buy, and the organisation may also have to permit
   the desktop app specifically. The toolkit cannot tell you whether you have
   it: the app will say so when you sign in.

If the app signs in but then fails with "error sending request for url", that
is the proxy rather than the licence, and
[`toolkit/troubleshooting.md`](toolkit/troubleshooting.md) covers it.

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

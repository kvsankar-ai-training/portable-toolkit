---
name: portable-toolkit
description: Install and use a self-contained Git, Node, uv and Python toolchain on a locked-down Windows machine, with no administrator rights. Use when a task needs Python, Node or Git and they are not available, or when a script must run against the toolkit's shared Python environment.
---

# Portable Toolkit

Git, Node, uv and Python installed under `C:\tools`, or `%USERPROFILE%\tools`
if the machine refused the first. One shared Python environment serves every
folder on the machine.

## Check first

Run `<root>\toolkit\check.ps1`. It changes nothing and reports two things: what
is installed, and whether a bare `python` or `node` actually reaches this
folder. If anything is missing, run `SETUP.cmd` from the extracted folder and
wait for it to finish.

## Running a command

Setup adds the toolkit to the user PATH, so in a window opened afterwards the
commands work by name:

```
python script.py
pip install requests
node app.js
git status
```

Two situations break that, and `check.ps1` distinguishes them:

- **The window predates setup.** A process keeps the environment it started
  with. Open a new one.
- **The tool is installed machine-wide.** Windows reads the system PATH before
  the user PATH, so a machine-wide Python, Node or Git wins and no user-level
  change can outrank it. Only an administrator can alter that.

In either case, use `run.cmd`, which sets the paths for one command:

```
<root>\run.cmd python script.py
<root>\run.cmd pip install requests
```

Or call the file directly, which needs no setup at all, because a virtual
environment's `python.exe` resolves its own `site-packages` from where it sits:

```
<root>\env\Scripts\python.exe script.py
<root>\node\node.exe app.js
<root>\git\cmd\git.exe status
```

Prefer bare names when `check.ps1` reports them green, and `run.cmd` otherwise.

## Installing a package

```
pip install <package>
```

`pip` lives inside the shared environment, so it installs there by construction
and every folder on the machine sees it. Do not create a virtual environment per
project and do not run `uv init`.

Prefer `pip` over `uv pip` here. Bare `uv` does not know about this folder and
writes its caches under `%APPDATA%`; `run.cmd uv ...` is what keeps it
contained.

Add the package to the `python.packages` list in `toolkit\tools.json` as well,
so a fresh install gets it too.

## Documents

The document libraries are optional and are not installed by `SETUP.cmd`. Check
first with `check.ps1`, which reports how many are present. To add them, run `SETUP.cmd extras`,
or open `GUI.cmd`, tick **Also install the extras**, and press Install / Fix.

Reading any of docx, pdf, xlsx, pptx, html or csv is one call:

```python
from markitdown import MarkItDown
print(MarkItDown().convert("report.docx").text_content)
```

Writing uses the format libraries: `python-docx` for Word, `python-pptx` for
PowerPoint, `openpyxl` for Excel. `pdfplumber` gets text and tables out of a
PDF when markitdown's plain text is not enough, and `pypdf` splits and merges.

What this toolkit cannot do, and should say so rather than guess: convert
between formats with full fidelity, or edit a document in place while
preserving everything it does not understand. Those need LibreOffice or
Microsoft Office, neither of which this installs.

## Adding a tool

Add an entry to `toolkit\tools.json` with its version, URL, the SHA-256
published by whoever distributes it, and a command that proves it runs. Do not
edit `install.ps1` or the PATH handling; both are driven by the manifest.

## Corporate NTLM proxy (Px)

`px` is installed like the other tools but is not used like them: it is an
NTLM/Kerberos proxy relay for machines where a corporate proxy demands
authentication that most command-line tools cannot supply. It does nothing
until configured and started.

It is not needed for setup's own downloads, which go the way a browser goes -
whatever Windows resolves for the address, with the logged-in session offered
if the proxy asks. Reach for `px` when a particular program fails against the
proxy, not as a matter of course. The GitHub Copilot desktop app is the usual
one that does.

```
run.cmd px --save --proxy=your-proxy:port
run.cmd px --install
```

The second command registers it to start at logon. After that, point tools at
`http://127.0.0.1:3128` instead of the real proxy address. Only set this up if
a tool is actually failing against an authenticating proxy; do not do it by
default.

`GUI.cmd` does the same three actions (save, start, stop) from buttons, for a
participant who would rather not type commands. Prefer pointing someone there
over walking them through the CLI, unless they ask for the commands directly.

`GUI.cmd` can also relaunch the GitHub Copilot desktop app itself, closing any
running copy first so the new one picks up current proxy settings instead of
whatever it started with. Point someone there if Copilot's desktop app fails
to sign in or create a session with a proxy configured, even if `px` already
looks correctly set up - the running copy may simply predate the fix.

## Site-specific values

This repo is generic on purpose: no proxy address or other organisation-specific
value belongs in any tracked file. If one is needed, it goes in
`toolkit\site.json` (git-ignored, see `toolkit\site.example.json` for the
shape), distributed separately from the repo. Never add a real value to
`site.example.json`, `tools.json`, or any other tracked file.

## What not to do

- Do not install anything outside the toolkit folder.
- Do not change the user or machine PATH on the participant's behalf. Setup
  asks, and that question is theirs to answer.
- If a download fails a checksum, stop and report it. Do not retry with
  verification disabled.
- If a machine policy blocks something, report what it said. Do not work around
  it.

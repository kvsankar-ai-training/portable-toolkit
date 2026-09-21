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

## Adding a tool

Add an entry to `toolkit\tools.json` with its version, URL, the SHA-256
published by whoever distributes it, and a command that proves it runs. Do not
edit `install.ps1` or the PATH handling; both are driven by the manifest.

## What not to do

- Do not install anything outside the toolkit folder.
- Do not change the user or machine PATH on the participant's behalf. Setup
  asks, and that question is theirs to answer.
- If a download fails a checksum, stop and report it. Do not retry with
  verification disabled.
- If a machine policy blocks something, report what it said. Do not work around
  it.

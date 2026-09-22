PORTABLE TOOLKIT
================

This installs Git, Node, uv, Python and Px without administrator rights and
without a software request. Px is a proxy helper for programs that cannot get
through an authenticating proxy on their own. Setup starts it by itself
when this network has a proxy, because the Python package downloads need
it; the GitHub Copilot desktop app often needs it too (see
toolkit\troubleshooting.md).


WHAT TO DO
----------

1. Right-click the zip you downloaded, choose Properties, tick Unblock, click OK.
   Then extract it. The setup clears that mark itself as well, so this is a
   belt-and-braces step rather than a required one.

2. Double-click GUI.cmd.

3. Press Install / Fix, and wait. The log on the right shows what is
   happening; the longest step is the Python download.

That installs the tools. To add the document libraries, ripgrep and jq as
well, tick "Also install the extras" before pressing Install / Fix. You can
come back and tick it later; nothing has to be undone first.

It downloads about 130 MB, uses about 320 MB once installed, and takes a few
minutes - roughly double that with the extras.

If you would rather not use the window, SETUP.cmd does the same thing from a
command prompt, and "SETUP.cmd extras" includes the extras.


WHERE IT INSTALLS
-----------------

Into C:\tools, not into the folder you extracted. If your machine will not allow
a folder at C:\, it uses %USERPROFILE%\tools instead, and says which it chose.

The folder you extracted is only the installer. You can delete it once setup has
finished.


WHAT IT CHANGES ON YOUR MACHINE
-------------------------------

Setup changes two things, and nothing else:

  - the C:\tools folder
  - five entries added to your user PATH, so the tools work by name

It does not touch the system PATH or any other folder. Setup shows you the five
entries before adding them.

There is a third change, but only if you ask for it. If you configure Px and
tick "start at logon" in the GUI, or run "px --install" yourself, Px is
registered to start with Windows. That registration lives outside C:\tools and
would survive deleting the folder, so uninstall handles it.

To undo everything:

    C:\tools\toolkit\uninstall.ps1

That removes the PATH entries and tells you to delete the folder. Run it
before deleting C:\tools, not after.

Px is deliberately left running, because it is how this machine reaches the
internet through an authenticating proxy - stopping it would break the next
install. Use Remove everything in GUI.cmd, or uninstall.ps1 -Full, to stop and
deregister it along with everything else.


USING THE TOOLS
---------------

Open a new terminal, then just use them:

    python myscript.py
    pip install requests
    node app.js
    git status

A terminal that was already open when setup ran will not see the change. Close
it and open a new one. The same applies to any assistant or editor that was
running.

Before opening a new window, or if you answered no to the PATH question:

    C:\tools\run.cmd python myscript.py


CHECKING IT WORKED
------------------

    C:\tools\toolkit\check.ps1

It reports what is installed and, more usefully, whether a plain "python" or
"node" actually reaches this folder.

If your machine already has Python, Node or Git installed for all users, those
win, because Windows reads the system PATH before yours and only an
administrator can change it. check.ps1 says so when it happens. Use run.cmd, or
the full path under C:\tools, in that case.


THE WINDOW
----------

GUI.cmd is the way in. It installs, reports what is installed, removes things
again, configures and starts Px, and launches GitHub Copilot - all from one
window, with a log you can copy with one button. It needs nothing beyond what
Windows already provides, so it works before Python or Node exist on the
machine.


LAUNCHING GITHUB COPILOT
------------------------

The "Launch (fresh settings)" button closes GitHub Copilot if it is running,
starts Px if Px is configured and not already serving, points the app at it,
and opens the app again.

Restarting it is the point. A program keeps the environment it started with,
so an app opened before the proxy was sorted out keeps failing until it is
restarted, however correct the settings have since become.

Two things have to be true first, and neither is something this toolkit can
do for you:

  1. The GitHub Copilot desktop app is installed. Get it from
     https://github.com/features/ai/github-app
     The button says "not found at the usual install location" if it is not.

  2. Your GitHub account has Copilot enabled - any plan, including the free
     one. On a work account that is usually something your organisation
     grants rather than something you buy, and the organisation may also have
     to permit the desktop app. This toolkit cannot tell you whether you have
     it; the app will say so when you sign in.

If the app signs in and then fails with "error sending request for url", that
is the proxy rather than the licence. See toolkit\troubleshooting.md.


SITE-SPECIFIC VALUES (PROXY ADDRESSES)
---------------------------------------

This repo names no specific organisation's proxy. If Px needs a real address
for your network, put it in toolkit\site.json (copy toolkit\site.example.json
and fill it in). The GUI reads it to pre-fill the proxy field. site.json is
not part of the public repo; get it from whoever runs your training or set up
your network, separately from this download.


OPTIONAL EXTRAS
---------------

SETUP.cmd installs what you need to have a working Python, Node and Git. The
extras are everything beyond that:

  ripgrep    fast search across a folder of files
  jq         command-line tool for JSON
  Python libraries for documents:
             markitdown   reads Word, PDF, Excel, PowerPoint, HTML and CSV
             python-docx  writes Word files
             python-pptx  writes PowerPoint files
             openpyxl     reads and writes Excel files
             pandas       working with tables of data
             pdfplumber   pulling text and tables out of PDFs
             pypdf        splitting, merging and rearranging PDFs
             Pillow       images

Install them at any time: GUI.cmd, tick the extras box, then Install / Fix.
Or:

    SETUP.cmd extras

Reading a document is one call. The assistant will write the script; this is
what it looks like:

    from markitdown import MarkItDown
    print(MarkItDown().convert("report.docx").text_content)


IF SOMETHING GOES WRONG
-----------------------

If it is a network or proxy problem, the window already has the answer: it
runs a network check by itself whenever setup fails, and there is a Network
check button above the log to run it any time. Press Copy and send the log.

The same check from a console:

    C:\tools\toolkit\network-check.ps1

It changes nothing, and reports how this machine reaches the internet and how
the installer does - which are not the same route, and can disagree.

Otherwise read toolkit\troubleshooting.md. If a policy on your machine blocked
something, that is worth reporting rather than working around.

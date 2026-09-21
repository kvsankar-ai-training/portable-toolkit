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
   Then extract it. SETUP.cmd clears that mark itself as well, so this is a
   belt-and-braces step rather than a required one.

2. Double-click SETUP.cmd.

   That installs the tools. To also get the extras - ripgrep, jq and the
   Python libraries for Word, Excel, PowerPoint and PDF - use GUI.cmd and
   choose Full, or run SETUP.cmd from a command prompt with the word full:

       SETUP.cmd full

   You can add them later; nothing is lost by starting with the tools.

3. Answer the question at the end. Enter accepts yes.

It downloads about 130 MB, uses about 320 MB once installed, and takes a few
minutes.


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
install. Use the Full option in GUI.cmd, or uninstall.ps1 -Full, to stop and
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


GUI
---

Double-click GUI.cmd instead, if you would rather not use a terminal. It
installs, checks status, uninstalls, and configures, starts and stops Px, all
from one window, and needs nothing beyond what Windows already provides.


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

Install them at any time: GUI.cmd, choose Full, then Install / Fix. Or:

    SETUP.cmd full

Reading a document is one call. The assistant will write the script; this is
what it looks like:

    from markitdown import MarkItDown
    print(MarkItDown().convert("report.docx").text_content)


IF SOMETHING GOES WRONG
-----------------------

If it is a network or proxy problem, run this first and send the output:

    C:\tools\toolkit\network-check.ps1

It changes nothing, and reports how this machine reaches the internet and how
the installer does - which are not the same route, and can disagree.

Otherwise read toolkit\troubleshooting.md. If a policy on your machine blocked
something, that is worth reporting rather than working around.

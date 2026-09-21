PORTABLE TOOLKIT
================

This installs Git, Node, uv and Python without administrator rights and without
a software request.


WHAT TO DO
----------

1. Right-click the zip you downloaded, choose Properties, tick Unblock, click OK.
   Then extract it. SETUP.cmd clears that mark itself as well, so this is a
   belt-and-braces step rather than a required one.

2. Double-click SETUP.cmd.

3. Answer the question at the end. Enter accepts yes.

It downloads about 110 MB, uses about 290 MB once installed, and takes a few
minutes.


WHERE IT INSTALLS
-----------------

Into C:\tools, not into the folder you extracted. If your machine will not allow
a folder at C:\, it uses %USERPROFILE%\tools instead, and says which it chose.

The folder you extracted is only the installer. You can delete it once setup has
finished.


WHAT IT CHANGES ON YOUR MACHINE
-------------------------------

Two things, and nothing else:

  - the C:\tools folder
  - five entries added to your user PATH, so the tools work by name

It does not touch the system PATH, the registry beyond that, or any other
folder. Setup shows you the five entries before adding them.

To undo both:

    C:\tools\toolkit\uninstall.ps1

That removes the PATH entries and tells you to delete the folder.


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


IF SOMETHING GOES WRONG
-----------------------

Read toolkit\troubleshooting.md. If a policy on your machine blocked something,
that is worth reporting rather than working around.

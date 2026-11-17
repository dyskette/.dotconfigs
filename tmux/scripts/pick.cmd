@echo off
rem fzf's way back into the pickers on Windows: fzf runs its callbacks
rem (list, preview, the Enter action) through cmd.exe, which cannot start a
rem bash script, and quotes do not survive fzf handing it the line. So the
rem callbacks name this file, and the paths live here instead:
rem
rem   pick.cmd NAME ARGS...   runs NAME.sh from this folder with Git's bash
rem
rem usr\bin\bash.exe is bash itself (mux-lib.sh puts /usr/bin first).
"%ProgramFiles%\Git\usr\bin\bash.exe" "%~dp0%~1.sh" %2 %3 %4 %5 %6 %7 %8 %9

@echo off
rem edit.sh for Windows programs: lazygit and yazi run their edit commands
rem through cmd.exe, which cannot start a bash script. Git's usr\bin\bash.exe
rem is bash itself (mux-lib.sh puts /usr/bin first); the arguments pass
rem through untouched.
"%ProgramFiles%\Git\usr\bin\bash.exe" "%~dp0edit.sh" %*

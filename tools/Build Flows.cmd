@echo off
setlocal
rem Builds the scene flows for Mantella Living World - OStim Expansion from your OStim animation packs.
rem Mod Organizer 2: reads the packs enabled in your current profile and creates the Flows mod in MO2.
rem Vortex: reads the packs Vortex deployed to the game's Data folder and makes a zip to install in Vortex.
rem Run it with the game closed.
where py >nul 2>nul || (
  echo Python 3 is needed once to build the flows: https://www.python.org/downloads/windows/
  pause
  exit /b 1
)
py -3 "%~dp0flowgen.py" --auto
if errorlevel 1 (
  echo.
  echo Flows were NOT built. See the message above.
  pause
  exit /b 1
)
pause

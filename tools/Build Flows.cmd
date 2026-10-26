@echo off
setlocal
rem Builds the scene flows for Mantella Living World - OStim Expansion from the OStim animation packs enabled
rem in your current Mod Organizer 2 profile. Run it with the game closed, then enable the Flows mod it creates.
set "HERE=%~dp0"
for %%I in ("%HERE%..\..\..\..") do set "MO2=%%~fI"
if not exist "%MO2%\ModOrganizer.ini" (
  echo Could not find Mod Organizer 2 next to this mod: %MO2%
  echo Run this from the installed mod: mods\Mantella Living World - OStim Expansion\tools\...
  pause
  exit /b 1
)
where py >nul 2>nul || (
  echo Python 3 is needed once to build the flows: https://www.python.org/downloads/windows/
  pause
  exit /b 1
)
set "PROFILE="
for /f "tokens=2 delims=()" %%P in ('findstr /b "selected_profile" "%MO2%\ModOrganizer.ini"') do set "PROFILE=%%P"
if "%PROFILE%"=="" set "PROFILE=Default"
echo Mod Organizer 2: %MO2%
echo Profile: %PROFILE%
py -3 "%HERE%flowgen.py" --mo2 "%MO2%" --profile "%PROFILE%" --out "%MO2%\mods\Mantella Living World - OStim Expansion - Flows"
echo.
echo Done. Refresh Mod Organizer 2 and enable "Mantella Living World - OStim Expansion - Flows".
pause

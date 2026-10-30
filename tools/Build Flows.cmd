@echo off
setlocal
rem Builds the scene flows for Mantella Living World - OStim Expansion from your OStim animation packs.
rem Mod Organizer 2: reads the packs enabled in your current profile and creates the Flows mod in MO2.
rem Vortex: reads the packs Vortex deployed to the game's Data folder and makes a zip to install in Vortex.
rem Run it with the game closed.
set "HERE=%~dp0"
for %%I in ("%HERE%..\..\..\..") do set "MO2=%%~fI"
where py >nul 2>nul || (
  echo Python 3 is needed once to build the flows: https://www.python.org/downloads/windows/
  pause
  exit /b 1
)
if not exist "%MO2%\ModOrganizer.ini" goto vortex
set "PROFILE="
for /f "tokens=2 delims=()" %%P in ('findstr /b "selected_profile" "%MO2%\ModOrganizer.ini"') do set "PROFILE=%%P"
if "%PROFILE%"=="" set "PROFILE=Default"
echo Mod Organizer 2: %MO2%
echo Profile: %PROFILE%
py -3 "%HERE%flowgen.py" --mo2 "%MO2%" --profile "%PROFILE%" --out "%MO2%\mods\Mantella Living World - OStim Expansion - Flows"
echo.
echo Done. Refresh Mod Organizer 2 and enable "Mantella Living World - OStim Expansion - Flows".
pause
exit /b 0

:vortex
set "ZIP=%USERPROFILE%\Documents\Mantella Living World\Mantella Living World - OStim Expansion - Flows.zip"
echo No Mod Organizer 2 found: using the game's Data folder (Vortex). Deploy your mods in Vortex first.
py -3 "%HERE%flowgen.py" --data auto --zip "%ZIP%"
if errorlevel 1 (
  pause
  exit /b 1
)
echo.
echo Done. In Vortex: Mods, Install From File, pick
echo   %ZIP%
echo then enable it and deploy. After adding or removing animation packs, run this again and reinstall the zip.
pause

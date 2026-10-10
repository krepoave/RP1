@echo off
cd /d "%~dp0"
echo Starting ROADPRINT in Chrome...
call "%USERPROFILE%\Flutter\flutter\bin\flutter.bat" pub get
if errorlevel 1 pause & exit /b 1
call "%USERPROFILE%\Flutter\flutter\bin\flutter.bat" run -d chrome
pause

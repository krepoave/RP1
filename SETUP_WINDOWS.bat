@echo off
cd /d "%~dp0"
where flutter >nul 2>nul
if errorlevel 1 (
 echo Flutter was not found. Install Flutter SDK and add its bin folder to PATH.
 echo See README.md
 pause
 exit /b 1
)
if not exist .metadata (
 echo Generating platform project files...
 flutter create --platforms=android,web --project-name roadprint .
 if errorlevel 1 (pause & exit /b 1)
)
echo Installing Flutter dependencies (internet needed the first time)...
flutter pub get
pause

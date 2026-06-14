@echo off
echo Starting PermissionHub Dashboard...
echo.

:: Try Python 3 first
python --version >nul 2>&1
if %errorlevel% == 0 (
    echo Opening http://localhost:8080 in your browser...
    start "" "http://localhost:8080"
    python -m http.server 8080
    goto end
)

:: Try py launcher
py --version >nul 2>&1
if %errorlevel% == 0 (
    echo Opening http://localhost:8080 in your browser...
    start "" "http://localhost:8080"
    py -m http.server 8080
    goto end
)

:: Try Node.js npx
npx --version >nul 2>&1
if %errorlevel% == 0 (
    echo Opening http://localhost:8080 in your browser...
    start "" "http://localhost:8080"
    npx serve -p 8080 .
    goto end
)

echo ERROR: Python or Node.js not found.
echo Please install Python from https://python.org and try again.
echo Or open this folder in VS Code and use the Live Server extension.
pause

:end

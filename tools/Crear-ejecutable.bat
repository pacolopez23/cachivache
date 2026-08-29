@echo off
rem =====================================================================
rem  Crear Cachivache.exe con doble clic
rem
rem  Esto NO hace nada que no haga Compilar-Lanzador.ps1: es el mismo
rem  script, invocado de una forma que no exige abrir PowerShell ni saber
rem  que existe la politica de ejecucion. Quien descarga el codigo como
rem  ZIP desde GitHub no tiene por que saber ninguna de las dos cosas.
rem
rem  Y NO hace falta para usar el programa. Cachivache.bat lo abre tal
rem  cual, sin compilar nada. El .exe solo sirve para que no quede una
rem  consola detras durante toda la sesion.
rem
rem  El pause del final es deliberado: al abrirlo con doble clic la
rem  ventana se cerraria de golpe y no se leeria ni el resultado ni, si
rem  falla, el motivo, que es justo lo que hay que copiar para pedir
rem  ayuda.
rem =====================================================================

title Crear Cachivache.exe

where powershell >nul 2>&1
if errorlevel 1 (
    echo.
    echo   No se ha encontrado PowerShell en este equipo.
    echo   Cachivache necesita PowerShell 5.1 o superior, que viene de
    echo   serie con Windows 10 y 11.
    echo.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Compilar-Lanzador.ps1"
set CODIGO=%ERRORLEVEL%

if not "%CODIGO%"=="0" (
    echo.
    echo   No se ha podido crear el ejecutable. El motivo esta arriba.
    echo.
    echo   Mientras tanto puedes usar el programa igualmente: haz doble
    echo   clic en Cachivache.bat, en la carpeta de arriba.
    echo.
)

pause
exit /b %CODIGO%

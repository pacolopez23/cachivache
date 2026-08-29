@echo off
rem =====================================================================
rem  Cachivache - lanzador de respaldo y de diagnostico
rem
rem  El lanzador normal es Cachivache.exe, que abre el programa SIN dejar
rem  una consola detras. Se genera con tools\Compilar-Lanzador.ps1 y se
rem  descarga ya hecho de la pagina de versiones; no esta en el
rem  repositorio a proposito (el motivo, en la cabecera de ese script).
rem
rem  Este .bat sigue aqui por dos razones, y las dos son buenas:
rem
rem    1. Funciona siempre, sin compilar nada.
rem    2. Deja la consola A LA VISTA. Si el programa no llega a abrirse,
rem       es aqui donde se lee el motivo, con el archivo y la linea
rem       exactos. Esa consola no es un descuido: es la unica forma de
rem       ver un fallo que ocurre ANTES de que exista una ventana donde
rem       mostrarlo.
rem
rem  Arranca SIN permisos de administrador a proposito: los modulos que
rem  los necesitan se activan desde el propio programa, en Ajustes >
rem  Reiniciar como administrador. Asi lo normal es ejecutarlo con los
rem  permisos minimos.
rem =====================================================================

title Cachivache
cd /d "%~dp0"

rem  Ruta COMPLETA a PowerShell, no el nombre suelto: cmd busca primero
rem  en el directorio actual, y este .bat hace "cd" a su propia carpeta.
rem  Como el .zip se descomprime donde quiera el usuario -normalmente
rem  Descargas-, un powershell.exe ajeno al lado se ejecutaria en vez del
rem  de Windows.
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if not exist "%PS%" (
    echo No se ha encontrado Windows PowerShell en:
    echo   %PS%
    echo Cachivache necesita PowerShell 5.1 o superior.
    pause
    exit /b 1
)

"%PS%" -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Cachivache.ps1" %*
if errorlevel 1 (
    echo.
    echo El programa ha terminado con errores.
    echo Revisa el registro en %%LOCALAPPDATA%%\Cachivache\registros
    echo.
    pause
)

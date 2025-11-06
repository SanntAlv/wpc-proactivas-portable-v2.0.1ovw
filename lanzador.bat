@echo off

setlocal
set "BASE_DIR=%~dp0"

set "RESULT_FILE=%BASE_DIR%resultado.txt"
IF EXIST "%RESULT_FILE%" (
    echo Limpiando archivo de resultado anterior...
    del "%RESULT_FILE%"
)

echo [PASO 1 de 3] - Ejecutando la recoleccion de datos de vSphere...
echo (Se abrira una nueva ventana para este paso)
echo.

call "%BASE_DIR%run.bat"

IF ERRORLEVEL 1 (
    echo.
    echo El usuario cancelo la operacion. El flujo de trabajo se ha detenido.
    GOTO :end_script
)

echo.
echo [PASO 2 de 3] - Recoleccion finalizada. Ejecutando la conversion a Excel...
echo (Se abrira una nueva ventana para este paso)
echo.

start "Paso 2: Conversion a Excel" /wait pwsh.exe -ExecutionPolicy Bypass -File "%BASE_DIR%JSONtoExcels.ps1" 2>nul

IF NOT EXIST "%RESULT_FILE%" (
    echo.
    echo ADVERTENCIA: No se encontró el archivo de resultado. Omitiendo el paso 3.
    GOTO :end_script
)

echo.

:: Buscamos la palabra "_Proactiva" DENTRO del archivo resultado.txt
echo "%RESULT_FILE%" | findstr /I "_Proactiva" >nul

:: Si findstr la encontró (ERRORLEVEL 0), ejecutamos el paso 3.
IF %ERRORLEVEL% == 0 (
    echo [PASO 3 de 3] - Reporte completo de Proactiva detectado. Ejecutando el filtrado y generando el Anexo...
    echo (Se abrira una nueva ventana para este paso)
    echo.
    start "Paso 3: Generando Anexo" /wait pwsh.exe -ExecutionPolicy Bypass -File "%BASE_DIR%proactivas-auto2.0.ps1" 2>nul
)

:end_script
echo.
echo Proceso completado.
pause
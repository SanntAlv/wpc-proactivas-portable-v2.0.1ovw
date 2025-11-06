pwsh.exe -command "Set-ExecutionPolicy -Scope CurrentUser Unrestricted"
@start "Paso 1: Recoleccion de Datos" /wait pwsh.exe -ExecutionPolicy Bypass -Command "$ErrorActionPreference = 'SilentlyContinue'; & ".\devops-powershell\portable.ps1"

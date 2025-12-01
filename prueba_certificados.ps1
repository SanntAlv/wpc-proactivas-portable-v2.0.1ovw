# prueba_certificados.ps1
# Script de diagnóstico para probar la carga de módulos de certificados.

Write-Host '--- INICIO DE LA PRUEBA DE DIAGNÓSTICO DE CERTIFICADOS ---' -ForegroundColor Yellow

# --- 1. Definir Rutas Absolutas (Basado en tu estructura) ---
# $PSScriptRoot es la carpeta donde está este script (la raíz del proyecto)
$baseDir = $PSScriptRoot 
$modulesPath = Join-Path -Path $baseDir -ChildPath 'Modules'
$vCenterModulePath = Join-Path -Path $modulesPath -ChildPath 'VMware.PowerCLI.VCenter\VMware.PowerCLI.VCenter.psd1'
$coreModulePath = Join-Path -Path $modulesPath -ChildPath 'VMware.VimAutomation.Core\VMware.VimAutomation.Core.psd1'

Write-Host 'Ruta de Módulos a probar: $modulesPath'

# 2. Desbloquear archivos (muy importante para módulos copiados)
Write-Host '`nPaso 1: Desbloqueando archivos de módulos (seguridad de Windows)...'
try {
    Get-ChildItem -Path $modulesPath -Recurse | Unblock-File -ErrorAction Stop
    Write-Host '-> Desbloqueo completado.' -ForegroundColor Green
}
catch {
    Write-Warning 'No se pudo ejecutar Unblock-File. $($_.Exception.Message)'
}

# 3. Importar Módulo Core (para Connect-VIServer)
Write-Host '`nPaso 2: Importando módulo Core...'
try {
    Import-Module -Name $coreModulePath -Force -ErrorAction Stop
    Write-Host '-> Módulo Core importado.' -ForegroundColor Green
}
catch {
    Write-Error 'FALLO CRÍTICO: No se pudo cargar el módulo Core.'
    Write-Error 'Revisa que la ruta sea correcta: $coreModulePath'
    Read-Host 'Presiona Enter para salir.'
    exit 1
}

# 4. Importar Módulo VCenter (el que tiene los comandos de certificados)
Write-Host '`nPaso 3: Importando módulo VCenter (VMware.PowerCLI.VCenter)...'
try {
    Import-Module -Name $vCenterModulePath -Force -ErrorAction Stop
    Write-Host '-> Módulo VCenter importado.' -ForegroundColor Green
}
catch {
    Write-Error 'FALLO CRÍTICO: No se pudo cargar VMware.PowerCLI.VCenter.'
    Write-Error 'Error: $($_.Exception.Message)'
    Write-Error 'Asegúrate de que este módulo Y sus dependencias (como VMware.VimAutomation.Certificate) estén en la carpeta '$modulesPath'.'
    Read-Host 'Presiona Enter para salir.'
    exit 1
}

# 5. Verificar si los comandos ahora existen
Write-Host '`nPaso 4: Verificando si los comandos ahora existen...'
$cmd1 = Get-Command Get-VIMachineCertificate -ErrorAction SilentlyContinue
$cmd2 = Get-Command Get-VITrustedCertificate -ErrorAction SilentlyContinue

if ($cmd1 -and $cmd2) {
    Write-Host '-> ¡ÉXITO! Los comandos Get-VIMachineCertificate y Get-VITrustedCertificate se han cargado.' -ForegroundColor Green
} else {
    Write-Error 'FALLO: Los comandos no se encontraron, incluso después de cargar los módulos.'
    Read-Host 'Presiona Enter para salir.'
    exit 1
}

# 6. Conectar al vCenter
Write-Host '`nPaso 5: Conectando al vCenter...'
$vcenter = Read-Host 'Ingresa el FQDN del vCenter para la prueba'
$vcenterConnection = $null
try {
    # Ignoramos certificados inválidos para la prueba
    Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -confirm:$false
    $vcenterConnection = Connect-VIServer -Server $vcenter -ErrorAction Stop
}
catch {
    Write-Error 'FALLO: No se pudo conectar al vCenter. Error: $($_.Exception.Message)'
    Read-Host 'Presiona Enter para salir.'
    exit 1
}
Write-Host '-> Conexión exitosa a $vcenter.' -ForegroundColor Green

# 7. Ejecutar los comandos de certificados
Write-Host '`nPaso 6: Ejecutando Get-VIMachineCertificate...'
try {
    $machineCert = Get-VIMachineCertificate -VCenterOnly -ErrorAction Stop
    Write-Host '-> ÉXITO: Get-VIMachineCertificate se ejecutó.' -ForegroundColor Green
    $machineCert | Format-Table Subject, NotAfter
}
catch {
    Write-Error 'FALLO al ejecutar Get-VIMachineCertificate. Error: $($_.Exception.Message)'
}

Write-Host '`nPaso 7: Ejecutando Get-VITrustedCertificate...'
try {
    $trustedCerts = Get-VITrustedCertificate -VCenterOnly -ErrorAction Stop
    Write-Host '-> ÉXITO: Get-VITrustedCertificate se ejecutó. Se encontraron $($trustedCerts.Count) certificados.' -ForegroundColor Green
}
catch {
    Write-Error 'FALLO al ejecutar Get-VITrustedCertificate. Error: $($_.Exception.Message)'
}

Write-Host '`n--- PRUEBA FINALIZADA ---' -ForegroundColor Yellow
Disconnect-VIServer -Confirm:$false -ErrorAction SilentlyContinue
Read-Host 'Presiona Enter para salir.'

$global:connections = @()
$global:cisConnections = @{}

function Set-Endpoints($modules) {
	$components = @()

	foreach ($module in $modules) {
			$cs = $module.component.Split(";")
			foreach ($c in $cs) {
				if (!$components.Contains($c)) {
					$components += $c
					$Global:connections += [PSCustomObject] @{component=$c; host=""; conn=$null}
				}
			}
	}
}


function Test-vRopsConnection($hostName, $cred){
	$uri = "https://{0}/suite-api/api/versions/current/" -f $hostName
	$headers = @{"Accept" = "application/json"}
	try{
		$result = Invoke-WebRequest -SkipCertificateCheck -Uri $uri -Credential $cred -Headers $headers
	}catch{
		Write-Host "Connection Failure!"
		if($_ -like "No such host is known"){
			Write-Host "Unkown host. Try again."
			return $false
		}

		if($_.Exception.Response.ReasonPhrase -like 401 -or $_.Exception.Response.statusCode -like "Unauthorized"){
			Write-Host "Invalid credentials. Try again."
			return $false
		}

		if($_.FullyQualifiedErrorId -like "CannotConvertArgumentNoMessage,Microsoft.PowerShell.Commands.InvokeWebRequestCommand"){
			Write-Host "Invalid hostname. Try again."
			return $false
		}

		if($_.Exception.Message -like "A connection attempt failed because the connected party did not properly respond after a period of time, or established connection failed because connected host has failed to respond"){
			Write-Host "Response timeout, the hostname did not respond anything. Try again."
			return $false
		}

		
		$result = $_
	}
	if($result.statusCode -like 200){
		return $true
	}
	Write-Host $result
	Write-Host "Unexpected exception!"
	return $false
}

#funcion no necesaria de momento
#function Test-vCenterConnection(){
#	try{
#		$connection = Connect-VIServer -ea Stop
#	}catch{
#		Write-Host "Connection Failure!"
#	
#		Write-Host "Failed to connect. Try again."
#		return $false
#	}
#
#	return $connection
#}


#Para cada credencial exitosa (logra conectar al vcenter), se guardan en un "llavero", al pasar al siguiente fqdn prueba 
#con la crendencial en el llavero, en caso de que esta falle, entonces pide ingresar otra credencial, 
#que en caso de exito se vuelve a almacenar en el llavero. Al pasar al siguiente fqdn
#prueba la conexion con alguna de las claves de llevero, repite el proceso indefinidamente.
function Connect-Endpoints($modules) {
    $vcenterEndpoint = $Global:connections | Where-Object { $_.component -eq "vcenter" }
    if (-not $vcenterEndpoint) { return $true }

    Write-Host "`n--- Configuración de Conexión a vCenter ---" -ForegroundColor Yellow
    $serverListInput = Read-Host "Ingrese los servidores vCenter a conectar, separados por coma (,)"
    
    if ([string]::IsNullOrWhiteSpace($serverListInput)) {
        Write-Warning "No se ingresaron servidores. Omitiendo la recolección de vCenter."
        return $false
    }

    $serverList = $serverListInput.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $successfulConnections = @()
    
    $credentialCache = [System.Collections.ArrayList]@()

    foreach ($serverName in $serverList) {
        $connectedSuccessfully = $false
        
        if ($credentialCache.Count -gt 0) {
            Write-Host "`nProbando credenciales guardadas en '$serverName'..." -ForegroundColor Cyan
            foreach ($cachedCred in $credentialCache) {
                try {
                    # 1. Conectar a VIServer (SOAP)
                    $connection = Connect-VIServer -Server $serverName -Credential $cachedCred -ErrorAction Stop
                    Write-Host "-> Conexión VIServer (SOAP) automática exitosa." -ForegroundColor Green
                    $successfulConnections += $connection
                    $connectedSuccessfully = $true
                    
                    # --- [NUEVA LÓGICA CIS] ---
                    # 2. Si VIServer conectó, conectar a CisServer (REST)
                    try {
                        Write-Host "`t-> Intentando conexión CIS (REST) automática..."
                        $cisConn = Connect-CisServer -Server $serverName -Credential $cachedCred -ErrorAction Stop
                        $global:cisConnections[$serverName] = $cisConn # Guardamos en el llavero CIS
                        Write-Host "`t-> Conexión CIS automática exitosa." -ForegroundColor Green
                    } catch {
                        Write-Warning "`t-> La conexión CIS automática falló. Los certificados internos no se podrán leer para $serverName."
                    }
                    # --- [FIN LÓGICA CIS] ---
                    
                    break # Salimos del bucle de credenciales
                }
                catch {
                    # Falló esta credencial, probamos la siguiente
                }
            }
        }

        if ($connectedSuccessfully) {
            continue # Pasamos al siguiente servidor
        }

        while (-not $connectedSuccessfully) {
            Write-Host "`nIntentando conectar a '$serverName' (se necesita nueva credencial)..."
            try {
                $credential = Get-Credential -Message "Ingrese credenciales para '$serverName'"
                if (-not $credential) { throw "Operación cancelada por el usuario." }
                
                # 1. Conectar a VIServer (SOAP)
                $connection = Connect-VIServer -Server $serverName -Credential $credential -ErrorAction Stop
                Write-Host "-> Conexión VIServer (SOAP) con '$serverName' exitosa." -ForegroundColor Green
                $successfulConnections += $connection
                $connectedSuccessfully = $true 
                $credentialCache.Add($credential) | Out-Null
                
                # --- [NUEVA LÓGICA CIS] ---
                # 2. Si VIServer conectó, conectar a CisServer (REST)
                try {
                    Write-Host "`t-> Intentando conexión CIS (REST)..."
                    $cisConn = Connect-CisServer -Server $serverName -Credential $credential -ErrorAction Stop
                    $global:cisConnections[$serverName] = $cisConn # Guardamos en el llavero CIS
                    Write-Host "`t-> Conexión CIS exitosa." -ForegroundColor Green
                } catch {
                    Write-Warning "`t-> La conexión CIS falló. Los certificados internos no se podrán leer para $serverName."
                }
                # --- [FIN LÓGICA CIS] ---
            }
            catch {
                Write-Warning "-> FALLO la conexión VIServer con '$serverName'."
                Write-Warning "   Error: $($_.Exception.Message)"
                $choice = Read-Host "Presiona 'R' para reintentar la conexión con este servidor, o 'X' para abortar todo el proceso"
                if ($choice.ToLower() -eq 'x') {
                    Write-Error "Operación abortada por el usuario."
                    exit 1
                }
            }
        } 
    } 

    if ($successfulConnections.Count -gt 0) {
        $vcenterEndpoint.conn = $successfulConnections
        $vcenterEndpoint.host = $successfulConnections.Name -join ", "
        Write-Host "`nConexión establecida con $($successfulConnections.Count) servidor(es) vCenter." -ForegroundColor Green
        return $true
    }
    else {
        return $false 
    }
}

function Connect-Endpoint($component){
	# if($component -eq "vcenter"){
	# 	"Debe conectarse a un vCenter. Ingrese los parametros para conectarse"
	# 	$server = Read-Host "Host"
	# 	$user = Read-Host "Usuario"
	# 	$pass = Read-Host "Password" -AsSecureString
	# 	$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass)
	# 	$UnsecurePassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
	# 	$connection = Connect-VIServer -Server $server -u $user -pass $UnsecurePassword
	# 	$newConnection = [PSCustomObject] @{component=$component; host=$connection.Name; conn=$connection}
	# 	$global:connections += $newConnection
	# }
}

function Disconnect-Endpoints {
    foreach ($conn in $global:connections) {
        if($conn.component -eq "vcenter"){
            # Desconecta VIServer (SOAP)
            Disconnect-VIServer -Server $conn.conn -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
    
    # --- [NUEVO] Desconecta todas las conexiones CIS (REST) ---
    foreach ($cisConn in $global:cisConnections.Values) {
        Disconnect-CisServer -Server $cisConn -Confirm:$false -ErrorAction SilentlyContinue
    }

    # Limpiamos las variables globales
    $global:connections = @()
    $global:cisConnections = @{}
}
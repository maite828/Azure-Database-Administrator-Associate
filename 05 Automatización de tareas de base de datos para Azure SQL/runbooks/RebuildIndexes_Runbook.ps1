<#
.SYNOPSIS
  Runbook para reconstruir índices en bases objetivo leídas desde una tabla de control o pasadas como parámetro.

.DESCRIPTION
  Este runbook está diseñado para ejecutarse en Azure Automation (PowerShell 7+). Intenta usar Managed Identity del Automation Account
  para autenticarse en Azure y obtener tokens AAD para autenticarse frente a Azure SQL mediante Access Token.

  Flujo:
  - Conectar a Azure con identidad administrada: Connect-AzAccount -Identity
  - Obtener targets desde una tabla de control o desde el parámetro $Targets
  - Para cada target, obtener token AAD y ejecutar el T-SQL de mantenimiento (por defecto: REBUILD de índices de tablas seleccionadas)

USAGE
  - Importar el script como Runbook (PowerShell) en Azure Automation.
  - Asegurar que el Automation Account tiene System Assigned Managed Identity habilitada y que la Managed Identity tiene el rol
    'Azure SQL Database Contributor' o permisos adecuados para conectarse a las bases (o use credenciales seguras almacenadas en Automation).
  - Crear la tabla de control (opcional) en una base de control con columnas: ServerName NVARCHAR(200), DatabaseName NVARCHAR(200), Enabled BIT.

PARAMETERS
  -ControlDbServer: servidor del control (ejecuta lectura de la tabla de control).
  -ControlDbName: base de datos de control (por defecto 'AutomationControl').
  -ControlTable: tabla de control completa (por defecto 'dbo.RebuildTargets').
  -Targets: array de objetos @{ ServerName='...'; DatabaseName='...'} para ejecutar sin tabla de control.
  -MaintenanceSql: T-SQL que se ejecutará en cada target. Por defecto ejecuta reconstrución de índices para tablas objetivo.

NOTAS
  - En entornos PaaS se recomienda usar Azure AD auth con Managed Identity o credenciales almacenadas en Key Vault.
  - Probar primero en bases no productivas y definir ventanas de mantenimiento.
#>

param(
  [string] $ControlDbServer = '',
  [string] $ControlDbName = 'AutomationControl',
  [string] $ControlTable = 'dbo.RebuildTargets',
  [array] $Targets = @(),
  [string] $MaintenanceSql = "-- Script de mantenimiento por defecto: rebuild índices para tablas específicas\n-- Ajusta según necesidad\nALTER INDEX ALL ON dbo.Orders REBUILD WITH (ONLINE = ON);",
  [switch] $UseControlTable
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module SqlServer -ErrorAction SilentlyContinue

Function Get-AccessTokenForSql {
  param(
    [string] $Resource = 'https://database.windows.net/'
  )
  $token = (Get-AzAccessToken -ResourceUrl $Resource).Token
  return $token
}

Try {
  Write-Output "Connecting to Azure using managed identity..."
  Connect-AzAccount -Identity | Out-Null
}
Catch {
  Write-Error "No se pudo conectar con Managed Identity: $_"
  Throw $_
}

if ($UseControlTable -and ($ControlDbServer -ne '')) {
  Write-Output "Leyendo targets desde la tabla de control $ControlTable en $ControlDbServer/$ControlDbName"
  $token = Get-AccessTokenForSql
  $sql = "SELECT ServerName, DatabaseName FROM $ControlTable WHERE Enabled = 1;"
  $targetsObj = Invoke-Sqlcmd -ServerInstance $ControlDbServer -Database $ControlDbName -AccessToken $token -Query $sql -ErrorAction Stop
  foreach ($row in $targetsObj) {
    $Targets += @{ ServerName = $row.ServerName; DatabaseName = $row.DatabaseName }
  }
}

if ($Targets.Count -eq 0) {
  Write-Warning "No se han detectado targets. Proporciona -Targets o habilita -UseControlTable con una tabla de control válida."
  return
}

foreach ($t in $Targets) {
  try {
    $server = $t.ServerName
    $db = $t.DatabaseName
    Write-Output "Ejecutando mantenimiento en $server / $db"
    $token = Get-AccessTokenForSql
    # Ejecutar el script de mantenimiento
    Invoke-Sqlcmd -ServerInstance $server -Database $db -AccessToken $token -Query $MaintenanceSql -QueryTimeout 0 -ErrorAction Stop
    Write-Output "Mantenimiento completado en $server/$db"
  }
  catch {
    Write-Error "Error en target $($t.ServerName)/$($t.DatabaseName): $_"
  }
}

Write-Output "Runbook finalizado."

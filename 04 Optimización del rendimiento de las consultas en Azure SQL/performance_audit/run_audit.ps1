<#
.SYNOPSIS
  Wrapper PowerShell para ejecutar capture_waits_and_index_audit.sql y guardar resultados.
.DESCRIPTION
  Usa Invoke-Sqlcmd (módulo SqlServer) o sqlcmd para ejecutar el script. El script SQL ya guarda snapshots
  en tablas dentro de la base de datos; este wrapper además puede exportar el SELECT final a fichero CSV.
.PARAMETER Server
  Servidor/instancia (p.ej. tcp:myserver.database.windows.net,1433)
.PARAMETER Database
  Base de datos destino.
.PARAMETER Username
  Usuario SQL (opcional). Si no se proporciona, intenta autenticación integrada.
.PARAMETER Password
  Contraseña del usuario SQL (opcional).
.PARAMETER OutCsv
  Ruta del CSV donde guardar el resumen de recomendaciones.
.EXAMPLE
  .\run_audit.ps1 -Server 'myserver.database.windows.net' -Database 'northwinddb' -Username 'sqladmin' -Password 'P@ssw0rd!' -OutCsv '.\audit_summary.csv'
#>
param(
  [Parameter(Mandatory=$true)][string]$Server,
  [Parameter(Mandatory=$true)][string]$Database,
  [string]$Username = '',
  [string]$Password = '',
  [string]$OutCsv = ''
)

$scriptPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) 'capture_waits_and_index_audit.sql'
if (-not (Test-Path $scriptPath)) { Write-Error "No se encuentra $scriptPath"; exit 1 }

$Query = Get-Content -Raw -Path $scriptPath

Try {
  if ($Username -ne '') {
    # Con credenciales SQL
    Invoke-Sqlcmd -ServerInstance $Server -Database $Database -Username $Username -Password $Password -Query $Query -QueryTimeout 0
    $summary = Invoke-Sqlcmd -ServerInstance $Server -Database $Database -Username $Username -Password $Password -Query "-- Recuperar resumen de recomendaciones\nWITH idx_usage AS ( SELECT s.object_id, s.index_id, i.name AS index_name, ISNULL(s.user_seeks,0) AS user_seeks, ISNULL(s.user_scans,0) AS user_scans, ISNULL(s.user_lookups,0) AS user_lookups, ISNULL(s.user_updates,0) AS user_updates FROM sys.dm_db_index_usage_stats s JOIN sys.indexes i ON s.object_id = i.object_id AND s.index_id = i.index_id WHERE s.database_id = DB_ID() ), idx_phys AS ( SELECT object_id, index_id, avg_fragmentation_in_percent, page_count FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, ''LIMITED'') ) SELECT OBJECT_SCHEMA_NAME(u.object_id) AS SchemaName, OBJECT_NAME(u.object_id) AS TableName, u.index_id, u.index_name, u.user_seeks, u.user_scans, u.user_lookups, u.user_updates, p.page_count, p.avg_fragmentation_in_percent, CASE WHEN (u.user_seeks + u.user_scans + u.user_lookups) = 0 AND u.user_updates > 1000 THEN 'ALTA ESCRITURA / BAJO USO: Revisar, posible DROP o consolidar índices' WHEN p.page_count > 1000 AND p.avg_fragmentation_in_percent > 30 THEN 'REBUILD recomendado' WHEN p.page_count > 1000 AND p.avg_fragmentation_in_percent BETWEEN 5 AND 30 THEN 'REORGANIZE recomendado' ELSE 'Sin acción inmediata' END AS Suggestion FROM idx_usage u LEFT JOIN idx_phys p ON u.object_id = p.object_id AND u.index_id = p.index_id ORDER BY Suggestion DESC, u.user_updates DESC" -QueryTimeout 0
  }
  else {
    # Autenticación integrada
    Invoke-Sqlcmd -ServerInstance $Server -Database $Database -Query $Query -QueryTimeout 0
    $summary = Invoke-Sqlcmd -ServerInstance $Server -Database $Database -Query "-- Recuperar resumen de recomendaciones\nWITH idx_usage AS ( SELECT s.object_id, s.index_id, i.name AS index_name, ISNULL(s.user_seeks,0) AS user_seeks, ISNULL(s.user_scans,0) AS user_scans, ISNULL(s.user_lookups,0) AS user_lookups, ISNULL(s.user_updates,0) AS user_updates FROM sys.dm_db_index_usage_stats s JOIN sys.indexes i ON s.object_id = i.object_id AND s.index_id = i.index_id WHERE s.database_id = DB_ID() ), idx_phys AS ( SELECT object_id, index_id, avg_fragmentation_in_percent, page_count FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, ''LIMITED'') ) SELECT OBJECT_SCHEMA_NAME(u.object_id) AS SchemaName, OBJECT_NAME(u.object_id) AS TableName, u.index_id, u.index_name, u.user_seeks, u.user_scans, u.user_lookups, u.user_updates, p.page_count, p.avg_fragmentation_in_percent, CASE WHEN (u.user_seeks + u.user_scans + u.user_lookups) = 0 AND u.user_updates > 1000 THEN 'ALTA ESCRITURA / BAJO USO: Revisar, posible DROP o consolidar índices' WHEN p.page_count > 1000 AND p.avg_fragmentation_in_percent > 30 THEN 'REBUILD recomendado' WHEN p.page_count > 1000 AND p.avg_fragmentation_in_percent BETWEEN 5 AND 30 THEN 'REORGANIZE recomendado' ELSE 'Sin acción inmediata' END AS Suggestion FROM idx_usage u LEFT JOIN idx_phys p ON u.object_id = p.object_id AND u.index_id = p.index_id ORDER BY Suggestion DESC, u.user_updates DESC" -QueryTimeout 0
  }

  if ($OutCsv -ne '') {
    $summary | Export-Csv -Path $OutCsv -NoTypeInformation -Encoding UTF8
    Write-Host "Resumen exportado a $OutCsv"
  }
  else {
    $summary | Format-Table -AutoSize
  }
}
Catch {
  Write-Error "Error ejecutando el script: $_"
  Exit 2
}

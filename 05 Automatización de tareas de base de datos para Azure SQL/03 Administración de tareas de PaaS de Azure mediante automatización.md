# Administración de tareas de PaaS de Azure mediante automatización

Este documento explica herramientas y patrones para automatizar tareas de administración sobre Azure SQL (PaaS) y SQL Server en IaaS: políticas, runbooks, integraciones sin código y ejecución de trabajos distribuidos.

## Ventajas de Azure Policy

Azure Policy permite aplicar gobernanza automatizada sobre recursos (por ejemplo: asegurar que todas las bases de datos tienen auditoría habilitada, o que los servidores usan TLS mínimo). Ventajas principales:

- **Cumplimiento consistente**: aplica reglas a escala suscripciones/resource groups.
- **Prevención y corrección**: `deny` bloquea recursos no conformes; `deployIfNotExists` permite desplegar configuraciones remediadoras automáticamente.
- **Reportabilidad**: evaluación y compliance dashboard para auditorías.
- **Integración con CI/CD**: políticas como paso en pipelines para evitar despliegues no conformes.

Ejemplo (AZ CLI) — asignar una policy built-in que exige cifrado del almacenamiento (ejemplo ilustrativo):

```bash
az policy assignment create \
	--name require-storage-encryption \
	--scope /subscriptions/<subscriptionId>/resourceGroups/my-rg \
	--policy "/providers/Microsoft.Authorization/policyDefinitions/yourPolicyId"
```

Explicación: `az policy assignment create` asocia una definición de política a un scope. `deployIfNotExists` puede definirse en la policy para remediar automáticamente.

## Funcionalidades de Azure Automation

Azure Automation es un servicio para ejecutar runbooks (PowerShell / PowerShell Workflow / Python), gestionar actualizaciones (Update Management), Desired State Configuration (DSC) y disponer de Hybrid Workers que permiten ejecutar runbooks contra recursos on-premises o en IaaS.

Principales funcionalidades:

- **Runbooks**: scripts automatizados reutilizables con programación, start/stop y control de versiones.
- **Update Management**: orquesta parches en VMs (Windows/Linux).
- **Desired State Configuration (DSC)**: asegurar configuración declarativa en máquinas.
- **Hybrid Runbook Worker**: ejecutar runbooks con acceso a redes privadas sin exponer puertos.

Ejemplo (PowerShell) — crear Automation Account y publicar un runbook mínimo que ejecuta un comando T-SQL contra Azure SQL (runbook en PowerShell):

```powershell
# Crear Automation Account (requiere Az.Automation module)
New-AzAutomationAccount -ResourceGroupName my-rg -Name myAutomation -Location westeurope

# Contenido de runbook (PowerShell) que ejecuta un T-SQL para rebuild de índices
$runbook = @'
Param(
	[string] $SqlServer,
	[string] $Database,
	[string] $SqlUser,
	[string] $SqlPassword
)
$connString = "Server=$SqlServer;Database=$Database;User Id=$SqlUser;Password=$SqlPassword;"
Invoke-Sqlcmd -ConnectionString $connString -Query "ALTER INDEX ALL ON dbo.Orders REBUILD;"
'@

# Nota: Publish/Import del runbook se realiza desde el portal, Azure Automation API o Az modules.
```

Explicación: el runbook usa `Invoke-Sqlcmd` para ejecutar T-SQL contra la base. En producción, use Managed Identities o credenciales almacenadas en Automation Credentials/KeyVault para evitar contraseñas en claro.

## Cómo usar Logic Apps

Logic Apps es una plataforma de integración sin código/low-code que permite orquestar flujos de trabajo con conectores (HTTP, SQL, Service Bus, Storage, Teams, etc.). Es ideal para integraciones event-driven, automatización de procesos y escenarios ETL ligero.

Patrón de uso típico para administración de bases de datos PaaS:

- Trigger: webhook, evento de Azure Monitor (alerta) o schedule.
- Acción: SQL Connector para ejecutar stored procedures o queries, o llamada a Azure Function/Automation Runbook.
- Notificación: enviar resultados a Teams/Email/Log Analytics.

Ejemplo conceptual (pasos):

1. Crear Logic App con trigger `Recurrence` (schedule diario).
2. Añadir acción `Execute stored procedure` usando el conector SQL y conexión con Managed Identity.
3. Añadir acción `Condition` para evaluar resultados y, si es necesario, notificar por Teams.

Explicación: Logic Apps permite orquestar sin escribir código; la autenticación con Managed Identity evita manejar credenciales.

## Azure Functions VS Logic Apps VS Azure Automation

Resumen de cuándo elegir cada uno:

- **Azure Functions**:
	- Pros: código (C#/PowerShell/JavaScript/Python), alto control, escalabilidad automática, buen fit para lógica personalizada y procesamiento intensivo.
	- Contras: requiere desarrollo, testing y gestión de versiones.
	- Usos: procesamiento de eventos, transformación de datos, microservicios que ejecutan lógica compleja (ej. análisis de planes, parseo, llamadas a APIs).

- **Logic Apps**:
	- Pros: low-code, connectors integrados, ideal para orquestación y tareas integradas (notificaciones, integraciones SaaS).
	- Contras: menos control fino sobre runtime y coste por acción en escenarios muy intensivos.
	- Usos: automatización de alertas, flujos de integración, llamadas a runbooks o funciones para acciones específicas.

- **Azure Automation**:
	- Pros: diseñado para operaciones y administración (runbooks PowerShell, DSC, Update Management), Hybrid Worker para redes privadas.
	- Contras: menos idóneo para lógica de negocio pesada o latencia muy baja.
	- Usos: tareas de mantenimiento (rebuild de índices, backups en IaaS, parcheo de VMs), ejecución con privilegios administrativos en entornos controlados.

Patrón combinado recomendado:

- Usar **Logic Apps** para orquestación y conexión entre servicios (alerta -> orquestador).
- En la acción crítica, invocar **Azure Automation** para ejecutar runbooks con credenciales/privilegios elevados, o invocar una **Azure Function** si hace falta lógica compleja o transformación previa.

Ejemplo práctico (flujo):

- Azure Monitor detecta aumento de `PAGEIOLATCH`.
- Logic App desencadenada por alerta obtiene top-queries y llama a una Function que analiza planes.
- Si la Function determina necesidad de mantenimiento, Logic App llama a un runbook de Azure Automation para ejecutar `ALTER INDEX ... REBUILD` usando Hybrid Worker (si es IaaS) o credenciales gestionadas (si es PaaS).

## Descripción y cuándo se usan los Trabajos Elásticos (Elastic Jobs)

Los Elastic Database Jobs (Elastic Jobs) permiten ejecutar scripts T-SQL a gran escala contra múltiples bases de datos dentro de una misma logical server o across elastic pools. Son útiles para tareas repetitivas que deben aplicarse a muchas bases (p. ej. actualizar estadísticas, ejecutar mantenimiento ligero, cambiar configuraciones).

Casos de uso comunes:

- Ejecutar la misma tarea de mantenimiento en cientos de bases (por ejemplo, rebuild de índices en bases pequeñas).
- Aplicar cambios de configuración a múltiples bases (p. ej. actualizar parámetros o user-defined settings).
- Recopilar métricas o ejecutar auditorías a escala.

Flujo de trabajo típico:

1. Crear un Elastic Job Agent (uno por subscription/region típicamente).
2. Crear un Job que contiene pasos T-SQL y un target group (lista de bases/databases o un query que devuelve targets).
3. Programar el Job o ejecutarlo ad-hoc.

Ejemplo de paso T-SQL (job step) — actualizar estadísticas y comprobar fragmentación mínimo:

```sql
-- Paso de job: actualizar estadísticas y devolver tablas con fragmentación > 30%
UPDATE STATISTICS dbo.Orders WITH FULLSCAN;

SELECT s.object_id, i.index_id, ips.avg_fragmentation_in_percent
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
JOIN sys.objects s ON i.object_id = s.object_id
WHERE ips.avg_fragmentation_in_percent > 30;
```

Explicación: el job step ejecuta mantenimiento ligero y devuelve un resultado que puede usarse para decidir acciones posteriores.

Nota operacional y seguridad

- Siempre probar en un conjunto reducido de bases antes de ejecutar a escala.
- Gestionar credenciales mediante Managed Identity o Key Vault; evitar credenciales en texto plano.
- Controlar ventanas de mantenimiento y `MAXDOP`/`FILLFACTOR` según carga y tipología de bases.

## Ejemplos rápidos de integración

1) Azure Policy para asegurar tagging y así facilitar targeting de automatizaciones (ejemplo visto antes).

2) PowerShell para invocar un runbook programáticamente (ejemplo básico):

```powershell
# Iniciar runbook existente en Automation Account
# Parametros: ResourceGroup, AutomationAccountName, RunbookName
$job = Start-AzAutomationRunbook -ResourceGroupName 'my-rg' -AutomationAccountName 'myAutomation' -Name 'MyRunbook' -Parameters @{
	SqlServer = 'myserver.database.windows.net';
	Database = 'northwinddb';
	SqlUser = 'sqladmin';
	SqlPassword = 'P@ssw0rd!'
}
```

Explicación: `Start-AzAutomationRunbook` lanza un runbook; los parámetros permiten pasar detalles de ejecución. En producción, use credenciales almacenadas y/o Managed Identity.

3) T-SQL de mantenimiento (ejemplo de rebuild de índices en PaaS):

```sql
ALTER INDEX ALL ON dbo.Orders REBUILD WITH (ONLINE = ON);
```

Explicación: reconstrución de todos los índices de la tabla `Orders`. En Azure SQL, `ONLINE = ON` reduce tiempo de bloqueo para la mayoría de niveles de servicio.

---

## Runbook: `RebuildIndexes_Runbook.ps1`

Runbook en PowerShell en la carpeta `runbooks` llamado `RebuildIndexes_Runbook.ps1`.

Resumen y uso:

- **Descripción**: runbook que reconstruye índices usando Azure AD authentication (Managed Identity) o ejecuta el T-SQL de mantenimiento que se pase como parámetro. Puede leer targets desde una tabla de control (`AutomationControl.dbo.RebuildTargets`) o recibir un array de targets como parámetro.
- **Dónde**: `05 Automatización de tareas de base de datos para Azure SQL/runbooks/RebuildIndexes_Runbook.ps1`.
- **Requisitos**: el Automation Account debe tener System Assigned Managed Identity habilitada y permisos para conectarse a las bases (o usar credenciales seguras). El módulo `Az.Accounts` debe estar disponible en el runbook (PowerShell 7+ recomendado).

Pasos rápidos para usarlo:

1. Importar el script como Runbook (tipo PowerShell) en el Automation Account.
2. Habilitar System Assigned Managed Identity en el Automation Account y asignarle permisos (p. ej. "Azure SQL DB Contributor" o permisos mínimos necesarios) sobre las bases objetivo.
3. (Opcional) Crear tabla de control `AutomationControl.dbo.RebuildTargets` con columnas `ServerName NVARCHAR(200)`, `DatabaseName NVARCHAR(200)`, `Enabled BIT` y activar `-UseControlTable` al ejecutar.
4. Probar manualmente con parámetros:

```powershell
# Ejecutar desde Azure Cloud Shell / Powershell con Az modules
Start-AzAutomationRunbook -ResourceGroupName 'my-rg' -AutomationAccountName 'myAutomation' -Name 'RebuildIndexes_Runbook' -Parameters @{
	Targets = @(@{ ServerName = 'myserver.database.windows.net'; DatabaseName = 'northwinddb' })
}
```

Explicación: `Start-AzAutomationRunbook` lanza el runbook; los parámetros permiten pasar una lista de targets. Alternativamente, programar el runbook o invocarlo desde Logic App / Elastic Job Agent.

Seguridad y buenas prácticas:

- No incluir credenciales en claro: use Managed Identity o Azure Key Vault.
- Pruebe primero en entornos no productivos y limite ventanas de mantenimiento.
- Loguee salidas y errores en un repositorio central o tabla de auditoría.

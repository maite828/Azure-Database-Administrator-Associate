# Configuración de bases de datos para el rendimiento óptimo

Este documento explica opciones de configuración a nivel de base de datos, las capacidades de procesamiento de consultas inteligentes (IQP), el ajuste automático en Azure y las tareas de mantenimiento relacionadas con índices y estadísticas. Incluye ejemplos de Azure PowerShell, Azure CLI y T-SQL (cuando procede con Northwind/AdventureWorksLT) y recomendaciones para entornos PaaS e IaaS.

## 1. Entender las opciones de configuración de ámbito de base de datos

Concepto

Las configuraciones de ámbito de base de datos (database-scoped configurations) permiten ajustar comportamientos del optimizador y del motor sin tocar la instancia entera. En SQL Server y en Azure SQL Managed Instance/Database algunas opciones se exponen como `ALTER DATABASE SCOPED CONFIGURATION`.

Ejemplos de opciones útiles

- `MAXDOP` (cuando está disponible a nivel de BD) para limitar paralelismo por base.
- `BATCH_MODE_ON_ROWSTORE` para permitir ejecución en modo batch sobre rowstore (mejora para cargas analíticas).
- Opciones de compatibilidad como `LEGACY_CARDINALITY_ESTIMATION`.

T-SQL: ver y cambiar configuraciones a nivel de base de datos

```sql
-- Ver configuraciones scoped
SELECT * FROM sys.database_scoped_configurations;

-- Habilitar Batch Mode on Rowstore (si está soportado)
ALTER DATABASE SCOPED CONFIGURATION SET BATCH_MODE_ON_ROWSTORE = ON;

-- Deshabilitar estimador de cardinalidad legacy
ALTER DATABASE SCOPED CONFIGURATION SET LEGACY_CARDINALITY_ESTIMATION = OFF;
```

Notas

- No todas las opciones están disponibles en todas las ediciones/plataformas; en Azure SQL Database PaaS Microsoft aplica muchas mejoras por defecto.
- Probar cambios en staging y monitorizar con Query Store y Extended Events.

## 2. Comprender las características del procesamiento de consultas inteligentes (IQP)

Qué es IQP

IQP (Intelligent Query Processing) agrupa mejoras del optimizador que reducen la necesidad de reescrituras manuales y mejoran desempeño: ejemplos prácticos incluyen Memory Grant Feedback, Batch Mode on Rowstore, Adaptive Joins, Interleaved Execution para funciones multi-statement TVF y Scalar UDF Inlining.

Beneficios

- Mejora del rendimiento sin cambios en la aplicación.
- Reducción de planes subóptimos en cargas dinámicas.

Comprobar y forzar comportamientos

```sql
-- Comprobar si Batch Mode on Rowstore está activo (consulta sys.database_scoped_configurations)
SELECT name, value, value_for_secondary FROM sys.database_scoped_configurations
WHERE name IN ('BATCH_MODE_ON_ROWSTORE','LEGACY_CARDINALITY_ESTIMATION');

-- Test sencillo en Northwind: comparar plan y tiempos con y sin batch-mode (ejecutar en entorno de pruebas)
SELECT COUNT_BIG(*)
FROM dbo.Orders o
INNER JOIN dbo.OrderDetails od ON o.OrderID = od.OrderID
WHERE o.OrderDate IS NOT NULL;
```

Recomendaciones

- Activar características una a una y evaluar con Query Store.
- Priorizar `Scalar UDF Inlining` y `Batch Mode on Rowstore` para cargas analíticas.

## 3. Explorar la característica de ajuste automático en Azure

Qué ofrece

- Azure SQL Database incluye `Automatic Tuning` que propone/crea/borra índices y fuerza el último plan bueno automáticamente (force last good plan). Esta funcionalidad es gestionada por la plataforma y puede configurarse a nivel servidor o base.

Azure CLI: ver/activar ajuste automático

```bash
# Ver estado de automatic tuning para una base
az sql db automatic-tuning show --resource-group RG --server myserver --database mydb

# Habilitar automatic tuning (createIndex/dropIndex/forceLastGoodPlan)
az sql db automatic-tuning update --resource-group RG --server myserver --database mydb \
	--desired-state Auto \
	--options "createIndex=On" "dropIndex=On" "forceLastGoodPlan=On"
```

Azure PowerShell (ejemplo)

```powershell
Get-AzSqlDatabaseAutomaticTuning -ResourceGroupName RG -ServerName myserver -DatabaseName mydb

Set-AzSqlDatabaseAutomaticTuning -ResourceGroupName RG -ServerName myserver -DatabaseName mydb -DesiredState Auto
```

T-SQL: consultar, habilitar y deshabilitar Automatic Tuning

```sql
-- Consultar estado de Automatic Tuning (opciones por base)
-- Nota: vista disponible en Azure SQL Database
SELECT * FROM sys.database_automatic_tuning_options;

-- Habilitar Automatic Tuning (activar opciones individuales)
ALTER DATABASE CURRENT
SET AUTOMATIC_TUNING = (
	FORCE_LAST_GOOD_PLAN = ON,
	CREATE_INDEX = ON,
	DROP_INDEX = ON
);

-- Deshabilitar Automatic Tuning (desactivar todas las opciones)
ALTER DATABASE CURRENT
SET AUTOMATIC_TUNING = (
	FORCE_LAST_GOOD_PLAN = OFF,
	CREATE_INDEX = OFF,
	DROP_INDEX = OFF
);
```

Notas

- En IaaS (SQL Server en VM) no existe el ajuste automático de plataforma; se pueden implementar automatismos propios (scripts/Job Agent/Azure Automation) para aplicar recomendaciones de índices.

## 4. Comprender las tareas de mantenimiento relacionadas con la indexación y las estadísticas

Importancia

- Índices eficientes y estadísticas actualizadas son clave para buenos planes de ejecución. En sistemas con cambios frecuentes en datos deben existir políticas de mantenimiento.

Operaciones habituales (T-SQL)

```sql
-- Reconstruir todos los índices de una tabla (online si soportado)
ALTER INDEX ALL ON dbo.OrderDetails REBUILD WITH (ONLINE = ON);

-- Reorganizar índices fragmentados
ALTER INDEX ALL ON dbo.OrderDetails REORGANIZE;

-- Actualizar estadísticas para una tabla específica
UPDATE STATISTICS dbo.Orders WITH FULLSCAN;

-- Actualizar todas las estadísticas de la base
EXEC sp_updatestats;
```

Estrategias y umbrales

- Usar `sys.dm_db_index_physical_stats` para detectar fragmentación y decidir REORGANIZE vs REBUILD (por ejemplo >30% REBUILD, 5-30% REORGANIZE).
- Para estadísticas, `AUTO_UPDATE_STATISTICS` y `AUTO_UPDATE_STATISTICS_ASYNC` ayudan, pero en cargas masivas conviene ejecutar `UPDATE STATISTICS` manualmente tras grandes cargas.

Agente SQL y PaaS

- En SQL Server IaaS normalmente se programa mantenimiento con SQL Server Agent.
- En Azure SQL Database PaaS no hay SQL Agent; alternativas:
	- Elastic Job Agent (servicio gestionado para ejecutar T-SQL en múltiples DBs)
	- Azure Automation Runbooks (PowerShell con Invoke-Sqlcmd)
	- Azure Logic Apps / Functions para orquestación

Ejemplo: runbook simple PowerShell para actualizar estadísticas (Azure Automation)

```powershell
# Runbook: ejecutar UPDATE STATISTICS en una DB PaaS
$connectionString = "Server=tcp:myserver.database.windows.net,1433;Initial Catalog=mydb;Persist Security Info=False;User ID=sqladmin;Password=MyP@ss;Encrypt=True;TrustServerCertificate=False;"
Invoke-Sqlcmd -ConnectionString $connectionString -Query "EXEC sp_updatestats;"
```

Ejemplo T-SQL sobre Northwind: mantenimiento de índices y estadísticas

```sql
-- Reconstruir índices en OrderDetails
ALTER INDEX ALL ON dbo.OrderDetails REBUILD;

-- Actualizar estadísticas de Orders con sampling
UPDATE STATISTICS dbo.Orders WITH SAMPLE 50 PERCENT;
```

Monitorización y verificación

- Usar `sys.dm_db_index_operational_stats`, `sys.dm_db_index_physical_stats` y Query Store para medir impacto.
- En PaaS, revisar recomendaciones de Intelligent Insights y Automatic Tuning suggestions.


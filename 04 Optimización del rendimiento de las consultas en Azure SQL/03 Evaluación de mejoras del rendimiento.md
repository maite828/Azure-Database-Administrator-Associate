# Evaluación de mejoras del rendimiento

Este documento recoge cómo evaluar efectos de tuning en Azure SQL / SQL Server mediante estadísticas de espera, DMVs de índices y prácticas de mantenimiento.

## Estadísticas de espera (wait stats)

Las esperas reflejan dónde el motor pasa tiempo mientras ejecuta solicitudes. Revisar `sys.dm_os_wait_stats` permite localizar cuellos de botella (CPU, I/O, memoria, locks, etc.).

Consulta básica para ver las esperas más relevantes:

```sql
SELECT TOP 50
	wait_type,
	SUM (wait_time_ms) AS wait_time_ms,
	SUM (signal_wait_time_ms) AS signal_wait_time_ms,
	SUM (waiting_tasks_count) AS waiting_tasks_count
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN (
	'CLR_SEMAPHORE','LAZYWRITER_SLEEP','RESOURCE_QUEUE','SLEEP_TASK','SLEEP_SYSTEMTASK',
	'SQLTRACE_BUFFER_FLUSH','BROKER_EVENTHANDLER','BROKER_RECEIVE_WAITFOR','BROKER_TASK_STOP',
	'CLR_MANUAL_EVENT','CLR_AUTO_EVENT','DISPATCHER_QUEUE_SEMAPHORE','FT_IFTS_SCHEDULER_IDLE_WAIT',
	'XE_TIMER_EVENT','XE_DISPATCHER_WAIT', 'BROKER_TO_FLUSH')
GROUP BY wait_type
ORDER BY wait_time_ms DESC;
```

Interpretación y esperas comunes:

- RESOURCE_SEMAPHORE alto: indica presión en concesiones de memoria para operaciones que requieren memoria (hash joins, sorts). Remedios: optimizar consultas (evitar spills), crear índices para evitar operaciones en memoria, reducir concurrencia, escalar recursos (vCore/DTU).
- SEMAPHORE: puede aparecer en diferentes contextos; revisar la `signal_wait_time_ms` para distinguir si es CPU vs sincronización interna.
- LCK_M_X / LCK_M_S altas: esperas de bloqueo (exclusive/shared). Indican bloqueo por transacciones largas o contención. Remedios: acortar transacciones, usar índices para reducir escaneos que bloquean, evaluar isolation levels (READ COMMITTED SNAPSHOT), revisar bloqueos con `sys.dm_tran_locks` y `sys.dm_os_waiting_tasks`.
- PAGEIOLATCH_* alto: esperas de I/O físico (lectura/escritura de páginas). Indica posible cuello de disco o demasiadas lecturas lógicas que escalan a físicas. Remedios: mejorar almacenamiento, aumentar caché, optimizar consultas/índices para reducir lecturas, considerar escala vertical/horizontal.
- SOS_*/SOS_Scheduler_* (p.ej. SOS_SCHEDULER_YIELD): suele relacionarse con CPU y programación de hilos; `SCHEDULER_YIELD` indica que tareas están cediendo tras consumir su quantum — posible CPU bound o contención de scheduling. Remedios: revisar uso CPU, optimizar consultas o escalar CPU, revisar MAXDOP y paralelismo.
- WAIT_FOR_RESULTS o esperas relacionadas con SH (shared) suelen indicar contención por lectura concurrente y bloqueos.

Ejemplo para localizar queries que esperan (join con requests):

```sql
SELECT
	w.session_id,
	r.status,
	r.command,
	r.cpu_time,
	r.total_elapsed_time,
	w.wait_type,
	w.wait_duration_ms,
	SUBSTRING(t.text, (r.statement_start_offset/2)+1,
		((CASE r.statement_end_offset
			WHEN -1 THEN DATALENGTH(t.text)
			ELSE r.statement_end_offset END
		- r.statement_start_offset)/2) + 1) AS current_statement
FROM sys.dm_os_waiting_tasks w
JOIN sys.dm_exec_requests r ON w.session_id = r.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
ORDER BY w.wait_duration_ms DESC;
```

Breves pautas de actuación según tipo de espera:

- Si predominan esperas de CPU / SCHEDULER_YIELD: perfilar consultas, revisar planes, reducir uso de CPU (reindex, estadísticas, filtros), revisar paralelismo.
- Si predominan PAGEIOLATCH: investigar I/O, buffer pool, TEMPDB, revisar índices y densidad de filas.
- Si predominan LCK_*: detectar bloqueos y transacciones largas; revisar locking hints sólo como último recurso.

## Evaluación de utilización de índices

1) sys.dm_db_index_operational_stats — actividad operacional (locks, latches, inserts, updates)

```sql
SELECT
	DB_NAME(database_id) AS DatabaseName,
	OBJECT_SCHEMA_NAME(i.object_id, database_id) AS SchemaName,
	OBJECT_NAME(i.object_id, database_id) AS ObjectName,
	i.index_id,
	ios.leaf_insert_count,
	ios.leaf_update_count,
	ios.leaf_delete_count,
	ios.range_scan_count,
	ios.singleton_lookup_count
FROM sys.dm_db_index_operational_stats(DB_ID(), NULL, NULL, NULL) AS ios
JOIN sys.indexes i
	ON ios.object_id = i.object_id AND ios.index_id = i.index_id
ORDER BY ios.range_scan_count DESC;
```

Explicación: muestra cuántas operaciones físicas/operacionales realiza cada índice (inserciones, actualizaciones, borrados, scans, lookups). Índices con muchas operaciones de escritura y bajo uso de lectura pueden penalizar rendimiento.

2) sys.dm_db_index_usage_stats — uso por consultas (seeks, scans, lookups, updates)

```sql
SELECT
	OBJECT_NAME(s.object_id) AS ObjectName,
	i.name AS IndexName,
	s.user_seeks,
	s.user_scans,
	s.user_lookups,
	s.user_updates
FROM sys.dm_db_index_usage_stats s
JOIN sys.indexes i
	ON s.object_id = i.object_id AND s.index_id = i.index_id
WHERE s.database_id = DB_ID()
ORDER BY s.user_seeks DESC;
```

Interpretación: índices con `user_updates` muy altos y `user_seeks/scans` bajos pueden ser candidatos a eliminar o revisar. `user_lookups` indica lookups por no cobertura y posiblemente mejorar mediante INCLUDE().

## Mantenimiento de índices y fragmentación

1) Estadísticas físicas: sys.dm_db_index_physical_stats

```sql
SELECT *
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID('dbo.Orders'), NULL, 0, 'LIMITED');
```

Campos clave:
- avg_fragmentation_in_percent: fragmentación lógica de páginas.
- page_count: número de páginas del índice (importante para decidir acciones).

Reglas comunes (orientativas):
- page_count < 1000: normalmente no hacer acción.
- 5% <= avg_fragmentation_in_percent <= 30%: considerar `ALTER INDEX ... REORGANIZE`.
- avg_fragmentation_in_percent > 30%: considerar `ALTER INDEX ... REBUILD`.

Comandos:

```sql
-- Reorganizar (línea, menor impacto)
ALTER INDEX IX_OrderDetails_Product ON dbo.Order_Details REORGANIZE;

-- Reconstruir (más agresivo, puede ser ONLINE si soportado)
ALTER INDEX IX_OrderDetails_Product ON dbo.Order_Details REBUILD WITH (ONLINE = ON);
```

Notas para Azure SQL: la opción `ONLINE = ON` está disponible en la mayoría de niveles de servicio; en IaaS depende de la edición/versión.

2) Columnstore / row groups

Para tablas columnstore, la fragmentación se explora con:

```sql
SELECT *
FROM sys.dm_db_column_store_row_group_physical_stats
WHERE object_id = OBJECT_ID('dbo.FactSales');
```

Campos de interés: `deleted_rows`, `state`, `total_rows`. Muchas filas eliminadas por row group indican necesidad de `REORGANIZE` del columnstore o `REBUILD` según caso.

3) Estadísticas de tabla y actualización

Las estadísticas afectan al optimizador; mantenerlas actualizadas es crítico. Comandos:

```sql
-- Actualizar estadísticas para una tabla
UPDATE STATISTICS dbo.Orders;

-- Actualizar todas las estadísticas en la base
EXEC sp_updatestats;
```

En Azure SQL, las opciones `AUTO_CREATE_STATISTICS` y `AUTO_UPDATE_STATISTICS` suelen estar activas; sin embargo, para cargas especiales conviene programar actualizaciones.

## Cuándo usar sugerencias de consulta (query hints)

Las sugerencias deben ser la última línea de defensa cuando: índices y estadísticas están correctas, y aún así el optimizador elige un plan claramente subóptimo para casos puntuales.

Ejemplos y explicaciones:

- `OPTION (RECOMPILE)`: fuerza recompilación de plan para evitar problemas de parameter sniffing. Útil para consultas que reciben parámetros con selectividad muy variable.

```sql
SELECT * FROM Orders WHERE CustomerID = @cid
OPTION (RECOMPILE);
```

- `FORCESEEK` / `FORCESCAN`: fuerza el uso de un índice seek o scan; usar con cuidado.

```sql
SELECT OrderID, OrderDate FROM Orders WITH (FORCESEEK)
WHERE OrderDate >= '2020-01-01';
```

- `OPTIMIZE FOR (@param = value)` y `OPTIMIZE FOR UNKNOWN`: ayudan a controlar parameter sniffing.

```sql
SELECT ... FROM Sales WHERE Region = @r
OPTION (OPTIMIZE FOR (@r = 'North'));
```

- `MAXDOP`: limitar paralelismo para consultas que generan demasiada sobrecarga.

```sql
SELECT SUM(Amount) FROM BigFact
OPTION (MAXDOP 1);
```

Riesgos: las sugerencias pueden enmascarar problemas subyacentes, volverse obsoletas cuando cambian datos o estadísticas y complicar mantenimiento. Siempre documentar y revisar periódicamente.

## Diagnóstico práctico — pasos recomendados

1. Capturar top waits con `sys.dm_os_wait_stats` y detectar patrón dominante.
2. Correlacionar con `sys.dm_exec_requests`, `sys.dm_os_waiting_tasks` para identificar queries afectadas.
3. Evaluar índices con `sys.dm_db_index_usage_stats` y `sys.dm_db_index_operational_stats`.
4. Revisar `sys.dm_db_index_physical_stats` y aplicar `REORGANIZE/REBUILD` según thresholds.
5. Actualizar estadísticas (`UPDATE STATISTICS`) y validar planes de ejecución.
6. Solo como último recurso, aplicar hints puntuales y documentar.


## Scripts de auditoría disponibles

- `./performance_audit/capture_waits_and_index_audit.sql`: script T-SQL que crea un esquema `perf_audit` (si no existe) y tablas para almacenar snapshots de `sys.dm_os_wait_stats`, `sys.dm_db_index_usage_stats`, `sys.dm_db_index_operational_stats` y `sys.dm_db_index_physical_stats`. Inserta los JSON de snapshot y produce un SELECT resumen con sugerencias básicas (REBUILD/REORGANIZE/revisión/eliminar índice). Requiere permisos para leer DMVs y crear objetos en la base (db_owner o permisos equivalentes).

- `./performance_audit/run_audit.ps1`: wrapper PowerShell que ejecuta el script SQL contra la base de datos objetivo usando `Invoke-Sqlcmd` (módulo `SqlServer`) y opcionalmente exporta el resumen a CSV. Soporta autenticación integrada o SQL auth.

Uso rápido:

1) Ejecutar manualmente el SQL en la base (SSMS / Azure Data Studio): abrir y ejecutar `./performance_audit/capture_waits_and_index_audit.sql`. Esto rellenará las tablas `perf_audit.*` y mostrará el resumen.

2) Ejecutar desde PowerShell (ejemplo):

```powershell
.\performance_audit\run_audit.ps1 -Server 'myserver.database.windows.net' -Database 'northwinddb' -Username 'sqladmin' -Password 'P@ssw0rd!' -OutCsv '.\audit_summary.csv'
```

Explicación: el wrapper ejecuta el SQL (crea/almacena snapshots) y recupera el SELECT resumen; si se pasa `-OutCsv` exporta el resumen a CSV. Ajustar credenciales y servidor según entorno.

Nota de seguridad y permisos: los scripts leen DMVs y pueden crear objetos; ejecútalos con una cuenta segura y revisa las políticas de retención/histórico en entornos de producción.



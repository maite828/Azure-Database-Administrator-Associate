-- capture_waits_and_index_audit.sql
-- Script: captura snapshots de waits, uso y estadísticas físicas de índices,
-- y genera recomendaciones básicas para mantenimiento (REORGANIZE/REBUILD/eliminar índice).
-- Explicación: ejecutar en la base de datos objetivo. El script crea el esquema
-- 'perf_audit' y tablas para almacenar snapshots (si no existen) y guarda los
-- resultados serializados en JSON. Finalmente emite un resumen con sugerencias.

SET NOCOUNT ON;

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'perf_audit')
  EXEC('CREATE SCHEMA perf_audit');

IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID('perf_audit.WaitStats') AND type = 'U')
BEGIN
  CREATE TABLE perf_audit.WaitStats(
    CapturedAt DATETIME2 NOT NULL,
    Data NVARCHAR(MAX) NOT NULL
  );
END

IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID('perf_audit.IndexUsage') AND type = 'U')
BEGIN
  CREATE TABLE perf_audit.IndexUsage(
    CapturedAt DATETIME2 NOT NULL,
    Data NVARCHAR(MAX) NOT NULL
  );
END

IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID('perf_audit.IndexOperational') AND type = 'U')
BEGIN
  CREATE TABLE perf_audit.IndexOperational(
    CapturedAt DATETIME2 NOT NULL,
    Data NVARCHAR(MAX) NOT NULL
  );
END

IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID('perf_audit.IndexPhysical') AND type = 'U')
BEGIN
  CREATE TABLE perf_audit.IndexPhysical(
    CapturedAt DATETIME2 NOT NULL,
    Data NVARCHAR(MAX) NOT NULL
  );
END

-- Capturar wait stats (filtrando waits de bajo interés)
INSERT INTO perf_audit.WaitStats(CapturedAt, Data)
SELECT SYSDATETIME(), (
  SELECT wait_type, wait_time_ms, signal_wait_time_ms, waiting_tasks_count
  FROM sys.dm_os_wait_stats
  WHERE wait_type NOT IN (
    'CLR_SEMAPHORE','LAZYWRITER_SLEEP','RESOURCE_QUEUE','SLEEP_TASK','SLEEP_SYSTEMTASK',
    'SQLTRACE_BUFFER_FLUSH','BROKER_EVENTHANDLER','BROKER_RECEIVE_WAITFOR','BROKER_TASK_STOP',
    'CLR_MANUAL_EVENT','CLR_AUTO_EVENT','DISPATCHER_QUEUE_SEMAPHORE','FT_IFTS_SCHEDULER_IDLE_WAIT',
    'XE_TIMER_EVENT','XE_DISPATCHER_WAIT')
  ORDER BY wait_time_ms DESC
  FOR JSON PATH
);

-- Capturar uso de índices (sys.dm_db_index_usage_stats)
INSERT INTO perf_audit.IndexUsage(CapturedAt, Data)
SELECT SYSDATETIME(), (
  SELECT DB_NAME(s.database_id) AS DatabaseName, s.object_id, OBJECT_SCHEMA_NAME(s.object_id) AS SchemaName,
         OBJECT_NAME(s.object_id) AS ObjectName, i.name AS IndexName, s.index_id,
         s.user_seeks, s.user_scans, s.user_lookups, s.user_updates
  FROM sys.dm_db_index_usage_stats AS s
  JOIN sys.indexes i ON s.object_id = i.object_id AND s.index_id = i.index_id
  WHERE s.database_id = DB_ID()
  ORDER BY s.user_seeks DESC
  FOR JSON PATH
);

-- Capturar stats operativas de índices
INSERT INTO perf_audit.IndexOperational(CapturedAt, Data)
SELECT SYSDATETIME(), (
  SELECT DB_NAME(ios.database_id) AS DatabaseName, ios.object_id, OBJECT_NAME(ios.object_id) AS ObjectName,
         ios.index_id, ios.leaf_insert_count, ios.leaf_update_count, ios.leaf_delete_count,
         ios.range_scan_count, ios.singleton_lookup_count
  FROM sys.dm_db_index_operational_stats(DB_ID(), NULL, NULL, NULL) AS ios
  JOIN sys.indexes i ON ios.object_id = i.object_id AND ios.index_id = i.index_id
  ORDER BY ios.range_scan_count DESC
  FOR JSON PATH
);

-- Capturar estadisticas físicas de índices (LIMITED para rendimiento)
INSERT INTO perf_audit.IndexPhysical(CapturedAt, Data)
SELECT SYSDATETIME(), (
  SELECT object_id, index_id, index_type_desc, alloc_unit_type_desc, avg_fragmentation_in_percent, page_count
  FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED')
  FOR JSON PATH
);

-- Generar resumen y recomendaciones básicas
;WITH idx_usage AS (
  SELECT s.object_id, s.index_id, i.name AS index_name,
         ISNULL(s.user_seeks,0) AS user_seeks, ISNULL(s.user_scans,0) AS user_scans,
         ISNULL(s.user_lookups,0) AS user_lookups, ISNULL(s.user_updates,0) AS user_updates
  FROM sys.dm_db_index_usage_stats s
  JOIN sys.indexes i ON s.object_id = i.object_id AND s.index_id = i.index_id
  WHERE s.database_id = DB_ID()
),
idx_phys AS (
  SELECT object_id, index_id, avg_fragmentation_in_percent, page_count
  FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED')
)
SELECT
  OBJECT_SCHEMA_NAME(u.object_id) AS SchemaName,
  OBJECT_NAME(u.object_id) AS TableName,
  u.index_id,
  u.index_name,
  u.user_seeks, u.user_scans, u.user_lookups, u.user_updates,
  p.page_count, p.avg_fragmentation_in_percent,
  CASE
    WHEN (u.user_seeks + u.user_scans + u.user_lookups) = 0 AND u.user_updates > 1000 THEN 'ALTA ESCRITURA / BAJO USO: Revisar, posible DROP o consolidar índices'
    WHEN p.page_count > 1000 AND p.avg_fragmentation_in_percent > 30 THEN 'REBUILD recomendado'
    WHEN p.page_count > 1000 AND p.avg_fragmentation_in_percent BETWEEN 5 AND 30 THEN 'REORGANIZE recomendado'
    ELSE 'Sin acción inmediata'
  END AS Suggestion
FROM idx_usage u
LEFT JOIN idx_phys p ON u.object_id = p.object_id AND u.index_id = p.index_id
ORDER BY Suggestion DESC, u.user_updates DESC;

-- Fin del script: los INSERTs almacenan snapshots; el SELECT produce recomendaciones legibles.
-- Ejecutar periódicamente (job/elastic job / PowerShell) para obtener históricos y tomar decisiones.

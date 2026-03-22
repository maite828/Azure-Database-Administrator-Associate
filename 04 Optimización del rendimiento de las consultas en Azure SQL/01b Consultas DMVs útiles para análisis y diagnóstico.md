# Consultas DMVs útiles para análisis y diagnóstico

Las siguientes consultas son prácticas para detectar consultas costosas, índices faltantes, estadísticas y problemas (spills, waits) en SQL Server / Azure SQL.

- Top consultas por CPU / lecturas:
```sql
SELECT TOP 10
 qs.total_worker_time AS total_cpu,
 qs.total_logical_reads AS total_logical_reads,
 qs.execution_count,
 qt.text AS sql_text,
 qs.plan_handle
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
ORDER BY qs.total_worker_time DESC;
```

- Consultas con planes y plan_handle (ver plan XML):
```sql
SELECT TOP 50
 qs.plan_handle,
 qs.sql_handle,
 qs.execution_count,
 qs.total_worker_time,
 qt.text AS sql_text,
 qp.query_plan
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
ORDER BY qs.total_worker_time DESC;
```

- Sugerencias de índices faltantes (missing index suggestions):
```sql
SELECT TOP 50
 migs.avg_user_impact,
 mid.equality_columns,
 mid.inequality_columns,
 mid.included_columns,
 OBJECT_NAME(mid.object_id) AS table_name
FROM sys.dm_db_missing_index_group_stats migs
JOIN sys.dm_db_missing_index_groups mig ON migs.group_handle = mig.index_group_handle
JOIN sys.dm_db_missing_index_details mid ON mig.index_handle = mid.index_handle
ORDER BY migs.avg_user_impact DESC;
```

- Estadísticas de un objeto y fecha de última actualización:
```sql
SELECT OBJECT_NAME(s.object_id) AS object_name,
 s.name AS stats_name,
 sp.last_updated,
 sp.rows,
 sp.rows_sampled
FROM sys.stats s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
WHERE OBJECTPROPERTY(s.object_id,'IsUserTable') = 1
ORDER BY sp.last_updated DESC;
```

- Buscar spill a tempdb en planes (indica memory grant/ejecuciones con spills):
```sql
SELECT qs.plan_handle, qt.text,
 qp.query_plan
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
WHERE qp.query_plan LIKE '%SpillToTempDb%'
OR qp.query_plan LIKE '%Spill%';
```

- Consultas con más lecturas lógicas (posible scan pesado):
```sql
SELECT TOP 50
 qs.total_logical_reads,
 qs.execution_count,
 qt.text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
ORDER BY qs.total_logical_reads DESC;
```

- Consultas para detectar waits y bloqueos recientes:
```sql
SELECT r.session_id, r.status, r.wait_type, r.wait_time, r.blocking_session_id,
 t.text AS sql_text
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.wait_type IS NOT NULL
ORDER BY r.wait_time DESC;
```

# Guía paso a paso en SSMS

1. Conectar con la instancia/servidor y seleccionar la base de datos.
2. Para ver el plan real: en la ventana de consulta activar "Include Actual Execution Plan" (Ctrl+M) y ejecutar la consulta.
	- El panel "Execution Plan" mostrará los operadores y podrás ver propiedades (Estimated vs Actual Rows, I/O, CPU por operador).
3. Para ver el plan estimado: usar "Display Estimated Execution Plan" (Ctrl+L) o `SET SHOWPLAN_XML ON` si no quieres ejecutar la consulta.
4. Habilitar estadísticas en la sesión para medir IO y tiempo:
   
```sql
SET STATISTICS TIME ON;
SET STATISTICS IO ON;
-- Ejecutar consulta
SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
```

1. Usar Query Store desde SSMS:
	- En el Explorador de Objetos, expandir la base de datos -> Query Store.
	- Visualizaciones útiles: "Top Resource Consuming Queries", "Regressed Queries", "Forcing / Forced Plans".
	- Forzar un plan gráficamente: abrir la consulta en Query Store -> pestaña "Plans" -> seleccionar el plan deseado -> botón "Force Plan".
  
2. Forzar vía T-SQL (alternativa a UI):
   
```sql
-- Identificar query_id y plan_id con las vistas de Query Store
-- Forzar
EXEC sp_query_store_force_plan @query_id = <query_id>, @plan_id = <plan_id>;
-- Desforzar
EXEC sp_query_store_unforce_plan @query_id = <query_id>;
```

# Guía paso a paso en Azure Portal

1. Abrir Azure Portal y navegar a `SQL databases` -> seleccionar la base de datos.
2. En el menú de la base de datos, abrir **Intelligent Performance** o **Query Performance Insight**.
	- Aquí verás métricas agregadas, top queries y tendencias por periodo.
3. Para inspeccionar Query Store (si está habilitado): en la sección correspondiente podrás ver queries, planes y comparativas por periodo.
4. Nota sobre forzar planes: la UI del Portal permite inspeccionar rendimiento y planes; sin embargo, el forzado de planes suele realizarse desde SSMS o con T-SQL (`sp_query_store_force_plan`).

&nbsp;
&nbsp;

# Ejemplos concretos para la base `northwind.sql` (tablas `Customer` y `Product`)

Las siguientes consultas están adaptadas para analizar el comportamiento de `Customer` y `Product` en una copia de Northwind. 
Ajusta el esquema/`dbo` si tus tablas están en otro esquema.

**1) Buscar queries que referencien `Customer` o `Product` (útil para identificar cargas frecuentes)**
```sql
SELECT TOP 100
 qs.total_worker_time, qs.total_logical_reads, qs.execution_count,
 qt.text AS sql_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
WHERE qt.text LIKE '%Customer%' OR qt.text LIKE '%Product%'
ORDER BY qs.total_worker_time DESC;
```

**2) Sugerencias de índices faltantes específicamente para Customer/Product**
```sql
SELECT TOP 50
 migs.avg_user_impact,
 mid.equality_columns,
 mid.inequality_columns,
 mid.included_columns,
 OBJECT_NAME(mid.object_id) AS table_name
FROM sys.dm_db_missing_index_group_stats migs
JOIN sys.dm_db_missing_index_groups mig ON migs.group_handle = mig.index_group_handle
JOIN sys.dm_db_missing_index_details mid ON mig.index_handle = mid.index_handle
WHERE OBJECT_NAME(mid.object_id) IN ('Customer','Product')
ORDER BY migs.avg_user_impact DESC;
```

**3) Uso de índices en estas tablas (lecturas/escrituras) — ver si hay índices no usados**
```sql
SELECT
 OBJECT_NAME(i.object_id) AS table_name,
 i.name AS index_name,
 us.user_seeks, us.user_scans, us.user_lookups, us.user_updates
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_usage_stats us
 ON i.object_id = us.object_id AND i.index_id = us.index_id AND us.database_id = DB_ID()
WHERE OBJECT_NAME(i.object_id) IN ('Customer','Product')
ORDER BY OBJECT_NAME(i.object_id), i.index_id;
```

**4) Tamaño y fragmentación de índices (recomendar REBUILD/REORGANIZE si procede)**
```sql
SELECT
 OBJECT_NAME(object_id) AS table_name,
 index_id,
 index_type_desc,
 avg_fragmentation_in_percent,
 page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED')
WHERE OBJECT_NAME(object_id) IN ('Customer','Product')
ORDER BY table_name, avg_fragmentation_in_percent DESC;
```

**5) Estadísticas de las tablas (última actualización)**
```sql
SELECT OBJECT_NAME(s.object_id) AS object_name,
 s.name AS stats_name,
 sp.last_updated
FROM sys.stats s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
WHERE OBJECT_NAME(s.object_id) IN ('Customer','Product')
ORDER BY sp.last_updated DESC;
```

### Propuestas de índices (ejemplos)
Antes de crear índices, valida impacto en escrituras y prueba en entorno de preproducción.

- Búsquedas por `CustomerID` (clave primaria): normalmente existe un índice clustered en `CustomerID`.
	- No crear si ya existe.

- Predicados frecuentes por `FirstName` (ejemplo: WHERE FirstName = 'Janet') — crear índice nonclustered si hay búsquedas frecuentes:
```sql
CREATE NONCLUSTERED INDEX IX_Customer_FirstName
ON dbo.Customer(FirstName)
INCLUDE (LastName, CustomerID);
```

- Consultas por color en `Product` (WHERE Color = 'Red') y para agrupar/contar por Color:
```sql
CREATE NONCLUSTERED INDEX IX_Product_Color
ON dbo.Product(Color)
INCLUDE (Name, ListPrice);
```

- Para ORDER BY `ListPrice` (si las consultas ordenan por precio y es frecuente):
```sql
CREATE NONCLUSTERED INDEX IX_Product_ListPrice
ON dbo.Product(ListPrice DESC)
INCLUDE (ProductID, Name);
```

- Índice para joins: si hay muchas consultas que unen `SalesOrderDetail.ProductID` con `Product.ProductID`:
```sql
CREATE NONCLUSTERED INDEX IX_SalesOrderDetail_ProductID
ON dbo.SalesOrderDetail(ProductID)
INCLUDE (OrderQty, SalesOrderID);
```

### Validación y pasos posteriores
1. Ejecutar las consultas de `dm_db_missing_index_details` y comparar con las propuestas.
2. Crear índices en entorno de pruebas y medir impacto con `SET STATISTICS IO/TIME` y comparar planes (antes/después).
3. Observar impacto en `sys.dm_db_index_usage_stats` y en métricas de carga (latencia, CPU).
4. Mantener políticas de mantenimiento de índices y estadísticas (`UPDATE STATISTICS`, `REBUILD`/`REORGANIZE`).

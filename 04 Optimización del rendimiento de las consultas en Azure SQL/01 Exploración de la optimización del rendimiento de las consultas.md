# Exploración de la optimización del rendimiento de las consultas

## Generar y guardar planes de ejecución
- Guardar o inspeccionar planes de ejecución puede hacerse de varias formas:
	- En SSMS: activar "Include Actual Execution Plan" (Ctrl+M) y ejecutar la consulta; el panel mostrará el plan gráfico.
	- SET STATISTICS XML ON; devuelve el plan en formato XML como resultado.
	- Mostrar plan estimado: "Display Estimated Execution Plan" en SSMS o `SET SHOWPLAN_XML ON` (no ejecuta la consulta).
	- Desde la caché de planes: `sys.dm_exec_cached_plans` + `sys.dm_exec_query_plan(plan_handle)` para recuperar el plan en ejecución.
	- Almacenar de forma persistente: habilitar y usar Query Store (recomendado en PaaS y disponible en SQL Server/IaaS) que captura planes reales y permite forzarlos.

Ejemplo: habilitar Query Store (IaaS / SQL Server):
```sql
ALTER DATABASE [MiBaseDatos]
SET QUERY_STORE = ON
-- Opciones recomendadas se configuran con ALTER DATABASE ... SET QUERY_STORE (OPTS...)
```

## Comparar los distintos tipos de planes de ejecución
- Plan estimado: generado por el optimizador antes de ejecutar la consulta; útil para ver decisiones de optimización sin costo de ejecución.
- Plan actual (actual execution plan): plan real usado ejecutando la consulta; muestra operadores reales, filas reales y tiempo.
- Plan en caché: plan guardado en memoria (plan handle); puede diferir del plan de Query Store si fue recompilado.
- Query Store: contiene histórico de planes y métricas por consulta (latencia, CPU, ejecuciones) y permite comparar planes por periodo.

Comparación práctica:
- Usa el plan estimado para diagnosticar por qué el optimizador eligió un plan sin ejecutar la consulta.
- Usa el plan actual para medir coste real (IO, CPU, tiempos por operador).
- Usa Query Store para comparar evolución temporal y regresiones (regression) entre planes.

## Cómo y por qué se generan planes de consulta
- El optimizador cost-based evalúa alternativas (índices disponibles, estadísticas, tipos de JOIN, ordenación) y elige el plan con coste estimado más bajo.
- Factores que influyen: estadísticas de distribución de valores, cardinality estimator, costes de I/O y CPU, disponibilidad de índices, parámetros y valores en ejecución.
- Recompilaciones ocurren cuando cambian objetos, estadísticas o parámetros que invalidan suposiciones.

## Operadores de plan comunes
Explicación y ejemplos prácticos para reconocerlos en el plan:

- SEEK vs SCAN
	- SEEK: acceso directo a rangos/registros usando un índice (bajo coste cuando hay predicado sargable).
	- SCAN: recorre toda la estructura (tabla o índice) y es más costoso en lecturas lógicas.

- Index Seek -> WHERE con clave/columna con índice (clustered o nonclustered)
- Index Scan -> Sin WHERE sargable o cuando el optimizador decide leer todo

- Nested Loops -> JOIN ideal para conjuntos pequeños; anida búsqueda por cada fila del conjunto externo.
- Hash Match -> JOIN para grandes conjuntos; construye una tabla hash; eficiente en joins no indexados con grandes volúmenes.
- Merge Join -> JOIN ordenado que necesita ambos inputs ordenados; muy eficiente si hay índices que mantiene orden.

- Sort -> operador usado por ORDER BY cuando no hay índice que ya satisfaga el orden. Coste alto en memoria/temporal.

- Hash Aggregate o Stream Aggregate -> operadores usados en GROUP BY; Stream Aggregate es más barato cuando los datos vienen ordenados.

**Ejemplos de consultas y los operadores esperados**

```sql
-- SEEK -> busca
-- SCAN -> recorre todo

-- Consulta Sencilla que utiliza (Index Seek)
-- Motivo: Índice de tipo clustered que da acceso directo al registro
SELECT * FROM SalesLT.Customer
WHERE CustomerID = 5
GO

-- Consulta Sencilla que utiliza (Index Scan)
-- Lee toda la tabla por falta de predicado WHERE
SELECT * FROM SalesLT.Customer
GO

-- Consulta Sencilla que utiliza (Index Scan)
-- Lee toda la tabla por que el predicado WHERE no tiene índice
SELECT * FROM SalesLT.Customer
WHERE FirstName = 'Janet'
GO

-- Consulta dificultad Media con JOIN
-- Busca utilizando índices de las diferentes tablas
-- Junta los resultado mediante (Nested Loops) ideal para pocos registros
SELECT c.CustomerID, c.FirstName, soh.SalesOrderID
FROM SalesLT.Customer c
INNER JOIN SalesLT.SalesOrderHeader soh
		ON c.CustomerID = soh.CustomerID
WHERE c.CustomerID = 29485
OPTION (MERGE JOIN)
GO

-- Consulta Compleja con JOIN y WHERE
-- Algunos se puede resolver median Index Seek y otros mediante Index Scan
-- dependiendo de los indices de cada tabla.
-- Posible operadores: Hash Match, Merge Join, Sort y Nested Loops (menos problable)
SELECT c.FirstName, c.LastName, p.Name, sod.OrderQty
FROM SalesLT.Customer c
INNER JOIN SalesLT.SalesOrderHeader soh
		ON c.CustomerID = soh.CustomerID
INNER JOIN SalesLT.SalesOrderDetail sod
		ON soh.SalesOrderID = sod.SalesOrderID
INNER JOIN SalesLT.Product p
		ON sod.ProductID = p.ProductID
WHERE p.Color = 'Red';

-- Ejemplo de Agregación
-- Operaciones costosa.
-- Suelen usar operadores Index Scan, Hash Match, Stream Aggregate y Sort
SELECT p.Color, COUNT(*) AS Total
FROM SalesLT.Product p
GROUP BY p.Color;

-- Ejemplo de Ordenación
-- Cualquier ORDER BY utiliza el operador Sort que tiene alto coste en la consuta,
-- salvo cuando ordenamos por ProductID que tiene un índice de tipo cluster donde
-- los registros estan ordenados y no utiliza el operador Sort
SELECT *
FROM SalesLT.Product
ORDER BY ProductID;
GO

SELECT *
FROM SalesLT.Product
ORDER BY Name;
GO

SELECT *
FROM SalesLT.Product
ORDER BY ListPrice DESC;
GO


-- Podemos forzar comportamiento para comparar los resultados
SELECT c.CustomerID, c.FirstName, soh.SalesOrderID
FROM SalesLT.Customer c
INNER JOIN SalesLT.SalesOrderHeader soh
		ON c.CustomerID = soh.CustomerID
WHERE c.CustomerID = 29485
OPTION (HASH JOIN)
GO

SELECT c.CustomerID, c.FirstName, soh.SalesOrderID
FROM SalesLT.Customer c
INNER JOIN SalesLT.SalesOrderHeader soh
		ON c.CustomerID = soh.CustomerID
WHERE c.CustomerID = 29485
OPTION (MERGE JOIN)
GO


SELECT c.CustomerID, c.FirstName, soh.SalesOrderID
FROM SalesLT.Customer c
INNER JOIN SalesLT.SalesOrderHeader soh
		ON c.CustomerID = soh.CustomerID
WHERE c.CustomerID = 29485
OPTION (LOOP JOIN)
GO
```

**Medir tiempos de CPU y lecturas lógicas con STATISTICS**
```sql
-- Activar estadísticas
-- Medir tiempos de CPU
SET STATISTICS TIME ON
-- Lecturas lógicas
SET STATISTICS IO ON

-- Desactivar estadísticas
SET STATISTICS TIME OFF
SET STATISTICS IO OFF
```

## Comprender la finalidad y las ventajas del Almacén de Consultas (Query Store)
- Propósito: capturar histórico de consultas, planes y métricas para detectar regresiones, comparar planes y forzar planes estables.
- Ventajas principales:
	- Persistencia del historial: los planes y rendimiento históricos se conservan aún tras reinicios (a diferencia de la caché en memoria).
	- Diagnóstico de regresiones: identificar cuándo un query cambió de plan y empeoró el rendimiento.
	- Forzar planes conocidos buenos para mitigar regresiones mientras se investiga la causa raiz.
	- Informes integrados en SSMS y Azure Portal para análisis rápido.

## Almacén de consultas — continuación e Informes
- Informes comunes en Query Store: Top Resource Consumers, Regressed Queries, Overall Performance, Queries with High Variance.
- Uso práctico:
	- Navegar a Query Store en SSMS -> Query Store -> Top Resource Consuming Queries.
	- Filtrar por periodo y comparar las métricas (avg duration, cpu time, logical reads) entre planes.

**Consulta para listar queries y planes en Query Store**
```sql
SELECT q.query_id, p.plan_id, qt.query_sql_text
FROM sys.query_store_query q
JOIN sys.query_store_plan p ON q.query_id = p.query_id
JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
ORDER BY q.query_id;
```

**Forzar un plan desde Query Store (ejemplo)**
```sql
-- Una vez identificado query_id y plan_id
EXEC sp_query_store_force_plan @query_id = 123, @plan_id = 456;

-- Para desforzar
EXEC sp_query_store_unforce_plan @query_id = 123;
```

En Azure SQL Database (PaaS) Query Store está habilitado por defecto en muchas configuraciones; en VM/IaaS puede requerir activación y ajuste de tamaño del capture window.

## Identificación de planes de ejecución problemáticos y cómo resolverlos

**Problemas comunes y cómo detectarlos:**

- SARGability
	- Descripción: Predicados no sargables (p. ej. wrapped in functions, operaciones sobre la columna) impiden seeks y fuerzan scans.
	- Detección: plan con Index Scan en lugar de Seek; alto número de lecturas lógicas.
	- Solución: reescribir predicado (evitar funciones sobre columnas), crear índices adecuados.

- Falta de índices
	- Descripción: Ausencia de índices que apoyen predicados o joins produce scans y operadores costosos (Hash Match).
	- Detección: usar DMV `sys.dm_db_missing_index_details` y revisar operadores del plan.
	- Solución: crear índices (clustered/nonclustered), cubrir columnas si procede.

- Estadísticas obsoletas
	- Descripción: Estimaciones de cardinalidad incorrectas llevan al optimizador a elegir planes ineficientes.
	- Detección: diferencias grandes entre estimated_rows y actual_rows en el plan; consulta `sys.dm_db_stats_properties`.
	- Solución: actualizar estadísticas (`UPDATE STATISTICS` o `sp_updatestats`), considerar `AUTO_UPDATE_STATISTICS` y `AUTO_CREATE_STATISTICS`.

- Bloqueos/contención
	- Descripción: Transacciones largas o escalado de aislamiento pueden serializar accesos y alargar tiempos.
	- Detección: revisar `sys.dm_tran_locks`, wait types `LCK_M_*` y bloqueos en `sys.dm_exec_requests`.
	- Solución: acortar transacciones, ajustar índices para reducir escaneos, revisar nivel de aislamiento (usar Read Committed Snapshot si procede).

- Hardware y recursos (IaaS)
	- Descripción: I/O lento, falta de CPU o memoria afecta tiempos reales y puede cambiar decisiones del optimizador (memoria insuficiente para hash spills).
	- Detección: waits tipo `PAGEIOLATCH_*`, `SOS_SCHEDULER_YIELD`, spills to tempdb en planes.
	- Solución: escalar la VM o mejorar almacenamiento, optimizar consultas para reducir spills, revisar tempdb.

- Nivel de aislamiento y transacciones
	- Descripción: altos niveles de aislamiento producen más bloqueos; snapshot puede reducir bloqueos pero cambiar comportamiento.
	- Detección: waits y bloqueo frecuente entre transacciones.
	- Solución: evaluar `READ COMMITTED SNAPSHOT`, revisar duración de transacciones.

**Pasos recomendados para investigar un mal plan**
1. Capturar el plan actual (Include Actual Plan) y medir con `SET STATISTICS IO ON` y `SET STATISTICS TIME ON`.
2. Comparar con plan estimado y Query Store para ver si hubo un cambio reciente de plan.
3. Revisar diferencias entre filas estimadas y reales en el plan (cardinality estimation).
4. Revisar índices y sugerencias de índices faltantes (DMVs).
5. Actualizar estadísticas o forzar un plan bueno temporalmente desde Query Store mientras se aplica una solución permanente.

**Comandos útiles rápidos**
```sql
-- Incluir plan real en SSMS
-- Habilitar estadísticas de tiempo y IO
SET STATISTICS TIME ON;
SET STATISTICS IO ON;

-- Recuperar plan de caché
SELECT cp.plan_handle, qp.query_plan
FROM sys.dm_exec_cached_plans cp
CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) qp;

-- Listar queries en Query Store
SELECT q.query_id, p.plan_id, qt.query_sql_text
FROM sys.query_store_query q
JOIN sys.query_store_plan p ON q.query_id = p.query_id
JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id;
```

---
**Conclusión y siguientes pasos**
Usar una combinación de: planes estimados/actuales, `SET STATISTICS` (IO/TIME), análisis de Query Store y DMVs permite identificar y resolver problemas de planes. En Azure PaaS, Query Store es la herramienta clave para histórico y forzamiento; en IaaS hay que habilitar y ajustar Query Store y revisar recursos de la VM/almacenamiento.

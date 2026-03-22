# Optimización del rendimiento de las consultas en Azure SQL

## Contenidos

## 01 - Descripción y herramientas de supervisión
- [01 - Exploración de la optimización del rendimiento de las consultas](01%20Exploraci%C3%B3n%20de%20la%20optimizaci%C3%B3n%20del%20rendimiento%20de%20las%20consultas.md): Conceptos y técnicas para analizar y optimizar consultas; incluye ejemplos de análisis de planes y recomendaciones prácticas.
	- [01b - Consultas DMVs útiles para análisis y diagnóstico](01b%20Consultas%20DMVs%20%C3%BAtiles%20para%20an%C3%A1lisis%20y%20diagn%C3%B3stico.md): Colección de consultas DMVs para detección de problemas (wait stats, bloqueos, uso de índices, spool, tempdb).

## 02 - Exploración del diseño de base de datos basado en el rendimiento
- [02 - Exploración del diseño de base de datos basado en el rendimiento](02%20Exploraci%C3%B3n%20del%20dise%C3%B1o%20de%20base%20de%20datos%20basado%20en%20el%20rendimiento.md): Guía sobre normalización (1NF–3NF), elección de tipos de datos, impacto en tamaño de página y estrategias de índices con ejemplos Northwind y T-SQL.

## 03 - Evaluación de mejoras del rendimiento
- [03 - Evaluación de mejoras del rendimiento](03%20Evaluaci%C3%B3n%20de%20mejoras%20del%20rendimiento.md): Cómo interpretar wait stats, DMVs de índices, fragmentación y cuándo aplicar mantenimiento o query hints; incluye ejemplos y scripts de auditoría.

## Scripts de auditoría (carpeta `performance_audit`)

En la carpeta `performance_audit` se incluyen scripts de apoyo para capturar snapshots y generar un resumen automatizado de la salud de índices y waits. No se incluyen enlaces directos a los ficheros en este índice; a continuación se describe su contenido:

- `capture_waits_and_index_audit.sql`: Script T-SQL que crea el esquema `perf_audit` y tablas para almacenar snapshots de `sys.dm_os_wait_stats`, `sys.dm_db_index_usage_stats`, `sys.dm_db_index_operational_stats` y `sys.dm_db_index_physical_stats`. Inserta los resultados en formato JSON y produce un SELECT resumen con recomendaciones (REBUILD/REORGANIZE/eliminar índice). Requiere permisos para leer DMVs y crear objetos en la base de datos.

- `run_audit.ps1`: Wrapper PowerShell que ejecuta el script T-SQL contra la base de datos objetivo usando `Invoke-Sqlcmd` (módulo `SqlServer`) o autenticación integrada; recupera el resumen y puede exportarlo a CSV. Útil para automatizar auditorías periódicas desde un cliente o job.

Uso recomendado: ejecutar primero los documentos `.md` para entender criterios y thresholds, y después usar los scripts de `performance_audit` en entornos de prueba antes de aplicarlos en producción. Ajustar credenciales y retención de snapshots según políticas de cada entorno.

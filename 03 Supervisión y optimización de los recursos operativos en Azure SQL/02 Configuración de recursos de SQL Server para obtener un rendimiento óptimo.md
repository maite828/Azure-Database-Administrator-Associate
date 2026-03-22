# Configuración de recursos de SQL Server para obtener un rendimiento óptimo

Este documento cubre recomendaciones prácticas y ejemplos (Azure PowerShell, Azure CLI y T-SQL) para escenarios PaaS e IaaS, con ejemplos sobre Northwind/AdventureWorksLT cuando procede.

## 1. Comprender las opciones de configuración para Azure Storage

Resumen

- Azure ofrece varios tipos de almacenamiento: Blob (Hot/Cool/Archive), Files, y Managed Disks (Standard HDD/Standard SSD/Premium SSD/Ultra SSD). Para SQL en IaaS, se usan Managed Disks y para almacenamientos compartidos puede usarse Azure Files o Azure NetApp Files.
- Replicación: `LRS`, `ZRS`, `GRS`, `RA-GRS` — elegir según disponibilidad y coste.
- Performance tier: `Standard` vs `Premium` vs `Ultra` (IOPS, latencia y throughput aumentan en Premium/Ultra).

Buenas prácticas para SQL Server en máquinas virtuales (IaaS)

- Separar discos: OS, Data, Log y TempDB en discos o conjuntos de discos diferentes.
- Logs: usar discos Premium/Ultra con baja latencia; configurar caché de disco a `None` para discos de log.
- Data: discos Premium o Ultra; caché `ReadOnly` suele ser apropiado para mejorar lecturas.
- TempDB: idealmente en discos locales temporales (si el SKU VM lo soporta) o en discos Premium/Ultra con configuración adecuada.

Comandos de ejemplo

Azure PowerShell: crear una cuenta de almacenamiento (ejemplo para blobs y files)

```powershell
New-AzStorageAccount -ResourceGroupName RG -Name mystorageacct -SkuName Standard_LRS -Kind StorageV2 -Location eastus
```

Azure CLI: crear la cuenta (equivalente)

```bash
az storage account create --name mystorageacct --resource-group RG --sku Standard_LRS --kind StorageV2 --location eastus
```

Crear disco administrado Premium (ejemplo para datos)

```powershell
New-AzDisk -ResourceGroupName RG -DiskName sqlDataDisk -DiskSizeGB 512 -AccountType Premium_LRS -Location eastus
```

Azure CLI:

```bash
az disk create --resource-group RG --name sqlDataDisk --size-gb 512 --sku Premium_LRS --location eastus
```

Explicación

- En IaaS controlas el tipo y número de discos; en PaaS (Azure SQL Database) la plataforma gestiona el almacenamiento y eliges una capa de servicio (vCore/DTU) que incluye IOPS y throughput.

## 2. Identificar la forma de configurar los archivos de datos de TempDB en SQL Server

Recomendaciones generales

- Colocar `tempdb` en un disco físico separado si es posible.
- Número de archivos `tempdb` data: 1 por núcleo lógico hasta un máximo razonable (por ejemplo 8) y aumentar según contención (follow-up: monitorizar `sys.dm_os_wait_stats` para latch contention).
- Tamaños uniformes para evitar autogrowth frecuentes.
- Archivos de log para tempdb: normalmente un único archivo de log.

T-SQL: crear múltiples archivos `tempdb` (ejemplo)

```sql
USE master;
GO
-- Ejemplo: agregar 4 archivos de tempdb de 1GB cada uno (ajusta según núcleos y disco)
ALTER DATABASE tempdb
MODIFY FILE (NAME = 'tempdev', FILENAME = 'E:\MSSQL\TEMPDB\tempdb.mdf', SIZE = 1024MB);

ALTER DATABASE tempdb
ADD FILE (NAME = 'tempdev2', FILENAME = 'E:\MSSQL\TEMPDB\tempdb2.ndf', SIZE = 1024MB);

ALTER DATABASE tempdb
ADD FILE (NAME = 'tempdev3', FILENAME = 'E:\MSSQL\TEMPDB\tempdb3.ndf', SIZE = 1024MB);

ALTER DATABASE tempdb
ADD FILE (NAME = 'tempdev4', FILENAME = 'E:\MSSQL\TEMPDB\tempdb4.ndf', SIZE = 1024MB);
GO

-- Reiniciar instancia para que cambios surtan efecto (en entornos de producción, planificar ventana)
SHUTDOWN WITH NOWAIT;
-- Reiniciar servicio de SQL Server desde el host/portal
```

Azure VM: crear VM con disco efímero (opcional para tempdb)

Azure CLI:

```bash
az vm create --resource-group RG --name sqlVM --image Win2019Datacenter --size Standard_DS14_v2 --admin-username adminuser --admin-password 'P@ssw0rd!' --ephemeral-os-disk true
```

Nota: las VM con discos efímeros (ephemeral OS) son útiles para TempDB porque ofrecen NVMe local con baja latencia, pero los datos se pierden en reimágenes; solo para datos temporales.

Recomendaciones de caché (Windows)

- OS disk: Read/Write
- Data disks: ReadOnly
- Log disk: None

## 3. Saber cómo elegir el tipo de máquina virtual adecuado para cargas de trabajo de SQL Server

Factores a considerar

- vCPU y memoria: relación vCPU/Memoria según la carga (OLTP necesita alta CPU y IOPS; Data Warehouse necesita memoria y throughput).
- IOPS y throughput por disco/VM: algunas series ofrecen NVMe local (Lsv2) o alto throughput (Mv2).
- Latencia de red y soporte de `accelerated networking`.
- Tamaños optimizados: E-series (memoria optimizada), M-series (memoria masiva), Lsv2 (storage/NVMe), Fsv2 (CPU optimizado).
- Coste y escalabilidad: comparar costo por vCore y opciones de licencia (Bring Your Own License vs licencia incluida).

Comandos para explorar tamaños

Azure PowerShell:

```powershell
Get-AzVMSize -Location eastus | Where-Object {$_.Name -like "Standard_E*"}
```

Azure CLI:

```bash
az vm list-sizes --location eastus --output table
```

Consejos prácticos

- OLTP moderado: E-series o D-series con discos Premium SSD.
- OLTP muy intensivo en I/O: Lsv2 (NVMe) o combinación de Premium/Ultra SSD.
- Cargas analíticas: M-series o máquinas con mucha memoria.
- Pruebas de carga: siempre realizar PoC con tamaños y discos representativos.

## 4. Comprender los casos de uso y la configuración de Resource Governor en SQL Server

Qué es y cuándo usarlo

- Resource Governor permite controlar recursos (CPU y memoria) por grupos de trabajo; útil para limitar cargas que podrían impactar a otras (ETL, consultas ad-hoc, reporting).
- Casos de uso: limitar sesiones de cargas batch, priorizar consultas OLTP frente a procesos de mantenimiento, evitar que cargas ad-hoc consuman toda la CPU.

Componentes principales

- Resource Pools: definen cuotas de recursos.
- Workload Groups: asignan sesiones a pools.
- Classifier function: función T-SQL que asigna una sesión a un workload group (basada en login, programa cliente, etiquetas de SESSION_CONTEXT, etc.).

Ejemplo T-SQL (Northwind/demo)

```sql
-- Crear Resource Pool y Workload Group
CREATE RESOURCE POOL rg_batch
WITH (
	MIN_CPU_PERCENT = 0,
	MAX_CPU_PERCENT = 20,
	MIN_MEMORY_PERCENT = 0,
	MAX_MEMORY_PERCENT = 20
);
GO

CREATE WORKLOAD GROUP wg_batch USING rg_batch;
GO

-- Función classifier básica: asigna por login
CREATE FUNCTION dbo.rg_classifier()
RETURNS sysname
WITH SCHEMABINDING
AS
BEGIN
	DECLARE @grp sysname;
	IF ORIGINAL_LOGIN() = 'ventas_uk' SET @grp = 'wg_batch';
	ELSE SET @grp = 'default';
	RETURN @grp;
END;
GO

-- Asociar la función al Resource Governor
ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = dbo.rg_classifier);
ALTER RESOURCE GOVERNOR RECONFIGURE;
GO

-- Ver estado
SELECT * FROM sys.resource_governor_resource_pools;
SELECT * FROM sys.resource_governor_workload_groups;
```

Explicaciones y buenas prácticas

- Probar la función classifier en entornos de staging antes de producción; errores pueden bloquear conexiones.
- Usar `SESSION_CONTEXT` para clasificar cargas desde la aplicación (por ejemplo `EXEC sp_set_session_context 'workload','batch';`).
- Monitorizar con `sys.dm_resource_governor_workload_groups` y `sys.dm_exec_requests`.

Limitaciones y Azure

- En Azure SQL Database (PaaS) no se dispone de Resource Governor como en SQL Server IaaS; en PaaS se controlan recursos mediante capas (vCore/DTU), elastic pools, y en Managed Instance hay controles de recursos más limitados.

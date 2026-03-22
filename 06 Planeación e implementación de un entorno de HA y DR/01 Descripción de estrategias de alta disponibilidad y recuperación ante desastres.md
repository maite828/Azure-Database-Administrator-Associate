# Descripción de estrategias de alta disponibilidad y recuperación ante desastres

Este documento resume conceptos RTO/RPO y opciones HADR (High Availability / Disaster Recovery) para Azure SQL (PaaS) y SQL Server sobre IaaS, con ejemplos de Azure CLI, PowerShell y T-SQL cuando corresponde.

## Objetivos: RTO y RPO

- **RTO (Recovery Time Objective)**: tiempo máximo aceptable para recuperar servicio tras un incidente (p. ej. 15 minutos, 1 hora). Diseña arquitectura y runbooks para alcanzar el RTO.
- **RPO (Recovery Point Objective)**: máxima pérdida de datos tolerable medida en tiempo (p. ej. 0s, 5 min, 1 hora). Determina la frecuencia de réplicas/backup y técnicas (sincrónico vs asincrónico).

Decisión práctica: RPO = 0 requiere sincronización (o close-to-zero) y suele implicar arquitectura con replicas sincrónicas o tolerancia a fallos automática; RPO relajado permite log shipping o backups frecuentes.

## Opciones HADR en Azure SQL Database (PaaS)

- **Backups automáticos y Point-in-Time Restore (PITR)**: restauración a un punto en el tiempo dentro de la retención configurada (RPO depende de retención y política interna). 

- **En Azure SQL PaaS las copias se gestionan automáticamente**: se realizan copias completas periódicas (normalmente semanal), diferenciales frecuentes (aprox. cada 12 horas) y copias de log/transaccionales frecuentes (aprox. cada 5–10 minutos) que permiten PITR; la retención y el comportamiento exacto dependen del nivel de servicio y la configuración de retención (incluyendo LTR).

- **Geo-Replication (Active Geo-Replication)**: para bases Single/Elastic — crea hasta 4 réplicas legibles en otras regiones (replicación asincrónica). Buen para RTO bajo y RPO pequeño.
- **Auto-Failover Groups (Failover Groups)**: agrupa bases en servidores lógicos y permite failover automático entre regiones para pares de servidores; soporta listener con reconexión automática.
- **Zona redundante / Business Critical**: nivel de servicio con réplicas locales (synchronous replicas) y redundancia por zona/availability infrastructure que reduce RTO para fallos de hardware/host.
- **Managed Instance HA**: Managed Instance ofrece opciones de alta disponibilidad y soporte para zona redundancia y failover controlado.

Ejemplo (AZ CLI) — crear failover group para un par de servidores y bases:

```bash
az sql failover-group create \
	--name myFailoverGroup \
	--resource-group my-rg \
	--server primary-server \
	--partner-server secondary-server \
	--read-write-dns-zone "myfailover.zone"
```

Explicación: `az sql failover-group create` configura un Auto-Failover Group entre `primary-server` y `secondary-server`; el listener DNS permite reconexión automática tras failover.

Ejemplo (PowerShell) equivalente:

```powershell
New-AzSqlDatabaseFailoverGroup -ResourceGroupName my-rg -ServerName primary-server -PartnerResourceId "/subscriptions/<sub>/resourceGroups/my-rg/providers/Microsoft.Sql/servers/secondary-server" -FailoverPolicy Automatic -Name myFailoverGroup
```

Explicación: crea un failover group con política automática; en producción ajuste grace period y read/write/listener según necesidades.

### Notas sobre PaaS

- Auto-failover groups son la opción recomendada para RTO corto entre regiones en PaaS.
- Active Geo-Replication es útil si necesita réplicas legibles para reporting/lecturas geográficas.
- Compruebe latencia entre regiones y el impacto de réplica asincrónica en RPO.

## Opciones HADR en SQL Server sobre IaaS

- **Always On Failover Cluster Instance (FCI)**: cluster basado en Windows Server Failover Clustering; requiere compartición de almacenamiento o Azure shared disks; conmutación por error a nivel instancia.
- **Always On Availability Groups (AG)**: réplica a nivel de bases; soporta réplicas sincrónicas y asincrónicas, réplicas legibles y failover automático/forzado según configuración.
- **Log Shipping**: backup/restore de logs en intervalos (RPO depende del intervalo), simple y robusto.
- **Database Mirroring** (deprecated en favor de AG) y **Replication** (para escenarios de distribución de datos específicos).
- **Azure Site Recovery (ASR)**: replicación del VM completo para recuperación ante desastres a nivel de máquina virtual (RTO mayor, pero cubre todo el servidor/OS/configuración).

Ejemplo (T-SQL) — secuencia básica de Log Shipping (simplificada):

```sql
-- En servidor primario: backup de log
BACKUP LOG [MyDb] TO DISK = 'C:\backups\MyDb_log.trn';

-- Copiar archivo al secundario (fuera de T-SQL, p.ej. robocopy / AzCopy)

-- En secundario: restaurar con NORECOVERY
RESTORE LOG [MyDb] FROM DISK = 'C:\backups\MyDb_log.trn' WITH NORECOVERY;
```

Explicación: log shipping toma backups de logs regularmente y los aplica en el secundario; el RPO depende del intervalo de backup y copia.

Ejemplo (PowerShell) — activar replicación de VM con Azure Site Recovery (esquema simplificado):

```powershell
# Registrar el vault y habilitar replicación para una VM (resumen simplificado)
$vault = Get-AzRecoveryServicesVault -Name 'myVault'
Set-AzRecoveryServicesVaultContext -Vault $vault

# Configuración y enable-protection steps require ASR configuration and provider setup (see ASR docs)
```

Explicación: ASR orquesta replicación de VMs entre regiones; requiere un Recovery Services Vault y configuración de replicación por VM.

## Diseñar una estrategia HADR (PaaS vs IaaS)

Pasos y recomendaciones:

1. **Definir RTO y RPO** por aplicación/tenant. Clasificar bases según criticidad.
2. **Seleccionar nivel de servicio**: en PaaS elegir Business Critical / Zone Redundant si necesita baja latencia y RTO corto.
3. **Elegir técnica**:
	 - PaaS crítico: Auto-Failover Groups + PITR + Geo-Replication para RTO bajo y RPO pequeño.
	 - PaaS menos crítico: Geo-Replication o backups con export.
	 - IaaS crítico: Availability Groups con réplicas sincrónicas locales y asincrónicas remotas.
	 - IaaS con menor presupuesto: Log Shipping + backups.
4. **Diseñar red y DNS**: planes de failover incluyen reconfiguración de endpoints/DNS; use private endpoints y global DNS/traffic manager si aplica.
5. **Automatizar runbooks**: tests de failover, failback, y comprobaciones post-failover (jobs, reconexión strings).
6. **Probar regularmente**: ejercicios de failover/DR con métricas (tiempos medidos de RTO y pérdida observada para RPO).

## Always On FCI vs Always On AG vs Log Shipping (resumen)

- **FCI (Failover Cluster Instance)**:
	- Nivel de failover: instancia completa.
	- Pros: transparencia para aplicaciones (no cambio de connection string), buena para instancias completas.
	- Contras: requiere infraestructura de clustering y almacenamiento compartido o Azure Shared Disks.

- **Availability Groups (AG)**:
	- Nivel: base de datos.
	- Pros: réplicas legibles, granularidad por base, opciones sincrónico/asincrónico.
	- Contras: no replica logins/agent jobs automáticamente; gestión adicional.

- **Log Shipping**:
	- Nivel: base de datos, método simple y robusto.
	- Pros: fácil de configurar, bajo coste.
	- Contras: RTO y RPO dependientes de intervalos, failover manual.

## Azure Site Recovery (ASR)

- ASR replica máquinas virtuales completas a otra región y permite failover/failback a nivel de VM. Es una solución adecuada para recuperar entornos SQL en IaaS donde se necesita restaurar todo el servidor (OS, configuración, jobs) rápidamente.
- Limitaciones: RTO es mayor que soluciones de base de datos nativas; RPO depende del ritmo de replicación de la VM y la configuración de ASR.

Ejemplo (AZ CLI) — comprobar estado de replicación (simplified):

```bash
az recoveryservices vault show --name myVault --resource-group my-rg
```

Explicación: comandos ASR son más extensos; la consola y documentación oficial detallan pasos para habilitar protección por VM.

## Resumen — decisiones claves

- Prioriza definir RTO/RPO por workload antes de elegir tecnología.
- En PaaS, prefiera Auto-Failover Groups + PITR para la mayoría de cargas críticas.
- En IaaS, Availability Groups ofrecen la mejor combinación de RPO/RTO si se diseñan con réplicas adecuadas; FCI es útil si necesita proteger la instancia entera.
- Automatice, pruebe y documente los procedimientos de failover/failback.

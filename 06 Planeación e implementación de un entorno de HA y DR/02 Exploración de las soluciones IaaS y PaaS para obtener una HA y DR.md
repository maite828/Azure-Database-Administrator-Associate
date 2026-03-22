# 02 Exploración de las soluciones IaaS y PaaS para obtener una alta disponibilidad y recuperación ante desastres

Este documento recoge consideraciones prácticas y ejemplos para implementar HADR en Azure, tanto para SQL Server sobre IaaS (VMs) como para Azure SQL (PaaS).

## Consideraciones al implementar un clúster de conmutación por error (WSFC) en Azure

Elementos clave a tener en cuenta:

- **Dominio/AD**: WSFC requiere que los nodos pertenezcan a un dominio; en Azure necesita un Active Directory (Azure AD DS o controladores de dominio en VM) accesible por los nodos.
- **Almacenamiento compartido**: tradicionalmente FCI requiere almacenamiento compartido. En Azure usar Azure Shared Disks (Premium/Ultra) o soluciones 3rd-party (SMB/Storage Spaces Direct está soportado con configuraciones específicas). Ver limitaciones de tamaños, snapshots y latencia.
- **Red y latencia**: mantener latencia baja entre nodos; use zonas/availability sets según topología. Evite distribuir nodos de clúster en regiones distintas si usa almacenamiento sincronizado que requiere baja latencia.
- **Quorum y testigo (witness)**: diseñe quorum (node majority, node and file share witness) y ubique el testigo en una ubicación resiliente (p. ej. un pequeño File Share witness en otra subred o resource group).
- **Azure Load Balancer / IP flotante**: en escenarios multi-subnet puede necesitar ILB para listener; para FCI la IP de cluster debe manejarse adecuadamente.
- **Patching y actualización**: planifique actualizaciones coordinadas y pruebas de failover.
- **Backup y recuperación**: aunque el clúster protege instancia, siga estrategias de backup y replicas adicionales (offsite).

Ejemplo (AZ CLI) — crear un disco administrado compartido (esquema):

```bash
az disk create --resource-group my-rg --name sharedDisk1 --size-gb 1024 --sku Premium_LRS --max-shares 2
```

Explicación: `--max-shares` crea un Managed Disk que puede montarse en varias VMs (Azure Shared Disks). Requiere imágenes/VMs compatibles y configuración de cluster para usarlo como disco compartido.

Ejemplo (PowerShell) — crear availability set (para fault/domain isolation):

```powershell
New-AzAvailabilitySet -ResourceGroupName my-rg -Name myAS -Location westeurope -Sku Aligned -PlatformFaultDomainCount 2 -PlatformUpdateDomainCount 5
```

Explicación: las Availability Sets minimizan el riesgo de que las VMs del clúster se vean afectadas simultáneamente por fallos de hardware o actualizaciones.

## Qué tener en cuenta al implementar un grupo de disponibilidad (Availability Group)

Puntos importantes:

- **Requisitos de WSFC**: las AG tradicionales requieren un cluster subyacente (WSFC) para coordination; en Azure esto implica los mismos requisitos de dominio y networking que FCI.
- **Listener y conectividad**: para que clientes usen el listener, en Azure IaaS puede necesitar configurar un Internal Load Balancer (ILB) para direccionar la IP virtual del listener entre nodos.
- **Réplicas y modos**: seleccionar réplicas síncronas (sincrónico con failover automático) para RPO cercano a 0 en la misma región, y réplicas asincrónicas para DR entre regiones.
- **Secuencias de failover**: automatizar failover solo cuando se han probado procedimientos y cuando dependencias externas (DNS, app gateways) están listas.
- **Consideraciones sobre logins y jobs**: AG no replica logins ni SQL Agent jobs; planifique sincronización (script de logins, job orchestration) y uses of Availability Group for user databases only.

Ejemplo (T-SQL) — crear AG (simplificado):

```sql
-- En primaria: crear grupo de disponibilidad
CREATE AVAILABILITY GROUP MyAG
	WITH (AUTOMATED_BACKUP_PREFERENCE = PRIMARY)
	FOR DATABASE MyDb
	REPLICA ON
		'replica1' WITH (ENDPOINT_URL = 'TCP://replica1:5022', AVAILABILITY_MODE = SYNCHRONOUS_COMMIT, FAILOVER_MODE = AUTOMATIC),
		'replica2' WITH (ENDPOINT_URL = 'TCP://replica2:5022', AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT, FAILOVER_MODE = MANUAL);

ALTER AVAILABILITY GROUP MyAG GRANT CREATE DATABASE;
```

Explicación: este T-SQL es un ejemplo sintético; en Azure es necesario configurar endpoints y WSFC previamente y asegurar endpoints firewall/NSG apropiados.

## Comprensión de la replicación geográfica activa (Active Geo-Replication)

Concepto:

- En Azure SQL PaaS, Active Geo-Replication crea réplicas asincrónicas legibles en otras regiones. Permite offloading de lecturas y proporciona opciones de failover (manual) o integración con Auto-Failover Groups para automatizar.

Características clave:

- Réplicas legibles: secundarias pueden usarse para reporting.
- Failover manual sencillo: promover réplica secundaria a primaria cuando sea necesario.
- Impacto en RPO: asincrónico → posible pérdida de datos entre la última transacción y el failover.

Ejemplo (AZ CLI) — crear réplica geográfica:

```bash
az sql db replica create \
	--resource-group my-rg \
	--server primary-server \
	--name mydb \
	--partner-server secondary-server
```

Explicación: este comando crea una réplica asincrónica de `mydb` en `secondary-server` para Active Geo-Replication.

## Exploración de Auto‑Failover Groups (agrupación y failover automático)

Descripción y ventajas:

- **Auto‑Failover Groups** agrupan varias bases y gestionan failover entre servidores lógicos (por ejemplo, entre regiones). Soportan política automática con grace period y listener DNS para reconexión.
- Simplifican el failover de aplicaciones multi‑base y permiten configuración centralizada de failover.

Configuración y control:

- Crear el failover group (ya mostrado en docs previas) y ajustar `failoverPolicy` (`Automatic` o `Manual`) y `gracePeriod` (en segundos) para tolerancia a falsos positivos.
- Probar failover (failover-test) y validar reconexión de aplicaciones.

Ejemplo (AZ CLI) — modificar política de failover:

```bash
az sql failover-group update \
	--name myFailoverGroup \
	--resource-group my-rg \
	--server primary-server \
	--failover-policy Automatic \
	--grace-period 1800
```

Explicación: este comando activa failover automático con un `grace-period` de 1800 segundos antes de forzar failover tras detectar la pérdida del primario.

## Pruebas y validación

- Realice ejercicios documentados de failover/failback en entornos no productivos.
- Supervise latencia de réplica, lag de transacciones y tiempos de reconexión de clientes.
- Documente pasos manuales cuando se requiera intervención (por ejemplo, para logins, certificados y jobs).

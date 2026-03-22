# Realizar copias de seguridad de bases de datos y restaurarlas

Este documento explica opciones y procedimientos de backup/restore para escenarios IaaS y PaaS en Azure, con ejemplos prácticos en Azure CLI, PowerShell y T-SQL.

## Copia de seguridad completa de una máquina virtual Azure (VM)

Azure Backup permite realizar copias de seguridad a nivel de VM (imagen) que capturan el estado completo de la máquina (OS, datos, configuración). Para VMs que ejecutan SQL Server, Azure Backup ofrece protección de aplicaciones mediante la extensión que garantiza consistencia de la base de datos usando VSS.

Ejemplo (AZ CLI) — crear Recovery Services vault y habilitar protección de VM:

```bash
# Crear Recovery Services Vault
az backup vault create --resource-group my-rg --name myVault --location westeurope

# Registrar la VM y habilitar protección (simplificado)
az backup protection enable-for-vm --resource-group my-rg --vault-name myVault --vm myVM --policy-name DefaultPolicy
```

Explicación: el vault centraliza backups; `enable-for-vm` aplica una política (schedule/retention). Para SQL Server en VM, Azure Backup puede hacer backups consistentes de la base usando la extensión y opcionalmente respaldos a nivel de base de datos.

PowerShell equivalente (crear vault y habilitar protección):

```powershell
New-AzRecoveryServicesVault -ResourceGroupName my-rg -Name myVault -Location westeurope
Set-AzRecoveryServicesVaultContext -Vault (Get-AzRecoveryServicesVault -Name myVault)
Enable-AzRecoveryServicesBackupProtection -ResourceGroupName my-rg -VaultId (Get-AzRecoveryServicesVault -Name myVault).Id -PolicyName 'DefaultPolicy' -VM (Get-AzVM -Name myVM -ResourceGroupName my-rg)
```

## Copias automatizadas mediante el proveedor de recursos de SQL Server (Azure Backup para SQL en VM)

Azure Backup para SQL Server in Azure VM permite respaldos a nivel de base de datos (Full/Diff/Log) y restauración granular. Se configura desde Recovery Services vault y se integra con la extensión de VM.

Pasos clave: habilitar protección, seleccionar bases, configurar schedule (full/diff/log) y retención.

## Tipos de copia de seguridad de SQL Server

- **Full (Completa)**: copia completa de la base. Punto de partida para diferenciales y restores.
- **Differential (Diferencial)**: copia de los cambios desde la última copia completa. Restaura más rápido y reduce espacio.
- **Transaction Log (Registro de transacciones)**: registra transacciones; permite recuperación punto-en-tiempo (PITR) si se aplican en orden.

Ejemplo T-SQL (backups locales a disco):

```sql
-- Backup completo
BACKUP DATABASE [MyDb] TO DISK = N'C:\backups\MyDb_full.bak' WITH INIT;

-- Backup diferencial
BACKUP DATABASE [MyDb] TO DISK = N'C:\backups\MyDb_diff.bak' WITH DIFFERENTIAL;

-- Backup de log
BACKUP LOG [MyDb] TO DISK = N'C:\backups\MyDb_log.trn';
```

Explicación: los comandos T-SQL realizan backups a archivos locales; en Azure es común enviar estos archivos a Azure Blob Storage (ver sección "backup a URL").

## Opciones de backup/restore en IaaS (VM con SQL Server)

- SQL Server nativo: usar BACKUP/RESTORE T-SQL a disco o a URL (Blob Storage). Control total sobre scheduling y retención.
- Azure Backup (Recovery Services): protección gestionada con políticas, copias consistentes y restauración guiada.
- Log Shipping, AlwaysOn AG/FCI: replicación y estrategias HADR para alta disponibilidad y recuperación.

Ejemplo: subir backup a Blob y restaurar desde URL.

### Preparar storage y SAS (AZ CLI)

```bash
# Crear cuenta de almacenamiento y contenedor
az storage account create -n mystorageacct -g my-rg -l westeurope --sku Standard_LRS
az storage container create --name sqlbackups --account-name mystorageacct

# Generar SAS temporal para la cuenta (lectura/escritura en contenedor)
SAS=$(az storage container generate-sas --account-name mystorageacct --name sqlbackups --permissions acdlrw --expiry 2026-12-31T00:00:00Z -o tsv)
URL="https://mystorageacct.blob.core.windows.net/sqlbackups"
```

Explicación: el SAS proporciona autorización temporal para que SQL Server escriba/lea blobs; en producción prefiera credenciales almacenadas en Key Vault.

### T-SQL — backup a URL (en servidor primario)

```sql
-- Crear credential en la instancia para el SAS (IDENTITY = 'SHARED ACCESS SIGNATURE')
CREATE CREDENTIAL [https://mystorageacct.blob.core.windows.net/sqlbackups] WITH IDENTITY='SHARED ACCESS SIGNATURE', SECRET = '<sas-token-without-?prefix>';

BACKUP DATABASE [MyDb] TO URL = 'https://mystorageacct.blob.core.windows.net/sqlbackups/MyDb_full.bak' WITH CREDENTIAL = 'https://mystorageacct.blob.core.windows.net/sqlbackups';
```

Explicación: `CREATE CREDENTIAL` almacena el SAS token en el servidor para permitir operaciones TO/FROM URL. El `BACKUP DATABASE ... TO URL` escribe el archivo directamente en Blob Storage.

## Opciones de backup/restore en PaaS (Azure SQL Database y Managed Instance)

- **Azure SQL Database (Single/Elastic)**: backups automáticos gestionados (PITR), LTR (Long Term Retention) opcional, Geo-Replication y export BACPAC para migraciones.
- **Azure SQL Managed Instance (MI)**: combina PaaS con compatibilidad casi completa T-SQL; soporta PITR, LTR y `BACKUP DATABASE ... TO URL` (native backup to blob) para movimientos manuales.

Ejemplo: exportar bacpac desde Azure SQL (portal o CLI) para migración/backup ligero.

```bash
# Exportar bacpac usando az (ejemplo conceptual)
az sql db export --admin-user sqladmin --admin-password 'P@ssw0rd!' --name northwinddb --resource-group my-rg --server myserver --storage-key-type StorageAccessKey --storage-key '<account-key>' --storage-uri 'https://mystorageacct.blob.core.windows.net/sqlbackups/northwinddb.bacpac'
```

Explicación: `az sql db export` crea un bacpac (schema + data) guardado en Blob; útil para migraciones pero no sustituye backups transaccionales para RTO/RPO críticos.

## Copia de seguridad y restauración a URL — ejemplos completos

1) Crear storage account y generar SAS (AZ CLI) — ya mostrado arriba.
2) Crear credential en SQL Server / Managed Instance (T-SQL) — ya mostrado.
3) Ejecutar BACKUP/RESTORE a URL.

T-SQL ejemplo para RESTORE desde URL:

```sql
RESTORE DATABASE [MyDb_Restore] FROM URL = 'https://mystorageacct.blob.core.windows.net/sqlbackups/MyDb_full.bak' WITH CREDENTIAL = 'https://mystorageacct.blob.core.windows.net/sqlbackups', MOVE 'MyDb_Data' TO 'D:\MSSQL\DATA\MyDb_Restore.mdf', MOVE 'MyDb_Log' TO 'D:\MSSQL\LOG\MyDb_Restore.ldf';
```

Explicación: `RESTORE DATABASE FROM URL` recupera el backup directamente desde Blob Storage; en Managed Instance la sintaxis y permisos son equivalentes.

## Copia de seguridad y restauración para Azure SQL Managed Instance

- Managed Instance realiza backups automáticos y ofrece PITR; además soporta `BACKUP DATABASE ... TO URL` y `RESTORE DATABASE ... FROM URL` para mover bases entre instancias o para export/restore manual.

Ejemplo T-SQL (Managed Instance) — backup a URL:

```sql
-- Crear credential con SAS (ejecutar en MI con permisos adecuados)
CREATE CREDENTIAL [https://mystorageacct.blob.core.windows.net/sqlbackups] WITH IDENTITY='SHARED ACCESS SIGNATURE', SECRET = '<sas-token-without-?>';

BACKUP DATABASE [MyDb] TO URL = 'https://mystorageacct.blob.core.windows.net/sqlbackups/MyDb_MI_full.bak' WITH CREDENTIAL = 'https://mystorageacct.blob.core.windows.net/sqlbackups';
```

Explicación: Managed Instance permite realizar backups nativos a blob para copias offsite o migraciones; recuerde gestionar SAS/credenciales de forma segura.

## Buenas prácticas

- Automatizar políticas de backup y retención (Recovery Services / Azure SQL settings) y documentarlas.
- Probar restauraciones periódicamente (restore drills) para asegurar RTO/RPO reales.
- Proteger los SAS/keys en Azure Key Vault y otorgar permisos mínimos.
- Para IaaS, prefiera Azure Backup para simplificar operaciones y aprovechar la consistencia de la aplicación.

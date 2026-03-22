# Creación y administración de trabajos del Agente SQL

Este documento cubre las tareas de mantenimiento que deben automatizarse en bases de datos, recomendaciones para planes de mantenimiento, y cómo configurar notificaciones/alertas tanto para SQL Server Agent (IaaS / Managed Instance) como para Azure SQL (PaaS) usando Azure Monitor y action groups.

## Actividades de mantenimiento recomendadas

Las tareas comunes que conviene automatizar son:

- Backups: Full/Differential/Log (en IaaS y Managed Instance). En PaaS Azure SQL gestiona backups automáticos, pero planifique retención y exportaciones si es necesario.
- Integridad: `DBCC CHECKDB` (ejecutar en copias o en ventanas controladas para IaaS; para PaaS evaluar copia/restores según SLA).
- Mantenimiento de índices: `ALTER INDEX ... REORGANIZE/REBUILD` según fragmentación y tamaños.
- Actualización de estadísticas: `UPDATE STATISTICS` o `sp_updatestats` para asegurar buenos planes de ejecución.
- Limpieza: purgar history de jobs, auditorías y tablas temporales; mantenimiento de `tempdb` en IaaS.
- Monitorización y recolección de métricas y telemetría (wait stats, index usage, bloqueo).

Ejemplo T-SQL de operaciones básicas:

```sql
-- DBCC CHECKDB (ejecutar fuera de picos)
DBCC CHECKDB (N'MyDatabase') WITH NO_INFOMSGS, ALL_ERRORMSGS;

-- Actualizar estadísticas de una tabla
UPDATE STATISTICS dbo.Orders;

-- Reconstruir índices si es necesario (uso en runbooks/jobs)
ALTER INDEX ALL ON dbo.Orders REBUILD WITH (ONLINE = ON);
```

Explicación: `DBCC CHECKDB` valida la integridad física y lógica; `UPDATE STATISTICS` mantiene la calidad de las estimaciones del optimizador; `ALTER INDEX ... REBUILD` corrige fragmentación pero consume I/O y CPU, prográmelo en ventanas de mantenimiento.

## Procedimientos recomendados para planes de mantenimiento

Consideraciones al diseñar planes:

- Frecuencia: estadísticas diarias, índices según fragmentación (reorganize semanal/rebuild mensual o según thresholds), backups diarios (full/more frequent for log backups).
- Ventanas y paralelismo: programar durante baja carga; ajuste `MAXDOP` si la reconstrución impacta CPU.
- Priorizar tablas críticas: evitar bloqueos largos en tablas transaccionales; usar online rebuild si disponible.
- Automatizar validaciones post-mantenimiento y alertas en caso de errores.

Ejemplo de calendario típico:

- Diario: Log backups (IaaS), actualización de estadísticas, recolección de métricas.
- Semanal: `REORGANIZE` índices en tablas medianas.
- Mensual: `REBUILD` índices grandes fuera de horas pico y `DBCC CHECKDB`.

## Configurar notificaciones y alertas para SQL Server Agent (IaaS / Managed Instance)

En entornos con SQL Server Agent (IaaS o Managed Instance), las notificaciones se configuran a través de Operators y Alerts en `msdb`.

Pasos generales:

1. Habilitar Database Mail y configurar un perfil de correo.
2. Crear un Operator para recibir notificaciones (email/pager).
3. Asociar notificaciones a jobs o crear Alerts que, al dispararse, notifiquen al Operator.

Ejemplo T-SQL para crear un operador y una alerta de ejemplo:

```sql
-- Crear operador
EXEC msdb.dbo.sp_add_operator
	@name = N'DBA_Team',
	@email_address = N'dba-team@example.com';

-- Crear una alerta basada en severidad o en condición de rendimiento (ejemplo simplificado)
EXEC msdb.dbo.sp_add_alert
	@name = N'High CPU Alert',
	@enabled = 1,
	@delay_between_responses = 0,
	@performance_condition = N"\"SQLServer:Resource Pool Stats\"\"% Processor Time\" > 80",
	@notification_message = N'CPU por encima del umbral';

-- Asociar alerta con operador
EXEC msdb.dbo.sp_add_notification @alert_name = N'High CPU Alert', @operator_name = N'DBA_Team', @notification_method = 1; -- 1 = email
```

Explicación: `sp_add_operator` crea un destinatario; `sp_add_alert` crea una alerta que puede basarse en un performance condition o severidad; `sp_add_notification` vincula alerta y operador. En la práctica, valide la sintaxis de `@performance_condition` y asegúrese de que Database Mail está funcionando.

Además, para trabajos de agente específicos, configure el job para notificar en fallo/éxito/fin mediante las propiedades del job (SSMS) o `sp_update_job`.

## Configurar alertas y notificaciones para Azure SQL (PaaS)

En PaaS (Azure SQL Database), use **Azure Monitor** y **Action Groups** para notificaciones. No hay SQL Agent en single databases; para ejecución centralizada use Elastic Jobs o Automation + Logic Apps.

Ejemplo AZ CLI: crear un Action Group y una alerta de métrica (CPU alto)

```bash
# Crear action group que envía email
az monitor action-group create \
	--resource-group my-rg \
	--name myActionGroup \
	--action email AdminEmail admin@example.com

# Crear alerta de métrica asociada al action group (CPU > 80% durante 5 minutos)
az monitor metrics alert create \
	--name HighCpuAlert \
	--resource-group my-rg \
	--scopes /subscriptions/<sub>/resourceGroups/my-rg/providers/Microsoft.Sql/servers/my-sql-server/databases/northwinddb \
	--condition "avg cpu_percent > 80" \
	--window-size 5m \
	--evaluation-frequency 1m \
	--action-group myActionGroup
```

Explicación: el `action-group` define los canales (email, webhook, Logic App); la `metrics alert` evalúa la métrica `cpu_percent` sobre la base y ejecuta el action group cuando la condición se cumple.

Ejemplo PowerShell equivalente (crear action group y regla de alerta):

```powershell
# Crear Action Group
New-AzActionGroup -ResourceGroupName my-rg -Name myActionGroup -ShortName MAG -ReceiverEmail AdminEmail admin@example.com

# Crear alerta de métricas
Add-AzMetricAlertRuleV2 -ResourceGroupName my-rg -Name 'HighCpuAlert' -TargetResourceId "/subscriptions/<sub>/resourceGroups/my-rg/providers/Microsoft.Sql/servers/my-sql-server/databases/northwinddb" -Condition "avg CPU_percentage > 80" -WindowSize 00:05:00 -EvaluationFrequency 00:01:00 -ActionGroupId '/subscriptions/<sub>/resourceGroups/my-rg/providers/microsoft.insights/actionGroups/myActionGroup'
```

Nota: adapte nombres de métricas (`cpu_percent` o `cpu_percent`) según el proveedor/namespace; use `az monitor metrics list-definitions` para ver métricas disponibles.

## Alertas basadas en valores del Monitor de rendimiento (PerfMon)

Para alertas basadas en contadores de rendimiento (PerfMon) en VMs/IaaS o en contadores expuestos por SQL Server, proceda así:

- Recopile contadores con Azure Monitor (agente de diagnóstico) en Log Analytics o use PerfMon local.
- Defina una alerta basada en la métrica agregada (avg, max) con ventana y frecuencia apropiadas para evitar falsas alarmas.
- Use action groups para notificar o para ejecutar remediaciones automáticas (Logic App / Runbook).

Ejemplo: crear alerta basada en contador de PerfMon de `% Processor Time` de la máquina virtual (CLI):

```bash
# Primero identifique el resource id de la VM
VM_RESOURCE_ID="/subscriptions/<sub>/resourceGroups/my-rg/providers/Microsoft.Compute/virtualMachines/myvm"

# Crear action group (si no existe)
az monitor action-group create --resource-group my-rg --name myActionGroup --action email AdminEmail admin@example.com

# Crear alerta basada en métrica de VM (Processor Time)
az monitor metrics alert create \
	--name VMHighCpu \
	--resource-group my-rg \
	--scopes $VM_RESOURCE_ID \
	--condition "avg Percentage CPU > 85" \
	--window-size 5m \
	--evaluation-frequency 1m \
	--action-group myActionGroup
```

Explicación: el agente de Monitor o Diagnostics extiende métricas al tenant; defina `window-size` y `evaluation-frequency` para controlar sensibilidad.

## Buenas prácticas para alertas y notificaciones

- Evitar alertas demasiado sensibles que provoquen ruido. Use `window-size` y `evaluation-frequency` apropiados.
- Agrupar alertas en Action Groups reutilizables (email, webhook, Logic App, Runbook).
- Documentar runbooks de remediación y automatizarlos cuando sea seguro.
- Asegurar que las notificaciones tienen suficientes datos contextuales (query id, server, database, timestamp).
- Revisar y ajustar umbrales periódicamente según patrones de uso y carga.
- En entornos críticos, considere alertas de múltiples niveles (warning/critical) con diferentes umbrales y acciones.
- Pruebe las alertas simulando condiciones para validar que se disparan correctamente y que las notificaciones llegan a los destinatarios.
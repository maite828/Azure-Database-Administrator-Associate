# Automatización de tareas de base de datos para Azure SQL

## Contenidos

## 01 - Automatización de la implementación de bases de datos
- [01 - Automatización de la implementación de bases de datos](01%20Automatizaci%C3%B3n%20de%20la%20implementaci%C3%B3n%20de%20bases%20de%20datos.md): Métodos para automatizar la creación y despliegue de bases de datos en Azure (PaaS) y SQL Server en IaaS, usando plantillas (ARM/Bicep), CLI/PowerShell y pipelines (Azure DevOps/GitHub Actions). Incluye comandos de ejemplo y recomendaciones de supervisión.

## 02 - Creación y administración de trabajos del Agente SQL
- [02 - Creación y administración de trabajos del Agente SQL](02%20Creaci%C3%B3n%20y%20administraci%C3%B3n%20de%20trabajos%20del%20Agente%20SQL.md): Guía para automatizar tareas de mantenimiento, configurar notificaciones y alertas en SQL Server Agent (IaaS/Managed Instance) y Azure SQL (PaaS) usando Azure Monitor y action groups.


## 03 - Administración de tareas de PaaS de Azure mediante automatización
- [03 - Administración de tareas de PaaS de Azure mediante automatización](03%20Administraci%C3%B3n%20de%20tareas%20de%20PaaS%20de%20Azure%20mediante%20automatizaci%C3%B3n.md): Cómo usar Azure Automation (runbooks) y Elastic Jobs para tareas de mantenimiento en Azure SQL, con ejemplos de runbooks PowerShell y recomendaciones para orquestación con Logic Apps.

## Script de automarización (carpeta `runbooks`)

En la carpeta `runbooks`  se encuentran scripts PowerShell diseñados para importarse como Runbooks en Azure Automation. Los runbooks implementan tareas de mantenimiento repetibles (por ejemplo, reconstrucción de índices por objetivo) y están preparados para ejecutarse preferiblemente con Managed Identity o credenciales seguras almacenadas en Azure Key Vault.

Notas:
- Probar siempre en entornos no productivos antes de programar en producción.
- Revisar y ajustar parámetros de mantenimiento (ventanas, MAXDOP, FILLFACTOR) según la carga.
- No se proporcionan enlaces directos desde el índice principal; consulte este README para una descripción rápida de los runbooks disponibles.

Runbooks incluidos (breve):
- RebuildIndexes_Runbook.ps1: runbook para reconstrucción/reorganización de índices en bases objetivo; admite lectura de targets desde una tabla de control o parámetros directos.
# Automatización de la implementación de bases de datos

Este documento describe métodos y prácticas para automatizar la creación y despliegue de bases de datos en Azure (PaaS) y SQL Server en IaaS, usando plantillas (ARM/Bicep), CLI/PowerShell y pipelines (Azure DevOps/GitHub Actions). Incluye comandos de ejemplo y recomendaciones de supervisión.

## Métodos de implementación en Azure

Principales métodos:

- Plantillas ARM y archivos Bicep (infraestructura como código, declarativo).
- Azure CLI (`az`) para scripting multiplataforma.
- Azure PowerShell (`Az` modules) y `Az.Sql` para tareas específicas de base de datos.
- Azure DevOps y GitHub Actions para CI/CD y despliegues automatizados.
- Portal de Azure para tareas ad-hoc y validación visual.

## Automatización con ARM y Bicep

Las plantillas ARM son JSON declarativo; Bicep es la sintaxis de nivel superior y más legible que compila a ARM. Ventajas: reproducibilidad, versionado en Git, validación previa al despliegue y posibilidad de `what-if` para evaluar cambios.

**Desplegar plantilla ARM con Azure CLI:**

```bash
# Desplegar un template ARM en un resource group
az deployment group create \
	--resource-group my-rg \
	--template-file ./azuredeploy.json \
	--parameters @azuredeploy.parameters.json
```

Explicación: `az deployment group create` aplica la plantilla al scope del resource group; los parámetros se pueden pasar en JSON o en línea.

**Desplegar archivo Bicep con Azure CLI (Bicep integrado en `az`):**

```bash
az deployment group create \
	--resource-group my-rg \
	--template-file ./main.bicep \
	--parameters dbName=northwinddb serviceObjective=S0
```

Explicación: `az` detecta archivos `.bicep`, compila y despliega. Esto permite usar Bicep sin pasos manuales de compilación.

**Desplegar Bicep/ARM con PowerShell (`Az` module):**

```powershell
New-AzResourceGroupDeployment -ResourceGroupName my-rg -TemplateFile .\main.bicep -TemplateParameterObject @{ dbName = 'northwinddb' }
```

Explicación: `New-AzResourceGroupDeployment` despliega plantillas desde PowerShell; admite archivos `.bicep` si el entorno tiene soporte o usa la compilación previa.

**Ventajas de plantillas ARM/Bicep:**

- Declarativas y repetibles: el mismo template produce la misma infraestructura.
- Integración con control de versiones (Git) y revisión de cambios.
- Soportan `what-if` y validación previa al despliegue.
- Permiten parametrización para entornos (dev/test/prod).

### Cómo instalar y usar Bicep

Instalación rápida (con Azure CLI):

```bash
az bicep install
az bicep version
```

Explicación: `az bicep install` instala el compilador Bicep y lo integra con el comando `az deployment`. También se puede instalar el binario `bicep` directamente desde releases de GitHub.

Operaciones comunes:

- `az bicep build --file main.bicep` → compila Bicep a ARM JSON.
- `az deployment group what-if --resource-group my-rg --template-file main.bicep` → evalúa cambios sin aplicarlos.

### Transformar ARM JSON a Bicep (decompile)

Si partes de una plantilla ARM existente y prefieres trabajar en Bicep, puedes decompilar el JSON a Bicep.

```bash
# Con Azure CLI (usa el comando bicep integrado cuando esté instalado):
az bicep decompile --file ./azuredeploy.json

# O usando el binario bicep directamente:
bicep decompile ./azuredeploy.json
```

Explicación: `decompile` intenta convertir la plantilla ARM JSON a sintaxis Bicep legible. Funciona mejor con plantillas relativamente simples; en plantillas complejas puede requerir ajustes manuales (expresiones, módulos, referencias). Siempre revisar y probar el resultado antes de usarlo en producción.

## Supervisión de implementaciones

Formas de supervisar y validar despliegues:

- Portal: historial de despliegues del resource group (Deployment history) con detalles y logs.
- Azure CLI / PowerShell:

```bash
# Ver estado del último despliegue
az deployment group show --resource-group my-rg --name <deploymentName>

# What-if (evaluar cambios sin aplicar)
az deployment group what-if --resource-group my-rg --template-file main.bicep
```

```powershell
# PowerShell: ver despliegues
Get-AzResourceGroupDeployment -ResourceGroupName my-rg
```

- Telemetría: enviar resultados a Log Analytics o Application Insights desde pipelines o runbooks para auditoría centralizada.

## Automatización mediante comandos CLI

**Ejemplo CLI y T-SQL combinado (crear servidor y base, luego ejecutar script de inicialización):**

```bash
# 1) Crear servidor y base (CLI)
az sql server create --name my-sql-server --resource-group my-rg --location westeurope --admin-user sqladmin --admin-password 'P@ssw0rd!'
az sql db create --resource-group my-rg --server my-sql-server --name northwinddb --service-objective S0

# 2) Ejecutar script T-SQL de inicialización (usando sqlcmd)
sqlcmd -S tcp:my-sql-server.database.windows.net -d northwinddb -U sqladmin -P 'P@ssw0rd!' -i ./init_schema.sql
```

Explicación: separar la provisión (infra) de la inicialización de datos. En pipelines, el paso de ejecución T-SQL se hace con tareas específicas (Azure SQL Database Deployment task, o `sqlcmd` / `Invoke-Sqlcmd`).

## Automatización mediante el módulo `Az.Sql` de PowerShell

`Az.Sql` proporciona cmdlets para gestionar servidores, bases, reglas de firewall y replicación.

Ejemplos:

```powershell
# Crear servidor
New-AzSqlServer -ResourceGroupName my-rg -ServerName my-sql-server -Location westeurope -SqlAdministratorCredentials (Get-Credential)

# Crear base
New-AzSqlDatabase -ResourceGroupName my-rg -ServerName my-sql-server -DatabaseName northwinddb -RequestedServiceObjectiveName 'S0'

# Configurar regla de firewall
New-AzSqlServerFirewallRule -ResourceGroupName my-rg -ServerName my-sql-server -FirewallRuleName AllowMyIP -StartIpAddress 1.2.3.4 -EndIpAddress 1.2.3.4
```

Explicación: use `Get-Credential` o Managed Identity en automation; en scripts CI use Service Principals con permisos mínimos.

## Automatización con Azure DevOps y GitHub Actions

Patrón CI/CD:

- Mantener plantillas en repositorio (Bicep preferido por legibilidad).
- Pipeline valida la plantilla (`what-if`) y la despliega a entornos mediante `az` o `Az`.
- Ejecutar tasks de post-deploy (migrations, seed data) con `sqlcmd`/`Invoke-Sqlcmd`.

Ejemplo breve de job en GitHub Actions (desplegar Bicep):

```yaml
name: Deploy Bicep
on: [push]
jobs:
	deploy:
		runs-on: ubuntu-latest
		steps:
			- uses: actions/checkout@v3
			- uses: azure/login@v1
				with:
					creds: ${{ secrets.AZURE_CREDENTIALS }}
			- name: Deploy Bicep
				run: |
					az bicep install
					az deployment group create --resource-group my-rg --template-file ./infra/main.bicep --parameters dbName=northwinddb
```

Explicación: `azure/login` configura credenciales; `secrets.AZURE_CREDENTIALS` contiene un service principal. El job instala bicep y despliega.

## Buenas prácticas

- Versionar plantillas y parámetros por entorno.
- Validar con `what-if` antes de aplicar.
- Usar Service Principals o Managed Identity con permisos mínimos en CI/CD.
- Separar provisión infra (servidor, redes) de despliegue de esquemas y datos.
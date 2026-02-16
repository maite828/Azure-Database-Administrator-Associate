# Instalación de SQL Server en Azure como IaaS (Máquina Virtual)

## Introducción

En este documento se describe paso a paso cómo desplegar **SQL Server en Azure bajo el modelo IaaS (Infrastructure as a Service)** utilizando una máquina virtual que incluye el sistema operativo y SQL Server preinstalado desde una imagen oficial del Marketplace.

En este modelo, el cliente es responsable de:

* Administración del sistema operativo
* Parches del sistema y SQL Server
* Configuración de seguridad
* Backups (si no se integran servicios adicionales)

---

## Requisitos Previos

Antes de comenzar, asegúrate de tener:

* Suscripción activa en Microsoft Azure
* Permisos Owner o Contributor
* Acceso al Portal de Azure: [https://portal.azure.com](https://portal.azure.com)
* Conocimiento básico de SQL Server y Windows Server

---

# Paso 1: Iniciar sesión en el Portal de Azure

1. Accede a [https://portal.azure.com](https://portal.azure.com)
2. Inicia sesión con tu cuenta.

---

# Paso 2: Crear una nueva máquina virtual

1. Haz clic en **"Crear un recurso"**.
2. Selecciona **"Máquina virtual"**.
3. Haz clic en **"Crear"**.

---

# Paso 3: Configuración básica de la máquina virtual

En la pestaña **Datos básicos**, configura lo siguiente:

## 3.1 Suscripción

Selecciona la suscripción correspondiente.

## 3.2 Grupo de recursos

* Selecciona uno existente o
* Crea uno nuevo (ejemplo: `rg-sql-iaas-demo`).

## 3.3 Nombre de la máquina virtual

Ejemplo: `vm-sql-01`

## 3.4 Región

Selecciona la región adecuada (ejemplo: West Europe).

## 3.5 Imagen

En "Imagen", selecciona una imagen del Marketplace que incluya SQL Server, por ejemplo:

* SQL Server 2022 on Windows Server 2022
* SQL Server 2019 on Windows Server 2019

Asegúrate de seleccionar una imagen que indique explícitamente que incluye SQL Server.

## 3.6 Tamaño de la máquina

Haz clic en **"Cambiar tamaño"** y selecciona una VM adecuada:

Recomendaciones:

* Entornos de laboratorio: Standard D2s v5
* Producción: Series optimizadas para memoria (Ej: E-series)

## 3.7 Cuenta de administrador

Configura:

* Usuario administrador del sistema operativo
* Contraseña segura

---

# Paso 4: Configuración de discos

Ve a la pestaña **Discos**.

Recomendaciones para SQL Server:

* Disco SO (por defecto)
* Disco adicional para datos
* Disco adicional para logs
* Opcional: Disco para TempDB

Para entornos productivos:

* Utilizar discos Premium SSD o Ultra Disk
* Separar datos y logs en discos distintos

---

# Paso 5: Configuración de red

En la pestaña **Redes**:

* Se creará una red virtual (VNet) automáticamente o puedes usar una existente.
* Configura una IP pública si necesitas acceso externo.
* Configura el NSG (Network Security Group).

Importante:

* Abrir puerto 3389 (RDP) para administración remota.
* Abrir puerto 1433 solo si se requiere acceso externo a SQL Server (no recomendado en producción sin protección adicional).

---

# Paso 6: Configuración de administración

En la pestaña **Administración**:

* Habilitar Backup automático (opcional).
* Habilitar Monitoring.
* Activar diagnóstico de arranque.

---

# Paso 7: Revisar y crear

1. Haz clic en **"Revisar y crear"**.
2. Verifica que la validación sea correcta.
3. Haz clic en **"Crear"**.

El despliegue tardará varios minutos.

---

# Paso 8: Conectarse a la máquina virtual

Una vez desplegada:

1. Accede al recurso de la VM.
2. Haz clic en **"Conectar"**.
3. Descarga el archivo RDP.
4. Conéctate usando el usuario administrador.

---

# Paso 9: Verificar SQL Server

Dentro de la máquina virtual:

1. Abre SQL Server Management Studio (si no está instalado, instálalo).
2. Conéctate a:

   * Nombre del servidor: `localhost`
   * Autenticación Windows o SQL
3. Verifica que el servicio SQL Server esté en ejecución desde:

   * Services.msc

---

# Paso 10: Configurar SQL Server (Buenas prácticas)

## 10.1 Configurar memoria máxima

```sql
EXEC sys.sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sys.sp_configure 'max server memory (MB)', 8192;
RECONFIGURE;
```

Ajustar según la memoria disponible en la VM.

## 10.2 Configurar TempDB

* Múltiples archivos de datos
* Tamaño inicial adecuado
* Ubicación en disco dedicado

## 10.3 Configurar backups

Opciones:

* Backup manual a disco
* Backup a Azure Blob Storage
* Integración con Azure Backup

---

# Paso 11: Configurar extensión SQL IaaS Agent (Recomendado)

Desde el recurso de la VM:

1. Ir a "SQL Virtual Machines".
2. Registrar la VM como SQL Virtual Machine.
3. Habilitar:

   * Automated backup
   * Automated patching
   * Azure Key Vault integration

Esto permite una administración mejorada sin convertirlo en PaaS.

---

# Diferencias clave vs PaaS

| Característica      | IaaS         | PaaS       |
| ------------------- | ------------ | ---------- |
| Gestión SO          | Cliente      | Microsoft  |
| Parches SQL         | Cliente      | Microsoft  |
| Alta disponibilidad | Configurable | Automática |
| Escalabilidad       | Manual       | Automática |
| Control total       | Sí           | Parcial    |

---

# Buenas prácticas de arquitectura

* Usar Availability Sets o Availability Zones
* Implementar Always On Availability Groups para HA
* Configurar Azure Monitor y Log Analytics
* Aplicar principio de mínimo privilegio
* Evitar exponer puerto 1433 a Internet



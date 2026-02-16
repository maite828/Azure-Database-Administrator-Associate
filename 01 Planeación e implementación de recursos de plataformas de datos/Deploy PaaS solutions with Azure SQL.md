# Instalación de Azure SQL Database como Base de Datos Única (PaaS)

## Introducción

Azure SQL Database es un servicio de base de datos relacional como plataforma como servicio (PaaS) completamente administrado por Microsoft Azure. En este documento se explica paso a paso cómo crear una **Base de Datos Única (Single Database)** en Azure.

---

## Requisitos Previos

Antes de comenzar, asegúrate de tener:

* Una suscripción activa de Microsoft Azure.
* Permisos para crear recursos (Owner o Contributor).
* Acceso al portal de Azure: [https://portal.azure.com](https://portal.azure.com)

---

## Paso 1: Iniciar sesión en el Portal de Azure

1. Accede a [https://portal.azure.com](https://portal.azure.com)
2. Inicia sesión con tu cuenta corporativa o cuenta Microsoft.

---

## Paso 2: Crear un nuevo recurso

1. Haz clic en **"Crear un recurso"**.
2. En el buscador, escribe **"Azure SQL"**.
3. Selecciona **"Azure SQL"**.
4. Haz clic en **"Crear"**.

---

## Paso 3: Seleccionar tipo de implementación

1. En la pantalla "Seleccionar opción de implementación SQL".
2. En la opción **Bases de datos SQL**, selecciona:

   * **Base de datos única (Single Database)**.
3. Haz clic en **"Crear"**.

---

## Paso 4: Configuración básica

En la pestaña **Datos básicos**, completa la siguiente información:

### 4.1 Suscripción

Selecciona la suscripción donde se desplegará el recurso.

### 4.2 Grupo de recursos

* Puedes seleccionar uno existente o
* Crear uno nuevo (ejemplo: `rg-sql-demo`).

### 4.3 Nombre de la base de datos

Introduce un nombre único (ejemplo: `sqldb-demo`).

### 4.4 Servidor

Debes crear un nuevo servidor lógico si no tienes uno:

1. Haz clic en **"Crear nuevo"**.
2. Introduce:

   * Nombre del servidor (ejemplo: `sqlserver-demo-001`).
   * Región (ejemplo: West Europe).
   * Usuario administrador.
   * Contraseña segura.
3. Haz clic en **Aceptar**.

---

## Paso 5: Configurar rendimiento (Compute + Storage)

1. En la sección **Proceso y almacenamiento**, haz clic en **"Configurar base de datos"**.
2. Selecciona el modelo de compra:

   * Basado en DTU
   * Basado en vCore (recomendado para producción)
3. Selecciona el nivel de servicio:

   * General Purpose
   * Business Critical
   * Hyperscale
4. Ajusta:

   * Número de vCores
   * Almacenamiento
5. Haz clic en **Aplicar**.

---

## Paso 6: Configuración de red

1. Ve a la pestaña **Redes**.
2. Configura el acceso:

   * Punto de conexión público (habilitado por defecto).
3. Agrega tu IP cliente actual si deseas conectarte desde tu equipo:

   * Haz clic en **"Agregar IP cliente actual"**.
4. Guarda la configuración.

---

## Paso 7: Configuración de seguridad adicional (Opcional)

En la pestaña **Seguridad**, puedes configurar:

* Microsoft Defender for SQL.
* Encriptación.
* Azure Active Directory como administrador.

---

## Paso 8: Revisar y crear

1. Haz clic en **"Revisar y crear"**.
2. Verifica que la validación sea correcta.
3. Haz clic en **"Crear"**.

El despliegue tardará unos minutos.

---

## Paso 9: Conectarse a la Base de Datos

Una vez desplegada:

1. Accede al recurso creado.
2. Haz clic en **"Cadenas de conexión"**.
3. Copia la cadena correspondiente a:

   * ADO.NET
   * JDBC
   * ODBC
   * PHP
4. Conéctate usando:

   * SQL Server Management Studio (SSMS)
   * Azure Data Studio
   * Aplicación personalizada

---

## Paso 10: Probar la conexión

1. Abre SSMS.
2. Introduce:

   * Nombre del servidor: `nombre-servidor.database.windows.net`
   * Autenticación SQL Server.
   * Usuario administrador.
   * Contraseña.
3. Haz clic en Conectar.
4. Crea una tabla de prueba:

```sql
CREATE TABLE Prueba (
    Id INT PRIMARY KEY,
    Nombre NVARCHAR(100)
);
```

Si la tabla se crea correctamente, la base de datos está operativa.

---

## Buenas Prácticas

* Utilizar autenticación con Azure AD cuando sea posible.
* Configurar reglas de firewall restrictivas.
* Monitorizar el rendimiento desde "Intelligent Performance".
* Configurar copias de seguridad automáticas y retención adecuada.
* Activar alertas de métricas.



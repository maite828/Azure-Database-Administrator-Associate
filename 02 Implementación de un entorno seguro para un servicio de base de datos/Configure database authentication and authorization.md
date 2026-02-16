# Autenticacion en Azure SQL: IaaS vs PaaS

Este documento resume como funciona la autenticacion en SQL Server desplegado en Azure como IaaS (VM) y en servicios PaaS (Azure SQL Database). Incluye tambien pautas basicas de autorizacion.

## Objetivo

- Entender los metodos de autenticacion disponibles en cada modelo.
- Elegir el metodo segun el tipo de usuario (humano o aplicacion).
- Aplicar autorizacion con minimo privilegio.

## IaaS: SQL Server en maquina virtual de Azure

En IaaS, tu administras el sistema operativo y SQL Server. La autenticacion depende de como configures Windows y SQL.

### Metodos de autenticacion

1. **Autenticacion de Windows (recomendada para usuarios humanos)**
	- Usa cuentas de Active Directory (AD DS) o Azure AD Domain Services.
	- Permite directivas de contrasena, bloqueo, y MFA si tu AD lo soporta.
	- Se integra bien con grupos para administrar permisos.

2. **Autenticacion de SQL Server (SQL Logins)**
	- Usa usuarios y contrasenas almacenados en SQL Server.
	- Util para cuentas de aplicacion cuando no hay AD.
	- Requiere politicas de contrasena y rotacion gestionadas por ti.

### Recomendaciones de seguridad en IaaS

- Deshabilita cuentas no usadas y renombra el login `sa`.
- Usa autenticacion de Windows para admins y soporte.
- Usa `TLS` y fuerza cifrado en conexiones.
- Evita exponer el puerto 1433 a Internet sin protecciones (NSG, VPN, Bastion).

## PaaS: Azure SQL Database

En PaaS, Azure gestiona el motor y la infraestructura. La autenticacion se centra en identidades de Azure AD y SQL.

### Metodos de autenticacion

1. **Azure AD (recomendada para usuarios y apps)**
	- Centraliza identidades en Entra ID (Azure AD).
	- Permite MFA, Conditional Access y auditoria centralizada.
	- Usa usuarios y grupos de Azure AD para acceso.

2. **SQL Authentication (usuarios contenidos)**
	- Usuarios y contrasenas definidos dentro de la base de datos.
	- Util para compatibilidad o escenarios sin Azure AD.

3. **Managed Identity (para aplicaciones en Azure)**
	- Evita secretos: la app usa su identidad administrada.
	- Se asignan permisos con usuarios de Azure AD.

### Recomendaciones de seguridad en PaaS

- Configura un **Azure AD admin** para el servidor.
- Usa **Azure AD** como metodo principal.
- Crea usuarios contenidos por base de datos, no logins a nivel servidor si no son necesarios.
- Restringe acceso con firewall y, si es posible, Private Endpoint.

## Autorizacion (IaaS y PaaS)

La autenticacion valida quien eres. La autorizacion define que puedes hacer.

### Buenas practicas

- Usa el principio de minimo privilegio.
- Asigna permisos por **roles** y **grupos** en lugar de cuentas individuales.
- Evita `db_owner` salvo para administradores.
- Separa cuentas de administrador y cuentas de aplicacion.

### Roles tipicos

- `db_datareader`: lectura de datos.
- `db_datawriter`: escritura de datos.
- `db_ddladmin`: cambios de esquema controlados.

## Resumen rapido

- **IaaS**: tu gestionas Windows, AD y SQL. Windows Auth es preferida si hay AD.
- **PaaS**: Azure AD es el metodo recomendado, con soporte para Managed Identity.
- En ambos casos, aplica minimo privilegio y segmenta accesos por rol.

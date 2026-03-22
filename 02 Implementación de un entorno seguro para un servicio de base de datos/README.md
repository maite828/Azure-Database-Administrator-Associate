# Implementación de un entorno seguro para un servicio de base de datos

## Contenidos

## 01 - Autenticación y autorización
- [01 Configuración de la autenticación y la autorización](01%20Configure%20database%20authentication%C2%A0and%20authorization.md): Explica métodos de autenticación para SQL Server (IaaS) y Azure SQL Database (PaaS), integración con Azure AD y recomendaciones de seguridad.
  - [Authorization examples](01.a%20Authorization%20examples.md): Ejemplos prácticos de creación de usuarios, asignación de permisos, roles y pruebas de acceso en T-SQL.

## 02 - Protección de datos y controles
- [02 Protección de los datos en tránsito y en reposo](02%20Protecci%C3%B3n%20de%20los%20datos%20en%20tr%C3%A1nsito%20y%20en%20reposo.md): Explica cifrado en tránsito, TDE, y consideraciones de cifrado por columna.
  - [Firewall examples](02.a%20Firewall%20examples.md): Comandos T-SQL para gestionar reglas de firewall a nivel de servidor y base de datos.
  - [TDE en Azure SQL Database PaaS](02.b%20TDE%20en%20Azure%20SQL%20Database%20PaaS.md): Procedimientos y buenas prácticas para TDE en PaaS, incluido CMK en Key Vault.
  - [TDE en SQL Server IaaS](02.c%20TDE%20en%20SQL%20Server%20IaaS.md): Pasos para crear certificados, DEK, activar TDE y respaldar claves en entornos VM.

## 03 - Controles de cumplimiento y datos confidenciales
- [03 Implementación de controles de cumplimiento para datos confidenciales](03%20Implementaci%C3%B3n%20de%20controles%20de%20cumplimiento%20para%20datos%20confidenciales.md): Conceptos generales de clasificación, flujo de trabajo, RLS, DDM, Ledger y Defender for SQL.
  - [Dynamic Data Masking Examples](03.a%20Dynamic%20Data%20Masking%20Examples.md): Ejemplos comentados de DDM sobre `AdventureWorksLT`, orden de ejecución y pruebas con `EXECUTE AS`.
  - [Ledger examples](03.b%20Ledger%20examples.md): Comandos y consultas para trabajar con Azure SQL Ledger, ejemplos de creación, consulta y deshabilitación.
  - [Seguridad de Fila (Row-Level Security)](03.c%20Seguridad%20de%20Fila.md): Ejemplo práctico con Northwind sobre cómo implementar RLS en la tabla `Orders`.

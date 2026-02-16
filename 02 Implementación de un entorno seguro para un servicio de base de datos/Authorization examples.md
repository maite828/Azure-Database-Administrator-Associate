# Ejemplos de autenticacion y autorizacion (SQL)

Este documento organiza los ejemplos solicitados, sin duplicados, y con una contrasena de ejemplo diferente a la original.

> Nota: Cambia las contrasenas en entornos reales y evita credenciales estaticas.

## 1) Creacion de usuarios

```sql
-- Creacion de un usuario
CREATE USER SalesUser WITH PASSWORD = 'T1ger!Azure2026';
GO

-- Crear usuario para Reportes
CREATE USER ReportUser WITH PASSWORD = 'T1ger!Azure2026';
GO
```

## 2) Permisos directos sobre un objeto

```sql
-- Conceder permisos para un usuario en un objeto
GRANT SELECT, DELETE
    ON SalesLT.Customer
    TO SalesUser;            -- Nombre del usuario

-- Eliminar permisos para un usuario en un objeto
REVOKE SELECT, DELETE
    ON SalesLT.Customer
    TO SalesUser;

-- Denegar permisos para un usuario en un objeto
DENY DELETE
    ON SalesLT.Customer
    TO SalesUser;
```

## 3) Creacion de rol y asignacion de permisos

```sql
-- Creacion de un rol
CREATE ROLE SalesReaders;

-- Conceder permisos SELECT al rol
GRANT SELECT, DELETE
    ON SalesLT.Customer
    TO SalesReaders;         -- Nombre del rol

-- Anadir al usuario como miembro del rol
ALTER ROLE SalesReaders
    ADD MEMBER SalesUser;
```

## 4) Esquema propio y permisos por esquema

```sql
-- Crear un nuevo esquema y una tabla dentro del esquema
CREATE SCHEMA SalesReporting;

CREATE TABLE SalesReporting.CustomerReport
(
    CustomerID INT,
    FullName NVARCHAR(150)
);

INSERT INTO SalesReporting.CustomerReport VALUES (1, 'Borja Cabeza');

-- Conceder permisos de lectura sobre TODO el esquema
GRANT SELECT
    ON SCHEMA::SalesReporting
    TO ReportUser;
```

## 5) Orden de aplicacion de permisos

- Base de datos
- Esquema
- Rol
- Usuario

## 6) Consultas y comprobaciones

```sql
-- Consulta de datos
SELECT * FROM [SalesLT].[Customer];
GO

-- Ver permisos asignados a un rol o usuario
SELECT
    pr.name AS Username,
    pr.type_desc AS LoginType,
    pe.permission_name AS PermissionName,
    pe.state_desc AS State,
    pe.class_desc AS ObjectType,
    OBJECT_NAME(pe.major_id) AS ObjectName
FROM
    sys.database_permissions pe
JOIN
    sys.database_principals pr ON pe.grantee_principal_id = pr.principal_id
WHERE
    pr.name = 'SalesReaders' OR pr.name = 'SalesUser';
GO
```

## 7) Pruebas de ejecucion con contexto de usuario

```sql
EXECUTE AS USER = 'SalesUser';
SELECT * FROM [SalesLT].[Customer];
REVERT;

EXECUTE AS USER = 'SalesUser';
DELETE FROM SalesLT.Customer
    WHERE CustomerID = 2;
REVERT;

EXECUTE AS USER = 'ReportUser';
SELECT * FROM SalesReporting.CustomerReport;
REVERT;
```

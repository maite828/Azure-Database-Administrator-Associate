# Exploración del diseño de base de datos basado en el rendimiento

## Normalización y formas normales

La normalización es el proceso de organizar datos en tablas para reducir la redundancia y evitar anomalías de inserción/actualización/borrado. Afecta directamente al diseño físico y al rendimiento: una normalización excesiva puede aumentar JOINs (más CPU y latencia), mientras que una desnormalización adecuada puede mejorar lecturas a costa de mayor coste en escrituras.

### Primera Forma Normal (1NF)

Regla: cada columna debe contener valores atómicos (no listas ni grupos repetidos) y cada fila debe ser única.

Ejemplo (violación de 1NF - tabla denormalizada):

Tabla `OrdersDenormalized` (ejemplo Northwind simplificado):

| OrderID | CustomerName | CustomerAddress | OrderDate | Items |
|---------|--------------|-----------------|-----------|-------|
| 10248   | Maria A.     | Calle 1         | 1996-07-04| "1xChai;2xQueso" |

`Items` contiene una lista separada por delimitadores → viola 1NF.

Solución: separar los grupos repetidos en filas: crear `OrderDetails` donde cada artículo es una fila.

T-SQL (ejemplo para normalizar):

```sql
-- Crear tablas normalizadas
CREATE TABLE Customers(
	CustomerID INT IDENTITY PRIMARY KEY,
	CustomerCode VARCHAR(20) NOT NULL UNIQUE,
	CompanyName NVARCHAR(100) NOT NULL,
	Address NVARCHAR(200)
);

CREATE TABLE Orders(
	OrderID INT IDENTITY PRIMARY KEY,
	CustomerID INT NOT NULL FOREIGN KEY REFERENCES Customers(CustomerID),
	OrderDate DATE NOT NULL
);

CREATE TABLE Order_Details(
	OrderDetailID INT IDENTITY PRIMARY KEY,
	OrderID INT NOT NULL FOREIGN KEY REFERENCES Orders(OrderID),
	ProductID INT NOT NULL,
	Quantity SMALLINT NOT NULL,
	UnitPrice DECIMAL(10,2) NOT NULL
);
```

Explicación: al convertir `Items` en filas separadas, cada celda almacena un valor atómico y la tabla cumple 1NF.

### Segunda Forma Normal (2NF)

Regla: estar en 1NF y que todas las columnas no-clave dependan de la clave completa (eliminar dependencias parciales en tablas con clave compuesta).

Ejemplo: si tenemos una tabla `OrderDetailsTemp(OrderID, ProductID, ProductName, ProductCategory, Quantity, UnitPrice)` y la clave es (OrderID, ProductID), `ProductName` depende solo de `ProductID` (dependencia parcial) → viola 2NF.

Solución: mover los atributos que dependen sólo de `ProductID` a una tabla `Products`.

T-SQL ejemplo (migración conceptual):

```sql
CREATE TABLE Products(
	ProductID INT PRIMARY KEY,
	ProductName NVARCHAR(200),
	Category NVARCHAR(100)
);

-- Order_Details ya no contiene ProductName ni Category
ALTER TABLE Order_Details
ADD ProductID INT; -- ya estaba en el diseño anterior
```

Explicación: con 2NF las repeticiones de información del producto desaparecen, reduciendo el tamaño de `Order_Details` y coste de actualización al cambiar datos de producto.

### Tercera Forma Normal (3NF)

Regla: estar en 2NF y eliminar dependencias transitivas (columnas que dependen de otras columnas no clave).

Ejemplo: si `Customers` tiene `City` y `City` determina `RegionName`, deberíamos mover `City`/`Region` a una tabla `Cities` para eliminar la dependencia transitiva.

Beneficios y trade-offs: 3NF reduce redundancia y el coste de actualizaciones, pero aumenta la cantidad de JOINs en consultas de lectura.

## Ejemplo práctico Northwind — estado y transformación

1) Estado denormalizado (violación 1NF):

```text
OrdersDenorm
- OrderID
- CustomerCode
- CustomerName
- CustomerAddress
- OrderDate
- ItemList ("ProductID:Qty;ProductID:Qty;...")
```

Problemas: consultas por producto o por cliente son costosas; actualizar dirección del cliente requiere cambiar muchas filas.

2) Aplicando 1NF:

- Separar `ItemList` en filas en `Order_Details`.

3) Aplicando 2NF:

- Extraer `Products` y `Customers` para eliminar dependencias parciales.

Resultado: tablas `Customers`, `Products`, `Orders`, `Order_Details` (modelo relacional clásico de Northwind).

## Ejemplo T-SQL completo (insertar datos simulados)

```sql
-- Insertar cliente
INSERT INTO Customers(CustomerCode, CompanyName, Address)
VALUES('ALFKI','Alfreds Futterkiste','Obere Str. 57');

-- Insertar pedido
INSERT INTO Orders(CustomerID, OrderDate)
VALUES( SCOPE_IDENTITY(), '1996-07-04'); -- simplificado

-- Insertar detalles
INSERT INTO Order_Details(OrderID, ProductID, Quantity, UnitPrice)
VALUES(1, 1, 10, 18.00), (1, 2, 5, 9.50);
```

Explicación: los ejemplo muestran cómo insertar en tablas normalizadas. `SCOPE_IDENTITY()` se usa para obtener la última identidad insertada dentro de la sesión (útil en scripts simplificados).

## Azure CLI y PowerShell — crear recurso de base de datos (contexto)

Usar Azure para desplegar el entorno donde aplicar los T-SQL es común. A continuación ejemplos mínimos y explicaciones.

AZ CLI (crear servidor y base de datos Azure SQL — PaaS):

```bash
az sql server create \
	--name my-sql-server \
	--resource-group my-rg \
	--location westeurope \
	--admin-user sqladmin \
	--admin-password 'P@ssw0rd!'

az sql db create \
	--resource-group my-rg \
	--server my-sql-server \
	--name northwinddb \
	--service-objective S0
```

Explicación: `az sql server create` crea el servidor lógico; `az sql db create` crea la base en modo PaaS. Reemplace credenciales por opciones seguras y use políticas de seguridad para producción.

PowerShell (equivalente con Az module):

```powershell
New-AzSqlServer -ResourceGroupName my-rg -ServerName my-sql-server -Location westeurope -SqlAdministratorCredentials (Get-Credential)
New-AzSqlDatabase -ResourceGroupName my-rg -ServerName my-sql-server -DatabaseName northwinddb -RequestedServiceObjectiveName 'S0'
```

Explicación: `Get-Credential` pedirá credenciales interactivamente. Estas órdenes configuran el entorno para ejecutar los scripts T-SQL.

## Elección de tipos de datos (SQL Server) y su impacto en rendimiento

Elegir tipos adecuados reduce tamaño de fila, mejora densidad en página y reduce I/O.

- Enteros: `tinyint` (0..255), `smallint`, `int`, `bigint`. Use el tipo más pequeño que cubra el rango.
- Números con decimales: `decimal(p,s)`/`numeric(p,s)` para exactitud financiera; `float`/`real` para aproximados.
- Fecha y hora: `date`, `time`, `datetime2`, `datetimeoffset` (este último para zonas horarias).
- Cadenas: `varchar(n)` (ASCII/ansi), `nvarchar(n)` (Unicode, 2 bytes por carácter), `char(n)`/`nchar(n)` para longitud fija.
- Binarios: `varbinary`, `image` (deprecated).
- Identificadores: `uniqueidentifier` (GUID) — grandes (16 bytes), afectan orden físico si se usan como clustered key sin GUID ordenados.

Unicode vs non-Unicode:

- `nvarchar` almacena UTF-16 internamente (2 bytes por carácter en la mayoría de casos). Use `nvarchar` cuando necesite soporte multilenguaje o caracteres Unicode.
- `varchar` es más compacto si solo usa ASCII/latin1.

Tamaño de página y efectos:

- SQL Server usa páginas de 8 KB (8192 bytes). Un extent = 8 páginas = 64 KB.
- Cuanto menor sea el tamaño por fila, más filas caben por página → menos páginas a leer → menor I/O y mejor rendimiento de lectura.
- Tipos `nvarchar(max)`, `varchar(max)` y LOBs pueden almacenarse fuera de la página (row-overflow), afectando rendimiento por accesos adicionales.

Ejemplo de cálculo: `nvarchar(100)` puede consumir hasta 200 bytes por fila (sin contar overhead). Si la fila cabe 40 veces por página → más densidad. Si usa `varchar(100)` y solo caracteres ASCII, consume ~100 bytes → mayor densidad aún.

Recomendaciones:

- Prefiera `int` para claves sustitutas si no necesita `bigint`.
- Evite `nvarchar(max)` si no es necesario; use longitudes apropiadas.
- Para claves clustering, prefiera columnas estrechas, estáticas y monotonamente crecientes (p.ej. identidad).

## Cómo los tipos de datos influyen en lecturas/escrituras

- Filas más anchas → menos filas por página → más I/O para escanear conjuntos de resultados.
- Tipos variables (`varchar`, `nvarchar`) requieren metadata adicional; excesiva fragmentación puede incrementa lecturas de páginas no contiguas.
- LOBs y columnas off-row requieren páginas adicionales y potencialmente lecturas aleatorias.

## Índices: tipos y evaluación

Tipos principales:

- Clustered Index: determina el orden físico de las filas en la tabla. Existe uno por tabla. Ideal en columnas clave primaria si la clave es estrecha y secuencial.
- Nonclustered Index: estructura separada que contiene las columnas indexadas y punteros (RID o clave clustered) a las filas. Puede ser multiple por tabla.
- Unique Index: impone unicidad.
- Filtered Index: índice sobre una porción de filas (útil para estados frecuentes).
- Columnstore Index: optimizado para cargas analíticas (alta compresión, escaneos rápidos).
- Hash / Memory-Optimized Indexes: para tablas in-memory y OLTP de baja latencia.

Clustered vs Nonclustered — evaluación práctica:

- Clustered (pros): lecturas por rango son rápidas; las búsquedas por PK son muy eficientes; reduce un nivel de indirection (no necesita lookup).
- Clustered (cons): reordenamiento al insertar si la clave no es secuencial (p.ej. GUID) → fragmentación y coste de escrituras.

- Nonclustered (pros): múltiples índices para diferentes patrones de consulta; se pueden crear índices cubrientes que eviten lookups.
- Nonclustered (cons): ocupan espacio extra; los cambios en la tabla pueden implicar mantenimiento de múltiples índices (coste en escrituras).

Recomendaciones para modelo Orders/Order_Details/Customers:

- `Customers`: clustered key en `CustomerID` (IDENTITY o `CustomerCode` si natural y estático). Crear índice nonclustered en `CompanyName` si hay búsquedas por nombre.
- `Orders`: clustered en `OrderID` (IDENTITY). Índice nonclustered en `CustomerID, OrderDate` si consultas por cliente y rango de fechas.
- `Order_Details`: clustered puede ser `OrderID, OrderDetailID` o `OrderID, ProductID` dependiendo de consultas; crear nonclustered sobre `ProductID` si se consultan ventas por producto.

Ejemplo T-SQL: creación de índices

```sql
-- Clustered primary keys (ya definidos en tablas anteriores)
ALTER TABLE Orders ADD CONSTRAINT PK_Orders PRIMARY KEY CLUSTERED (OrderID);

-- Índice nonclustered para consultas por cliente y fecha
CREATE NONCLUSTERED INDEX IX_Orders_CustomerDate ON Orders(CustomerID, OrderDate);

-- Índice nonclustered cubriente para Order_Details: cubre Quantity y UnitPrice
CREATE NONCLUSTERED INDEX IX_OrderDetails_Product ON Order_Details(ProductID)
INCLUDE(Quantity, UnitPrice);
```

Explicación: `INCLUDE()` añade columnas no indexadas a la estructura para evitar lookups (útil en consultas de sólo lectura que retornan esas columnas).

## Consejos de diseño y rendimiento para Azure SQL (PaaS) y SQL Server IaaS

- En PaaS, monitorice DTU/Service Objective o vCore; índices mal elegidos pueden incrementar consumo RU y costes.
- Para cargas analíticas en PaaS, considere `columnstore` para tablas de facturación/telemetría.
- Para alta concurrencia OLTP, mantenga índices simples y estrechos, evite columnas LOB en tablas calientes.
- Configure `fillfactor` para índices con muchas inserciones si quiere reducir page-splits; útil para claves no secuenciales.

## Resumen

- Normalizar hasta 3NF evita redundancia y reduce coste de actualización, pero incrementa joins.
- Seleccione tipos de datos estrechos y adecuados (usar `int` vs `bigint`, `varchar` vs `nvarchar`) para mejorar densidad de página y reducir I/O.
- Use clustered index en la clave primaria si es estrecha y secuencial; cree nonclustered y cubriente según patrones de consultas.
- En Azure SQL, el diseño de índices y tipos de datos impacta directamente en costes y rendimiento; monitorice y ajuste según necesidades.
- El diseño de base de datos es un equilibrio entre normalización, tipos de datos y estrategias de indexación para optimizar rendimiento según el caso de uso.
- En entornos de producción, siempre pruebe y monitorice el impacto de cambios en diseño e índices usando herramientas como Query Store, Execution Plans y métricas de rendimiento.
- Recuerde que el diseño óptimo depende del patrón de consultas, volumen de datos y requisitos de rendimiento específicos de su aplicación.
  
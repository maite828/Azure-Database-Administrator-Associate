# Implementación de controles de cumplimiento para datos confidenciales

## Clasificación de Datos

La clasificación de datos consiste en etiquetar los datos según su sensibilidad, valor legal o impacto si se divulgan. Debe realizarse de forma sistemática y apoyada por herramientas automáticas y revisiones manuales.

**¿Por qué clasificar los datos?**
- **Identificación:** Localiza datos sensibles automáticamente (PII, PCI, PHI, secretos).
- **Protección:** Permite aplicar controles diferenciados (encriptación, Data Masking, RLS).
- **Cumplimiento y gobierno:** Facilita auditorías, conservación y reporting para normativas.
- **Gestión de riesgo:** Prioriza esfuerzos y RUs para datos de mayor riesgo.

**Finalidad de la Clasificación de Datos**

- **🔍 Descubrimiento:** Identifica datos sensibles automáticamente usando escaneos y reglas.
- **🛡 Protección:** Permite aplicar políticas como Dynamic Data Masking y cifrado por columna.
- **📊 Gobierno:** Facilita auditorías y evidencias de cumplimiento.
- **📑 Reporting:** Genera informes para compliance y evaluaciones de riesgo.
- **🔐 Seguridad:** Complementa Transparent Data Encryption (TDE) y control de accesos.

**Flujo recomendado después de clasificar**

Clasificar → Evaluar riesgo → Proteger → Auditar → Gobernar → Revisar periódicamente

Explicación rápida:
- Clasificar: automatizar detección y añadir etiquetas/metadata.
- Evaluar riesgo: impacto y probabilidad; priorizar controles.
- Proteger: aplicar enmascaramiento, RLS, cifrado y logging.
- Auditar: revisar accesos y cambios sobre datos sensibles.
- Gobernar: políticas, procedimientos y responsabilidades.
- Revisar: reevaluar clasificación y controles con periodicidad.


**Ejemplos: comandos de clasificación (sensitivities)**

Los siguientes ejemplos muestran cómo consultar, añadir y eliminar clasificaciones de sensibilidad a nivel de columna. Requieren permisos suficientes en la base de datos (por ejemplo `ALTER` en el objeto o roles de seguridad adecuados).

Consultar las clasificaciones existentes:

```sql
SELECT * FROM sys.sensitivity_classifications;
```

Añadir una clasificación a una columna:
- `ADD SENSITIVITY CLASSIFICATION TO` aplica metadata de sensibilidad a la columna indicada.
- `LABEL` y `INFORMATION_TYPE` permiten estandarizar categorías usadas por gobernanza y reporting.

```sql
ADD SENSITIVITY CLASSIFICATION 
TO SalesLT.Customer.MiddleName
WITH (LABEL = 'Confidential', INFORMATION_TYPE = 'Contact Info');
```

Eliminar una clasificación existente:
- `DROP SENSITIVITY CLASSIFICATION FROM` elimina la metadata asociada a la columna.
- No elimina datos ni afecta permisos de acceso; solo quita la etiqueta de sensibilidad.

```sql
DROP SENSITIVITY CLASSIFICATION 
FROM SalesLT.Customer.MiddleName;
```

Notas adicionales:
- Estas clasificaciones son metadata que facilitan discovery, reporting y la aplicación automatizada de controles.
- Tras añadir o quitar clasificaciones, actualice procesos de auditoría y reporting para reflejar cambios.
- Compruebe compatibilidad con herramientas de clasificación automatizada y con políticas de Azure Purview si las usa.
  
&nbsp;

## Seguridad a nivel de fila (RLS) y Dynamic Data Masking (DDM)

**Seguridad a nivel de fila (Row-Level Security, RLS)**

RLS restringe las filas que puede ver o modificar un usuario según una política aplicada en la base de datos.

Ejemplo (Azure SQL Database / SQL Server) — crear función de predicado y política:

```sql
-- Función de predicado que limita filas por tenantId o por usuario
CREATE FUNCTION dbo.fn_predicate(@TenantId INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS fn_result
WHERE @TenantId = CAST(SESSION_CONTEXT(N'tenant_id') AS INT);

-- Política de RLS que usa la función
CREATE SECURITY POLICY dbo.SecurityPolicy
ADD FILTER PREDICATE dbo.fn_predicate(TenantId) ON dbo.Orders,
ADD BLOCK PREDICATE dbo.fn_predicate(TenantId) ON dbo.Orders AFTER INSERT;

ALTER SECURITY POLICY dbo.SecurityPolicy WITH (STATE = ON);
```

**Notas:**
- En escenarios PaaS (Azure SQL Database) y IaaS (SQL Server en VM) la sintaxis y comportamiento son los mismos.
- Use `SESSION_CONTEXT` o `CONTEXT_INFO()` para propagar el tenant/usuario desde la aplicación.

&nbsp;

**Dynamic Data Masking (DDM)** 

Descripción: DDM oculta o enmascara valores sensibles en las consultas resultantes, sin cambiar los datos subyacentes. Es una capa de protección para interfaces y usuarios que no necesitan ver los valores completos.

Ejemplo básico:

```sql
-- Añadir máscara a una columna
ALTER TABLE dbo.Customers
ALTER COLUMN Email ADD MASKED WITH (FUNCTION = 'email()');

-- Quitar máscara
ALTER TABLE dbo.Customers
ALTER COLUMN Email DROP MASKED;
```

Ejemplos de funciones de máscara comunes:
- `default()` — reemplaza por una constante por tipo.
- `email()` — preserves parcialmente formato de email.
- `partial(prefix, padding, suffix)` — máscara personalizada por trozos.

**Importante:**
- DDM no es un control criptográfico ni sustituto del cifrado; es una protección para reducir exposición accidental.
- Combine DDM con políticas de acceso, RLS, y auditoría.

**Buenas prácticas de implementación**
- Identificar roles que necesitan ver datos completos y otorgarles permiso `UNMASK`.
- Documentar y revisar máscaras en conjunto con clasificación.
- Registrar accesos y excepciones en auditoría.
  
&nbsp;

## Libro de contabilidad (Ledger) de Azure SQL Database

Concepto:
El ledger de Azure SQL Database (ledger) proporciona un registro inmutable y verificable de los cambios en los datos. Internamente usa una cadena de hashes criptográficos para enlazar versiones de filas, lo que permite probar que los datos no han sido alterados (integridad histórica).

Principales características:
- Añade un componente de integridad: cada cambio produce entradas con hash que se encadenan.
- Permite emitir pruebas (proofs) que pueden verificarse fuera de la base de datos.
- Útil para escenarios que requieren evidencia inmutable (contabilidad, contratos, auditoría forense).

Uso general:
- Diseñar tablas y procesos sabiendo que las operaciones ledger pueden añadir coste de almacenamiento y CPU.
- Hacer copias de seguridad y exportar evidencias cuando sea necesario para auditoría externa.

Nota técnica y enlaces: la habilitación y comandos concretos pueden cambiar; consulte la documentación oficial para pasos y ejemplos de habilitación y verificación del ledger.

&nbsp;

## Microsoft Defender for SQL (antes Advanced Threat Protection)

Qué ofrece:
- Detección de amenazas en tiempo real: anomalías en queries, accesos anómalos, actividades sospechosas.
- Vulnerability Assessment: escaneos automáticos con recomendaciones de hardening.
- Integración con Azure Security Center y alertas centralizadas.

Cómo usarlo (resumen):
- Activar Defender for SQL desde el portal Azure o mediante políticas de seguridad.
- Revisar hallazgos de Vulnerability Assessment y aplicar remediaciones.
- Configurar alertas y exportar logs a Log Analytics / SIEM.

Ejemplo rápido (conceptual):

- Activación en portal: `Defender for SQL` → habilitar para servidor/instancia → revisar recomendaciones.
- Integrar con `Azure Monitor`/`Log Analytics` para conservar y procesar alertas.

Buenas prácticas:
- Tratar las alertas como señales de investigación: correlacionar con logs de auditoría.
- Programar escaneos regulares de Vulnerability Assessment.
- Asegurar que la cuenta que gestiona Defender tenga permisos mínimos necesarios.
- 
&nbsp;

## Referencias y enlaces de interés

- Documentación oficial Azure SQL: https://learn.microsoft.com/azure/azure-sql/
- Dynamic Data Masking: https://learn.microsoft.com/azure/azure-sql/database/dynamic-data-masking-overview
- Row-Level Security: https://learn.microsoft.com/sql/relational-databases/security/row-level-security
- Azure SQL Ledger (buscar "ledger" en docs de Azure SQL): https://learn.microsoft.com/azure/azure-sql/
- Microsoft Defender for SQL: https://learn.microsoft.com/azure/defender-for-cloud/defender-for-sql

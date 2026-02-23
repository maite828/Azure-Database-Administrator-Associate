# Supervisión y optimización de los recursos operativos en Azure SQL

## Contenidos

## 01 - Descripción y herramientas de supervisión
- [01 Descripción de la supervisión de rendimiento](01%20Descripci%C3%B3n%20de%20la%20supervisi%C3%B3n%20de%20rendimiento.md): Conceptos clave sobre líneas de base, métricas importantes, Azure Monitor, eventos extendidos, monitores de base de datos y cómo ver el rendimiento de consultas en el Portal de Azure.
	- [Diagnostic settings en el Portal de Azure](01.a%20Diagnostic%20settings%20en%20el%20Portal%20de%20Azure.md): Guía paso a paso para configurar `Diagnostic settings` en el Portal y rutas de exportación a Log Analytics, Storage y Event Hub.
	- [Eventos Extendidos](01.b%20Eventos%20Extendidos.md): Ejemplo y documentación general de Extended Events (sesión a nivel de base de datos) con T-SQL, parsing del `ring_buffer` y recomendaciones.
	- [Eventos Extendidos](01.c%20Eventos%20Extendidos.md): Variante que escribe `.xel` en Azure Blob Storage; incluye creación de `MASTER KEY` y `DATABASE SCOPED CREDENTIAL` y procedimientos para actualización.
	- [Generar SAS y actualizar credencial](01.d%20Generar%20SAS%20y%20actualizar%20credencial.md): Scripts de ejemplo (PowerShell y az CLI) para generar SAS y actualizar la `DATABASE SCOPED CREDENTIAL` desde la línea de comandos.


# E-commerce Analytics — De Datos Crudos a Decisiones de Negocio

Jaime Lopez Garrido

Contacto:
- jaime.lopez.garrido@gmail.com
- LinkedIn: www.linkedin.com/in/jaime-lopez-garrido-1b274221b

Pipeline de datos end-to-end (MySQL) + modelo estrella + dashboard en Power BI, desde la ingesta de datos crudos hasta un modelo dimensional limpio, listo para autoservicio. Lo armé para responder preguntas de negocio concretas: cuánto vendemos, qué tan rentable es cada venta después de descuentos y cancelaciones, y qué productos y clientes generan más valor.

Este repositorio muestra el trabajo completo: los scripts SQL que arman el pipeline y el modelo dimensional, y el archivo `.pbix` con el dashboard ya construido sobre ese modelo.

---

## Tabla de contenidos

- [Arquitectura del pipeline](#arquitectura-del-pipeline)
- [Estructura del repositorio](#estructura-del-repositorio)
- [Modelo de datos (esquema estrella)](#modelo-de-datos-esquema-estrella)
- [Decisiones y desafíos técnicos en SQL](#decisiones-y-desafíos-técnicos-en-sql)
- [KPIs calculados en SQL](#kpis-calculados-en-sql)
- [Vistas para Power BI](#vistas-para-power-bi)
- [El dashboard (ecommerce_analytics.pbix)](#el-dashboard-ecommerce_analyticspbix)
- [Instrucciones de ejecución](#instrucciones-de-ejecución)
- [Stack técnico](#stack-técnico)

---

## Arquitectura del pipeline

El proyecto sigue una arquitectura de capas: raw → clean → modelado → consumo.

```
┌──────────────────┐     ┌──────────────────┐     ┌───────────────────┐     ┌──────────────────────┐
│   ARCHIVOS CSV    │     │   STAGING (raw)   │     │   CLEAN LAYER      │     │  STAR SCHEMA          │
│  orders.csv        │────▶│  stg_orders       │────▶│  clean_orders      │────▶│  dim_customers        │
│  order_items.csv   │     │  stg_order_items  │     │  clean_order_items │     │  dim_products         │
└──────────────────┘     └──────────────────┘     └───────────────────┘     │  dim_date              │
        script 01               script 01                script 02          │  fact_sales             │
                                                                              └───────────┬───────────┘
                                                                                          │ script 03
                                                                                          ▼
                                                                     ┌──────────────────────────────────┐
                                                                     │   VISTAS MART (script 04)         │
                                                                     │   vw_sales_analysis                │
                                                                     │   vw_customer_kpis                 │
                                                                     └────────────────┬─────────────────┘
                                                                                      │
                                                                                      ▼
                                                                        ┌──────────────────────┐
                                                                        │      POWER BI          │
                                                                        │  ecommerce_analytics.pbix│
                                                                        └──────────────────────┘
```

Decidí separar el proyecto en estas capas porque es la forma en la que trabajaría en un equipo real de datos: los datos crudos nunca se tocan directamente, cada capa se puede reconstruir desde cero corriendo los scripts en orden, y si algo sale mal en el medio del proceso, es fácil identificar en qué paso se rompió sin tener que revisar todo el pipeline de una.

También traté de dejar la mayor parte de la lógica de negocio resuelta en SQL (agregaciones, joins, cálculo de descuentos) para que Power BI reciba las vistas casi listas para usar, y las medidas DAX que armé en el tablero terminaran siendo pocas y simples.

---

## Estructura del repositorio

```
ecommerce_analytics/
│
├── 01_schema_and_staging.sql      -- creación de bd + tablas de staging (raw)
├── 02_data_cleaning.sql           -- deduplicación, tipado, estandarización e imputación
├── 03_dimensional_modeling.sql    -- construcción del star schema (dims + fact)
├── 04_views_and_kpis.sql          -- vistas para Power BI + validación de KPIs
├── ecommerce_analytics.pbix       -- dashboard de Power BI, construido sobre las vistas
├── vw_sales_analysis.csv          -- export de la vista, por si no querés conectar en vivo a MySQL
├── vw_customer_kpis.csv           -- export de la vista, por si no querés conectar en vivo a MySQL
└── README.md                      -- este documento
```

| Script | Responsabilidad | Salida |
|---|---|---|
| `01_schema_and_staging.sql` | Creación de la base de datos e ingesta cruda | `stg_orders`, `stg_order_items` |
| `02_data_cleaning.sql` | Limpieza, deduplicación (`row_number()`), tipado explícito e imputación de nulos | `clean_orders`, `clean_order_items` |
| `03_dimensional_modeling.sql` | Modelado dimensional en esquema estrella | `dim_customers`, `dim_products`, `dim_date`, `fact_sales` |
| `04_views_and_kpis.sql` | Vistas de consumo + queries de validación de KPIs | `vw_sales_analysis`, `vw_customer_kpis` |

Incluí los CSV exportados de las dos vistas junto con el `.pbix` para que cualquiera pueda abrir el dashboard y ver los datos sin tener que levantar una instancia de MySQL primero. La idea es que el pipeline SQL se pueda correr de forma independiente si alguien quiere reproducir todo desde cero, pero el dashboard no depende de eso para poder revisarse.

---

## Modelo de datos (esquema estrella)

```
                         ┌───────────────────────┐
                         │     dim_customers     │
                         │ ───────────────────── │
                         │ customer_id (PK)      │
                         │ first_name            │
                         │ last_name             │
                         │ email                 │
                         │ city                  │
                         │ country               │
                         │ signup_date           │
                         │ segment               │
                         └───────────┬───────────┘
                                     │
┌───────────────────────┐           │          ┌───────────────────────┐
│      dim_products     │           │          │        dim_date       │
│ ───────────────────── │           │          │ ───────────────────── │
│ product_id (PK)       │           │          │ date_id (PK)          │
│ product_name          │           │          │ full_date             │
│ category              │           │          │ year / quarter / month│
│ unit_price            │           │          │ month_name            │
└───────────┬───────────┘           │          │ day / day_of_week_name│
            │                       │          └───────────┬───────────┘
            │                       │                      │
            │           ┌───────────▼───────────┐          │
            └──────────▶│       fact_sales          │◀─────────┘
                        │ ───────────────────── │
                        │ order_item_id (PK)    │
                        │ order_id              │
                        │ customer_id (FK)      │
                        │ product_id (FK)       │
                        │ date_id (FK)          │
                        │ order_date            │
                        │ quantity              │
                        │ unit_price            │
                        │ discount_pct          │
                        │ gross_revenue         │
                        │ discount_amount       │
                        │ net_revenue           │
                        │ status                │
                        └───────────────────────┘
```

El grano de `fact_sales` es una fila por línea de ítem de orden (`order_item_id`). Elegí ese nivel de detalle, y no la orden completa, porque es el más granular disponible: desde ahí se puede reagregar libremente por cliente, producto, categoría, fecha o estado sin perder información, mientras que si hubiera agregado a nivel de orden habría perdido la posibilidad de analizar por producto o categoría.

Las claves de cliente y producto (`customer_id`, `product_id`) las dejé como clave natural en vez de generar una clave subrogada, porque en este dataset no hay necesidad de trackear históricos de cambios (SCD tipo 2) — con sobrescribir el dato más reciente alcanza para lo que necesita el análisis.

---

## Decisiones y desafíos técnicos en SQL

Algunas cosas que fui resolviendo mientras armaba el pipeline, y que me parece vale la pena dejar documentadas porque muestran cómo se llegó al resultado final:

**Deduplicación con `row_number()`.** Tanto `stg_orders` como `stg_order_items` pueden tener registros duplicados si el proceso de carga se corrió más de una vez. En vez de usar `distinct` (que no permite elegir cuál registro conservar), uso `row_number() over (partition by ... order by loaded_at desc)` y me quedo solo con `rn = 1`, así siempre se conserva la versión más reciente de cada fila.

**Conversión de texto a número, con datos sucios.** Los campos `discount_pct`, `quantity` y `unit_price` llegan como texto desde el staging, y en la práctica los datos crudos traían caracteres que rompían la conversión directa a `decimal` (por ejemplo el símbolo `%`, o comas usadas como separador decimal en vez de punto). La solución que terminé aplicando fue: limpiar el texto con `replace()`, validar con una expresión regular (`regexp`) que lo que queda sea realmente un número, y recién ahí hacer el `cast()`. Los valores que no pasan esa validación quedan nulos y se imputan después con un valor por defecto (0 para descuentos y cantidades faltantes). Separé esto en pasos (insertar el texto crudo primero, convertir después con un `update`) en vez de hacerlo todo en una sola consulta, porque mezclar conversión de texto a decimal con manejo de nulos dentro de un mismo `insert into ... select` me generaba errores de MySQL (error 1366) que no eran evidentes de resolver de otra forma.

**Imputación de emails faltantes.** Cuando el email viene nulo o vacío, genero uno sintético con el patrón `cliente_{customer_id}@sindatos.com`. La idea es no perder esa fila del análisis solo por un dato faltante, pero dejando explícito (con el dominio `sindatos.com`) que ese email no es real, para que no se confunda con un dato válido si alguien lo mira más adelante.

**`dim_date` generada con una CTE recursiva.** En vez de cargar un calendario desde un archivo externo, genero la tabla de fechas dinámicamente con `with recursive`, cubriendo el rango exacto que existe en `clean_orders` (de la fecha más antigua a la más nueva). Esto hace que la tabla de fechas siempre esté sincronizada con los datos reales, sin mantenimiento manual.

**`fact_sales` con métricas ya calculadas.** Calculo `gross_revenue`, `discount_amount` y `net_revenue` directamente en SQL al armar la tabla de hechos, en vez de dejar esas cuentas para que se resuelvan en Power BI. Esto simplifica bastante las medidas DAX del lado del reporte, y además asegura que cualquier otra herramienta que se conecte a esta base (no solo Power BI) va a ver los mismos números.

---

## KPIs calculados en SQL

El script `04_views_and_kpis.sql` incluye, además de las vistas, un set de consultas de validación que calculan los KPIs principales directamente en SQL. Esto sirve para poder chequear que las tarjetas y medidas del dashboard coincidan con lo que da la base de datos, sin depender únicamente de lo que muestra Power BI.

| KPI | Cómo se calcula | Por qué lo mido |
|---|---|---|
| Total Revenue / Net Revenue | Suma de `gross_revenue` vs. suma de `net_revenue` (bruto menos descuentos) | El bruto sobreestima lo que realmente entra al negocio; el neto es la plata real después de promociones |
| AOV (ticket promedio) | Net revenue de órdenes válidas dividido cantidad de esas órdenes | Mide cuánto deja en promedio cada compra, útil para pensar estrategias de upsell |
| Unidades vendidas | Suma de `quantity` en órdenes válidas | Da una idea del volumen operativo, útil para pensar inventario o logística |
| Frecuencia de compra | Órdenes por mes activo de cada cliente (en `vw_customer_kpis`) | Es una aproximación de qué tan recurrente es un cliente |
| Lifetime value (LTV básico) | Suma histórica de `net_revenue` por cliente | Ayuda a identificar qué clientes valen más para el negocio |
| Tasa de cancelación / devolución | Porcentaje de órdenes con status `cancelled` o `returned` sobre el total | Señala fricción en el proceso de compra |
| Top 5 productos | `dense_rank()` sobre unidades vendidas por producto | Prioriza qué productos mirar primero para inventario o marketing |
| Ventas acumuladas y variación mes a mes | `sum() over()` para el acumulado y `lag()` para comparar contra el mes anterior | Permite ver tendencia y detectar caídas o subas fuera de lo esperado |

---

## Vistas para Power BI

### `vw_sales_analysis`
Vista a nivel de línea de venta (26 columnas), con todos los atributos de las dimensiones ya resueltos vía join: fecha (`order_date`, `year`, `quarter`, `month`, `month_name`, `day_of_week_name`), cliente (`customer_id`, `first_name`, `last_name`, `email`, `city`, `country`, `segment`), producto (`product_id`, `product_name`, `category`) y las métricas de venta (`quantity`, `unit_price`, `discount_pct`, `gross_revenue`, `discount_amount`, `net_revenue`, `status`). Agrego también una columna `is_valid_sale` (0 o 1) que marca si la orden está cancelada o devuelta, para poder filtrar rápido sin tener que repetir la lista de estados en cada medida DAX.

Es la tabla principal del modelo en Power BI: casi todos los visuales del dashboard se arman directamente sobre esta vista.

### `vw_customer_kpis`
Vista agregada a nivel de cliente (una fila por `customer_id`), con `total_orders`, `first_order_date`, `last_order_date`, `customer_lifespan_days`, `lifetime_value`, `avg_order_value` y `purchase_frequency_monthly` ya calculados. La uso en la página de comportamiento del cliente del dashboard, para no tener que recalcular estas métricas con DAX.

---

## El dashboard (ecommerce_analytics.pbix)

El archivo `ecommerce_analytics.pbix` se conecta a las dos vistas (`vw_sales_analysis` y `vw_customer_kpis`), cargadas en modo importación. Tiene tres páginas.

### Medidas DAX

Como la mayoría de los cálculos ya vienen resueltos desde SQL, terminé necesitando solo cuatro medidas del lado de Power BI:

```dax
Ingresos Netos = SUM(vw_sales_analysis[net_revenue])
```
Es el net revenue total. La dejé como medida (y no como columna calculada) para que se recalcule automáticamente según los filtros que se apliquen en cada visual o slicer.

```dax
total_orders = DISTINCTCOUNT(vw_sales_analysis[order_id])
```
Cuento órdenes distintas y no filas, porque `vw_sales_analysis` está a nivel de línea de ítem: una misma orden puede tener varias filas si tiene varios productos.

```dax
Ticket_Promedio_AOV = DIVIDE([Ingresos Netos], [total_orders])
```
El AOV a nivel de reporte, usando `DIVIDE()` en vez de una división directa para evitar errores si en algún filtro `total_orders` da cero.

```dax
tasa_cancelacion = 
    DIVIDE(
        CALCULATE(DISTINCTCOUNT(vw_sales_analysis[order_id]), vw_sales_analysis[is_valid_sale] = 0),
        DISTINCTCOUNT(vw_sales_analysis[order_id])
    )
```
Divide las órdenes marcadas como no válidas (`is_valid_sale = 0`, es decir canceladas o devueltas) sobre el total de órdenes. Esta medida es la que justifica haber armado la columna `is_valid_sale` directamente en SQL: si no la tuviera, tendría que repetir la lista de estados (`'cancelled'`, `'returned'`, etc.) dentro de la medida DAX cada vez que la necesito.

Una decisión que quiero dejar anotada: para el eje de tiempo del dashboard usé la jerarquía de fechas automática que genera Power BI sobre `order_date` (dentro de `vw_sales_analysis`), en vez de conectar `dim_date` como tabla separada relacionada por `date_id`. Es más simple de armar y para este dashboard puntual no hacía falta más que eso, pero en un proyecto más grande, o si se necesitara controlar cosas como año fiscal personalizado o feriados, lo correcto sería usar `dim_date` como tabla de fechas real relacionada al modelo, tal como está pensada en el esquema estrella.

### Página 1: Executive Overview

Pensada para una vista rápida del estado general del negocio.

- Tarjetas: Ingresos Netos, cantidad de órdenes (`total_orders`), ticket promedio (`Ticket_Promedio_AOV`) y tasa de cancelación.
- Gráfico de líneas: evolución de Ingresos Netos a lo largo del tiempo (`order_date`).
- Gráfico de columnas: Ingresos Netos por segmento de cliente (`segment`).
- Slicers: segmento, país, categoría de producto, año y estado de la orden (`status`).

### Página 2: Análisis de Producto

- Matriz: categorías de producto en filas, meses en columnas, con Ingresos Netos como valor. La armé como matriz y no como tabla plana porque permite ver de un vistazo qué categorías tuvieron mejor o peor desempeño mes a mes, sin tener que cruzar varios gráficos.
- Gráfico de barras horizontales: top de productos por unidades vendidas (`quantity`), la versión visual del `dense_rank()` que ya había calculado en el script 04.

### Página 3: Comportamiento del Cliente

- Mapa: Ingresos Netos por país y ciudad, para ver de dónde viene la facturación geográficamente.
- Gráfico de dispersión (scatter): un punto por cliente, con frecuencia de compra mensual en el eje X y lifetime value en el eje Y. La idea de este gráfico es poder identificar de un vistazo a los clientes que compran seguido y además dejan mucha plata (arriba a la derecha), separados de los que compran poco o dejan poco valor.
- Tabla: listado de clientes con nombre, segmento, lifetime value y ticket promedio, para poder revisar el detalle de clientes puntuales además de verlos en el scatter.

---

## Instrucciones de ejecución

### Prerrequisitos
- MySQL 8.0 o superior (se usan window functions y CTEs recursivas).
- Un cliente SQL (MySQL Workbench, DBeaver, línea de comandos, etc.).
- Power BI Desktop, si querés abrir o modificar el dashboard.
- Archivos fuente `orders.csv` y `order_items.csv`, con la estructura descrita en este documento.

### Para reconstruir el pipeline SQL desde cero

1. Clonar el repositorio:
   ```bash
   git clone https://github.com/<tu-usuario>/ecommerce_analytics.git
   cd ecommerce_analytics
   ```

2. Ejecutar los scripts en orden estricto (cada uno depende del anterior), en una misma sesión de tu cliente MySQL:
   ```bash
   mysql -u <usuario> -p < 01_schema_and_staging.sql
   mysql -u <usuario> -p < 02_data_cleaning.sql
   mysql -u <usuario> -p < 03_dimensional_modeling.sql
   mysql -u <usuario> -p < 04_views_and_kpis.sql
   ```
   También se puede abrir cada archivo en MySQL Workbench y ejecutarlo completo en el orden 01 → 02 → 03 → 04.

3. Cargar los datos crudos a `stg_orders` / `stg_order_items`, si todavía no están cargados: se puede usar el Table Data Import Wizard de MySQL Workbench, o los `load data infile` comentados dentro de `01_schema_and_staging.sql`.

4. Validar los KPIs corriendo las consultas de la sección 3 de `04_views_and_kpis.sql`, para confirmar que la limpieza y el modelado dieron los resultados esperados.

### Para ver el dashboard

La forma más simple es abrir directamente `ecommerce_analytics.pbix` en Power BI Desktop; ya viene con los datos cargados desde los CSV incluidos en el repositorio (`vw_sales_analysis.csv` y `vw_customer_kpis.csv`).

Si en cambio se quiere que el dashboard lea en vivo desde una base de datos MySQL propia (por ejemplo después de correr el pipeline con datos nuevos):
1. En Power BI Desktop, ir a Inicio → Obtener datos → Base de datos MySQL.
2. Conectar con el servidor y base `ecommerce_analytics`.
3. Seleccionar `vw_sales_analysis` y `vw_customer_kpis`, y reemplazar el origen de los datos actuales por esta conexión (Transformar datos → Editor de Power Query → cambiar el paso "Origen" de cada tabla).
4. Modo de conexión recomendado: importación, para que las medidas y visuales respondan rápido.

---

## Stack técnico

- Base de datos: MySQL 8.0+ (CTEs, window functions, CTEs recursivas)
- Modelado: esquema estrella (Kimball)
- Visualización: Power BI Desktop
- Lenguaje: SQL estándar ANSI + extensiones de MySQL, DAX para las medidas del reporte

---

### Autor

Proyecto desarrollado por Jaime Lopez Garrido como parte de un portafolio de Data Analyst, mostrando el proceso completo: desde datos crudos con problemas reales de calidad, pasando por un modelo dimensional prolijo, hasta un dashboard funcional en Power BI.

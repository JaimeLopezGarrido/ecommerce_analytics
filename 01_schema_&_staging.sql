-- =====================================================================
-- script 01: creación de base de datos y tablas de staging (raw layer)
-- proyecto ecommerce_analytics
-- Este codigo define el esquema inicial y las tablas de staging que
-- cargan los datos crudos desde los archivos fuente orders.csv y 
-- order_items.csv que estan en la carpeta 'data'.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. creación de la base de datos
-- ---------------------------------------------------------------------
drop database if exists ecommerce_analytics;

create database ecommerce_analytics
    character set utf8mb4
    collate utf8mb4_unicode_ci;

use ecommerce_analytics;

-- ---------------------------------------------------------------------
-- 2. tabla de staging: stg_orders
-- almacena los datos crudos tal como llegan.
-- ---------------------------------------------------------------------
create table stg_orders (
    order_id        varchar(20),
    customer_id     varchar(20),
    first_name      varchar(100),
    last_name       varchar(100),
    email           varchar(150),
    city            varchar(100),
    country         varchar(100),
    signup_date     varchar(20),
    segment         varchar(50),
    order_date      varchar(20),
    status          varchar(30),
    discount_pct    varchar(20),
    loaded_at       timestamp default current_timestamp
);

-- ---------------------------------------------------------------------
-- 3. tabla de staging: stg_order_items
-- almacena los datos crudos de los ítemsde cada orden.
-- ---------------------------------------------------------------------
create table stg_order_items (
    order_item_id   varchar(20),
    order_id        varchar(20),
    product_id      varchar(20),
    product_name    varchar(150),
    category        varchar(100),
    quantity        varchar(20),
    unit_price      varchar(20),
    loaded_at       timestamp default current_timestamp
);

-- ---------------------------------------------------------------------
-- 4. carga de datos
-- ajustar la ruta local del archivo antes de ejecutar. 
-- Si te da el "Error 2068", hace lo siguiente:
-- 1. Anda al menú superior: Database, Manage Connections...
-- 2. Selecciona tu conexión y entra a la pestaña "Advanced".
-- 3. En la casilla "Others:", agrega la línea: OPT_LOCAL_INFILE=1
-- 4. Guarda, cierra la ventana y volve a abrir tu conexión.
-- ---------------------------------------------------------------------
-- Habilitar variable en el servidor para esta sesión
set global local_infile = 1;

-- cargo orders.csv
truncate table stg_orders;

load data local infile '/Users/jaimelopezgarrido/Desktop/Documentos/Cursos/SQL/proyectos_sql/data/orders.csv' # Cambia tu ruta
into table stg_orders
fields terminated by ','
enclosed by '"'
lines terminated by '\n'
ignore 1 rows
(order_id, customer_id, first_name, last_name, email, city, country, signup_date, segment, order_date, status, discount_pct);

select *
from stg_orders;

-- cargo order_items.csv
truncate table stg_order_items;

load data local infile '/Users/jaimelopezgarrido/Desktop/Documentos/Cursos/SQL/proyectos_sql/data/order_items.csv' # Cambia tu ruta
into table stg_order_items
fields terminated by ','
enclosed by '"'
lines terminated by '\n'
ignore 1 rows
(order_item_id, order_id, product_id, product_name, category, quantity, unit_price);

select *
from stg_order_items;

-- ---------------------------------------------------------------------
-- 5. índices básicos de staging para acelerar el proceso de limpieza
-- ---------------------------------------------------------------------
create index ix_stg_orders_order_id on stg_orders (order_id);
create index ix_stg_order_items_order_id on stg_order_items (order_id);

-- ---------------------------------------------------------------------
-- 6. verificación rápida de la carga
-- ---------------------------------------------------------------------
select count(*) as total_stg_orders from stg_orders;
select count(*) as total_stg_order_items from stg_order_items;

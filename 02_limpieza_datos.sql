use ecommerce_analytics;

-- =====================================================================
-- script 02: limpieza y preparación de datos 
-- El codigo deduplica, tipa explícitamente, estandariza texto e
-- imputa valores nulos/faltantes a partir de las tablas de staging,
-- generando las tablas limpias "clean" que pasaran el modelo dimensional.
--
-- Se guardan primero los datos como texto y después se convierten a 
-- número con update para evitar que MySQL falle por un error conocido.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. limpieza de stg_orders a clean_orders
-- ---------------------------------------------------------------------

-- 1.1: me quedo con el registro más reciente por order_id, 
-- según la fecha de carga

drop temporary table if exists tmp_orders_dedup;

create temporary table tmp_orders_dedup as
select *
from (
    select
        *,
        row_number() over (
            partition by order_id
            order by loaded_at desc
        ) as rn
    from stg_orders
    where order_id is not null
      and order_id <> ''
) as ranked
where rn = 1;

-- 1.2: creo la tabla final clean_orders

drop table if exists clean_orders;

create table clean_orders (
    order_id            varchar(20)     not null,
    customer_id         varchar(20),
    first_name          varchar(100),
    last_name           varchar(100),
    email               varchar(150),
    city                varchar(100),
    country             varchar(100),
    signup_date         date,
    segment              varchar(50),
    order_date          date            not null,
    status               varchar(30),
    discount_pct_raw     varchar(20), # columna temporal de texto
    discount_pct         decimal(5,2),
    primary key (order_id)
);

-- 1.3: inserto los datos ya estandarizados (texto y fechas),
-- pero el descuento se inserta todavía como texto crudo (discount_pct_raw)
insert into clean_orders (
    order_id, customer_id, first_name, last_name, email,
    city, country, signup_date, segment, order_date, status, discount_pct_raw
)
select
    trim(order_id)                                        as order_id,
    trim(customer_id)                                      as customer_id,
    -- estandarización de nombres: primera letra en mayúscula, resto en minúscula
    concat(
        upper(left(trim(first_name), 1)),
        lower(substring(trim(first_name), 2))
    )                                                       as first_name,
    concat(
        upper(left(trim(last_name), 1)),
        lower(substring(trim(last_name), 2))
    )                                                       as last_name,
    -- email en minúsculas, con imputación sintética si viene nulo/vacío
    case
        when email is null or trim(email) = '' then
            concat('cliente_', trim(customer_id), '@sindatos.com')
        else lower(trim(email))
    end                                                     as email,
    -- estandarización de ciudad (capitalización) y país (mayúsculas)
    concat(
        upper(left(trim(city), 1)),
        lower(substring(trim(city), 2))
    )                                                       as city,
    upper(trim(country))                                    as country,
    -- tipado explícito de fecha de registro, con manejo de formatos inválidos
    case
        when signup_date is not null and signup_date <> ''
             and str_to_date(signup_date, '%Y-%m-%d') is not null
        then str_to_date(signup_date, '%Y-%m-%d')
        else null
    end                                                     as signup_date,
    -- segmento estandarizado, con valor por defecto para nulos/vacíos
    coalesce(nullif(trim(segment), ''), 'sin segmento')     as segment,
    -- tipado explícito de fecha de orden
    str_to_date(order_date, '%Y-%m-%d')                     as order_date,
    -- estatus estandarizado en minúsculas, con valor por defecto
    coalesce(nullif(lower(trim(status)), ''), 'desconocido') as status,
    -- el descuento se guarda tal cual, como texto, y se convierte
    -- a decimal más abajo con un update
    trim(discount_pct)                                      as discount_pct_raw
from tmp_orders_dedup
where
    -- se descartan órdenes sin fecha de pedido válida, ya que son
    -- imprescindibles para el análisis temporal posterior
    order_date is not null
    and order_date <> ''
    and str_to_date(order_date, '%Y-%m-%d') is not null;

drop temporary table if exists tmp_orders_dedup;

-- 1.4: convierto discount_pct de texto a decimal, con un update
-- separado (esto es lo que evita el bug de mysql)

-- 1.4.a: limpio caracteres especiales (% y comas) antes de hacer el cast a decimal
update clean_orders
set discount_pct = cast(
    replace(replace(trim(discount_pct_raw), '%', ''), ',', '.') 
    as decimal(5,2)
)
where discount_pct_raw is not null
  and trim(discount_pct_raw) <> ''
  -- para que solo intente castear valores que sean puramente numéricos
  and replace(replace(trim(discount_pct_raw), '%', ''), ',', '.') regexp '^-?[0-9]+(\.[0-9]+)?$';
-- 1.4.b: para los que quedaron nulos imputo con 0
update clean_orders
set discount_pct = 0.00
where discount_pct is null;

-- 1.5: elimino la columna temporal de texto
alter table clean_orders
    drop column discount_pct_raw;

create index ix_clean_orders_customer on clean_orders (customer_id);
create index ix_clean_orders_date on clean_orders (order_date);

-- ---------------------------------------------------------------------
-- 2. limpieza de stg_order_items a clean_order_items
-- ---------------------------------------------------------------------

-- 2.1: deduplicar por order_item_id
drop temporary table if exists tmp_items_dedup;

create temporary table tmp_items_dedup as
select *
from (
    select
        *,
        row_number() over (
            partition by order_item_id
            order by loaded_at desc
        ) as rn
    from stg_order_items
    where order_item_id is not null
      and order_item_id <> ''
) as ranked
where rn = 1;

-- 2.2: creo la tabla final clean_order_items
-- quantity_raw y unit_price_raw son columnas temporales de texto, sólo
-- para guardar el valor crudo. 
drop table if exists clean_order_items;

create table clean_order_items (
    order_item_id     varchar(20)     not null,
    order_id          varchar(20)     not null,
    product_id        varchar(20),
    product_name      varchar(150),
    category          varchar(100),
    quantity_raw      varchar(20),
    unit_price_raw    varchar(20),
    quantity          int,
    unit_price        decimal(10,2),
    primary key (order_item_id)
);

-- 2.3: insertar los datos ya estandarizados (texto), pero cantidad
-- y precio unitario se insertan todavía como texto crudo
insert into clean_order_items (
    order_item_id, order_id, product_id, product_name, category,
    quantity_raw, unit_price_raw
)
select
    trim(order_item_id)                                     as order_item_id,
    trim(order_id)                                          as order_id,
    trim(product_id)                                        as product_id,
    trim(product_name)                                      as product_name,
    coalesce(nullif(trim(category), ''), 'sin categoría')   as category,
    trim(quantity)                                          as quantity_raw,
    trim(unit_price)                                        as unit_price_raw
from tmp_items_dedup
where order_id is not null
  and order_id <> '';

drop temporary table if exists tmp_items_dedup;

-- 2.4: convierto quantity y unit_price de texto a numérico

-- 2.4.a: quantity - convierto los valores válidos
update clean_order_items
set quantity = cast(quantity_raw as signed)
where quantity_raw is not null
  and quantity_raw <> '';

-- 2.4.b: quantity - imputo 0 en los que quedaron nulos
update clean_order_items
set quantity = 0
where quantity is null;

-- 2.4.c: unit_price - convierto los valores válidos
update clean_order_items
set unit_price = cast(unit_price_raw as decimal(10,2))
where unit_price_raw is not null
  and unit_price_raw <> '';

-- 2.4.d: unit_price - imputo 0.00 en los que quedaron nulos
update clean_order_items
set unit_price = 0.00
where unit_price is null;

-- paso 2.5: elimino las columnas temporales de texto
alter table clean_order_items
    drop column quantity_raw,
    drop column unit_price_raw;

-- paso 2.6: elimino líneas con cantidad 0 o negativa (dato inválido)
delete from clean_order_items
where quantity <= 0;

create index ix_clean_items_order on clean_order_items (order_id);
create index ix_clean_items_product on clean_order_items (product_id);

-- ---------------------------------------------------------------------
-- 3. validación rápida de calidad de datos post-limpieza
-- ---------------------------------------------------------------------
select
    (select count(*) from stg_orders)        as total_stg_orders,
    (select count(*) from clean_orders)      as total_clean_orders,
    (select count(*) from stg_order_items)   as total_stg_items,
    (select count(*) from clean_order_items) as total_clean_items;

-- chequeo adicional: emails imputados sintéticamente
select count(*) as emails_imputados
from clean_orders
where email like '%@sindatos.com';

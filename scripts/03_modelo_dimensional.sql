use ecommerce_analytics;

-- =====================================================================
-- script 03: modelo dimensional estrella
-- Se construye las tablas de dimensión y la tabla de hechos
-- a partir de las tablas limpias creadas en la etapa anterior,
-- siguiendo un esquema en estrella clásico listo para power bi.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. dim_customers: atributos únicos del cliente
-- se toma el registro más reciente de cada cliente (según su última
-- orden) para reflejar su estado más actualizado.
-- ---------------------------------------------------------------------
drop table if exists dim_customers;

create table dim_customers as
with customers_ranked as (
    select
        customer_id,
        first_name,
        last_name,
        email,
        city,
        country,
        signup_date,
        segment,
        row_number() over (
            partition by customer_id
            order by order_date desc
        ) as rn
    from clean_orders
)
select
    customer_id,
    first_name,
    last_name,
    email,
    city,
    country,
    signup_date,
    segment
from customers_ranked
where rn = 1;

alter table dim_customers
    add primary key (customer_id);

-- ---------------------------------------------------------------------
-- 2. dim_products: atributos de producto
-- se toma el precio unitario más reciente registrado para cada
-- producto, a partir de la fecha de la orden.
-- ---------------------------------------------------------------------
drop table if exists dim_products;

create table dim_products as
with products_ranked as (
    select
        i.product_id,
        i.product_name,
        i.category,
        i.unit_price,
        row_number() over (
            partition by i.product_id
            order by o.order_date desc
        ) as rn
    from clean_order_items i
    inner join clean_orders o
        on i.order_id = o.order_id
)
select
    product_id,
    product_name,
    category,
    unit_price
from products_ranked
where rn = 1;

alter table dim_products
    add primary key (product_id);

-- ---------------------------------------------------------------------
-- 3. dim_date: tabla de calendario generada dinámicamente
-- ---------------------------------------------------------------------
drop table if exists dim_date;

-- profundidad máxima de recursión permitida por mysql para cubrir rangos de fechas amplios.
set session cte_max_recursion_depth = 100000;

create table dim_date as
with recursive fechas as (
    select min(order_date) as full_date
    from clean_orders
    union all
    select date_add(full_date, interval 1 day)
    from fechas
    where full_date < (select max(order_date) from clean_orders)
)
select
    cast(date_format(full_date, '%Y%m%d') as unsigned) as date_id,
    full_date,
    year(full_date)                                     as year,
    quarter(full_date)                                  as quarter,
    month(full_date)                                    as month,
    monthname(full_date)                                as month_name,
    day(full_date)                                      as day,
    dayname(full_date)                                  as day_of_week_name
from fechas;

alter table dim_date
    add primary key (date_id);

create index ix_dim_date_full_date on dim_date (full_date);

-- ---------------------------------------------------------------------
-- 4. fact_sales: tabla de hechos a nivel de línea de ítem 
-- con métricas de negocio (revenue bruto/neto, descuentos) y
-- las claves foráneas hacia cada dimensión.
-- ---------------------------------------------------------------------
drop table if exists fact_sales;

create table fact_sales as
select
    i.order_item_id,
    i.order_id,
    o.customer_id,
    i.product_id,
    o.order_date,
    cast(date_format(o.order_date, '%Y%m%d') as unsigned)          as date_id,
    i.quantity,
    i.unit_price,
    o.discount_pct,
    -- ingreso bruto: cantidad x precio unitario
    round(i.quantity * i.unit_price, 2)                             as gross_revenue,
    -- monto de descuento aplicado sobre el ingreso bruto de la línea
    round(i.quantity * i.unit_price * (o.discount_pct / 100), 2)    as discount_amount,
    -- ingreso neto: bruto menos descuento
    round(
        (i.quantity * i.unit_price) -
        (i.quantity * i.unit_price * (o.discount_pct / 100)),
        2
    )                                                                as net_revenue,
    o.status
from clean_order_items i
inner join clean_orders o
    on i.order_id = o.order_id;

alter table fact_sales
    add primary key (order_item_id);

create index ix_fact_sales_customer on fact_sales (customer_id);
create index ix_fact_sales_product on fact_sales (product_id);
create index ix_fact_sales_date on fact_sales (date_id);
create index ix_fact_sales_order on fact_sales (order_id);

-- ---------------------------------------------------------------------
-- 5. claves foráneas
-- ---------------------------------------------------------------------
alter table fact_sales
    add constraint fk_fact_customer
        foreign key (customer_id) references dim_customers (customer_id),
    add constraint fk_fact_product
        foreign key (product_id) references dim_products (product_id),
    add constraint fk_fact_date
        foreign key (date_id) references dim_date (date_id);

-- ---------------------------------------------------------------------
-- 6. validación rápida del modelo dimensional
-- ---------------------------------------------------------------------
select
    (select count(*) from dim_customers) as total_dim_customers,
    (select count(*) from dim_products)  as total_dim_products,
    (select count(*) from dim_date)      as total_dim_date,
    (select count(*) from fact_sales)    as total_fact_sales;

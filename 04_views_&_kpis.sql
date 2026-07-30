use ecommerce_analytics;

-- =====================================================================
-- script 04: vistas de negocio y validación de KPIs
-- se crea vistas listas para conectar a power bi y se
-- valida los principales kpis de negocio.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. vw_sales_analysis
-- vista consolidada a nivel de línea de venta
-- ---------------------------------------------------------------------
create or replace view vw_sales_analysis as
select
    f.order_item_id,
    f.order_id,
    f.order_date,
    d.year,
    d.quarter,
    d.month,
    d.month_name,
    d.day_of_week_name,
    c.customer_id,
    c.first_name,
    c.last_name,
    c.email,
    c.city,
    c.country,
    c.segment,
    p.product_id,
    p.product_name,
    p.category,
    f.quantity,
    f.unit_price,
    f.discount_pct,
    f.gross_revenue,
    f.discount_amount,
    f.net_revenue,
    f.status,
    case
        when f.status in ('cancelled', 'returned', 'cancelado', 'devuelto') then 0
        else 1
    end as is_valid_sale
from fact_sales f
inner join dim_customers c on f.customer_id = c.customer_id
inner join dim_products p on f.product_id = p.product_id
inner join dim_date d on f.date_id = d.date_id;

-- ---------------------------------------------------------------------
-- 2. vw_customer_kpis
-- vista agregada a nivel de cliente
-- ---------------------------------------------------------------------
create or replace view vw_customer_kpis as
with customer_orders as (
    select
        c.customer_id,
        c.first_name,
        c.last_name,
        c.segment,
        c.country,
        o.order_id,
        o.order_date,
        o.status
    from dim_customers c
    inner join clean_orders o on c.customer_id = o.customer_id
),
customer_revenue as (
    select
        customer_id,
        sum(net_revenue)          as total_net_revenue,
        count(distinct order_id)  as total_orders_with_sales
    from fact_sales
    where status not in ('cancelled', 'returned', 'cancelado', 'devuelto')
    group by customer_id
)
select
    co.customer_id,
    co.first_name,
    co.last_name,
    co.segment,
    co.country,
    count(distinct co.order_id)                               as total_orders,
    min(co.order_date)                                         as first_order_date,
    max(co.order_date)                                         as last_order_date,
    datediff(max(co.order_date), min(co.order_date))            as customer_lifespan_days,
    coalesce(cr.total_net_revenue, 0)                           as lifetime_value,
    -- ticket promedio por cliente (net_revenue / órdenes válidas)
    round(
        coalesce(cr.total_net_revenue, 0) /
        nullif(coalesce(cr.total_orders_with_sales, 0), 0),
        2
    )                                                            as avg_order_value,
    -- frecuencia de compra: órdenes por mes activo del cliente
    round(
        count(distinct co.order_id) /
        nullif((datediff(max(co.order_date), min(co.order_date)) / 30.0), 0),
        2
    )                                                            as purchase_frequency_monthly
from customer_orders co
left join customer_revenue cr on co.customer_id = cr.customer_id
group by
    co.customer_id, co.first_name, co.last_name, co.segment,
    co.country, cr.total_net_revenue, cr.total_orders_with_sales;

-- =====================================================================
-- 3. consultas de validación de kpis (business intelligence)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 3.1 total revenue vs net revenue
-- ---------------------------------------------------------------------
select
    round(sum(gross_revenue), 2)   as total_gross_revenue,
    round(sum(discount_amount), 2) as total_discount_amount,
    round(sum(net_revenue), 2)     as total_net_revenue,
    round(
        sum(case when status not in ('cancelled', 'returned', 'cancelado', 'devuelto')
            then net_revenue else 0 end), 2
    )                               as net_revenue_valid_orders
from fact_sales;

-- ---------------------------------------------------------------------
-- 3.2 ticket promedio calculado a nivel de orden (no de línea de ítem), 
-- sólo sobre órdenes válidas (no canceladas/devueltas)
-- ---------------------------------------------------------------------
with order_totals as (
    select
        order_id,
        sum(net_revenue) as order_net_revenue
    from fact_sales
    where status not in ('cancelled', 'returned', 'cancelado', 'devuelto')
    group by order_id
)
select
    round(avg(order_net_revenue), 2) as average_order_value
from order_totals;

-- ---------------------------------------------------------------------
-- 3.3 cantidad total de órdenes, unidades y productos vendidos
-- ---------------------------------------------------------------------
select
    count(distinct order_id)   as total_orders,
    sum(quantity)               as total_units_sold,
    count(distinct product_id)  as total_distinct_products_sold
from fact_sales
where status not in ('cancelled', 'returned', 'cancelado', 'devuelto');

-- ---------------------------------------------------------------------
-- 3.4 tasa % de devoluciones / cancelaciones (churn de órdenes)
-- ---------------------------------------------------------------------
with order_status as (
    select distinct order_id, status
    from fact_sales
)
select
    count(*)                                                              as total_orders,
    sum(case when status in ('cancelled', 'returned', 'cancelado', 'devuelto')
        then 1 else 0 end)                                                as cancelled_or_returned_orders,
    round(
        100.0 * sum(case when status in ('cancelled', 'returned', 'cancelado', 'devuelto')
            then 1 else 0 end) / count(*),
        2
    )                                                                      as cancellation_rate_pct
from order_status;

-- ---------------------------------------------------------------------
-- 3.5 top 5 productos más vendidos (por unidades) con dense_rank()
-- ---------------------------------------------------------------------
with product_sales as (
    select
        p.product_id,
        p.product_name,
        p.category,
        sum(f.quantity)    as total_units_sold,
        sum(f.net_revenue) as total_net_revenue
    from fact_sales f
    inner join dim_products p on f.product_id = p.product_id
    where f.status not in ('cancelled', 'returned', 'cancelado', 'devuelto')
    group by p.product_id, p.product_name, p.category
),
product_ranked as (
    select
        *,
        dense_rank() over (order by total_units_sold desc) as sales_rank
    from product_sales
)
select
    sales_rank,
    product_id,
    product_name,
    category,
    total_units_sold,
    round(total_net_revenue, 2) as total_net_revenue
from product_ranked
where sales_rank <= 5
order by sales_rank;

-- ---------------------------------------------------------------------
-- 3.6 ventas acumuladas y variación mes a mes (mom growth) con lag()
-- ---------------------------------------------------------------------
with monthly_sales as (
    select
        date_format(order_date, '%Y-%m') as sales_month,
        sum(net_revenue)                  as monthly_net_revenue
    from fact_sales
    where status not in ('cancelled', 'returned', 'cancelado', 'devuelto')
    group by date_format(order_date, '%Y-%m')
),
monthly_with_growth as (
    select
        sales_month,
        round(monthly_net_revenue, 2) as monthly_net_revenue,
        round(
            sum(monthly_net_revenue) over (
                order by sales_month
                rows between unbounded preceding and current row
            ), 2
        ) as cumulative_net_revenue,
        round(
            lag(monthly_net_revenue) over (order by sales_month), 2
        ) as previous_month_revenue
    from monthly_sales
)
select
    sales_month,
    monthly_net_revenue,
    cumulative_net_revenue,
    previous_month_revenue,
    -- variación porcentual mes a mes (mom growth)
    round(
        100.0 * (monthly_net_revenue - previous_month_revenue) /
        nullif(previous_month_revenue, 0),
        2
    ) as mom_growth_pct
from monthly_with_growth
order by sales_month;

-- ---------------------------------------------------------------------
-- 4. Guardado de vistas para luego cargar en Power BI Web en caso de usar Mac
-- ---------------------------------------------------------------------
-- Se exportan como csv.
select *
from vw_sales_analysis;

select * 
from vw_customer_kpis;

/*
Project Goals:
1. Insights & trends for overall perfomance
2. Top performing products & categories
3. Customer behavior & preferences
4. Sales & revenue over time
5. Factors contributing to retention
6. Marketing & promotion recommendations
*/

/*Goal 1: Insights & trends for overall perfomance */
-- SUM(COUNT(*)) OVER() calculates the grand total of rows across all groups in a GROUP BY query, 
-- allowing me to see both individual group counts and the overall total side-by-side without needing a subquery or CTE
select 
	order_status,
    count(*) as order_count,
    sum(count(*)) over() as total_orders,
    round(100.0 * count(*) / sum(count(*)) over(),2) as pct_of_total
from olist_orders_dataset
group by order_status
order by order_count desc;
-- returns count of order_status, order_count, total_orders & pct_of_total

-- Need to measure how often Olist delivers on time vs. late
-- DATEDIFF(order_delivered_customer_date, order_estimated_delivery_date) > gives me exact day difference (delivered - estimate)
select
	case 
		when datediff(order_delivered_customer_date, order_estimated_delivery_date) > 0 then 'Late'
        else 'On Time or Early'
	end as delivery_status,
    count(*) as order_count,
    round(count(*) * 100.0 / sum(count(*)) over(),2) as percentage
from olist_orders_dataset
where order_status = 'delivered'
	and order_delivered_customer_date is not null
group by delivery_status
order by order_count desc;

/* Need to know where in the fulfillment pipeline delays happen when orders are late
 orders move in 3 stages: 
 Approval: order_purchase_timestamp --> order_approved_at
 Seller Handling: order_approved_at --> order_delivered_carrier_date
 Carrier Transit: ordered_delivered_carrier_date --> order_delivered_customer_date */
select
	case
		when datediff(order_delivered_customer_date, order_estimated_delivery_date) > 0 then 'Late'
        else 'On Time or Early'
	end as delivery_status,
    count(*) as order_count,
    -- stage 1: purchase to payment/order approval
    round(avg(datediff(order_approved_at, order_purchase_timestamp)),2) as avg_approval_days,
	-- stage 2: approval to carrier handoff
    round(avg(datediff(order_delivered_carrier_date, order_approved_at)),2) as avg_carrier_handoff_days,
    -- stage 3: carrier handoff to customer delivery
   round(avg(datediff(order_delivered_customer_date, order_delivered_carrier_date)),2) as avg_transit_days,
   -- total end-to-end delivery time (purchase to customer)
   round(avg(datediff(order_delivered_customer_date, order_purchase_timestamp)),2) as avg_total_delivery_days
from olist_orders_dataset
where order_status = 'delivered'
	and order_purchase_timestamp is not null
    and order_approved_at is not null
    and order_delivered_carrier_date is not null
    and order_delivered_customer_date is not null
    and order_estimated_delivery_date is not null
group by
	case
		when datediff(order_delivered_customer_date, order_estimated_delivery_date) > 0 then 'Late'
        else 'On Time or Early'
	end
order by delivery_status;


/*Goal 2: Top performing products & categories*/
with order_reviews as (
    select
        order_id,
        avg(review_score) as avg_order_review
    from olist_order_reviews_dataset
    group by order_id
)
select
	item.product_id,
    coalesce(prod.product_category_name, 'uncategorized') as category,
    count(*) as units_sold,
    count(distinct item.order_id) as total_orders,
    round(sum(item.price), 2) as total_revenue,
    round(avg(item.price), 2) as avg_item_price,
    round(avg(rev.avg_order_review), 2) as avg_review_score
from olist_order_items_dataset as item
join olist_orders_dataset as ord
    on item.order_id = ord.order_id
join olist_products_dataset as prod
    on item.product_id = prod.product_id
left join order_reviews as rev
    on item.order_id = rev.order_id
where ord.order_status = 'delivered'
group by item.product_id, coalesce (prod.product_category_name, 'uncategorized')
order by total_revenue desc
limit 10;

-- top 10 individual products

/*Goal 3: Customer behavior & preferences*/
-- payment preferences
select
	pmt.payment_type,
	count(distinct pmt.order_id) as order_count,
	round(count(distinct pmt.order_id) * 100.00 / sum(count(distinct pmt.order_id)) over(), 2) as order_share_pct,
	round(sum(pmt.payment_value),2) as total_payment_value,
	round(avg(pmt.payment_value),2) as avg_payment_value,
	round(avg(pmt.payment_installments),2) as avg_installments
from olist_order_payments_dataset as pmt
inner join olist_orders_dataset as ord
	on pmt.order_id = ord.order_id
where ord.order_status = 'delivered'
group by pmt.payment_type
order by order_count desc;

-- geographic behaviours
with order_totals as (
	select
		order_id,
        sum(payment_value) as order_payment_value
	from olist_order_payments_dataset
    group by order_id
)
select
	cust.customer_state,
    count(distinct ord.order_id) as order_count,
    round(count(distinct ord.order_id) * 100.00 / sum(count(distinct ord.order_id)) over(), 2) as order_share_pct,
    round(avg(ot.order_payment_value),2) as avg_order_payment_value
from olist_orders_dataset as ord
inner join olist_customers_dataset as cust
	on ord.customer_id = cust.customer_id
inner join order_totals as ot
	on ord.order_id = ot.order_id
where ord.order_status = 'delivered'
group by cust.customer_state
order by order_count desc
limit 10;



/*Goal 4: Sales & revenue over time*/
with order_totals as (
    select
        order_id,
        SUM(payment_value) as order_payment_value
    from olist_order_payments_dataset
    group by order_id
),
monthly_sales as (
    select
        date_format(ord.order_purchase_timestamp, '%Y-%m-01') as order_month,
        count(distinct ord.order_id) as total_orders,
        round(sum(ot.order_payment_value), 2) as total_revenue,
        round(avg(ot.order_payment_value), 2) as avg_order_value
    from olist_orders_dataset as ord
    inner join order_totals as ot
        on ord.order_id = ot.order_id
    where ord.order_status = 'delivered'
      and ord.order_purchase_timestamp is not null
    group by date_format(ord.order_purchase_timestamp, '%Y-%m-01')
)
select
    order_month,
    total_orders,
    round((total_orders - lag(total_orders) over (order by order_month)) * 100.0 / lag(total_orders) over (order by order_month), 2) as mom_order_growth_pct,
    total_revenue, round((total_revenue - lag(total_revenue) over (order by order_month)) * 100.0 / lag(total_revenue) over (order by order_month),2) as mom_revenue_growth_pct, avg_order_value
from monthly_sales
order by order_month asc;


/*Goal 5: Factors contributing to retention*/
with customer_orders as (
    select 
        cust.customer_unique_id,
        count(distinct ord.order_id) as delivered_order_count
    from olist_orders_dataset as ord
    inner join olist_customers_dataset as cust
        on ord.customer_id = cust.customer_id
    where ord.order_status = 'delivered'
    group by cust.customer_unique_id
)
select 
    case 
        when delivered_order_count = 1 then 'One-Time'
        else 'Repeat'
    end as customer_type,
    count(*) as customer_count,
    round(count(*) * 100.0 / sum(count(*)) over(), 2) as customer_share_pct
from customer_orders
group by 
    case 
        when delivered_order_count = 1 then 'One-Time'
        else 'Repeat'
    end
order by customer_count desc;

/*
customer_type	customer_count	customer_share_pct
One-Time			90557			97.00
Repeat				2801			3.00
97% one time vs 3% repeat
need to compare customers first order (overall experience)
*/

with order_reviews as (
    select
        order_id,
        avg(review_score) as avg_order_review
    from olist_order_reviews_dataset
    group by order_id
),
customer_first_order as (
    select
        cust.customer_unique_id,
        ord.order_id,
        ord.order_purchase_timestamp,
        ord.order_delivered_customer_date,
        ord.order_estimated_delivery_date,
        row_number() over (
            partition by cust.customer_unique_id
            order by ord.order_purchase_timestamp ASC, ord.order_id asc) as order_seq,
        COUNT(*) over (partition by cust.customer_unique_id) as total_orders
    from olist_orders_dataset as ord
    inner join olist_customers_dataset as cust
        on ord.customer_id = cust.customer_id
    where ord.order_status = 'delivered'
      and ord.order_delivered_customer_date is not null
)
select
    case
        when cfo.total_orders = 1 then 'One-Time'
        else 'Repeat'
    end as customer_type,
    count(*) as customer_count,
    round(avg(rev.avg_order_review), 2) as avg_first_review_score,
    round(avg(DATEDIFF(cfo.order_delivered_customer_date, cfo.order_purchase_timestamp)), 2) as avg_first_delivery_days,
    round(avg(
			case
				when DATEDIFF(cfo.order_delivered_customer_date, cfo.order_estimated_delivery_date) > 0 then 100.0
            else 0.0
			end),2) as first_order_late_pct
from customer_first_order as cfo
left join order_reviews as rev
    on cfo.order_id = rev.order_id
where cfo.order_seq = 1
group by
    case
        when cfo.total_orders = 1 then 'One-Time'
        else 'Repeat'
    end
order by customer_count desc;

/*

First-order satisfaction and shipping speed help slightly (especially avoiding a late first delivery), but they do not explain why 97% of customers never return. 
Even satisfied 5-star customers mostly buy once and leave—meaning Olist's retention problem is structural (lack of loyalty/remarketing programs, 
marketplace model where buyers don't bond with a brand, or one-off product categories), rather than just a shipping-speed issue.

*/
with customer_first_order as (
    select
        cust.customer_unique_id,
        ord.order_id,
        row_number() over (partition by cust.customer_unique_id 
        order by ord.order_purchase_timestamp asc, ord.order_id asc) as order_seq,
        count(*) over (partition by cust.customer_unique_id) as total_orders
    from olist_orders_dataset as ord
    inner join olist_customers_dataset as cust
        on ord.customer_id = cust.customer_id
    where ord.order_status = 'delivered'
      and ord.order_delivered_customer_date is not null
)
select
    coalesce(prod.product_category_name, 'uncategorized') as first_category,
    count(distinct cfo.customer_unique_id) as total_customers,
    count(distinct case when cfo.total_orders > 1 then cfo.customer_unique_id end) as repeat_customers,
    round(count(distinct case when cfo.total_orders > 1 then cfo.customer_unique_id end) * 100.0 / count(distinct cfo.customer_unique_id),2) as repeat_rate_pct
from customer_first_order as cfo
inner join olist_order_items_dataset as item
    on cfo.order_id = item.order_id
inner join olist_products_dataset as prod
    on item.product_id = prod.product_id
where cfo.order_seq = 1
group by coalesce(prod.product_category_name, 'uncategorized')
having count(distinct cfo.customer_unique_id) >= 500
order by repeat_rate_pct desc
limit 10;

/*
this directly connects product category to customer retention
*/


/*Goal 6: Marketing & promotion recommendations*/



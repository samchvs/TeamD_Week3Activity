-- JOIN LOYALTY CARDHOLDERS WITH TRANSACTION DETAILS --
-- This creates a complete customer transaction history by combining:
--   • loyalty_cardholders_silver: customer profile (birthday, registration date)
--   • transaction_details_silver: purchase history (products, retailers, dates)

SELECT 
    -- CUSTOMER INFORMATION --
    l.user_id AS customer_id,
    l.registered_date,
    l.birthday,
    YEAR(CURRENT_DATE()) - YEAR(l.birthday) AS age,
    
    -- TRANSACTION INFORMATION --
    t.transaction_id,
    t.receipt_number,
    t.receipt_date,
    t.transaction_date,
    
    -- PRODUCT INFORMATION --
    t.product_sku,
    t.product_brand,
    t.quantity,
    t.total_unit_price,
    
    -- RETAILER INFORMATION --
    t.retailer,
    t.branch

FROM loyalty_cardholders_silver l

-- JOIN KEY: user_id (loyalty) = customer_id (transactions)
-- INNER JOIN = Only show customers who have made purchases
INNER JOIN transaction_details_silver t 
    ON l.user_id = t.customer_id
    AND t.data_quality_flag = 'OK'  -- Only include valid transactions

-- Only include customers with valid profiles
WHERE l.data_quality_flag = 'OK'

ORDER BY l.user_id, t.transaction_date, t.transaction_id
LIMIT 100;

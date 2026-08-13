-- 01 PRELIMINARY DATA CHECK
-- ============================================================
-- Purpose:
-- Identify NULL values, duplicates, invalid values, and
-- inconsistencies in the cardholders and transactions tables
-- before applying any data transformations.
-- ============================================================


-- ============================================================
-- 1. CARDHOLDER TABLE CHECKING
-- ============================================================


-- ------------------------------------------------------------
-- 1.1 CHECK FOR NULL VALUES
-- ------------------------------------------------------------

-- Check for NULL user IDs
SELECT *
FROM cardholders
WHERE user_id IS NULL;

-- Check for NULL birthdays
SELECT *
FROM cardholders
WHERE birthday IS NULL;

-- Check for NULL registration dates
SELECT *
FROM cardholders
WHERE registered_date IS NULL;


-- ------------------------------------------------------------
-- 1.2 CHECK FOR DUPLICATE VALUES
-- ------------------------------------------------------------

-- Check for duplicate user IDs
SELECT
    user_id,
    COUNT(*) AS record_count
FROM cardholders
GROUP BY user_id
HAVING COUNT(*) > 1;


-- ------------------------------------------------------------
-- 1.3 CHECK FOR INVALID BIRTHDAY VALUES
-- ------------------------------------------------------------

-- Check for birthday values with a four-digit year.
-- Used to identify unusually old/invalid birth years.
SELECT *
FROM cardholders
WHERE LEN(
    CAST(REGEXP_EXTRACT(birthday, '(\\d+)$', 1) AS INT)
) = 4;


-- Check for future birth dates after standardizing
-- two-digit year values.
SELECT *
FROM (
    SELECT
        *,
        CASE
            WHEN REGEXP_EXTRACT(birthday, '(\\d+)$', 1)::INT <= 26
                THEN TO_DATE(
                    REGEXP_REPLACE(
                        birthday,
                        '(\\d+)$',
                        CONCAT(
                            '20',
                            REGEXP_EXTRACT(birthday, '(\\d+)$', 1)
                        )
                    ),
                    'M/d/yyyy'
                )
            ELSE TO_DATE(
                REGEXP_REPLACE(
                    birthday,
                    '(\\d+)$',
                    CONCAT(
                        '19',
                        REGEXP_EXTRACT(birthday, '(\\d+)$', 1)
                    )
                ),
                'M/d/yyyy'
            )
        END AS bday_valid
    FROM cardholders
    WHERE LEN(
        CAST(REGEXP_EXTRACT(birthday, '(\\d+)$', 1) AS INT)
    ) <> 4
) AS valid_yr
WHERE bday_valid > CURRENT_DATE();


-- Check for unreasonable customer ages.
-- Customers younger than 18 or older than 100 are flagged.
SELECT COUNT(*)
FROM (
    SELECT
        *,
        CASE
            WHEN user_id <> 9437
                 AND REGEXP_EXTRACT(birthday, '(\\d+)$', 1)::INT <= 24
                THEN TO_DATE(
                    REGEXP_REPLACE(
                        birthday,
                        '(\\d+)$',
                        CONCAT(
                            '20',
                            REGEXP_EXTRACT(birthday, '(\\d+)$', 1)
                        )
                    ),
                    'M/d/yyyy'
                )
            ELSE TO_DATE(
                REGEXP_REPLACE(
                    birthday,
                    '(\\d+)$',
                    CONCAT(
                        '19',
                        REGEXP_EXTRACT(birthday, '(\\d+)$', 1)
                    )
                ),
                'M/d/yyyy'
            )
        END AS bday_valid
    FROM cardholders
    WHERE LEN(
        CAST(REGEXP_EXTRACT(birthday, '(\\d+)$', 1) AS INT)
    ) <> 4
) AS valid_yr
WHERE (
    YEAR(CURRENT_DATE()) - YEAR(bday_valid) < 18
    OR YEAR(CURRENT_DATE()) - YEAR(bday_valid) > 100
);


-- ============================================================
-- 2. TRANSACTION TABLE CHECKING
-- ============================================================


-- ------------------------------------------------------------
-- 2.1 CHECK FOR NULL VALUES
-- ------------------------------------------------------------

-- Customer ID
SELECT *
FROM transactions
WHERE customer_id IS NULL;

-- Transaction ID
SELECT *
FROM transactions
WHERE transaction_id IS NULL;

-- Receipt date
SELECT *
FROM transactions
WHERE receipt_date IS NULL;

-- Transaction date
SELECT *
FROM transactions
WHERE transaction_date IS NULL;

-- Receipt number
SELECT *
FROM transactions
WHERE receipt_number IS NULL;

-- Product SKU
SELECT *
FROM transactions
WHERE product_sku IS NULL;

-- Product brand
SELECT *
FROM transactions
WHERE product_brand IS NULL;

-- Quantity
SELECT *
FROM transactions
WHERE quantity IS NULL;

-- Total unit price
SELECT *
FROM transactions
WHERE total_unit_price IS NULL;

-- Retailer
SELECT *
FROM transactions
WHERE retailer IS NULL;

-- Branch
SELECT *
FROM transactions
WHERE branch IS NULL;


-- ------------------------------------------------------------
-- 2.2 CHECK FOR INVALID VALUES
-- ------------------------------------------------------------

-- Check for future receipt dates
SELECT *
FROM transactions
WHERE receipt_date > CURRENT_DATE();


-- Check for non-positive quantities
SELECT *
FROM transactions
WHERE quantity <= 0;


-- Check for non-positive total unit prices
SELECT *
FROM transactions
WHERE total_unit_price <= 0;


-- ------------------------------------------------------------
-- 2.3 CHECK NAMING CONSISTENCY
-- ------------------------------------------------------------

-- Check unique product brands
SELECT DISTINCT product_brand
FROM transactions;


-- Check unique retailers
SELECT DISTINCT retailer
FROM transactions;


-- Count distinct raw product SKUs
SELECT COUNT(DISTINCT product_sku) AS raw_unique_skus
FROM transactions;


-- Count distinct product SKU and brand combinations
SELECT COUNT(DISTINCT (product_sku, product_brand))
    AS raw_unique_sku_brand_combinations
FROM transactions;


-- ------------------------------------------------------------
-- 2.4 CHECK PRODUCT SKU CONSISTENCY
-- ------------------------------------------------------------
-- Standardize SKU format by:
-- 1. Removing non-alphanumeric characters
-- 2. Removing leading/trailing spaces
-- 3. Converting to uppercase
--
-- This identifies different raw SKUs that refer to the
-- same cleaned SKU.


WITH unique_products AS (
    SELECT DISTINCT product_sku
    FROM transactions
    WHERE product_sku IS NOT NULL
),

cleaned_products AS (
    SELECT
        product_sku AS product_raw,
        UPPER(
            TRIM(
                REGEXP_REPLACE(
                    product_sku,
                    '[^a-zA-Z0-9]',
                    ''
                )
            )
        ) AS clean_sku
    FROM unique_products
),

count_duplicates AS (
    SELECT
        product_raw,
        clean_sku,
        COUNT(*) OVER (
            PARTITION BY clean_sku
        ) AS duplicate_cnt
    FROM cleaned_products
)

SELECT *
FROM count_duplicates
WHERE duplicate_cnt > 1
ORDER BY clean_sku, product_raw;


-- ------------------------------------------------------------
-- 2.5 CHECK PRODUCT SKU AND BRAND CONSISTENCY
-- ------------------------------------------------------------
-- Identify SKUs associated with more than one product brand.
-- These records require further investigation and correction.


SELECT DISTINCT
    product_sku,
    product_brand
FROM transactions
WHERE product_sku IN (
    SELECT product_sku
    FROM transactions
    GROUP BY product_sku
    HAVING COUNT(DISTINCT product_brand) > 1
)
ORDER BY product_sku, product_brand;


-- ------------------------------------------------------------
-- 2.6 CHECK FOR PRICE ABNORMALITIES
-- ------------------------------------------------------------
-- Compare the actual unit price against the median and mode
-- price of each product SKU.
--
-- Prices are flagged as potentially abnormal when they are
-- more than 5 times higher or lower than the median price.
-- ------------------------------------------------------------

WITH product_prices AS (
    SELECT
        transaction_id,
        product_sku,
        retailer,
        ROUND(total_price / quantity, 2) AS actual_price,

        -- Calculate the median price for each product SKU
        MEDIAN(total_price / quantity)
            OVER (PARTITION BY product_sku) AS median_price,

        -- Calculate the most frequently occurring price
        ROUND(
            MODE(total_price / quantity)
                OVER (PARTITION BY product_sku),
            2
        ) AS mode_price

    FROM cleaned_transactions
)

SELECT
    transaction_id,
    product_sku,
    retailer,
    actual_price,
    median_price,
    mode_price,

    -- Calculate the difference between actual and median price
    ROUND(actual_price - median_price, 2) AS price_difference

FROM product_prices

-- Flag potentially abnormal prices
WHERE actual_price > (median_price * 5)
   OR actual_price < (median_price / 5)

ORDER BY ABS(price_difference) DESC;


-- ============================================================
-- END OF PRELIMINARY DATA CHECK
-- ============================================================

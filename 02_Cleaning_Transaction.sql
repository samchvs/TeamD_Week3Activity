-- CREATE A CLEANED RESULT 
CREATE OR REPLACE TABLE transaction_details_silver AS 
WITH cleaned_data AS (

    SELECT 
        -- 1. CUSTOMER ID: rename column (has # prefix), ensure ID is stored as number
        TRY_CAST(`# customer_id` AS BIGINT) AS customer_id, 
        -- 2. TRANSACTION ID: remove spaces, keep ID as string
        TRIM(CAST(transaction_id AS STRING)) AS transaction_id,
        -- 3. RECEIPT DATE: already TIMESTAMP in bronze, just cast to DATE
        CAST(receipt_date AS DATE) AS receipt_date,
        -- 4. TRANSACTION DATE: already TIMESTAMP in bronze, just cast to DATE
        CAST(transaction_date AS DATE) AS transaction_date,
        -- 5. RECEIPT NUMBER: remove spaces, keep ID as string
        REGEXP_REPLACE(TRIM(CAST(receipt_number AS STRING)),'\\s+','') AS receipt_number,
        -- 6. PRODUCT_SKU: formatting/standardized, consider if relevant to change other entries special prefixes may mean something OR NOT?
        -- pass raw value forward; cleaning happens in next CTE
        TRIM(CAST(product_sku AS STRING)) AS product_sku_raw,
        -- 7. PRODUCT_BRAND: missing 3 just identify or assume basing from product sku
        -- pass raw value forward; nulls are filled in next CTE.
        TRIM(CAST(product_brand AS STRING)) AS product_brand_raw,
        --
        -- 8. QUANTITY:
        TRY_CAST(quantity AS DECIMAL(10,2)) AS quantity,
        -- 9. TOTAL UNIT PRICE:
        TRY_CAST(total_unit_price AS DECIMAL(10,2)) AS total_unit_price,
        -- 10. RETAILER:
        TRIM(CAST(retailer AS STRING)) AS retailer,
        -- 11. BRANCH:
        TRIM(CAST(branch AS STRING)) AS branch

    FROM transaction_details_bronze
),

-- PRODUCT SKU CLEANING -- 
-- with special prefixes:  
-- $ prefix  → e.g. "$UFC GFP/OL950ML"   (221 rows)
-- << prefix → e.g. "<< UFC T/A B/KET32" (103 rows, incl. variants)
-- *MDF_     → e.g. "*MDF_UFC CREAM..."   (69 rows)

product_sku_cleaned AS (
    SELECT *,
            TRIM(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(
                            product_sku_raw,
                            '^\\$\\s*<<\\s*', ''  -- combined $ << prefix
                        ),
                        '^\\$\\s*',          ''   -- standalone $ prefix
                    ),
                    '^<<\\s*',               ''   -- standalone << prefix
                ),
                '^\\*MDF_?\\s*',             ''   -- *MDF_ or *MDF prefix
            )
        ) AS product_sku
 
    FROM cleaned_data
),

-- PRODUCT BRAND NULL FILLED -- 
-- 3 rows are empty but identifiable

product_brand_cleaned AS (
    SELECT
        * EXCEPT (product_brand_raw),
 -- COALESCE returns the existing value if populated; only runs the REGEXP on nulls. Pattern order matters — more specific prefixes (DPUTI, PAPA) must come before shorter ones (DP, PAP) to avoid early-exit mismatches.
        COALESCE(
            NULLIF(TRIM(product_brand_raw), ''),
            CASE
                WHEN product_sku RLIKE '^(DP |DPU|DPUTI|DATU)'  THEN 'Datu Puti'
                WHEN product_sku RLIKE '^UFC'                    THEN 'UFC'
                WHEN product_sku RLIKE '^(SS |SLV|S/S|SILVER)'  THEN 'Silver Swan'
                WHEN product_sku RLIKE '^(GF |GFS|GOLDEN)'      THEN 'Golden Fiesta'
                WHEN product_sku RLIKE '^(MT |M\.T|MANG)'       THEN 'Mang Tomas'
                WHEN product_sku RLIKE '^LOC'                    THEN 'Locally'
                WHEN product_sku RLIKE '^JUF'                    THEN 'Jufran'
                WHEN product_sku RLIKE '^(HAP|HF |HFS)'         THEN 'Hapi Fiesta'
                WHEN product_sku RLIKE '^(PAP|PAPA)'            THEN 'Papa'
                ELSE 'Unknown'
            END
        ) AS product_brand

    FROM product_sku_cleaned
),
-- DATE VALIDATION --
dates_validated AS (
    SELECT * EXCEPT (receipt_date),
        -- Nullify receipt_date if outside the loyalty program's known date window (2024–2025).
        -- 22 rows have future dates (2026, 2080, 2094) — confirmed data entry errors.
        -- We do NOT substitute transaction_date because receipt_date = date printed on
        -- the physical receipt, which is a distinct field with its own meaning.
        CASE
            WHEN receipt_date BETWEEN DATE('2024-01-01') AND DATE('2025-12-31')
                THEN receipt_date
            ELSE NULL
        END AS receipt_date
    FROM product_brand_cleaned
),

-- RETAILER & BRANCH STANDARDISATION --
retailer_branch_cleaned AS (
    SELECT * EXCEPT (retailer, branch),

        -- Retailer: source values are already consistent; TRIM only, no casing changes needed.
        -- Kept as-is to match official brand names (e.g. "WalterMart Supermarket Inc").
        TRIM(retailer) AS retailer,

        -- Branch: 588 unique names with severe mixed-casing ("Puregold - Dalandanan" vs
        -- "PUREGOLD NOVALICHES"). UPPER() normalises all to one case since ~85% are
        -- already uppercase. Two known errors are also fixed here:
        --   (a) EASTMART → EASYMART: typo in 3 Robinsons Easymart branch names.
        --   (b) Double spaces collapsed: e.g. "PUREGOLD -  DON ANTONIO" → single space.
        REGEXP_REPLACE(
            UPPER(TRIM(
                REGEXP_REPLACE(branch, '^EASTMART', 'EASYMART')  -- (a) fix EASTMART typo
            )),
        '\\s{2,}', ' ')  -- (b) collapse double spaces
        AS branch,

        -- Retailer correction: EASYMART SANTA MONICA is a Robinsons Easymart branch
        -- but appears under "Robinsons Supermarket" in 11 rows. Corrected here.
        -- The 1 row already correctly assigned to Robinsons Easymart is left unchanged.
        CASE
            WHEN TRIM(branch) = 'EASYMART SANTA MONICA'
             AND TRIM(retailer) = 'Robinsons Supermarket'
                THEN 'Robinsons Easymart'
            ELSE TRIM(retailer)
        END AS retailer_corrected

    FROM dates_validated
),

-- DATA QUALITY FLAG --
final AS (
    SELECT
        customer_id,
        transaction_id,
        receipt_date,
        transaction_date,
        receipt_number,
        product_sku,
        product_brand,
        TRY_CAST(quantity AS INT) AS quantity,       -- INT: no fractional quantities exist in data
        TRY_CAST(total_unit_price AS DECIMAL(10,2))  AS total_unit_price,
        retailer_corrected                           AS retailer,
        branch,

        -- Attach a flag instead of silently dropping questionable rows.
        -- Analysts can then filter on this column as needed.
        CASE
            WHEN quantity = 0 AND total_unit_price = 0  THEN 'VOIDED'
            -- 2 rows: qty=0 and price=0 — cancelled/void line items.
            WHEN total_unit_price = 0 AND quantity > 0  THEN 'ZERO_PRICE'
            -- 4 rows: items scanned but price missing — possible promo or system error.
            WHEN receipt_date IS NULL THEN 'INVALID_RECEIPT_DATE'
            -- 22 rows: receipt_date was outside 2024–2025 and nullified above.
            ELSE 'OK'
        END AS data_quality_flag

    FROM retailer_branch_cleaned
)

-- FINAL OUTPUT --
-- Excludes only confirmed void rows (qty=0 AND price=0).
-- ZERO_PRICE and INVALID_RECEIPT_DATE rows are retained but flagged
-- so the business can decide — not assumed to be errors.
SELECT * FROM final
WHERE data_quality_flag != 'VOIDED';

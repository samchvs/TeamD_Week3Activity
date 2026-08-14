CREATE OR REPLACE TABLE workspace.default.transactions_cleaned AS

-- CLEAN THE PRODUCT SKU
-- WITH creates a temporary result called "cleaned_sku" that we can use in the main SELECT statement below.
WITH cleaned_sku AS (
  SELECT *, -- Keep all columns from the original transactions table. 

    -- Create a cleaned version of product_sku.
    -- The goal is to:
    -- 1. Remove special characters/symbols
    -- 2. Replace removed symbols with spaces
    -- 3. Remove extra spaces
    -- 4. Remove spaces at the beginning/end
    -- 5. Convert everything to uppercase
    -- "UFC-Choco! Malt" → "UFC CHOCO MALT"

    UPPER(
      TRIM(
        -- REGEXP_REPLACE #2:
        -- Replace multiple consecutive spaces with a single space.
        -- ' +' means one or more spaces.
        -- ' ' is what we replace them with.
        REGEXP_REPLACE(

          -- REGEXP_REPLACE #1:
          -- Replace anything that is NOT a letter, number,
          -- or normal space with a space.
          --
          -- [^a-zA-Z0-9 ] means:
          -- Keep A-Z, a-z, 0-9, and spaces.
          -- Anything else is replaced with ' '.
          --
          -- Example:
          -- "UFC-123!" → "UFC 123 "
          REGEXP_REPLACE(
            product_sku,
            '[^a-zA-Z0-9 ]',
            ' '
          ),

          ' +',
          ' '
        )
      )
    ) AS product_sku_clean

  -- Get the original transaction data from the bronze/raw table.
  FROM workspace.default.transaction_details_bronze
)


-- SELECT THE CLEANED COLUMNS

SELECT
  `# customer_id` AS customer_id,   -- Rename it to the cleaner name "customer_id".
  transaction_id,                   -- Keep the transaction's unique ID as-is.


  -- RECEIPT DATE
  -- Convert receipt_date from text into a real TIMESTAMP.
  -- COALESCE returns the first value that is NOT NULL. This allows us to support multiple date formats.
  
  -- First, try: yyyy-MM-dd HH:mm:ss
  -- If that fails, try: dd/MM/yyyy HH:mm

  -- TRY_TO_TIMESTAMP is used instead of CAST because TRY_TO_TIMESTAMP returns NULL when the value cannot 
  -- be converted instead of causing the entire query to fail.

  COALESCE(
    -- Try the first timestamp format.
    TRY_TO_TIMESTAMP(
      receipt_date,
      'yyyy-MM-dd HH:mm:ss'
    ),

    -- If the first format fails, try this format.
    TRY_TO_TIMESTAMP(
      receipt_date,
      'dd/MM/yyyy HH:mm'
    )

  ) AS receipt_date,

  -- IMPORTANT: We are intentionally NOT changing the suspicious years such as 2080/2094 or the 2024/2025/2026 mismatch.
  -- The decision is to leave these values unchanged rather than guessing what the correct date should be.
  -- We also do not delete these rows.

  -- TRANSACTION DATE
  -- dates are consistent, no additional cleaning or correction is necessary.
  -- Just convert transaction_date into a proper TIMESTAMP.
  -- CAST changes the data type so SQL can treat this as
  -- Example: "2024-06-15" → 2024-06-15 00:00:00

  CAST(transaction_date AS TIMESTAMP) AS transaction_date,

  -- RECEIPT NUMBER
  -- TRIM removes unnecessary spaces from the beginning and end of the receipt number.
  -- Example: "  RCP12345  " → "RCP12345"
  
  TRIM(receipt_number) AS receipt_number,

  -- PRODUCT SKU
  -- ==========================================================
  -- Use the cleaned SKU that we created in the CTE above.
  --
  -- UPPER ensures the final SKU is always uppercase.
  --
  -- Example:
  -- "ufc choco malt" → "UFC CHOCO MALT"
  UPPER(product_sku_clean) AS product_sku,

  -- PRODUCT BRAND
  -- Clean and standardize the product brand.
  -- We use the PRODUCT SKU as the more reliable source when identifying UFC or Datu Puti products.

  -- 1. Some rows have a NULL/missing brand. We can infer the brand from the SKU.
  -- 2. Some rows have a mismatch between the SKU and brand.
  --    For example: SKU = UFC... / Brand = Datu Puti

  UPPER(
    CASE
      -- If the cleaned SKU starts with "UFC", classify the product as UFC.
      WHEN product_sku_clean LIKE 'UFC%'
        THEN 'UFC'
      -- If the SKU starts with "DP ", "DATU PUTI", or "DPUTI",  classify the product as Datu Puti.
      WHEN product_sku_clean LIKE 'DP %'
        OR product_sku_clean LIKE 'DATU PUTI%'
        OR product_sku_clean LIKE 'DPUTI%'
        THEN 'Datu Puti'
      -- TRIM removes unnecessary spaces around the brand.
      ELSE TRIM(product_brand)
    END
  ) AS product_brand,

  -- QUANTITY
  -- Zero-quantity transactions will be removed later using the WHERE condition at the bottom.
  quantity,


  -- TOTAL UNIT PRICE
  -- ROUND(value, 2) rounds the price to exactly 2 decimal places.
  -- Example: 125.678 → 125.68
  -- The 4 near-zero-price rows are intentionally NOT changed.
  ROUND(total_unit_price, 2) AS total_unit_price,

  -- The high-price standard-deviation outliers are also intentionally left unchanged.


  -- RETAILER
  -- Convert retailer names to uppercase for consistency.
  UPPER(retailer) AS retailer,
  -- Company E branches were already correctly classified as Puregold in the source data.

  -- BRANCH
  -- Clean and standardize the branch name.
  -- 1. Fix the typo "EASTMART" → "EASYMART"
  -- 2. Standardize hyphens/dashes to " - "
  -- 3. Remove extra spaces and convert to uppercase
  UPPER(
    -- TRIM removes spaces from the beginning and end.
    TRIM(
      -- REGEXP_REPLACE standardizes different types of hyphens/dashes.
      -- [-–]+ means one or more normal hyphens "-"
      -- They are replaced with " - ".
      REGEXP_REPLACE(
        -- REPLACE fixes the specific EASTMART typo.
        REPLACE(
          branch,
          'EASTMART',
          'EASYMART'
        ),
        '[-–]+',
        ' - '
      )
    )
  ) AS branch

--SOURCE TABLE
FROM cleaned_sku

-- REMOVE ZERO-QUANTITY TRANSACTIONS
-- Only keep transactions where quantity is NOT zero.
WHERE quantity <> 0;

-- VIEW THE CLEANED TABLE
SELECT *
FROM transactions_cleaned;

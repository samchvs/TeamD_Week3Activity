-- CREATE CLEANED LOYALTY CARDHOLDERS SILVER TABLE --
CREATE OR REPLACE TABLE loyalty_cardholders_silver AS
WITH parsed_birthday AS (
    SELECT
        user_id,
        registered_date,
    
-- PARSE/FORMATTING FOR BIRTHDAYS --
-- COALESCE returns the first successful dates/values, used to allow us to handle different formats
        COALESCE(
            TRY_CAST(birthday AS DATE),   -- Tries to convert if already in ISO format (yyyy-MM-dd)
            TRY_TO_DATE(birthday, 'M/d/yy'), -- Months & days with 2-digit year (7/25/98, 12/5/01)
            TRY_TO_DATE(birthday, 'M/d/yyyy'), -- Months & days with 4-digit year (7/25/1998)
            TRY_TO_DATE(birthday, 'MM-dd-yyyy') -- Zero-padded format with dashes (07-25-1998)
        ) AS parsed_birthday_raw
    FROM loyalty_cardholders_bronze
),

-- ADJUSTED YEARS FOR THE 2-DIGIT YEAR CENTURY PROBLEM CASE --
-- When 2-digit years like '98' are parsed as 2098 (future), subtract 100 years to get 1998
-- This assumes birthdates should be in the past (no one born in the future can register)

adjusted_birthday AS (
    SELECT
        user_id,
        registered_date,
        CASE
            WHEN parsed_birthday_raw > CURRENT_DATE() 
                THEN DATE_SUB(parsed_birthday_raw, 100 * 365)  -- minus 100 years (98 -> 1998)
            ELSE parsed_birthday_raw
        END AS parsed_birthday
    FROM parsed_birthday
)

-- VALIDATION RULES OF BIRTHDAYS --
-- 1. must be a VALID DATE
-- 2. cannot be in the FUTURE
-- 3. cannot occur after the REGISTRATION DATE (person must exist before registering)
-- 4. cannot be older than 122 years at registration time (MAXIMUM AGE VALIDATION/oldest verified person)
SELECT
    user_id,
    CAST(registered_date AS DATE) AS registered_date,  -- Convert TIMESTAMP to DATE for consistency
    CASE 
        WHEN parsed_birthday IS NULL THEN NULL -- if the bday is an INVALID DATE/cannot be converted
        WHEN parsed_birthday > CURRENT_DATE() THEN NULL -- if bday is in the FUTURE
        WHEN parsed_birthday > registered_date THEN NULL -- if bday occurs AFTER registration date
        WHEN DATEDIFF(registered_date, parsed_birthday) / 365.25 > 122 
            THEN NULL -- if person was older than 122 years at registration time
        ELSE parsed_birthday -- if all validation rules are passed
    END AS birthday,
    
    -- DATA QUALITY FLAG: identify rows with data issues
    CASE
        WHEN parsed_birthday IS NULL THEN 'INVALID_BIRTHDAY_FORMAT'
        WHEN parsed_birthday > CURRENT_DATE() THEN 'BIRTHDAY_IN_FUTURE'
        WHEN parsed_birthday > registered_date THEN 'BIRTHDAY_AFTER_REGISTRATION'
        WHEN DATEDIFF(registered_date, parsed_birthday) / 365.25 > 122 THEN 'AGE_EXCEEDS_122_YEARS'
        ELSE 'OK'
    END AS data_quality_flag
FROM adjusted_birthday;


  -- Final summary
  -- SELECT
   -- COUNT(*) AS total_records,
   -- COUNT(DISTINCT user_id) AS unique_users,
   -- MIN(registered_date) AS earliest_registration,
   -- MAX(registered_date) AS latest_registration,
   -- MIN(birthday) AS oldest_birthday,
   -- MAX(birthday) AS youngest_birthday,
   -- SUM(CASE WHEN birthday IS NULL THEN 1 ELSE 0 END) AS null_birthdays
-- FROM loyalty_cardholders_silver;

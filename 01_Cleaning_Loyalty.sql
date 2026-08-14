
-- Create a new cleaned customer table.
-- If the table already exists, REPLACE it with the new results.
CREATE OR REPLACE TABLE workspace.default.customers_cleaned AS

SELECT
  -- Keep the customer's unique ID from the original table.
  user_id,


  -- Convert the birthday from text (MM/DD/YY) into a proper DATE format.
  -- split() separates the birthday into month, day, and year.
  -- CAST() converts the text values into numbers.
  -- make_date() combines the year, month, and day into a date.
  make_date(

    -- Convert the 2-digit year into a 4-digit year.
    -- If the year is 30 or below, assume it belongs to the 2000s.
    -- Example: 25 -> 2025
    -- Otherwise, assume it belongs to the 1900s.
    -- Example: 85 -> 1985
    CASE
      WHEN CAST(split(birthday, '/')[2] AS INT) <= 30
        THEN 2000 + CAST(split(birthday, '/')[2] AS INT)
      ELSE 1900 + CAST(split(birthday, '/')[2] AS INT)
    END,

    -- Extract the month from the birthday.
    CAST(split(birthday, '/')[0] AS INT),

    -- Extract the day from the birthday.
    CAST(split(birthday, '/')[1] AS INT)

  ) AS birthday,


  -- Keep the customer's original registration date.
  registered_date,

  -- FLAGGING SUSPICIOUS AGES
  -- Create a flag to identify customers whose calculated age appears unrealistic or likely caused by incorrect data.
  --
  -- FLAGGED = age is over 100 or under 18
  -- VALID   = age is between 18 and 100
  --
  -- We keep the FLAGGED records instead of deleting them so that
  -- we can trace and review the original data later.
  CASE
    -- Calculate the customer's age.
    -- DATEDIFF(YEAR, birthday, CURRENT_DATE()) returns the
    -- approximate number of years between the birthday and today.
    --
    -- If the calculated age is greater than 100,
    -- mark the record as FLAGGED.
    WHEN DATEDIFF(
           YEAR,
           -- Convert the text birthday into a proper date again.
           make_date(
             CASE
               WHEN CAST(split(birthday, '/')[2] AS INT) <= 30
                 THEN 2000 + CAST(split(birthday, '/')[2] AS INT)
               ELSE 1900 + CAST(split(birthday, '/')[2] AS INT)
             END,
             -- Month
             CAST(split(birthday, '/')[0] AS INT),

             -- Day
             CAST(split(birthday, '/')[1] AS INT)
           ),

           -- Use today's date as the reference point for calculating age.
           CURRENT_DATE()

         ) > 100
      THEN 'FLAGGED'

    -- If the calculated age is below 18,
    -- mark the record as FLAGGED.
    WHEN DATEDIFF(
           YEAR,

           -- Convert the text birthday into a proper date again.
           make_date(
             CASE
               WHEN CAST(split(birthday, '/')[2] AS INT) <= 30
                 THEN 2000 + CAST(split(birthday, '/')[2] AS INT)
               ELSE 1900 + CAST(split(birthday, '/')[2] AS INT)
             END,

             -- Month
             CAST(split(birthday, '/')[0] AS INT),

             -- Day
             CAST(split(birthday, '/')[1] AS INT)
           ),

           -- Use today's date to calculate the age.
           CURRENT_DATE()

         ) < 18
      THEN 'FLAGGED'


    -- If the age is between 18 and 100,
    -- consider the birthday data valid.
    ELSE 'VALID'

  END AS age_validity_flag

-- Get the original customer data from the bronze table.
-- "bronze" is typically the raw/unprocessed layer in a data pipeline.
FROM workspace.default.loyalty_cardholders_bronze;

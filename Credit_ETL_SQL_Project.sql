CREATE DATABASE ETL;
USE ETL;

-- making table same table structure with stg_customer.
CREATE TABLE stg_customers
LIKE cc_customers_dirty;

-- insert all the raw data from cc_cards_dirty to stg customer table for ETL process.
INSERT stg_customers
SELECT * FROM cc_customers_dirty;

CREATE TABLE stg_cards
LIKE cc_cards_dirty;

INSERT stg_cards
SELECT * FROM cc_cards_dirty;

CREATE TABLE stg_transactions
LIKE  cc_transactions_dirty;

INSERT stg_transactions
SELECT * FROM cc_transactions_dirty;

select count(*) from stg_customers;
select count(*) from stg_cards;
select count(*) from stg_transactions;

use etl;
show tables ;
select * from cc_cards_dirty;
select * from cc_customers_dirty;
select * from cc_transactions_dirty;

select * from stg_cards;

SELECT * FROM stg_customers;

-- change date column from text to date
alter table stg_customers
modify date_of_birth date;

-- finding null or blank values in customer, cards or tansactions table -- 
select count(*) from stg_customers where email is null or phone_number is null;
select count(*) from stg_customers where email = "" or phone_number = "";
-- we have 600 rows where customer email or phone number is blank -- 
-- replace blank values with "N/A" --
update stg_customers
set email = "N/A",
phone_number = "N/A"
where email = "" or phone_number = "";
select * from stg_customers;

-- cards -- 
select count(*) from stg_cards where credit_limit is null;
select count(*) from stg_cards where credit_limit = "";

-- 10 rows where credit limit is missing -- 
-- we can use null as well but since i don't have null value so used blank.
select * from stg_cards where credit_limit = ""; 

-- transaction table -- 
select count(*) from stg_transactions where merchant_name = "";
-- we have found 291 merchant names are missing in transaction table 
update stg_transactions
set merchant_name = "N/A"
WHERE merchant_name = ""; 
select * from stg_transactions where merchant_name = "";

-- Find Inconsistent Text/Typos (and count them):
select distinct card_type, length(card_type) as card_length from stg_cards order by card_type;
-- we have leading or trailing spaces in the card type -- 
update stg_cards
set card_type = trim(card_type);

-- customers -- 
select city, count(*) from stg_customers group by city having count(*) < 5; 
-- (Small counts might indicate typos) we don't have it
select * from stg_cards;

-- transactions -- 
select distinct transaction_currency from stg_transactions;
-- we have inconsistency on currency --
update stg_transactions
set transaction_currency =
case
	when transaction_currency = "GB" then "GBP"
    when transaction_currency = "IN" then "INR"
    when transaction_currency = "EU" then "EUR"
    when transaction_currency = "US$" then "USD"
    else transaction_currency
end;
select * from stg_transactions;

-- Detect Duplicates:
select * from stg_customers;
select customer_name, email, count(*) as dup_count
from stg_customers
group by customer_name, email
having count(*) > 1;

-- using windows functions -- 
with cus_dup as (
	select *, 
	row_number() over(partition by customer_name, email order by customer_id) as dup_rank
	from stg_customers
 )   
select * from cus_dup where dup_rank > 1;

select * from stg_customers where customer_name in('Lipika Sinha', 'Udant bhargava', 'yashica radhakrishnan');

-- Identify Outliers/Invalid Ranges:
select min(transaction_amount) as min_amt, max(transaction_amount) as max_amt
from stg_transactions;
-- (Look for negatives or extremely high values) and we have observed it.

select customer_id, date_of_birth 
from stg_customers where date_of_birth > curdate() or date_of_birth < '1920-01-01';

select date_of_birth, date_format(date_of_birth, "%d-%b-%y") as DOB from stg_customers;

SELECT card_id, expiration_date FROM stg_cards WHERE STR_TO_DATE(expiration_date, '%Y-%m-%d') < CURDATE(); -- (Expired cards)

-- Check Referential Integrity Violations:
select
t.card_id from stg_transactions t 
left join stg_cards  c on t.card_id = c.card_id
where c.card_id is null limit 25;

select * from (
select *,
row_number() over(partition by customer_name, email order by customer_Id) as rnk
from stg_customers
where customer_name != '' or email != ""
) as b
where b.rnk > 1;

-- lastly we can creat a new table and import all the data using etl process to directly EXTRACT TRANSFORM AND LOAD -- 

CREATE TABLE dim_customers (
    customer_pk INT AUTO_INCREMENT PRIMARY KEY, -- Surrogate key
    customer_id VARCHAR(50) UNIQUE, -- Natural key
    customer_name VARCHAR(255),
    email VARCHAR(255),
    phone_number VARCHAR(50),
    address TEXT,
    city VARCHAR(100),
    country VARCHAR(100),
    date_of_birth DATE,
    age INT, -- Derived attribute
    employment_status VARCHAR(100),
    income_level DECIMAL(12,2)
);

INSERT INTO dim_customers (customer_id, customer_name, email, phone_number, address, city, country, date_of_birth, age, employment_status, income_level)
SELECT
    sq.customer_id,
    TRIM(sq.customer_name),
    COALESCE(TRIM(sq.email), 'N/A'),
    COALESCE(TRIM(sq.phone_number), 'N/A'),
    TRIM(sq.address),
    CASE -- Clean city names
        WHEN LOWER(sq.city) = 'mumbai ' THEN 'Mumbai'
        WHEN LOWER(sq.city) = 'new yorkx' THEN 'New York'
        ELSE TRIM(sq.city)
    END,
    CASE -- Clean country names
        WHEN LOWER(sq.country) = 'us' THEN 'USA'
        WHEN LOWER(sq.country) = 'united kingdom' THEN 'UK'
        ELSE TRIM(sq.country)
    END,
    STR_TO_DATE(sq.date_of_birth, '%Y-%m-%d'), -- Assuming primary format
    TIMESTAMPDIFF(YEAR, STR_TO_DATE(sq.date_of_birth, '%Y-%m-%d'), CURDATE()), -- Calculate age
    TRIM(sq.employment_status),
    CASE -- Handle income level outliers/nulls
        WHEN CAST(sq.income_level AS DECIMAL(12,2)) < 1000 OR CAST(sq.income_level AS DECIMAL(12,2)) IS NULL THEN 0.00 -- Or an average
        ELSE CAST(sq.income_level AS DECIMAL(12,2))
    END
FROM (
    SELECT
        *,
        ROW_NUMBER() OVER(PARTITION BY customer_name, email ORDER BY customer_id) as rn
    FROM stg_customers
    WHERE email IS NOT NULL AND customer_name IS NOT NULL -- Simple filter for duplicates
) sq
WHERE sq.rn = 1 -- Only take the first instance for duplicates
AND STR_TO_DATE(sq.date_of_birth, '%Y-%m-%d') BETWEEN '1920-01-01' AND CURDATE() - INTERVAL 18 YEAR; -- Filter valid ages;

select * from dim_customers;

SELECT * FROM stg_cards;
SELECT * FROM stg_transactions;
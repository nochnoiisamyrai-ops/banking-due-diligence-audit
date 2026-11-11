-- =====================================================================
-- DATABASE SCHEMA: Bank Analytics DB (Star Schema)
-- Target Platform: PostgreSQL 15+
-- Description: Creates 12 relational tables (dimensions and facts)
-- =====================================================================

DROP TABLE IF EXISTS fact_account_balance_monthly CASCADE;
DROP TABLE IF EXISTS fact_bonus_redemption CASCADE;
DROP TABLE IF EXISTS fact_bonus_accrual CASCADE;
DROP TABLE IF EXISTS fact_payments CASCADE;
DROP TABLE IF EXISTS fact_transfers CASCADE;
DROP TABLE IF EXISTS fact_transactions CASCADE;
DROP TABLE IF EXISTS dim_bonus_programs CASCADE;
DROP TABLE IF EXISTS dim_channels CASCADE;
DROP TABLE IF EXISTS dim_merchants CASCADE;
DROP TABLE IF EXISTS dim_cards CASCADE;
DROP TABLE IF EXISTS dim_accounts CASCADE;
DROP TABLE IF EXISTS dim_customers CASCADE;

-- ---------------------------------------------------------------------
-- DIMENSION TABLES (dim_*)
-- ---------------------------------------------------------------------

-- 1. dim_customers (15,000 rows)
CREATE TABLE dim_customers (
    customer_id INT PRIMARY KEY,
    first_name TEXT,
    last_name TEXT,
    gender TEXT,
    birth_date DATE,
    city TEXT,
    region TEXT,
    segment TEXT,
    registration_date DATE,
    kyc_status TEXT,
    income_bracket TEXT,
    marital_status TEXT,
    referral_source TEXT,
    is_churned BOOLEAN,
    churn_date DATE,
    email TEXT,
    phone TEXT
);

-- 2. dim_accounts (22,521 rows)
CREATE TABLE dim_accounts (
    account_id INT PRIMARY KEY,
    customer_id INT REFERENCES dim_customers(customer_id),
    account_type TEXT,
    currency TEXT,
    open_date DATE,
    close_date DATE,
    status TEXT,
    credit_limit NUMERIC,
    interest_rate NUMERIC
);

-- 3. dim_cards (16,895 rows)
CREATE TABLE dim_cards (
    card_id INT PRIMARY KEY,
    account_id INT REFERENCES dim_accounts(account_id),
    card_type TEXT,
    card_network TEXT,
    issue_date DATE,
    expiry_date DATE,
    status TEXT,
    is_virtual BOOLEAN
);

-- 4. dim_merchants (5,000 rows)
CREATE TABLE dim_merchants (
    merchant_id INT PRIMARY KEY,
    merchant_name TEXT,
    mcc_code TEXT,
    category TEXT,
    city TEXT,
    is_online BOOLEAN
);

-- 5. dim_channels (7 rows)
CREATE TABLE dim_channels (
    channel_id INT PRIMARY KEY,
    channel_name TEXT
);

-- 6. dim_bonus_programs (8 rows)
CREATE TABLE dim_bonus_programs (
    program_id INT PRIMARY KEY,
    program_name TEXT,
    category TEXT,
    accrual_rate_pct NUMERIC
);


-- ---------------------------------------------------------------------
-- FACT TABLES (fact_*)
-- ---------------------------------------------------------------------

-- 7. fact_transactions (700,000 rows)
CREATE TABLE fact_transactions (
    transaction_id BIGINT PRIMARY KEY,
    account_id INT REFERENCES dim_accounts(account_id),
    card_id INT REFERENCES dim_cards(card_id),
    merchant_id INT REFERENCES dim_merchants(merchant_id),
    category TEXT,
    channel_id INT REFERENCES dim_channels(channel_id),
    transaction_type TEXT,
    amount NUMERIC,
    currency TEXT,
    transaction_ts TIMESTAMP,
    status TEXT,
    is_fraud_flag BOOLEAN,
    balance_after NUMERIC
);

-- 8. fact_transfers (84,415 rows)
CREATE TABLE fact_transfers (
    transfer_id BIGINT PRIMARY KEY,
    transaction_id BIGINT REFERENCES fact_transactions(transaction_id),
    sender_account_id INT REFERENCES dim_accounts(account_id),
    receiver_account_id INT REFERENCES dim_accounts(account_id),
    receiver_bank TEXT,
    transfer_type TEXT,
    fee_amount NUMERIC
);

-- 9. fact_payments (76,590 rows)
CREATE TABLE fact_payments (
    payment_id BIGINT PRIMARY KEY,
    transaction_id BIGINT REFERENCES fact_transactions(transaction_id),
    account_id INT REFERENCES dim_accounts(account_id),
    provider_category TEXT,
    provider_name TEXT,
    amount NUMERIC,
    status TEXT
);

-- 10. fact_bonus_accrual (197,278 rows)
CREATE TABLE fact_bonus_accrual (
    accrual_id BIGINT PRIMARY KEY,
    transaction_id BIGINT REFERENCES fact_transactions(transaction_id),
    customer_id INT REFERENCES dim_customers(customer_id),
    program_id INT REFERENCES dim_bonus_programs(program_id),
    points_earned NUMERIC,
    accrual_date TIMESTAMP
);

-- 11. fact_bonus_redemption (50,000 rows)
CREATE TABLE fact_bonus_redemption (
    redemption_id BIGINT PRIMARY KEY,
    customer_id INT REFERENCES dim_customers(customer_id),
    program_id INT REFERENCES dim_bonus_programs(program_id),
    points_spent NUMERIC,
    redemption_date DATE,
    redemption_type TEXT,
    status TEXT
);

-- 12. fact_account_balance_monthly (540,504 rows)
CREATE TABLE fact_account_balance_monthly (
    account_id INT REFERENCES dim_accounts(account_id),
    snapshot_month TEXT, -- Format 'YYYY-MM'
    balance NUMERIC,
    avg_daily_balance NUMERIC,
    transaction_count INT,
    is_open_flag BOOLEAN,
    is_active_flag BOOLEAN,
    PRIMARY KEY (account_id, snapshot_month)
);

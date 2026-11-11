-- =====================================================================
-- BLOCK 2. BALANCES AND DEPOSITS
-- Buyer's key question: how much money does the bank actually hold,
-- and how stable is it?
-- Tables: fact_account_balance_monthly, dim_accounts, dim_customers
-- Period: monthly data 2024-01 to 2025-12
-- =====================================================================

-- DEFINITIONS
-- Deposit funds    = balances on accounts of type current, savings, deposit
--                    (credit accounts are analysed separately)
-- Month-end balance = balance at the end of the month
-- Large customer   = top 10% by total balance in the last month
-- Hidden churn     = customer with is_churned = false and no active account
--                    for 3 consecutive months (see Block 1)
-- Currencies are analysed separately: there is no exchange rate table in the database.

-- DATA PASSPORT
-- 1. Distribution of accounts by type and currency
SELECT
    account_type,
    currency,
    COUNT(*) AS accounts
FROM dim_accounts
GROUP BY account_type, currency
ORDER BY account_type, currency;
-- result: types: credit, current, deposit, savings; currencies: EUR, KGS, USD

-- 2. Sign and size of balances by account type (credit accounts in particular)
SELECT
    a.account_type,
    COUNT(b.balance) AS rows_with_balance,
    MIN(b.balance) AS min_balance,
    ROUND(AVG(b.balance), 0) AS avg_balance,
    MAX(b.balance) AS max_balance
FROM fact_account_balance_monthly b
JOIN dim_accounts a ON a.account_id = b.account_id
GROUP BY a.account_type
ORDER BY a.account_type;

-- 3. Number of rows by month, share of NULL in balance
SELECT
    snapshot_month,
    COUNT(*) AS rows_total,
    COUNT(balance) AS rows_with_balance,
    COUNT(*) - COUNT(balance) AS balance_null
FROM fact_account_balance_monthly
GROUP BY snapshot_month
ORDER BY snapshot_month;
-- result: 24 monthly snapshots (2024-01 to 2025-12)

-- HYPOTHESIS 2.1. Total balance is growing
-- Question: does the total balance of deposit funds in KGS grow
-- from month to month in 2024-2025?
-- Expectation: yes, it grows.
-- Meaning for the buyer: the bank's funding base is growing or shrinking.
-- Limitation: other currencies are not converted to KGS.
SELECT
    a.currency,
    b.snapshot_month,
    COUNT(b.balance) AS accounts_with_balance,
    ROUND(SUM(b.balance), 0) AS total_balance,
    ROUND(AVG(b.balance), 0) AS avg_balance_per_account,
    ROUND(100.0 * (SUM(b.balance) - LAG(SUM(b.balance)) OVER (PARTITION BY a.currency ORDER BY b.snapshot_month))
          / LAG(SUM(b.balance)) OVER (PARTITION BY a.currency ORDER BY b.snapshot_month), 1) AS mom_pct
FROM fact_account_balance_monthly b
JOIN dim_accounts a ON a.account_id = b.account_id
WHERE a.account_type IN ('current', 'savings', 'deposit')
  AND a.currency = 'KGS'
  AND b.balance IS NOT NULL
GROUP BY a.currency, b.snapshot_month
ORDER BY a.currency, b.snapshot_month;
-- result: KGS deposit funds 81.4 million (2024-01) -> 343.5 million (2025-12), +322%;
-- average balance per account 24,495 -> 24,939 (+1.8%)

-- HYPOTHESIS 2.2. Deposit concentration
-- Question: do the top 10% of customers hold more than half of deposits?
-- Expectation: yes.
-- Meaning for the buyer: the departure of a few customers hits the bank's funding.
-- Limitation: calculated per customer, not per account; one month (2025-12), KGS only.
WITH cust AS (
    SELECT
        a.customer_id,
        SUM(b.balance) AS total_balance
    FROM fact_account_balance_monthly b
    JOIN dim_accounts a ON b.account_id = a.account_id
    WHERE b.snapshot_month = '2025-12'
    AND a.currency = 'KGS'
    AND a.account_type IN ('current', 'savings', 'deposit')
        AND b.balance IS NOT NULL
    GROUP BY a.customer_id
),
    ranked AS (
        SELECT customer_id, total_balance,
               NTILE(10) OVER (ORDER BY total_balance DESC) AS decile
        FROM cust
    )
SELECT
    decile,
    COUNT(*) AS customers,
    ROUND(SUM(total_balance), 0) AS total_balance,
    ROUND(100.0 * SUM(total_balance) / SUM(SUM(total_balance)) OVER (), 1) AS pct
FROM ranked
GROUP BY decile
ORDER BY decile;
-- result: the top 10% of customers (decile 1) hold 41.1% of KGS deposits

-- HYPOTHESIS 2.3. Balance structure by account type
-- Question: do balances on current accounts outweigh term deposits?
-- Expectation: yes.
-- Meaning for the buyer: money on current accounts is less stable.
-- Limitations: calculated on a single snapshot (2025-12) and in KGS only;
-- account type is used as a proxy for stability (deposit terms are not
-- in the data); credit accounts are excluded; the data is synthetic.
SELECT
    a.account_type,
    COUNT(b.balance) AS accounts,
    ROUND(SUM(b.balance), 0) AS total_balance,
    ROUND(100.0 * SUM(b.balance) / SUM(SUM(b.balance)) OVER (), 1) AS pct
FROM fact_account_balance_monthly b
JOIN dim_accounts a ON a.account_id = b.account_id
WHERE b.snapshot_month = '2025-12'
  AND a.currency = 'KGS'
  AND a.account_type IN ('current', 'savings', 'deposit')
  AND b.balance IS NOT NULL
GROUP BY a.account_type
ORDER BY total_balance DESC;
-- result: current 54.8%, savings 28.6%, deposit 16.5%

-- HYPOTHESIS 2.4. Balance behaviour before account closure
-- Question: does the balance decline in the 3-6 months before an account is closed?
-- Expectation: yes.
-- Meaning for the buyer: an early signal of money outflow.
-- Limitation: accounts closed before 2024 are not visible in the data.
WITH closed AS (
    SELECT account_id, close_date
    FROM dim_accounts
    WHERE close_date >= '2024-07-01'
      AND currency = 'KGS'
      AND account_type IN ('current', 'savings', 'deposit')
)
SELECT
    (EXTRACT(YEAR FROM c.close_date) * 12 + EXTRACT(MONTH FROM c.close_date))
  - (EXTRACT(YEAR FROM TO_DATE(b.snapshot_month || '-01', 'YYYY-MM-DD')) * 12
     + EXTRACT(MONTH FROM TO_DATE(b.snapshot_month || '-01', 'YYYY-MM-DD'))) AS months_before_close,
    COUNT(b.balance) AS accounts,
    ROUND(AVG(b.balance), 0) AS avg_balance
FROM closed c
JOIN fact_account_balance_monthly b ON b.account_id = c.account_id
WHERE b.balance IS NOT NULL
GROUP BY 1
HAVING (EXTRACT(YEAR FROM c.close_date) * 12 + EXTRACT(MONTH FROM c.close_date))
     - (EXTRACT(YEAR FROM TO_DATE(b.snapshot_month || '-01', 'YYYY-MM-DD')) * 12
        + EXTRACT(MONTH FROM TO_DATE(b.snapshot_month || '-01', 'YYYY-MM-DD'))) BETWEEN 1 AND 6
ORDER BY months_before_close DESC;
-- result: average balance 6 -> 1 months before closure: 25,276 -> 24,380 (-3.5%), uneven

-- HYPOTHESIS 2.5. Money held by hidden-churn customers
-- Question: what share of balances is held by customers with hidden churn
--           from Block 1?
-- Expectation: noticeable.
-- Meaning for the buyer: shows whether the money is lost together with the customer.
-- Limitation: customers without a KGS balance in 2025-12 are not included;
--             customers registered after June 2025 are excluded.
WITH cust_month AS (
    SELECT a.customer_id, b.snapshot_month,
           MAX(CASE WHEN b.is_active_flag THEN 1 ELSE 0 END) AS active
    FROM fact_account_balance_monthly b
    JOIN dim_accounts a ON a.account_id = b.account_id
    GROUP BY a.customer_id, b.snapshot_month
),
last_active AS (
    SELECT customer_id, MAX(snapshot_month) AS last_active_month
    FROM cust_month
    WHERE active = 1
    GROUP BY customer_id
),
bal AS (
    SELECT a.customer_id, SUM(b.balance) AS balance
    FROM fact_account_balance_monthly b
    JOIN dim_accounts a ON a.account_id = b.account_id
    WHERE b.snapshot_month = '2025-12'
      AND a.currency = 'KGS'
      AND a.account_type IN ('current', 'savings', 'deposit')
      AND b.balance IS NOT NULL
    GROUP BY a.customer_id
)
SELECT
    CASE WHEN la.last_active_month IS NULL OR la.last_active_month <= '2025-09'
         THEN 'hidden_churn_3m' ELSE 'active' END AS client_group,
    COUNT(*) AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_customers,
    ROUND(SUM(bal.balance), 0) AS total_balance,
    ROUND(100.0 * SUM(bal.balance) / SUM(SUM(bal.balance)) OVER (), 1) AS pct_of_balance
FROM dim_customers c
JOIN bal ON bal.customer_id = c.customer_id
LEFT JOIN last_active la ON la.customer_id = c.customer_id
WHERE NOT c.is_churned
  AND c.registration_date < '2025-07-01'
GROUP BY 1;
-- result: hidden-churn customers hold 5.2% of balances, against about 11.4% of
-- not-churned customers (Block 1)

-- =====================================================================
-- BLOCK 2 SUMMARY. BALANCES AND DEPOSITS
-- =====================================================================
-- Block status: requires attention
--
-- Rationale: the funding base is growing, but through a larger number of
--   accounts rather than larger balances per account; more than half of the
--   money sits on current accounts; the top 10% of customers hold 41% of deposits.
--
-- Results by hypothesis:
--   2.1 Total balance is growing: confirmed. 81.4 million (2024-01) ->
--       343.5 million KGS (2025-12), growth of 322%. Average balance per account
--       barely changed: 24,495 -> 24,939 (+1.8%), so growth comes
--       from a larger number of accounts.
--   2.2 Concentration: not confirmed. The top 10% of customers hold 41.1%
--       of deposits (the 50% threshold is not reached), concentration is moderate.
--   2.3 Structure: confirmed. current 54.8%, savings 28.6%,
--       deposit 16.5%. More than half of the money sits on accounts that
--       can be closed at any time.
--   2.4 Balance before account closure: not confirmed as an early signal.
--       From 6 -> 1 months before closure the balance falls by 3.5%
--       (25,276 -> 24,380) and unevenly: money leaves together
--       with the closure of the account, not in advance.
--   2.5 Money held by hidden-churn customers: they account for 5.2%
--       of balances, with such customers making up about 11.4% of not-churned
--       customers (Block 1). Inactive customers hold less money than their
--       headcount share suggests, so the distortion of churn reporting is
--       smaller in money terms than in customer terms.
--
-- What this means for the buyer:
--   The stability of the funding base depends on the inflow of new customers
--   and accounts. An outflow of money cannot be anticipated from balances.
--   The departure of several large customers would be noticeable but not
--   critical. The understatement of churn in reporting (Block 1) is limited
--   in money terms.
--
-- Main limitation: no exchange rates (KGS only); account type is used
--   as a proxy for stability (no deposit terms); structure and concentration
--   are calculated for one month; customers without a KGS balance are not
--   included in 2.5; the data is synthetic.

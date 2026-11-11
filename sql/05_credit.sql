-- =====================================================================
-- BLOCK 5. CREDIT PORTFOLIO
-- Buyer's key question: what should the bank get back, and are there
-- signs of customer over-indebtedness?
-- Tables: dim_accounts, fact_account_balance_monthly, dim_customers,
--         dim_cards
-- Period: monthly data 2024-01 to 2025-12
-- Important: the database has no data on delinquencies or defaults; only
-- the use of credit lines is assessed.
-- =====================================================================

-- DEFINITIONS
-- Credit portfolio  = accounts with account_type = 'credit', currency KGS,
--                     open in the month (balance is not NULL)
-- Debt              = balance on the credit account (all balances are positive)
-- Limit utilization = debt / credit_limit
-- High utilization  = 80% or more
-- Unused            = utilization of 0


-- DATA PASSPORT
-- 0.1 Credit accounts by status and currency, limits and rates
SELECT
    status,
    currency,
    COUNT(*) AS accounts,
    COUNT(credit_limit) AS with_limit,
    ROUND(MIN(credit_limit), 0) AS min_limit,
    ROUND(AVG(credit_limit), 0) AS avg_limit,
    ROUND(MAX(credit_limit), 0) AS max_limit,
    ROUND(MIN(interest_rate), 1) AS min_rate,
    ROUND(AVG(interest_rate), 1) AS avg_rate,
    ROUND(MAX(interest_rate), 1) AS max_rate
FROM dim_accounts
WHERE account_type = 'credit'
GROUP BY status, currency
ORDER BY currency, status;
-- result 0.1: all KGS credit accounts with a balance were included in the calculation
-- (sum of monthly account counts in 5.1 = 18,249 = rows in 0.2)

-- 0.2 Sign of balances, limit overruns
SELECT
    a.currency,
    COUNT(b.balance) AS rows_with_balance,
    SUM(CASE WHEN b.balance < 0 THEN 1 ELSE 0 END) AS negative_rows,
    SUM(CASE WHEN b.balance = 0 THEN 1 ELSE 0 END) AS zero_rows,
    SUM(CASE WHEN b.balance > 0 THEN 1 ELSE 0 END) AS positive_rows,
    ROUND(MIN(b.balance), 0) AS min_balance,
    ROUND(AVG(b.balance), 0) AS avg_balance,
    ROUND(MAX(b.balance), 0) AS max_balance,
    SUM(CASE WHEN ABS(b.balance) > a.credit_limit THEN 1 ELSE 0 END) AS over_limit_rows
FROM fact_account_balance_monthly b
JOIN dim_accounts a ON a.account_id = b.account_id
WHERE a.account_type = 'credit'
GROUP BY a.currency
ORDER BY a.currency;
-- result 0.2: all balances are positive (no negative or zero balances);
-- rows with debt above the limit: KGS 1,456 of 18,249, EUR 89 of 1,051, USD 219 of 2,237

-- 0.3 Credit cards by status
SELECT
    c.status,
    COUNT(*) AS cards,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM dim_cards c
JOIN dim_accounts a ON a.account_id = c.account_id
WHERE a.account_type = 'credit'
GROUP BY c.status
ORDER BY cards DESC;
-- result 0.3: 2,784 credit cards; active 2,676 (96.1%), expired 58 (2.1%), blocked 50 (1.8%)

-- 0.4 Number of credit accounts per customer
WITH x AS (
    SELECT customer_id, COUNT(*) AS n_credit
    FROM dim_accounts
    WHERE account_type = 'credit'
    GROUP BY customer_id
)
SELECT
    n_credit,
    COUNT(*) AS customers
FROM x
GROUP BY n_credit
ORDER BY n_credit;
-- result 0.4: 2,129 customers with credit accounts (all time, all currencies, all statuses):
-- 1 account - 2,037, 2 accounts - 90, 3 accounts - 2; 2,223 credit accounts in total;
-- 4.3% of borrowers have more than one credit account, so accounts are aggregated
-- to customer level in 5.4 and 5.5

-- HYPOTHESIS 5.1. Debt grows faster than limits
-- Question: does limit utilization (debt / limit) grow from 2024-01 to 2025-12?
-- Expectation: yes, it grows.
-- Meaning for the buyer: shows whether the issued lines are used more actively.
-- Limitation: utilization is not the same as delinquency or default.
SELECT
    b.snapshot_month,
    COUNT(*) AS credit_accounts,
    ROUND(SUM(a.credit_limit), 0) AS total_limit,
    ROUND(SUM(ABS(b.balance)), 0) AS total_debt,
    ROUND(100.0 * SUM(ABS(b.balance)) / SUM(a.credit_limit), 1) AS utilization_pct
FROM fact_account_balance_monthly b
JOIN dim_accounts a ON a.account_id = b.account_id
WHERE a.account_type = 'credit'
  AND a.currency = 'KGS'
  AND a.credit_limit > 0
  AND b.balance IS NOT NULL
GROUP BY b.snapshot_month
ORDER BY b.snapshot_month;
-- result 5.1: utilization 25.5% (2024-01) -> 26.1% (2025-12), 24.7-26.5% during the period;
-- debt 9.2 -> 37.2 million KGS, limits 36.2 -> 142.6 million, accounts 389 -> 1,492

-- HYPOTHESIS 5.2. A significant share of lines is barely used
-- Question: what share of accounts uses less than 10% of the limit, and how much debt is on them?
-- Expectation: yes, more than one third of accounts.
-- Meaning for the buyer: unused limits are a potential liability of the
--   bank that earns no income.
-- Limitation: a single snapshot (2025-12).
WITH u AS (
    SELECT
        a.account_id,
        ABS(b.balance) AS debt,
        ABS(b.balance) / a.credit_limit AS util
    FROM fact_account_balance_monthly b
    JOIN dim_accounts a ON a.account_id = b.account_id
    WHERE a.account_type = 'credit'
      AND a.currency = 'KGS'
      AND a.credit_limit > 0
      AND b.snapshot_month = '2025-12'
      AND b.balance IS NOT NULL
)
SELECT
    CASE WHEN util = 0 THEN '0: unused'
         WHEN util < 0.10 THEN '1: under 10%'
         WHEN util < 0.50 THEN '2: 10-50%'
         WHEN util < 0.80 THEN '3: 50-80%'
         WHEN util <= 1 THEN '4: 80-100%'
         ELSE '5: over limit' END AS util_bucket,
    COUNT(*) AS accounts,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_accounts,
    ROUND(SUM(debt), 0) AS debt,
    ROUND(100.0 * SUM(debt) / NULLIF(SUM(SUM(debt)) OVER (), 0), 1) AS pct_debt
FROM u
GROUP BY 1
ORDER BY 1;
-- result 5.2 (2025-12): under 10% - 514 accounts (34.5%), 8.5% of debt; 10-50% - 667 (44.7%);
-- 50-80% - 135 (9.0%); 80-100% - 42 (2.8%); over limit - 134 (9.0%), 36.1% of debt;
-- there is no "unused" bucket in the result

-- HYPOTHESIS 5.3. The share of high utilization grows
-- Question: does the share of accounts with utilization of 80% or more grow from 2024-01 to 2025-12?
-- Expectation: yes.
-- Meaning for the buyer: growing customer over-indebtedness.
-- Limitation: the 80% threshold was chosen by the author; high utilization includes limit overruns.
SELECT
    b.snapshot_month,
    COUNT(*) AS credit_accounts,
    SUM(CASE WHEN ABS(b.balance) >= 0.8 * a.credit_limit THEN 1 ELSE 0 END) AS high_util_accounts,
    ROUND(100.0 * SUM(CASE WHEN ABS(b.balance) >= 0.8 * a.credit_limit THEN 1 ELSE 0 END) / COUNT(*), 1) AS high_util_pct
FROM fact_account_balance_monthly b
JOIN dim_accounts a ON a.account_id = b.account_id
WHERE a.account_type = 'credit'
  AND a.currency = 'KGS'
  AND a.credit_limit > 0
  AND b.balance IS NOT NULL
GROUP BY b.snapshot_month
ORDER BY b.snapshot_month;
-- result 5.3: the share of 80%+ grew from 9.5% (37 accounts) to 11.8% (176 accounts)

-- Additional check: limit overruns by month
SELECT
    b.snapshot_month,
    COUNT(*) AS credit_accounts,
    SUM(CASE WHEN ABS(b.balance) > a.credit_limit THEN 1 ELSE 0 END) AS over_limit_accounts,
    ROUND(100.0 * SUM(CASE WHEN ABS(b.balance) > a.credit_limit THEN 1 ELSE 0 END) / COUNT(*), 1) AS over_limit_pct,
    ROUND(SUM(CASE WHEN ABS(b.balance) > a.credit_limit
                   THEN ABS(b.balance) - a.credit_limit ELSE 0 END), 0) AS excess_amount
FROM fact_account_balance_monthly b
JOIN dim_accounts a ON a.account_id = b.account_id
WHERE a.account_type = 'credit'
  AND a.currency = 'KGS'
  AND a.credit_limit > 0
  AND b.balance IS NOT NULL
GROUP BY b.snapshot_month
ORDER BY b.snapshot_month;
-- result: accounts over the limit 30 (7.7%) in 2024-01, 46 (7.5%) in 2024-12, 134 (9.0%) in 2025-12;
-- amount above the limit 1.9 -> 2.4 -> 6.5 million KGS

-- HYPOTHESIS 5.4. High utilization is more common among low-income customers
-- Question: is the share of customers with 80%+ utilization higher in the low group than in high and very_high?
-- Expectation: yes.
-- Meaning for the buyer: whether credit is granted without regard to repayment capacity.
-- Limitation: income is self-declared and missing for ~15%; groups are small; high utilization
--   includes accounts over the limit, so the shares partly reflect overruns,
--   not only high but permitted utilization.
WITH cust AS (
    SELECT
        a.customer_id,
        SUM(ABS(b.balance)) AS debt,
        SUM(a.credit_limit) AS lim
    FROM fact_account_balance_monthly b
    JOIN dim_accounts a ON a.account_id = b.account_id
    WHERE a.account_type = 'credit'
      AND a.currency = 'KGS'
      AND a.credit_limit > 0
      AND b.snapshot_month = '2025-12'
      AND b.balance IS NOT NULL
    GROUP BY a.customer_id
)
SELECT
    COALESCE(c.income_bracket, 'not specified') AS income_group,
    COUNT(*) AS customers,
    ROUND(100.0 * SUM(cust.debt) / SUM(cust.lim), 1) AS utilization_pct,
    SUM(CASE WHEN cust.debt >= 0.8 * cust.lim THEN 1 ELSE 0 END) AS high_util_customers,
    ROUND(100.0 * SUM(CASE WHEN cust.debt >= 0.8 * cust.lim THEN 1 ELSE 0 END) / COUNT(*), 1) AS high_util_pct
FROM cust
JOIN dim_customers c ON c.customer_id = cust.customer_id
GROUP BY 1
ORDER BY high_util_pct DESC;
-- result 5.4 (share of customers with 80%+ utilization): not specified 14.5% (35), medium 12.0% (60),
-- high 11.5% (24), low 10.6% (46), very_high 8.7% (6, not interpretable)

-- HYPOTHESIS 5.5. Debt is concentrated in a small share of customers
-- Question: do the top 10% of borrowers hold more than half of the debt?
-- Expectation: yes.
-- Meaning for the buyer: dependence of the portfolio on a few borrowers.
-- Limitation: one month, KGS only, only customers with debt above zero.
WITH cust AS (
    SELECT
        a.customer_id,
        SUM(ABS(b.balance)) AS debt
    FROM fact_account_balance_monthly b
    JOIN dim_accounts a ON a.account_id = b.account_id
    WHERE a.account_type = 'credit'
      AND a.currency = 'KGS'
      AND b.snapshot_month = '2025-12'
      AND b.balance IS NOT NULL
    GROUP BY a.customer_id
    HAVING SUM(ABS(b.balance)) > 0
),
ranked AS (
    SELECT customer_id, debt,
           NTILE(10) OVER (ORDER BY debt DESC, customer_id) AS decile
    FROM cust
)
SELECT
    decile,
    COUNT(*) AS customers,
    ROUND(SUM(debt), 0) AS debt,
    ROUND(100.0 * SUM(debt) / SUM(SUM(debt)) OVER (), 1) AS pct
FROM ranked
GROUP BY decile
ORDER BY decile;
-- result 5.5: the top 10% of borrowers (146 of 1,453) hold 44.5% of the debt, the top 20% hold 62.0%, the top 30% hold 73.2%


-- =====================================================================
-- BLOCK 5 SUMMARY. CREDIT PORTFOLIO
-- =====================================================================
-- Block status: requires attention
--
-- Rationale: limit utilization is stable (about 26%), but 134 accounts (9.0%)
--   exceed their limit and hold 36.1% of all debt. Overruns are present from
--   the start of the period (7.7% of accounts in January 2024); the amount above
--   the limit grows more slowly than debt (3.4x versus 4.0x), but the share of
--   accounts with overruns is slowly rising. The scale is small (6.5 million KGS),
--   the nature of the overruns is unknown. The database has no data on
--   delinquencies or defaults, so what is assessed is the use of credit lines,
--   not the quality of the portfolio.
--
-- Results by hypothesis:
--   5.1 Debt grows faster than limits: not confirmed. Utilization 25.5%
--       (2024-01) -> 26.1% (2025-12), within 24.7-26.5% during the period.
--       Debt 9.2 -> 37.2 million KGS (4.0x), limits 36.2 -> 142.6 million
--       (3.9x), credit accounts 389 -> 1,492.
--   5.2 Unused lines: confirmed by account count, narrowly (34.5% against a
--       one-third threshold). In December 2025, 34.5% of accounts (514) with
--       utilization under 10% hold 8.5% of debt; there are no fully unused
--       lines (the "unused" bucket is absent from the result). Over the limit:
--       134 accounts (9.0%), 13.4 million, 36.1% of debt.
--   5.3 Share of high utilization (80%+): grows slightly. 9.5% (37 accounts) ->
--       11.8% (176 accounts). Of which over the limit: 30 accounts
--       (7.7% of all) -> 134 (9.0%); the 80-100% bucket: 1.8% -> 2.8%.
--       Amount above the limit: 1.9 -> 6.5 million KGS (3.4x while debt grew
--       4.0x); the overrun share of debt 20.4% -> 16.0% -> 17.4%
--       (2024-01, 2024-12, 2025-12). On accounts with overruns, debt is on
--       average about 1.9 times the limit.
--   5.4 Utilization and income: not confirmed. Share of customers with high
--       utilization: low 10.6%, medium 12.0%, high 11.5%, very_high 8.7%
--       (6 customers, not interpretable), income not specified 14.5%
--       (35 customers, the difference from low may be random).
--   5.5 Concentration: moderate. The top 10% of borrowers (146 of 1,453) hold
--       44.5% of debt, the top 20% hold 62.0%, the top 30% hold 73.2%. For
--       comparison, deposits in Block 2: 41.1%.
--
-- What this means for the buyer:
--   The use of credit lines is stable and does not depend on declared
--   income. About a tenth of accounts exceed their limit, and they carry
--   more than a third of the debt; the amount above the limit is 4.5% of all limits and
--   1.9% of KGS deposits. The bank should be asked whether this is a permitted
--   overdraft or a breach of limits. Debt on credit accounts is
--   10.8% of KGS deposits (343.5 million), so the portfolio is small; unused
--   lines are at least 105 million KGS.
--
-- Main limitation: no data on delinquencies, defaults or provisions;
--   only the use of lines is assessed; debt = ABS(balance),
--   all balances are positive; KGS only; the high-utilization threshold of 80%
--   was chosen by the author; income is self-declared, missing for ~15%; high utilization
--   includes limit overruns; the 2024-2025 trend is set against the anomalous
--   growth of 2025; the link between concentration and overruns was not tested;
--   the nature of the overruns is not visible in the data; the customer analysis (5.4, 5.5)
--   covers 1,453 customers with an open KGS account in December 2025 out of 2,129
--   customers with credit accounts over all time; the data is synthetic.

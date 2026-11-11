-- =====================================================================
-- BLOCK 4. OPERATIONAL RISKS & FRAUD AUDIT
-- Project: Bank Analytics DB (M&A Due Diligence for State Acquisition)
-- Objective: Analyze transaction decline rates, fraud flag distribution,
--            channel risk concentration, and frozen assets.
-- Tables: fact_transactions, dim_channels, dim_merchants, dim_accounts
-- Data Period: 2023-01-01 to 2025-12-31
-- =====================================================================

-- ---------------------------------------------------------------------
-- HYPOTHESIS 4.1: Transaction Decline Rate Trends
-- Question: Is the overall share of declined transactions increasing year-over-year?
-- ---------------------------------------------------------------------
SELECT 
    EXTRACT(YEAR FROM transaction_ts)::INT AS transaction_year,
    COUNT(*) AS total_txns,
    SUM(CASE WHEN status = 'declined' THEN 1 ELSE 0 END) AS declined_txns,
    ROUND(100.0 * SUM(CASE WHEN status = 'declined' THEN 1 ELSE 0 END) / COUNT(*), 2) AS declined_pct,
    SUM(CASE WHEN is_fraud_flag THEN 1 ELSE 0 END) AS fraud_txns,
    ROUND(100.0 * SUM(CASE WHEN is_fraud_flag THEN 1 ELSE 0 END) / COUNT(*), 3) AS fraud_pct
FROM fact_transactions
WHERE transaction_type <> 'fee'
GROUP BY 1
ORDER BY 1;


-- ---------------------------------------------------------------------
-- HYPOTHESIS 4.2: Decline Rate Concentration across Channels (Lift Analysis)
-- Question: Do specific service channels exhibit a disproportionate decline lift (> 1.5)?
-- ---------------------------------------------------------------------
WITH channel_base AS (
    SELECT 
        ch.channel_name,
        t.status
    FROM fact_transactions t
    JOIN dim_channels ch ON ch.channel_id = t.channel_id
    WHERE t.transaction_type <> 'fee'
),
channel_agg AS (
    SELECT 
        channel_name,
        COUNT(*) AS txn_count,
        SUM(CASE WHEN status = 'declined' THEN 1 ELSE 0 END) AS declined_count
    FROM channel_base
    GROUP BY channel_name
)
SELECT 
    channel_name,
    txn_count,
    declined_count,
    ROUND(100.0 * declined_count / txn_count, 2) AS declined_pct,
    ROUND((1.0 * declined_count / SUM(declined_count) OVER ()) / (1.0 * txn_count / SUM(txn_count) OVER ()), 2) AS decline_lift
FROM channel_agg
ORDER BY decline_lift DESC;


-- ---------------------------------------------------------------------
-- HYPOTHESIS 4.3: Fraud Flag Concentration by Channel & Merchant Type
-- Question: Are suspicious operations concentrated in specific online merchants or channels?
-- ---------------------------------------------------------------------
WITH fraud_channel_agg AS (
    SELECT 
        ch.channel_name,
        COUNT(*) AS txn_count,
        SUM(CASE WHEN t.is_fraud_flag THEN 1 ELSE 0 END) AS fraud_count
    FROM fact_transactions t
    JOIN dim_channels ch ON ch.channel_id = t.channel_id
    WHERE t.transaction_type <> 'fee'
    GROUP BY ch.channel_name
)
SELECT 
    channel_name,
    txn_count,
    fraud_count,
    ROUND(100.0 * fraud_count / txn_count, 3) AS fraud_pct,
    ROUND((1.0 * fraud_count / NULLIF(SUM(fraud_count) OVER (), 0)) / (1.0 * txn_count / SUM(txn_count) OVER ()), 2) AS fraud_lift
FROM fraud_channel_agg
ORDER BY fraud_lift DESC;


-- ---------------------------------------------------------------------
-- HYPOTHESIS 4.4: Blocked Accounts & Frozen Liquidity Risk
-- Question: What proportion of accounts and balances are currently frozen/blocked?
-- ---------------------------------------------------------------------
SELECT 
    a.status AS account_status,
    COUNT(*) AS total_accounts,
    ROUND(SUM(b.balance), 0) AS total_balance_kgs,
    ROUND(100.0 * SUM(b.balance) / SUM(SUM(b.balance)) OVER (), 1) AS balance_share_pct
FROM dim_accounts a
LEFT JOIN fact_account_balance_monthly b 
       ON b.account_id = a.account_id 
      AND b.snapshot_month = '2025-12'
WHERE a.currency = 'KGS' 
  AND a.account_type IN ('current', 'savings', 'deposit')
GROUP BY a.status
ORDER BY total_accounts DESC;


-- =====================================================================
-- EXECUTIVE FINDINGS & M&A AUDIT VERDICT: BLOCK 4
-- =====================================================================
/*
STATUS: REQUIRES ATTENTION

Key Metrics & Findings:
1. Low Visible Operational Risk:
   - Overall transaction decline rates remain exceptionally stable (~5.55%), and fraud flags account for a very small fraction of operations (~0.06%).
2. Synthetic Data Uniformity Artifact:
   - Decline rates across individual service channels show an unnatural uniformity (lift values hover strictly around 1.0), revealing a synthetic data generator limitation.
3. Frozen Assets Impact:
   - Blocked accounts represent 0.8% of active KGS accounts, locking up approximately 3.35M KGS (~1.0% of total retail deposit balances).

Buyer Recommendations:
- Request verification from the target bank regarding AML/CFT transaction monitoring coverage, as fraud flags in the database are heavily concentrated in specific subsets (e.g., card purchases) leaving potential blind spots in transfers and payments.
*/

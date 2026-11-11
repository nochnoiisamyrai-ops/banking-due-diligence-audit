-- =====================================================================
-- BLOCK 3. OPERATIONAL ACTIVITY & CHANNEL DYNAMICS
-- Project: Bank Analytics DB (M&A Due Diligence for State Acquisition)
-- Objective: Evaluate whether bank transaction volume growth is organic,
--            assess channel migration, and measure holiday/payroll seasonality.
-- Tables: fact_transactions, dim_channels, dim_accounts
-- Data Period: 2023-01-01 to 2025-12-31
-- =====================================================================

-- ---------------------------------------------------------------------
-- HYPOTHESIS 3.1: YoY Transaction Volume Growth
-- Question: Is active transaction volume growing steadily year-over-year?
-- Operational definition: Completed transactions excluding internal fee charges.
-- ---------------------------------------------------------------------
SELECT 
    EXTRACT(YEAR FROM transaction_ts)::INT AS transaction_year,
    COUNT(*) AS total_completed_txns,
    COUNT(DISTINCT account_id) AS active_accounts,
    ROUND(COUNT(*) * 1.0 / COUNT(DISTINCT account_id), 2) AS txns_per_active_account
FROM fact_transactions
WHERE status = 'completed' AND transaction_type <> 'fee'
GROUP BY 1
ORDER BY 1;


-- ---------------------------------------------------------------------
-- HYPOTHESIS 3.2: Organic Intensity vs. Client Count Expansion
-- Question: Is growth driven by higher activity per account or strictly new accounts?
-- ---------------------------------------------------------------------
WITH monthly_metrics AS (
    SELECT 
        DATE_TRUNC('month', transaction_ts)::DATE AS month_start,
        COUNT(*) AS monthly_txns,
        COUNT(DISTINCT account_id) AS active_accounts
    FROM fact_transactions
    WHERE status = 'completed' AND transaction_type <> 'fee'
    GROUP BY 1
)
SELECT 
    month_start,
    monthly_txns,
    active_accounts,
    ROUND(1.0 * monthly_txns / active_accounts, 2) AS txns_per_account_ratio
FROM monthly_metrics
ORDER BY month_start;


-- ---------------------------------------------------------------------
-- HYPOTHESIS 3.3: Payroll Day & Year-End Load Seasonality
-- Question: Do transaction volumes concentrate heavily on payroll dates (5th, 25th, 30th)?
-- ---------------------------------------------------------------------
SELECT 
    CASE 
        WHEN EXTRACT(DAY FROM transaction_ts) IN (5, 25, 30) THEN 'Payroll Days (5, 25, 30)'
        ELSE 'Regular Days'
    END AS day_category,
    COUNT(*) AS total_txns,
    ROUND(COUNT(*) * 1.0 / COUNT(DISTINCT DATE(transaction_ts)), 0) AS avg_daily_transactions
FROM fact_transactions
WHERE status = 'completed' AND transaction_type <> 'fee'
GROUP BY 1;


-- ---------------------------------------------------------------------
-- HYPOTHESIS 3.4: Digital Channel Adoption Stagnation
-- Question: Is the share of digital transactions (Mobile App, Internet Bank, QR) increasing?
-- ---------------------------------------------------------------------
WITH channel_classified AS (
    SELECT 
        EXTRACT(YEAR FROM t.transaction_ts)::INT AS txn_year,
        CASE 
            WHEN ch.channel_name IN ('Mobile App', 'Internet Bank', 'QR Payment') THEN 'Digital'
            ELSE 'Physical / Traditional'
        END AS channel_type
    FROM fact_transactions t
    JOIN dim_channels ch ON ch.channel_id = t.channel_id
    WHERE t.status = 'completed' AND t.transaction_type <> 'fee'
)
SELECT 
    txn_year,
    COUNT(*) AS total_txns,
    SUM(CASE WHEN channel_type = 'Digital' THEN 1 ELSE 0 END) AS digital_txns,
    ROUND(100.0 * SUM(CASE WHEN channel_type = 'Digital' THEN 1 ELSE 0 END) / COUNT(*), 2) AS digital_share_pct
FROM channel_classified
GROUP BY txn_year
ORDER BY txn_year;


-- =====================================================================
-- EXECUTIVE FINDINGS & M&A AUDIT VERDICT: BLOCK 3
-- =====================================================================
/*
STATUS: REQUIRES ATTENTION

Key Metrics & Findings:
1. Operational Volume Anomaly in 2025:
   - Transaction count expanded rapidly: 43,032 (2023) -> 89,024 (2024) -> 499,046 (2025).
   - 2025 accounts for ~79% of all 3-year system transactions.
   - Transactions per active account jumped from 2.52 (2024) to 4.80 (2025).

2. Digital Channel Stagnation (Synthetic Constraint):
   - Digital channel share remained completely flat at exactly 47.5% - 47.6% across all 3 years.
   - Audit Note: Static channel distribution reflects synthetic data generator rules rather than organic digital transformation.

3. Operational Seasonality:
   - Payroll days (5th, 25th, 30th) generate 26%–36% higher daily volume compared to regular operational days.

Buyer Recommendations:
- Verify whether the 5.6x transaction spike in 2025 represents real organic customer activity or automated technical batch processing prior to sale.
*/

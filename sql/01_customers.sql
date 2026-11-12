-- =====================================================================
-- BLOCK 1. CUSTOMER BASE & CHURN ANALYSIS
-- Project: Bank Analytics DB (M&A Due Diligence for State Acquisition)
-- Objective: Evaluate customer base growth, cohort retention, segment vulnerabilities,
--            and validate official vs. behavioral churn definitions.
-- Tables: dim_customers, dim_accounts, fact_account_balance_monthly
-- Data Period: 2023-01-01 to 2025-12-31 (Monthly activity available: 2024–2025)
-- =====================================================================
-- Check 1.1.1: Total customers vs accounts mapping
SELECT 
    COUNT(DISTINCT c.customer_id) AS total_customers,
    COUNT(DISTINCT a.account_id) AS total_accounts,
    COUNT(DISTINCT c.customer_id) FILTER (WHERE a.account_id IS NOT NULL) AS customers_with_account,
    COUNT(DISTINCT c.customer_id) FILTER (WHERE a.account_id IS NULL) AS orphan_customers
FROM dim_customers c
LEFT JOIN dim_accounts a ON a.customer_id = c.customer_id;
-- Check 1.1.2: Logical inconsistencies in registration and churn dates
SELECT 
    SUM(CASE WHEN is_churned AND churn_date IS NULL THEN 1 ELSE 0 END) AS churned_without_date,
    SUM(CASE WHEN NOT is_churned AND churn_date IS NOT NULL THEN 1 ELSE 0 END) AS date_without_churn_flag,
    SUM(CASE WHEN churn_date < registration_date THEN 1 ELSE 0 END) AS churn_before_registration
FROM dim_customers;
-- ---------------------------------------------------------------------
-- HYPOTHESIS 1.1: Customer Base Growth dynamics
-- Question: Is new customer acquisition slowing down year-over-year?
-- ---------------------------------------------------------------------
SELECT 
    EXTRACT(YEAR FROM registration_date)::INT AS registration_year,
    COUNT(*) AS new_customers,
    COUNT(*) - LAG(COUNT(*)) OVER (ORDER BY EXTRACT(YEAR FROM registration_date)) AS yoy_abs_change,
    ROUND(
        100.0 * (COUNT(*) - LAG(COUNT(*)) OVER (ORDER BY EXTRACT(YEAR FROM registration_date))) 
        / LAG(COUNT(*)) OVER (ORDER BY EXTRACT(YEAR FROM registration_date)), 
        1
    ) AS yoy_pct_change
FROM dim_customers
GROUP BY 1
ORDER BY 1;
-- ---------------------------------------------------------------------
-- HYPOTHESIS 1.2: 12-Month Cohort Retention Degradation
-- Question: Is the 12-month churn rate higher in the 2024 cohort than in 2023?
-- Note: Excludes 2025 cohort as 12 months of observation are not completed.
-- ---------------------------------------------------------------------
SELECT 
    EXTRACT(YEAR FROM registration_date)::INT AS cohort_year,
    COUNT(*) AS total_cohort_customers,
    SUM(CASE WHEN is_churned AND churn_date <= registration_date + INTERVAL '12 months' THEN 1 ELSE 0 END) AS churned_12m,
    ROUND(
        100.0 * SUM(CASE WHEN is_churned AND churn_date <= registration_date + INTERVAL '12 months' THEN 1 ELSE 0 END) 
        / COUNT(*), 
        2
    ) AS churn_12m_pct
FROM dim_customers
WHERE registration_date >= '2023-01-01' AND registration_date < '2025-01-01'
GROUP BY 1
ORDER BY 1;
-- ---------------------------------------------------------------------
-- HYPOTHESIS 1.3: Churn Rate Concentration across Customer Segments
-- Question: Are mass-segment clients or low-income clients churning at higher rates?
-- ---------------------------------------------------------------------
-- By Wealth Segment:
SELECT 
    segment,
    COUNT(*) AS total_customers,
    SUM(CASE WHEN is_churned THEN 1 ELSE 0 END) AS churned_customers,
    ROUND(100.0 * SUM(CASE WHEN is_churned THEN 1 ELSE 0 END) / COUNT(*), 1) AS churn_rate_pct
FROM dim_customers
GROUP BY segment
ORDER BY churn_rate_pct DESC;
-- By Declared Income Bracket (NULLs isolated):
SELECT 
    COALESCE(income_bracket, 'Unspecified') AS income_bracket,
    COUNT(*) AS total_customers,
    SUM(CASE WHEN is_churned THEN 1 ELSE 0 END) AS churned_customers,
    ROUND(100.0 * SUM(CASE WHEN is_churned THEN 1 ELSE 0 END) / COUNT(*), 1) AS churn_rate_pct
FROM dim_customers
GROUP BY 1
ORDER BY churn_rate_pct DESC;
-- ---------------------------------------------------------------------
-- HYPOTHESIS 1.4: Cross-sell Depth vs. Retention
-- Question: Does holding multiple accounts lower the probability of churn?
-- ---------------------------------------------------------------------
WITH account_counts AS (
    SELECT 
        customer_id,
        COUNT(*) AS num_accounts
    FROM dim_accounts
    GROUP BY customer_id
)
SELECT 
    ac.num_accounts,
    COUNT(*) AS total_customers,
    SUM(CASE WHEN c.is_churned THEN 1 ELSE 0 END) AS churned_customers,
    ROUND(100.0 * SUM(CASE WHEN c.is_churned THEN 1 ELSE 0 END) / COUNT(*), 1) AS churn_rate_pct
FROM dim_customers c
JOIN account_counts ac ON ac.customer_id = c.customer_id
GROUP BY ac.num_accounts
ORDER BY ac.num_accounts;
-- ---------------------------------------------------------------------
-- HYPOTHESIS 1.5: Official Churn Flag Inaccuracy (Behavioral vs. Official Churn)
-- Question: Are inactive clients (no transactions for 3+ months) misclassified as active?
-- Filter: Exclude customers registered after 2025-09-30 (insufficient observation window).
-- ---------------------------------------------------------------------
WITH monthly_activity AS (
    SELECT 
        a.customer_id,
        b.snapshot_month,
        MAX(CASE WHEN b.is_active_flag THEN 1 ELSE 0 END) AS was_active
    FROM fact_account_balance_monthly b
    JOIN dim_accounts a ON a.account_id = b.account_id
    GROUP BY a.customer_id, b.snapshot_month
),
last_activity AS (
    SELECT 
        customer_id,
        MAX(snapshot_month) AS last_active_month
    FROM monthly_activity
    WHERE was_active = 1
    GROUP BY customer_id
)
SELECT 
    c.is_churned AS official_churn_flag,
    CASE 
        WHEN la.last_active_month >= '2025-10' THEN 'Active (Last 3M)'
        WHEN la.last_active_month IS NULL THEN 'No Activity Recorded (2024-2025)'
        ELSE 'Behavioral Churn (Inactive 3M+)'
    END AS behavioral_status,
    COUNT(*) AS customer_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS share_pct
FROM dim_customers c
LEFT JOIN last_activity la ON la.customer_id = c.customer_id
WHERE c.registration_date < '2025-10-01'
GROUP BY 1, 2
ORDER BY 1, 2;
-- =====================================================================
-- EXECUTIVE FINDINGS & M&A AUDIT VERDICT: BLOCK 1
-- =====================================================================
/*
STATUS: REQUIRES ATTENTION / RISK

Key Metrics & Findings:
1. Customer Acquisition Anomaly:
   - Registrations surged in 2025: 2,240 (2023) -> 2,706 (2024) -> 5,000 (2025), representing an 84.8% YoY jump in 2025.
   - Buyer Risk: The sudden acceleration in 2025 requires verification of account acquisition quality (e.g., promotional accounts or synthetic batch loading).

2. Retention Quality Degradation:
   - 12-month cohort churn increased from 7.81% (2023 cohort) to 11.68% (2024 cohort), indicating declining customer lifetime value (LTV).

3. Official vs. Actual Churn Misstatement:
   - 11.4% of clients marked as "active" (`is_churned = FALSE`) had zero account activity for 3+ consecutive months.
   - Official reporting understates actual churn, artificially inflating active user counts presented to the buyer.

Buyer Recommendations:
- Require vendor to adjust valuation based on behavioral active clients rather than official database flags.
- Request full audit of the 5,000 new customers registered in 2025 to verify KYC compliance and real transactional activity.
*/

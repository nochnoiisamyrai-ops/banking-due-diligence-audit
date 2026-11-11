-- =====================================================================
-- BLOCK 1: CUSTOMER BASE & CHURN AUDIT
-- M&A Due Diligence - Bank Analytics DB
-- Goal: Verify active user base, registration cohorts, and validate 
--       official churn vs actual transaction behavior.
-- =====================================================================

-- 1. Data Integrity & Orphan Check
-- NOTE: Checking if any customers exist without linked accounts
SELECT 
    COUNT(DISTINCT c.customer_id) AS total_cust,
    COUNT(DISTINCT a.account_id) AS total_acc,
    COUNT(DISTINCT c.customer_id) FILTER (WHERE a.account_id IS NOT NULL) AS cust_with_acc,
    COUNT(DISTINCT c.customer_id) FILTER (WHERE a.account_id IS NULL) AS orphan_cust
FROM dim_customers c
LEFT JOIN dim_accounts a ON a.customer_id = c.customer_id;

-- Sanity check on dates
SELECT 
    COUNT(*) FILTER (WHERE is_churned AND churn_date IS NULL) AS churn_no_date,
    COUNT(*) FILTER (WHERE NOT is_churned AND churn_date IS NOT NULL) AS active_with_churn_date,
    COUNT(*) FILTER (WHERE churn_date < registration_date) AS invalid_churn_dates
FROM dim_customers;


-- 2. Customer Acquisition Dynamics (YoY)
SELECT 
    EXTRACT(YEAR FROM registration_date)::INT AS reg_year,
    COUNT(*) AS new_cust,
    COUNT(*) - LAG(COUNT(*)) OVER (ORDER BY EXTRACT(YEAR FROM registration_date)) AS abs_change,
    ROUND(
        100.0 * (COUNT(*) - LAG(COUNT(*)) OVER (ORDER BY EXTRACT(YEAR FROM registration_date))) 
        / LAG(COUNT(*)) OVER (ORDER BY EXTRACT(YEAR FROM registration_date)), 
        1
    ) AS yoy_growth_pct
FROM dim_customers
GROUP BY 1
ORDER BY 1;


-- 3. 12-Month Cohort Retention Degradation
-- Exclude 2025 cohort (observation window < 12 months)
SELECT 
    EXTRACT(YEAR FROM registration_date)::INT AS cohort_year,
    COUNT(*) AS cohort_size,
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


-- 4. Churn Rate by Wealth Segment & Income
SELECT 
    segment,
    COUNT(*) AS total_cust,
    SUM(CASE WHEN is_churned THEN 1 ELSE 0 END) AS churned_cust,
    ROUND(100.0 * SUM(CASE WHEN is_churned THEN 1 ELSE 0 END) / COUNT(*), 1) AS churn_pct
FROM dim_customers
GROUP BY segment
ORDER BY churn_pct DESC;

SELECT 
    COALESCE(income_bracket, 'Unspecified') AS income_bracket,
    COUNT(*) AS total_cust,
    SUM(CASE WHEN is_churned THEN 1 ELSE 0 END) AS churned_cust,
    ROUND(100.0 * SUM(CASE WHEN is_churned THEN 1 ELSE 0 END) / COUNT(*), 1) AS churn_pct
FROM dim_customers
GROUP BY 1
ORDER BY churn_pct DESC;


-- 5. Cross-sell Depth vs Churn
WITH acc_per_cust AS (
    SELECT customer_id, COUNT(*) AS acc_count
    FROM dim_accounts
    GROUP BY customer_id
)
SELECT 
    apc.acc_count,
    COUNT(*) AS total_cust,
    SUM(CASE WHEN c.is_churned THEN 1 ELSE 0 END) AS churned_cust,
    ROUND(100.0 * SUM(CASE WHEN c.is_churned THEN 1 ELSE 0 END) / COUNT(*), 1) AS churn_pct
FROM dim_customers c
JOIN acc_per_cust apc ON apc.customer_id = c.customer_id
GROUP BY apc.acc_count
ORDER BY apc.acc_count;


-- 6. Behavioral vs Official Churn Audit (Hidden Inactivity)
-- Looking for clients marked as active but having 0 transactions in last 3 months
WITH monthly_act AS (
    SELECT 
        a.customer_id,
        b.snapshot_month,
        MAX(CASE WHEN b.is_active_flag THEN 1 ELSE 0 END) AS active
    FROM fact_account_balance_monthly b
    JOIN dim_accounts a ON a.account_id = b.account_id
    GROUP BY a.customer_id, b.snapshot_month
),
last_act AS (
    SELECT customer_id, MAX(snapshot_month) AS last_month
    FROM monthly_act
    WHERE active = 1
    GROUP BY customer_id
)
SELECT 
    c.is_churned AS official_flag,
    CASE 
        WHEN la.last_month >= '2025-10' THEN 'Active (Last 3M)'
        WHEN la.last_month IS NULL THEN 'No Activity (2024-2025)'
        ELSE 'Behavioral Churn (Inactive 3M+)'
    END AS actual_status,
    COUNT(*) AS cust_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS share_pct
FROM dim_customers c
LEFT JOIN last_act la ON la.customer_id = c.customer_id
WHERE c.registration_date < '2025-10-01'
GROUP BY 1, 2
ORDER BY 1, 2;


/* =====================================================================
   SUMMARY & M&A AUDIT NOTES: BLOCK 1
   ---------------------------------------------------------------------
   • Status: REQUIRES ATTENTION (Audit Adjustment Needed)
   • 2025 Registration Spike: New client influx jumped +84.8% in 2025 
     (2,706 -> 5,000). Needs onboarding verification prior to acquisition.
   • Retention Degradation: First-year churn grew from 7.81% (2023 cohort) 
     to 11.68% (2024 cohort), signaling lower quality acquisition.
   • Reporting Discrepancy: ~11.4% of clients marked as active in the database 
     show zero monthly transactional activity for 3+ months (hidden churn).
   ===================================================================== */

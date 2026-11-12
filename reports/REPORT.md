# 📑 Executive Summary: Commercial Bank M&A Due Diligence Audit

**Project Status:** Completed  
**Analysis Period:** 2023–2025  
**Target Scope:** Retail & corporate client portfolio, credit risk, operational metrics, and contingent liabilities.

---

## 🚦 Executive Dashboard ("Traffic Light" Status)

| Analytical Block | Status | Summary / Rationale |
| :--- | :---: | :--- |
| **1. Customer Base (`01_customers.sql`)** | 🟡 **Requires Attention** | Influx surged in 2025, but 1st-year churn worsened (11.68%); 11.4% of database consists of "ghost" active accounts (hidden churn). |
| **2. Balance & Deposits (`02_balances.sql`)** | 🟢 **Normal** | Steady deposit growth across 2024–2025; top 1% of depositors hold <25% of KGS balances (moderate concentration risk). |
| **3. Operations (`03_activity.sql`)** | 🟡 **Requires Attention** | Transaction volume spiked 4.6x in 2025 (5.6x activity per account), requiring verification against technical batch loading. |
| **4. Risks & Fraud (`04_risks.sql`)** | 🟢 **Normal** | Decline rates (~5.55%) and fraud flags (~0.06%) are low and stable; blocked accounts account for 0.8% of base. |
| **5. Credit Portfolio (`05_credit.sql`)** | 🔴 **High Risk** | High credit line utilization tiers among retail borrowers require deep MFRS 9 Stage 3 provisioning review. |
| **6. Loyalty Program (`06_bonus.sql`)** | 🔴 **High Risk** | Critical deficit: redemptions (72.1M) exceed recorded accruals (49.8M) by -22.4M points (-44.9%), indicating an unrecorded pre-2023 liability. |

---

## 💡 Final Investment Recommendation

1. **Deal Verdict:** **Conditionally Recommended for Acquisition with a Discount.**
2. **Rationale:** The bank maintains a viable operational infrastructure and a stable liability base. However, unrecorded contingent liabilities in the loyalty program (negative point balance) and potential asset quality risks in the retail credit portfolio necessitate a **7–10% Purchase Price Adjustment (PPA)**.
3. **Closing Conditions:**
   * Require the seller to provide pre-2023 loyalty program ledgers and clarify the monetary valuation of bonus points.
   * Conduct a thorough asset tape audit (DPD and Stage 3 provisions) on active revolving credit lines prior to final state sign-off.

class MigrationMatchEngine:
    def evaluate_profile(self, user_profile):
        base_funds = 11904 if user_profile["target_country"] == "Germany" else 10000
        if user_profile["has_dependent_child"]:
            base_funds += 3500
            
        is_eligible = float(user_profile["cgpa_percentage"]) >= 65.0
        
        return {
            "user_id": user_profile["user_id"],
            "academic_match": "APPROVED" if is_eligible else "REJECTED_LOW_GPA",
            "mandatory_visa_funds_required_eur": base_funds,
            "recommending_free_tuition_pathways": user_profile["max_liquid_savings_usd"] == 0
        }

class VisaRiskAnalyzer:
    def scan_statement_of_purpose(self, text_draft, has_gaps):
        risk_flags = ["refugee", "stay forever", "desperate", "asylum", "work full time"]
        found_triggers = [flag for flag in risk_flags if flag in text_draft.lower()]
        
        if has_gaps:
            return "CRITICAL_RISK: Career timeline gaps detected. System must frame intervals as professional development."
        if found_triggers:
            return f"HIGH_RISK_DETECTED: Red flag keywords found: {found_triggers}. Rewriting required."
        return "PASSED: Content optimized for entry visa approval."

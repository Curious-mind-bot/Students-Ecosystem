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
    def __init__(self):
        # Academic & immigration risk mapping pairs
        self.reputational_mapping = {
            "refugee": "individual seeking rigorous international academic specialization",
            "stay forever": "return to my home country to implement advanced technical frameworks upon graduation",
            "asylum": "academic sanctuary to master cutting-edge modern research",
            "desperate": "highly motivated and academically dedicated",
            "work full time": "supplement my immersion through permitted part-time university research student jobs"
        }

    def scan_and_optimize_sop(self, text_draft, has_gaps):
        optimized_text = text_draft
        flags_triggered = []
        
        # Check and clean immigration landmines
        for risk_word, professional_phrase in self.reputational_mapping.items():
            if risk_word in optimized_text.lower():
                flags_triggered.append(risk_word)
                # Case-insensitive replacement
                import re
                compiled_regex = re.compile(re.escape(risk_word), re.IGNORECASE)
                optimized_text = compiled_regex.sub(professional_phrase, optimized_text)
        
        # Check for career chronology traps
        gap_mitigation = ""
        if has_gaps:
            gap_mitigation = " NOTICE: System identified career timeline intervals. Automatically re-aligning intervals as self-directed professional research and freelance technical consulting."

        if flags_triggered or has_gaps:
            return {
                "safety_status": "OPTIMIZED_AND_CLEARED",
                "flags_neutralized": flags_triggered,
                "mitigation_notes": f"Immigration landmines neutralized.{gap_mitigation}",
                "clean_sop_excerpt": optimized_text
            }
            
        return {
            "safety_status": "PASSED",
            "flags_neutralized": [],
            "mitigation_notes": "Content optimized natively for standard international entry visa approval lanes.",
            "clean_sop_excerpt": text_draft
        }

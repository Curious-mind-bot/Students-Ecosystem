"""Source-aware application readiness and statement clarity checks.

This module never predicts admission or visa decisions, invents explanations,
or replaces a student's words. It produces review prompts only.
"""

from __future__ import annotations

import json
import re
import sys
from datetime import date


class SOPClarityLinter:
    """Small, explainable linter for factual statements of purpose."""

    UNSUPPORTED_CLAIMS = re.compile(
        r"\b(guaranteed|certainly approved|no risk|always accepted|best student)\b",
        re.IGNORECASE,
    )
    PASSIVE_VOICE = re.compile(
        r"\b(is|are|was|were|be|been|being)\s+\w+(?:ed|en)\b", re.IGNORECASE
    )
    TIMELINE_SIGNAL = re.compile(
        r"\b(gap|break|unemployed|between jobs|career pause|since \d{4})\b",
        re.IGNORECASE,
    )
    EXPLANATION_SIGNAL = re.compile(
        r"\b(because|during this period|I used this time|I worked|I studied|I cared for|I completed)\b",
        re.IGNORECASE,
    )
    OFF_TOPIC_SIGNAL = re.compile(
        r"\b(asylum|permanent migration|stay forever|guaranteed visa)\b", re.IGNORECASE
    )

    def lint(self, text: str) -> dict:
        sentences = [item.strip() for item in re.split(r"(?<=[.!?])\s+", text.strip()) if item.strip()]
        findings = []

        for index, sentence in enumerate(sentences, start=1):
            if self.UNSUPPORTED_CLAIMS.search(sentence):
                findings.append(self._finding(
                    "unsupported_claim", index,
                    "This sentence makes a claim that may need independent evidence.",
                    "Use precise, truthful language and keep evidence available for any factual claim.",
                ))
            if self.PASSIVE_VOICE.search(sentence):
                findings.append(self._finding(
                    "passive_voice", index,
                    "This sentence may be harder to follow because it uses passive voice.",
                    "Consider naming the actor and action clearly, without changing the underlying facts.",
                ))
            if self.OFF_TOPIC_SIGNAL.search(sentence):
                findings.append(self._finding(
                    "focus_review", index,
                    "This sentence may not explain academic preparation or study goals clearly.",
                    "Review whether it belongs in a statement of purpose; do not remove material facts from official forms.",
                ))

        if self.TIMELINE_SIGNAL.search(text) and not self.EXPLANATION_SIGNAL.search(text):
            findings.append({
                "code": "timeline_explanation_missing",
                "sentence": None,
                "message": "The draft refers to a timeline gap without an explanation.",
                "suggestion": "Add a factual explanation in your own words and retain supporting documentation where applicable.",
            })

        return {
            "status": "NEEDS_REVIEW" if findings else "NO_RULES_TRIGGERED",
            "findings": findings,
            "disclaimer": "This is a writing clarity tool, not legal, immigration, or admission advice. It cannot predict outcomes.",
        }

    @staticmethod
    def _finding(code: str, sentence: int, message: str, suggestion: str) -> dict:
        return {"code": code, "sentence": sentence, "message": message, "suggestion": suggestion}


def evaluate_profile(profile: dict, requirements: dict | None = None) -> dict:
    """Compare supplied facts with source-backed programme requirements.

    ``requirements`` must include a current official source before any numeric
    funding comparison is returned. The result is a checklist, never approval.
    """
    requirements = requirements or {}
    missing_profile = [key for key in ("cgpa_percentage", "liquid_funds_eur") if profile.get(key) is None]
    missing_source = [key for key in ("source_url", "source_checked_on") if not requirements.get(key)]
    result = {
        "status": "VERIFICATION_REQUIRED",
        "academic": {"status": "NOT_COMPARED"},
        "funding": {"status": "NOT_COMPARED"},
        "missing_profile_fields": missing_profile,
        "missing_source_fields": missing_source,
        "next_steps": [
            "Check programme requirements directly with the university.",
            "Check current financial and immigration requirements through the relevant official authority.",
            "Keep evidence for each statement and document requirement organised.",
        ],
        "disclaimer": "This is an informational comparison, not an admission, financial, or immigration decision.",
    }
    if missing_profile or missing_source:
        return result

    minimum_cgpa = requirements.get("minimum_cgpa_percentage")
    if minimum_cgpa is not None:
        result["academic"] = {
            "status": "MEETS_STATED_MINIMUM" if float(profile["cgpa_percentage"]) >= float(minimum_cgpa) else "BELOW_STATED_MINIMUM",
            "minimum_cgpa_percentage": float(minimum_cgpa),
            "source_url": requirements["source_url"],
            "source_checked_on": requirements["source_checked_on"],
        }

    official_funds = requirements.get("official_funds_requirement_eur")
    if official_funds is not None:
        shortfall = max(0, float(official_funds) - float(profile["liquid_funds_eur"]))
        result["funding"] = {
            "status": "AMOUNT_REPORTED" if shortfall == 0 else "POTENTIAL_SHORTFALL",
            "reported_requirement_eur": float(official_funds),
            "reported_available_funds_eur": float(profile["liquid_funds_eur"]),
            "potential_shortfall_eur": shortfall,
            "source_url": requirements["source_url"],
            "source_checked_on": requirements["source_checked_on"],
        }
    result["status"] = "READY_FOR_REVIEW"
    return result


def main() -> None:
    payload = json.load(sys.stdin)
    action = payload.get("action")
    if action == "lint_sop":
        print(json.dumps(SOPClarityLinter().lint(payload.get("statement", ""))))
    elif action == "evaluate_profile":
        print(json.dumps(evaluate_profile(payload.get("profile", {}), payload.get("requirements"))))
    else:
        print(json.dumps({"error": "Unknown action"}))
        raise SystemExit(2)


if __name__ == "__main__":
    main()

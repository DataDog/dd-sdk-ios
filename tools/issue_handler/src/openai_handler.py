# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

"""
Manages OpenAI API calls for issue analysis.
"""
import os
import json
import re
from typing import Dict, Optional, List, Any
from dataclasses import dataclass, asdict
import openai
from .github_handler import GithubIssue

# ---- Constants / enums ----

ALLOWED_SCOPE = {"sdk", "custom", "unclear"}
ALLOWED_CATEGORY = {
    "question", "bug", "crash", "compilation", "configuration",
    "feature_request", "docs", "performance", "other"
}
ALLOWED_CONFIDENCE = {"high", "medium", "low"}

def _norm_str(value: Any, default: str = "unknown") -> str:
    return value if isinstance(value, str) and value.strip() else default

def _norm_list_str(value: Any) -> List[str]:
    if isinstance(value, list):
        return [str(x).strip() for x in value if str(x).strip()]
    if isinstance(value, str) and value.strip():
        return [value.strip()]
    return []

@dataclass
class AnalysisResult:
    """Represents the analysis of a GitHub issue."""
    summary: str
    problem: str
    scope: str
    category: str
    confidence_level: str
    next_steps: List[str]
    clarifying_questions: List[str]
    suggested_response: str
    
    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)

class OpenAIHandler:
    """Handles interactions with OpenAI API."""
    
    # Content limits to prevent abuse
    MAX_CONTENT_LENGTH = 4000
    MAX_RESPONSE_TOKENS = int(os.environ.get("OPENAI_MAX_RESPONSE_TOKENS", "500"))

    def __init__(self, api_key: str):
        """
        Initialize the OpenAI handler.
        
        Args:
            api_key: OpenAI API key
        """
        self.client = openai.OpenAI(api_key=api_key)
        
        # Load system prompt from environment variable
        self.system_prompt = os.environ.get("OPENAI_SYSTEM_PROMPT")
        if not self.system_prompt:
            raise EnvironmentError("OPENAI_SYSTEM_PROMPT environment variable must be set")

        # Model can be overridden via env
        self.model = os.environ.get("OPENAI_MODEL", "chatgpt-4o-latest")

    def analyze_issue(self, issue: GithubIssue) -> AnalysisResult:
        """
        Analyze a GitHub issue using OpenAI.
        
        Args:
            issue: GithubIssue object containing the issue details
            
        Returns:
            AnalysisResult containing the analysis
            
        Raises:
            OpenAIError: If there's an error calling the OpenAI API
        """
        try:
            # Sanitize and truncate input content
            sanitized_content = self._sanitize_input(issue.body)
            truncated_content = self._truncate_content(sanitized_content)
            
            # Log content processing for debugging
            print(f"Content processing - Original: {len(issue.body)}, Sanitized: {len(sanitized_content)}, Truncated: {len(truncated_content)}")

            # Include a bit more context if available
            labels_text = ""
            try:
                labels = getattr(issue, "labels", None)
                if labels:
                    if isinstance(labels, (list, tuple)):
                        label_names = [l.get("name", str(l)) if isinstance(l, dict) else str(l) for l in labels]
                        labels_text = f"Labels: {', '.join(label_names)}\n"
            except Exception:
                pass

            user_msg = self._format_issue_content(issue, truncated_content, labels_text)

            # Prepare the messages
            messages = [
                {"role": "system", "content": self.system_prompt},
                {"role": "user", "content": user_msg}
            ]

            # Call OpenAI API with token limits
            response = self.client.chat.completions.create(
                model=self.model,
                messages=messages,
                temperature=float(os.environ.get("OPENAI_TEMPERATURE", "0.4")),
                max_tokens=self.MAX_RESPONSE_TOKENS,
                response_format={"type": "json_object"}
            )

            # Parse the JSON response and normalize
            try:
                payload = response.choices[0].message.content
                result = json.loads(payload)
                normalized = self._normalize_result(result)
                return AnalysisResult(**normalized)
            except (json.JSONDecodeError, KeyError, TypeError) as e:
                raise OpenAIError(f"Invalid response format: {str(e)}")

        except Exception as e:
            raise OpenAIError(f"Failed to analyze issue: {str(e)}") from e

    # ---- Helpers ----

    def _sanitize_input(self, content: str) -> str:
        """Sanitize input to prevent prompt injection attacks."""
        if not content:
            return ""

        # Remove HTML comments that could contain prompt injection
        content = re.sub(r'<!--.*?-->', '', content, flags=re.DOTALL)

        # Remove any content that looks like system instructions
        content = re.sub(r'(?i)(instructions|prompt|system|openai|gpt|ai).*?{.*?}', '', content, flags=re.DOTALL)

        # Remove any suspicious patterns that might be used for injection
        content = re.sub(r'(?i)(ignore previous|forget all|new instructions|system prompt)', '', content)

        return content.strip()

    def _truncate_content(self, content: str) -> str:
        """Truncate content to prevent excessive token usage."""
        if len(content) <= self.MAX_CONTENT_LENGTH:
            return content

        truncated = content[:self.MAX_CONTENT_LENGTH]
        truncated += f"\n\n[Content truncated at {self.MAX_CONTENT_LENGTH} characters]"
        return truncated

    def _format_issue_content(self, issue: GithubIssue, content: str, labels_text: str) -> str:
        """Format the issue content for the OpenAI prompt."""
        return f"""
Issue Title: {issue.title}
Issue URL: {issue.html_url}
Created By: {issue.user}
Issue Number: {issue.number}
{labels_text}
Content:
{content}
""".strip()

    def _normalize_result(self, r: Dict[str, any]) -> Dict[str, any]:
        """Normalize/validate the model JSON to our schema with safe defaults."""
        summary = _norm_str(r.get("summary"), "[missing]")
        problem = _norm_str(r.get("problem"), "unclear")

        scope = _norm_str(r.get("scope"), "unclear").lower()
        if scope not in ALLOWED_SCOPE:
            scope = "unclear"

        category = _norm_str(r.get("category"), "other").lower()
        if category not in ALLOWED_CATEGORY:
            category = "other"

        confidence = _norm_str(r.get("confidence_level"), "low").lower()
        if confidence not in ALLOWED_CONFIDENCE:
            confidence = "low"

        next_steps = _norm_list_str(r.get("next_steps"))[:5]
        questions = _norm_list_str(r.get("clarifying_questions"))[:5]

        suggested_response = _norm_str(r.get("suggested_response"), "[missing]")

        return {
            "summary": summary,
            "problem": problem,
            "scope": scope,
            "category": category,
            "confidence_level": confidence,
            "next_steps": next_steps,
            "clarifying_questions": questions,
            "suggested_response": suggested_response,
        }

class OpenAIError(Exception):
    """Custom exception for OpenAI API related errors."""
    pass

def create_openai_handler() -> OpenAIHandler:
    """
    Factory function to create an OpenAIHandler from environment variables.

    Returns:
        Configured OpenAIHandler instance

    Raises:
        EnvironmentError: If OPENAI_TOKEN environment variable is not set
    """
    api_key = os.environ.get("OPENAI_TOKEN")
    if not api_key:
        raise EnvironmentError("OPENAI_TOKEN environment variable must be set")

    return OpenAIHandler(api_key)

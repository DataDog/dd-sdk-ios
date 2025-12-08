# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog, Inc.
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

"""
Posts issue notifications and analysis to Slack using webhooks.
"""
import os
import json
import re
from typing import Dict, Any, List
import requests
from dataclasses import dataclass, is_dataclass, asdict
from .github_handler import GithubIssue

@dataclass
class SlackMessage:
    """Represents a formatted Slack message."""
    blocks: list[Dict]

class SlackHandler:
    """Handles posting messages to Slack using webhooks."""

    def __init__(self, webhook_url: str):
        """
        Initialize the Slack handler.

        Args:
            webhook_url: Slack webhook URL
        """
        self.webhook_url = webhook_url

    def post_issue_with_analysis(self, issue: GithubIssue, analysis: Dict[str, Any] | Any) -> None:
        """
        Post GitHub issue notification with OpenAI analysis in a single message.

        Args:
            issue: GithubIssue object containing the issue details
            analysis: Analysis results from OpenAI

        Raises:
            SlackError: If there's an error posting to Slack
        """
        try:
            # Convert dataclass -> dict if needed
            if is_dataclass(analysis):
                analysis = asdict(analysis)

            # Sanitize analysis content before posting
            sanitized = self._sanitize_analysis(analysis)

            # Build GitHub URL from environment variables
            github_url = self._build_github_url(issue)

            # Compact badges line
            badges = f"*Category:* `{sanitized['category']}`   *Scope:* `{sanitized['scope']}`   *Confidence:* `{sanitized['confidence_level']}`"

            # Feature docs usage line (if any docs were consulted)
            feature_docs = sanitized.get('feature_docs_used', {})
            docs_consulted = feature_docs.get('consulted', [])
            docs_helpful = feature_docs.get('helpful', False)
            docs_sections = feature_docs.get('relevant_sections', [])
            if docs_consulted:
                docs_list = ", ".join(docs_consulted)
                # Add relevant sections in parentheses if available
                if docs_sections:
                    sections_str = ", ".join(docs_sections)
                    docs_list = f"{docs_list} ({sections_str})"
                helpful_indicator = "✅" if docs_helpful else "❌"
                docs_badge = f"*Docs:* `{docs_list}`   *Helpful:* {helpful_indicator}"
            else:
                docs_badge = "*Docs:* `none`"

            # Build bullets for steps & questions
            def bullets(items: List[str]) -> str:
                return "\n".join([f"• {i}" for i in items]) if items else "_None_"

            blocks = [
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": f":github-squircle: New GitHub issue opened by *{issue.user}*:\n<{github_url}|#{issue.number} {issue.title}>"
                    }
                },
                {"type": "divider"},
                {"type": "section", "text": {"type": "mrkdwn", "text": ":robot_face: :mag_right: *Analysis*"}},
                {"type": "section", "text": {"type": "mrkdwn", "text": f"*Summary*\n{sanitized['summary']}"}}
            ]

            if sanitized.get("problem"):
                blocks.append({"type": "section", "text": {"type": "mrkdwn", "text": f"*Problem*\n{sanitized['problem']}"}})

            blocks.extend([
                {"type": "context", "elements": [{"type": "mrkdwn", "text": badges}]},
                {"type": "context", "elements": [{"type": "mrkdwn", "text": docs_badge}]},
                {"type": "section", "text": {"type": "mrkdwn", "text": f"*Next Steps (for handler)*\n{bullets(sanitized.get('next_steps', []))}"}},
            ])

            # Clarifying questions (optional)
            if sanitized.get("clarifying_questions"):
                blocks.append({"type": "section", "text": {"type": "mrkdwn", "text": f"*Clarifying Questions*\n{bullets(sanitized['clarifying_questions'])}"}})

            # Suggested response last
            blocks.extend([
                {"type": "divider"},
                {"type": "section", "text": {"type": "mrkdwn", "text": f"*Suggested Response*\n{sanitized['suggested_response']}"}},
            ])

            response = requests.post(
                self.webhook_url,
                headers={"Content-Type": "application/json"},
                json={"blocks": blocks}
            )
            response.raise_for_status()

        except Exception as e:
            raise SlackError(f"Failed to post to Slack: {str(e)}") from e

    def _build_github_url(self, issue: GithubIssue) -> str:
        """Build a GitHub URL using environment variables and issue number."""
        github_repo = os.environ.get("GITHUB_REPOSITORY")
        if not github_repo:
            raise EnvironmentError("GITHUB_REPOSITORY environment variable must be set")

        # Build URL manually for extra safety
        return f"https://github.com/{github_repo}/issues/{issue.number}"

    # ---- Sanitization ----

    def _sanitize_analysis(self, analysis: Dict[str, Any]) -> Dict[str, Any]:
        """Sanitize analysis content to prevent malicious content in Slack."""
        def sanitize_text(text: str, content_type: str) -> str:
            if not text:
                return "[No content]"

            original_text = text
            sanitization_applied = False

            # Remove any markdown links that could be malicious
            if re.search(r'\[([^\]]+)\]\([^)]+\)', text):
                text = re.sub(r'\[([^\]]+)\]\([^)]+\)', r'\1', text)
                sanitization_applied = True

            # Remove any URLs
            if re.search(r'http[s]?://(?:[a-zA-Z]|[0-9]|[$-_@.&+]|[!*\\(\\),]|(?:%[0-9a-fA-F][0-9a-fA-F]))+', text):
                text = re.sub(r'http[s]?://(?:[a-zA-Z]|[0-9]|[$-_@.&+]|[!*\\(\\),]|(?:%[0-9a-fA-F][0-9a-fA-F]))+', '[URL REMOVED]', text)
                sanitization_applied = True

            # Remove any HTML tags
            if re.search(r'<[^>]+>', text):
                text = re.sub(r'<[^>]+>', '', text)
                sanitization_applied = True

            # Remove any suspicious content patterns
            if re.search(r'(?i)(click here|download|free|urgent|limited time)', text):
                text = re.sub(r'(?i)(click here|download|free|urgent|limited time)', '[CONTENT REMOVED]', text)
                sanitization_applied = True

            # Remove any potential script-like content
            if re.search(r'(?i)(javascript:|vbscript:|onload|onerror|onclick)', text):
                text = re.sub(r'(?i)(javascript:|vbscript:|onload|onerror|onclick)', '[SCRIPT REMOVED]', text)
                sanitization_applied = True

            # Limit length to prevent abuse
            max_length = 2000 if content_type in ('summary', 'problem') else 3000
            if len(text) > max_length:
                text = text[:max_length] + "\n[Content truncated]"
                sanitization_applied = True

            if sanitization_applied:
                print(f"Content sanitization applied: {original_text[:100]}... -> {text[:100]}...")

            return text

        def sanitize_list(items: Any, item_type: str) -> List[str]:
            out: List[str] = []
            if isinstance(items, list):
                for it in items[:5]:
                    out.append(sanitize_text(str(it), item_type))
            elif isinstance(items, str) and items.strip():
                out.append(sanitize_text(items.strip(), item_type))
            return out

        # Handle feature_docs_used - can be dict or dataclass
        feature_docs_raw = analysis.get("feature_docs_used", {})
        if hasattr(feature_docs_raw, '__dict__'):
            # It's a dataclass, convert to dict
            feature_docs_raw = {
                "consulted": getattr(feature_docs_raw, 'consulted', []),
                "helpful": getattr(feature_docs_raw, 'helpful', False),
                "relevant_sections": getattr(feature_docs_raw, 'relevant_sections', [])
            }
        
        feature_docs_used = {
            "consulted": sanitize_list(feature_docs_raw.get("consulted", []), "docs"),
            "helpful": bool(feature_docs_raw.get("helpful", False)),
            "relevant_sections": sanitize_list(feature_docs_raw.get("relevant_sections", []), "docs"),
        }

        return {
            "summary": sanitize_text(analysis.get("summary", ""), "summary"),
            "problem": sanitize_text(analysis.get("problem", ""), "problem"),
            "confidence_level": analysis.get("confidence_level", "low"),
            "scope": analysis.get("scope", "unclear"),
            "category": analysis.get("category", "other"),
            "next_steps": sanitize_list(analysis.get("next_steps"), "next_steps"),
            "clarifying_questions": sanitize_list(analysis.get("clarifying_questions"), "questions"),
            "suggested_response": sanitize_text(analysis.get("suggested_response", ""), "response"),
            "feature_docs_used": feature_docs_used,
        }

class SlackError(Exception):
    """Custom exception for Slack API related errors."""
    pass

def create_slack_handler() -> SlackHandler:
    """
    Factory function to create a SlackHandler from environment variables.

    Returns:
        Configured SlackHandler instance

    Raises:
        EnvironmentError: If required environment variables are not set
    """
    webhook_url = os.environ.get("SLACK_WEBHOOK_URL")

    if not webhook_url:
        raise EnvironmentError("SLACK_WEBHOOK_URL environment variable must be set")

    return SlackHandler(webhook_url)

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
from typing import Dict
import requests
from dataclasses import dataclass
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

    def post_issue_with_analysis(self, issue: GithubIssue, analysis: Dict) -> None:
        """
        Post GitHub issue notification with OpenAI analysis in a single message.
        
        Args:
            issue: GithubIssue object containing the issue details
            analysis: Analysis results from OpenAI
            
        Raises:
            SlackError: If there's an error posting to Slack
        """
        try:
            # Sanitize analysis content before posting
            sanitized_analysis = self._sanitize_analysis(analysis)
            
            # Build GitHub URL from environment variables
            github_url = self._build_github_url(issue)
            
            blocks = [
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": f":github-squircle: New GitHub issue opened by *{issue.user}*:\n<{github_url}|#{issue.number} {issue.title}>"
                    }
                },
                {
                    "type": "divider"
                },
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": f":robot_face: :mag_right: *Analysis:*"
                    }
                },
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": f"*Summary:*\n{sanitized_analysis['summary']}"
                    }
                },
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": f"*Suggested Response:*\n{sanitized_analysis['suggested_response']}"
                    }
                }
            ]
            
            # Add confidence level
            blocks.append({
                "type": "context",
                "elements": [
                    {
                        "type": "mrkdwn",
                        "text": f"Confidence Level: {sanitized_analysis['confidence_level']}"
                    }
                ]
            })
            
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

    def _sanitize_analysis(self, analysis: Dict) -> Dict:
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
            
            # Limit length to prevent abuse (different limits for different content types)
            max_length = 2000 if content_type == 'summary' else 3000  # Summary: 2000, Response: 3000
            if len(text) > max_length:
                text = text[:max_length] + "\n[Content truncated]"
                sanitization_applied = True
            
            # Log if sanitization was applied
            if sanitization_applied:
                print(f"Content sanitization applied: {original_text[:100]}... -> {text[:100]}...")
            
            return text
        
        return {
            'summary': sanitize_text(analysis['summary'], 'summary'),
            'suggested_response': sanitize_text(analysis['suggested_response'], 'response'),
            'confidence_level': analysis['confidence_level']
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
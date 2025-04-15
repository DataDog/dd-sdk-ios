"""
Posts issue notifications and analysis to Slack using webhooks.
"""
import os
import json
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
            blocks = [
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": f":github-squircle: New GitHub issue opened by *{issue.user}*:\n<{issue.html_url}|#{issue.number} {issue.title}>"
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
                        "text": f"*Summary:*\n{analysis['summary']}"
                    }
                },
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": f"*Suggested Response:*\n{analysis['suggested_response']}"
                    }
                }
            ]
            
            # Add confidence level
            blocks.append({
                "type": "context",
                "elements": [
                    {
                        "type": "mrkdwn",
                        "text": f"Confidence Level: {analysis['confidence_level']}"
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
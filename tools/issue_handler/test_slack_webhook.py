#!/usr/bin/env python3
"""
Test script to verify Slack webhook functionality.
Run this to test if your webhook URL is working correctly.
"""

import os
import sys
from pathlib import Path
from dotenv import load_dotenv

# Try to load environment variables from .env file
env_path = Path(__file__).parent / '.env'
if env_path.exists():
    load_dotenv(env_path)

from src.slack_handler import create_slack_handler

def test_slack_webhook():
    """Test the Slack webhook by sending a test message."""
    try:
        # Create Slack handler
        slack = create_slack_handler()
        print("✅ Slack handler created successfully")
        
        # Send a test message
        test_blocks = [
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": ":white_check_mark: *Test Message* - GitHub Issue Handler webhook is working!"
                }
            },
            {
                "type": "context",
                "elements": [
                    {
                        "type": "mrkdwn",
                        "text": "This is a test message to verify webhook functionality"
                    }
                ]
            }
        ]
        
        # Create a mock issue for testing
        from src.github_handler import GithubIssue
        
        mock_issue = GithubIssue(
            title="Test Issue",
            body="This is a test issue body",
            html_url="https://github.com/test/repo/issues/123",
            number=123,
            user="testuser"
        )
        
        slack.post_issue_with_analysis(mock_issue, {
            "summary": "Test summary",
            "suggested_response": "Test response",
            "follow_up_questions": ["Test question 1", "Test question 2"],
            "confidence_level": "high"
        })
        
        print("✅ Test message sent successfully!")
        print("📋 Check your Slack channel to see the test message")
        
    except Exception as e:
        print(f"❌ Error testing Slack webhook: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    print("🧪 Testing Slack webhook functionality...")
    test_slack_webhook()
    print("🎉 Test completed!") 
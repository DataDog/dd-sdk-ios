# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

#!/usr/bin/env python3
"""
Local testing script with mock data to verify Slack webhook functionality.
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
from src.github_handler import GithubIssue

def test_slack_webhook():
    """Test the Slack webhook with a mock issue."""
    try:
        print("🧪 Testing Slack webhook functionality...")
        
        # Create Slack handler
        slack = create_slack_handler()
        print("✅ Slack handler created successfully")
        
        # Create a mock issue for testing
        mock_issue = GithubIssue(
            title="Test Issue: iOS SDK Integration Problem",
            body="I'm having trouble integrating the Datadog iOS SDK into my project. I followed the documentation but I'm getting build errors. Can someone help me?",
            html_url="https://github.com/DataDog/dd-sdk-ios/issues/1234",
            number=1234,
            user="testuser"
        )
        
        # Create mock analysis
        mock_analysis = {
            "summary": "User is experiencing build errors when integrating the Datadog iOS SDK into their project.",
            "suggested_response": "Hi! I'd be happy to help you with the iOS SDK integration. Could you please share:\n1. The specific build error messages you're seeing\n2. Your iOS version and Xcode version\n3. How you're integrating the SDK (CocoaPods, SPM, or manual)\n4. Your current Podfile or Package.swift configuration\n\nThis will help me provide a more targeted solution.",
            "confidence_level": "medium"
        }
        
        # Post to Slack
        slack.post_issue_with_analysis(mock_issue, mock_analysis)
        
        print("✅ Test message sent successfully!")
        print("📋 Check your Slack channel to see the test message")
        print("🎉 Test completed!")
        
    except Exception as e:
        print(f"❌ Error testing Slack webhook: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    test_slack_webhook() 
# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

#!/usr/bin/env python3

"""
Main entry point that orchestrates GitHub issue fetching, OpenAI analysis, and Slack posting.
"""

import os
import sys
from pathlib import Path
from dotenv import load_dotenv

# Try to load environment variables from .env file
env_path = Path(__file__).parent.parent / '.env'
if env_path.exists():
    load_dotenv(env_path)

from .github_handler import create_github_handler
from .openai_handler import create_openai_handler
from .slack_handler import create_slack_handler

def main():
    if len(sys.argv) != 2:
        print("Usage: python -m src.analyze_issue ISSUE_NUMBER")
        sys.exit(1)
        
    try:
        issue_number = int(sys.argv[1])
    except ValueError:
        print("Error: Issue number must be a number")
        sys.exit(1)

    try:
        # First fetch the issue
        github = create_github_handler()
        issue = github.get_issue(issue_number)
        if not issue:
            print(f"\nIssue #{issue_number} not found")
            return

        print(f"\nAnalyzing issue #{issue_number}: {issue.title}")
        
        # Analyze with OpenAI first
        openai = create_openai_handler()
        analysis = openai.analyze_issue(issue)
        
        # Post issue notification with analysis to Slack
        slack = create_slack_handler()
        slack.post_issue_with_analysis(issue, analysis)
        print("\nPosted issue notification with analysis to Slack")
        
        # Print results to console too
        print("\nAnalysis Results:")
        print(f"\nSummary:")
        print(analysis.summary)
        
        print(f"\nSuggested Response:")
        print(analysis.suggested_response)

        print(f"\nConfidence Level: {analysis.confidence_level}")
            
    except Exception as e:
        print(f"\nError: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main() 
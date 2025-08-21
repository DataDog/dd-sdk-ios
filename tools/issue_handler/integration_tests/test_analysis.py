"""
Test script for analyzing real GitHub issues.
"""
import os
import argparse
import sys
from pathlib import Path
from dotenv import load_dotenv

# Try to load environment variables from .env file
env_path = Path(__file__).parent.parent / '.env'
if env_path.exists():
    load_dotenv(env_path)

# Add src directory to Python path
src_dir = Path(__file__).parent.parent / "src"
sys.path.append(str(src_dir))

from src.github_handler import create_github_handler
from src.openai_handler import create_openai_handler

def parse_args():
    parser = argparse.ArgumentParser(description='Test GitHub issue analysis')
    parser.add_argument('--issue', type=int, required=True,
                      help='Issue number to analyze')
    return parser.parse_args()

def main():
    args = parse_args()
    try:
        # First fetch the issue
        github = create_github_handler()
        issue = github.get_issue(args.issue)
        if not issue:
            print(f"\nIssue #{args.issue} not found")
            return

        print(f"\nAnalyzing issue #{args.issue}: {issue.title}")
        
        # Then analyze it
        openai = create_openai_handler()
        analysis = openai.analyze_issue(issue)
        
        # Print results
        print("\nAnalysis Results:")
        print(f"\nSummary:")
        print(analysis.summary)
        
        print(f"\nSuggested Response:")
        print(analysis.suggested_response)
        
        print(f"\nConfidence Level: {analysis.confidence_level}")
            
    except Exception as e:
        print(f"\nError: {str(e)}")

if __name__ == "__main__":
    main() 
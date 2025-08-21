"""
Integration test for processing actual GitHub issues.
"""
import argparse
import os
import sys
from pathlib import Path
from dotenv import load_dotenv
from src.github_handler import create_github_handler

# Try to load environment variables from .env file
env_path = Path(__file__).parent.parent / '.env'
if env_path.exists():
    load_dotenv(env_path)

# Add src directory to Python path
src_dir = Path(__file__).parent.parent / "src"
sys.path.append(str(src_dir))

def parse_args():
    parser = argparse.ArgumentParser(description='Test GitHub issue fetching')
    parser.add_argument('--issue', type=int, default=1,
                      help='Issue number to fetch (default: 1)')
    return parser.parse_args()

def main():
    args = parse_args()
    try:
        if not os.environ.get("GITHUB_TOKEN"):
            print("\nError: GITHUB_TOKEN environment variable is not set.")
            print("Please set it using:")
            print("  export GITHUB_TOKEN='your-token'")
            return

        # Create handler using environment variables (GITHUB_REPOSITORY should be set in .env)
        handler = create_github_handler()
        
        print(f"\nFetching issue #{args.issue} from {os.environ.get('GITHUB_REPOSITORY', 'unknown')}...")
        
        issue = handler.get_issue(args.issue)
        if issue:
            print("\nSuccessfully fetched issue:")
            print(f"Title: {issue.title}")
            print(f"Created by: {issue.user}")
            print(f"URL: {issue.html_url}")
            print(f"\nBody preview: {issue.body[:200]}...")
        else:
            print(f"\nIssue #{args.issue} not found")
            
    except Exception as e:
        print(f"\nError: {str(e)}")
        if "GITHUB_REPOSITORY" in str(e):
            print("\nMake sure GITHUB_REPOSITORY is set in your .env file (e.g., 'DataDog/dd-sdk-ios')")

if __name__ == "__main__":
    main() 
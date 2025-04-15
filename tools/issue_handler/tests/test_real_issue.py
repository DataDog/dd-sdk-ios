"""
Integration test for processing actual GitHub issues.
"""
import argparse
import os
from src.github_handler import create_github_handler

def parse_args():
    parser = argparse.ArgumentParser(description='Test GitHub issue fetching')
    parser.add_argument('--owner', default='DataDog',
                      help='Repository owner (default: DataDog)')
    parser.add_argument('--repo', default='dd-sdk-ios',
                      help='Repository name (default: dd-sdk-ios)')
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

        # Create handler with specified repository
        handler = create_github_handler(
            owner=args.owner,
            repo=args.repo
        )
        
        print(f"\nFetching issue #{args.issue} from {args.owner}/{args.repo}...")
        
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

if __name__ == "__main__":
    main() 
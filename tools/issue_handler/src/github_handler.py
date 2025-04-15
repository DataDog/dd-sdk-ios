"""
Handles GitHub API calls to fetch issue details.
"""
from typing import Optional
from dataclasses import dataclass
import requests
import os

@dataclass
class GithubIssue:
    """Represents a GitHub issue with essential information."""
    title: str
    body: str
    html_url: str
    number: int
    created_at: str
    user: str

class GithubAPIError(Exception):
    """Custom exception for GitHub API related errors."""
    pass

class GithubHandler:
    """Handles GitHub API interactions."""
    
    def __init__(self, token: str, repository: str):
        """
        Initialize the GitHub handler.
        
        Args:
            token: GitHub API token
            repository: Repository in format 'owner/repo'
        """
        self.token = token
        self.repository = repository
        self.base_url = "https://api.github.com"
        self.session = requests.Session()
        self.session.headers.update({
            "Authorization": f"token {token}",
            "Accept": "application/vnd.github.v3+json",
            "User-Agent": "DatadogSDK-IssueHandler"
        })

    def get_issue(self, issue_number: int) -> Optional[GithubIssue]:
        """
        Fetch issue details from GitHub.
        
        Args:
            issue_number: The issue number to fetch
            
        Returns:
            GithubIssue object if successful, None if issue not found
            
        Raises:
            GithubAPIError: If there's an error accessing the GitHub API
        """
        try:
            url = f"{self.base_url}/repos/{self.repository}/issues/{issue_number}"
            response = self.session.get(url)
            
            if response.status_code == 404:
                return None
                
            response.raise_for_status()
            data = response.json()
            
            return GithubIssue(
                title=data["title"],
                body=data["body"] or "",
                html_url=data["html_url"],
                number=data["number"],
                created_at=data["created_at"],
                user=data["user"]["login"]
            )
            
        except (requests.exceptions.RequestException, Exception) as e:
            raise GithubAPIError(f"Failed to fetch issue: {str(e)}") from e
        except KeyError as e:
            raise GithubAPIError(f"Invalid response format: {str(e)}") from e

def create_github_handler(owner: str = "DataDog", repo: str = "dd-sdk-ios") -> GithubHandler:
    """
    Factory function to create a GithubHandler from parameters or environment variables.
    
    Args:
        owner: Repository owner (default: DataDog)
        repo: Repository name (default: dd-sdk-ios)
        
    Returns:
        Configured GithubHandler instance
        
    Raises:
        EnvironmentError: If GITHUB_TOKEN environment variable is not set
    """
    # Get token from environment
    github_token = os.environ.get("GITHUB_TOKEN")
    if not github_token:
        raise EnvironmentError(
            "GITHUB_TOKEN environment variable must be set"
        )
        
    return GithubHandler(github_token, f"{owner}/{repo}") 
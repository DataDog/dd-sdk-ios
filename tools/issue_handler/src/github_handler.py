# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

"""
Handles GitHub API calls to fetch issue details.
"""
from typing import Optional
from dataclasses import dataclass
import requests
import os

@dataclass
class GithubIssue:
    """Represents a GitHub issue."""
    title: str
    body: str
    html_url: str
    number: int
    user: str

class GithubAPIError(Exception):
    """Custom exception for GitHub API related errors."""
    pass

class GithubHandler:
    """Handles GitHub API interactions."""
    
    # Reasonable limits to prevent abuse
    MIN_ISSUE_NUMBER = 1
    MAX_ISSUE_NUMBER = 10000
    
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
        
    def _validate_issue_number(self, issue_number: int) -> None:
        """
        Validate issue number format and range.
        
        Args:
            issue_number: The issue number to validate
            
        Raises:
            ValueError: If issue number is invalid
        """
        if not isinstance(issue_number, int):
            raise ValueError("Issue number must be an integer")
        
        if issue_number < self.MIN_ISSUE_NUMBER or issue_number > self.MAX_ISSUE_NUMBER:
            raise ValueError(f"Issue number must be between {self.MIN_ISSUE_NUMBER} and {self.MAX_ISSUE_NUMBER}")
    
    def get_issue(self, issue_number: int) -> Optional[GithubIssue]:
        """
        Fetch issue details from GitHub.
        
        Args:
            issue_number: The issue number to fetch
            
        Returns:
            GithubIssue object if found, None otherwise
            
        Raises:
            ValueError: If issue number is invalid
            GithubAPIError: If there's an error accessing the GitHub API
        """
        # Validate issue number
        self._validate_issue_number(issue_number)
        
        try:
            url = f"{self.base_url}/repos/{self.repository}/issues/{issue_number}"
            headers = {
                "Authorization": f"token {self.token}",
                "Accept": "application/vnd.github.v3+json"
            }
            
            response = requests.get(url, headers=headers)
            
            if response.status_code == 404:
                return None
                
            response.raise_for_status()
            data = response.json()
            
            return GithubIssue(
                title=data["title"],
                body=data["body"] or "",
                html_url=data["html_url"],
                number=data["number"],
                user=data["user"]["login"]
            )
            
        except requests.exceptions.RequestException as e:
            raise GithubAPIError(f"Failed to fetch issue: {str(e)}") from e
        except KeyError as e:
            raise GithubAPIError(f"Invalid response format: {str(e)}") from e

def create_github_handler() -> GithubHandler:
    """
    Factory function to create a GithubHandler from environment variables.
    
    Returns:
        Configured GithubHandler instance
        
    Raises:
        EnvironmentError: If required environment variables are not set
    """
    token = os.environ.get("GITHUB_TOKEN")
    repository = os.environ.get("GITHUB_REPOSITORY")
    
    if not token:
        raise EnvironmentError("GITHUB_TOKEN environment variable must be set")
    if not repository:
        raise EnvironmentError("GITHUB_REPOSITORY environment variable must be set")
        
    return GithubHandler(token, repository) 

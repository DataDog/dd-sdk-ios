"""
Manages OpenAI API calls for issue analysis.
"""
import os
import json
from typing import Dict, Optional
from dataclasses import dataclass
import openai
from .github_handler import GithubIssue

@dataclass
class AnalysisResult:
    """Represents the analysis of a GitHub issue."""
    summary: str
    suggested_response: str
    confidence_level: str  # high, medium, low

class OpenAIHandler:
    """Handles interactions with OpenAI API."""
    
    def __init__(self, api_key: str):
        """
        Initialize the OpenAI handler.
        
        Args:
            api_key: OpenAI API key
        """
        self.client = openai.OpenAI(api_key=api_key)
        
        # Load system prompt from environment variable
        self.system_prompt = os.environ.get("OPENAI_SYSTEM_PROMPT")
        if not self.system_prompt:
            raise EnvironmentError("OPENAI_SYSTEM_PROMPT environment variable must be set")

    def analyze_issue(self, issue: GithubIssue) -> AnalysisResult:
        """
        Analyze a GitHub issue using OpenAI.
        
        Args:
            issue: GithubIssue object containing the issue details
            
        Returns:
            AnalysisResult containing the analysis
            
        Raises:
            OpenAIError: If there's an error calling the OpenAI API
        """
        try:
            # Prepare the messages
            messages = [
                {"role": "system", "content": self.system_prompt},
                {"role": "user", "content": self._format_issue_content(issue)}
            ]
            
            # Call OpenAI API
            response = self.client.chat.completions.create(
                model="gpt-3.5-turbo",
                messages=messages,
                temperature=0.7,
                response_format={"type": "json_object"}
            )
            
            # Parse the JSON response
            try:
                result = json.loads(response.choices[0].message.content)
                return AnalysisResult(
                    summary=result["summary"],
                    suggested_response=result["suggested_response"],
                    confidence_level=result["confidence_level"]
                )
            except (json.JSONDecodeError, KeyError) as e:
                raise OpenAIError(f"Invalid response format: {str(e)}")
            
        except Exception as e:
            raise OpenAIError(f"Failed to analyze issue: {str(e)}") from e

    def _format_issue_content(self, issue: GithubIssue) -> str:
        """Format the issue content for the OpenAI prompt."""
        return f"""
Issue Title: {issue.title}
Issue URL: {issue.html_url}
Created By: {issue.user}
Issue Number: {issue.number}

Content:
{issue.body}
"""

class OpenAIError(Exception):
    """Custom exception for OpenAI API related errors."""
    pass

def create_openai_handler() -> OpenAIHandler:
    """
    Factory function to create an OpenAIHandler from environment variables.
    
    Returns:
        Configured OpenAIHandler instance
        
    Raises:
        EnvironmentError: If OPENAI_TOKEN environment variable is not set
    """
    api_key = os.environ.get("OPENAI_TOKEN")
    if not api_key:
        raise EnvironmentError("OPENAI_TOKEN environment variable must be set")
        
    return OpenAIHandler(api_key) 
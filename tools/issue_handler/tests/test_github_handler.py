"""
Unit tests for GitHub API handler functionality.
"""
import pytest
from unittest.mock import Mock, patch
from src.github_handler import GithubHandler, GithubIssue, GithubAPIError

@pytest.fixture
def mock_response():
    """Create a mock response with test issue data."""
    return {
        "title": "Test Issue",
        "body": "Test body",
        "html_url": "https://github.com/owner/repo/issues/1",
        "number": 1,
        "created_at": "2024-03-20T12:00:00Z",
        "user": {
            "login": "test-user"
        }
    }

@pytest.fixture
def github_handler():
    """Create a GithubHandler instance with test credentials."""
    return GithubHandler("test-token", "owner/repo")

def test_get_issue_success(github_handler, mock_response):
    """Test successful issue retrieval."""
    with patch("requests.Session.get") as mock_get:
        mock_get.return_value.status_code = 200
        mock_get.return_value.json.return_value = mock_response
        
        issue = github_handler.get_issue(1)
        
        assert isinstance(issue, GithubIssue)
        assert issue.title == "Test Issue"
        assert issue.number == 1
        assert issue.user == "test-user"

def test_get_issue_not_found(github_handler):
    """Test handling of non-existent issue."""
    with patch("requests.Session.get") as mock_get:
        mock_get.return_value.status_code = 404
        
        issue = github_handler.get_issue(999)
        assert issue is None

def test_get_issue_api_error(github_handler):
    """Test handling of API errors."""
    with patch("requests.Session.get") as mock_get:
        mock_get.side_effect = Exception("API Error")
        
        with pytest.raises(GithubAPIError):
            github_handler.get_issue(1)

def test_get_issue_invalid_response(github_handler):
    """Test handling of invalid API response format."""
    with patch("requests.Session.get") as mock_get:
        mock_get.return_value.status_code = 200
        mock_get.return_value.json.return_value = {}  # Missing required fields
        
        with pytest.raises(GithubAPIError):
            github_handler.get_issue(1) 
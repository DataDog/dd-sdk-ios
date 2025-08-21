# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

"""
Tests for GitHub handler functionality.
"""
import pytest
import os
from unittest.mock import Mock, patch
from src.github_handler import GithubHandler, GithubIssue, GithubAPIError


class TestGithubHandler:
    """Test cases for GithubHandler class."""
    
    def setup_method(self):
        """Set up test fixtures."""
        self.handler = GithubHandler("test_token", "DataDog/dd-sdk-ios")
    
    def test_valid_issue_number(self):
        """Test that valid issue numbers are accepted."""
        # Test valid numbers
        assert self.handler._validate_issue_number(1) is None
        assert self.handler._validate_issue_number(100) is None
        assert self.handler._validate_issue_number(10000) is None
    
    def test_invalid_issue_number_types(self):
        """Test that invalid issue number types raise errors."""
        with pytest.raises(ValueError, match="Issue number must be an integer"):
            self.handler._validate_issue_number("not_a_number")
        
        with pytest.raises(ValueError, match="Issue number must be an integer"):
            self.handler._validate_issue_number(3.14)
        
        with pytest.raises(ValueError, match="Issue number must be an integer"):
            self.handler._validate_issue_number(None)
    
    def test_issue_number_out_of_range(self):
        """Test that out-of-range issue numbers raise errors."""
        with pytest.raises(ValueError, match="Issue number must be between 1 and 10000"):
            self.handler._validate_issue_number(0)
        
        with pytest.raises(ValueError, match="Issue number must be between 1 and 10000"):
            self.handler._validate_issue_number(-1)
        
        with pytest.raises(ValueError, match="Issue number must be between 1 and 10000"):
            self.handler._validate_issue_number(10001)
    
    @patch('src.github_handler.requests.get')
    def test_get_issue_success(self, mock_get):
        """Test successful issue retrieval."""
        # Mock successful response
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "number": 123,
            "title": "Test Issue",
            "body": "This is a test issue body",
            "user": {"login": "testuser"},
            "html_url": "https://github.com/DataDog/dd-sdk-ios/issues/123"
        }
        mock_get.return_value = mock_response
        
        # Test the method
        result = self.handler.get_issue(123)
        
        # Verify result
        assert result is not None
        assert result.number == 123
        assert result.title == "Test Issue"
        assert result.body == "This is a test issue body"
        assert result.user == "testuser"
        assert result.html_url == "https://github.com/DataDog/dd-sdk-ios/issues/123"
        
        # Verify API call
        mock_get.assert_called_once()
        call_args = mock_get.call_args
        assert "Authorization" in call_args[1]["headers"]
        assert call_args[1]["headers"]["Authorization"] == "token test_token"
    
    @patch('src.github_handler.requests.get')
    def test_get_issue_not_found(self, mock_get):
        """Test handling of non-existent issues."""
        # Mock 404 response
        mock_response = Mock()
        mock_response.status_code = 404
        mock_get.return_value = mock_response
        
        # Test the method - should return None for 404
        result = self.handler.get_issue(9999)
        assert result is None
    
    @patch('src.github_handler.requests.get')
    def test_get_issue_api_error(self, mock_get):
        """Test handling of API errors."""
        # Mock API error
        mock_response = Mock()
        mock_response.status_code = 500
        mock_response.raise_for_status.side_effect = Exception("500 Internal Server Error")
        mock_get.return_value = mock_response
        
        # Test the method - should raise exception
        with pytest.raises(Exception, match="500 Internal Server Error"):
            self.handler.get_issue(123)
    
    def test_get_issue_validation_error(self):
        """Test that validation errors prevent API calls."""
        with pytest.raises(ValueError):
            self.handler.get_issue("invalid")
        
        with pytest.raises(ValueError):
            self.handler.get_issue(0)
        
        with pytest.raises(ValueError):
            self.handler.get_issue(10001)


class TestGithubIssue:
    """Test cases for GithubIssue dataclass."""
    
    def test_github_issue_creation(self):
        """Test GithubIssue object creation."""
        issue = GithubIssue(
            number=123,
            title="Test Issue",
            body="Test body",
            user="testuser",
            html_url="https://github.com/test/issues/123"
        )
        
        assert issue.number == 123
        assert issue.title == "Test Issue"
        assert issue.body == "Test body"
        assert issue.user == "testuser"
        assert issue.html_url == "https://github.com/test/issues/123"


class TestGithubHandlerFactory:
    """Test cases for create_github_handler factory function."""
    
    @patch.dict(os.environ, {
        'GITHUB_TOKEN': 'test_token',
        'GITHUB_REPOSITORY': 'DataDog/dd-sdk-ios'
    })
    def test_create_github_handler_success(self):
        """Test successful handler creation."""
        from src.github_handler import create_github_handler
        
        handler = create_github_handler()
        assert handler.token == 'test_token'
        assert handler.repository == 'DataDog/dd-sdk-ios'
    
    @patch.dict(os.environ, {}, clear=True)
    def test_create_github_handler_missing_token(self):
        """Test error when GITHUB_TOKEN is missing."""
        from src.github_handler import create_github_handler
        
        with pytest.raises(EnvironmentError, match="GITHUB_TOKEN environment variable must be set"):
            create_github_handler()
    
    @patch.dict(os.environ, {'GITHUB_TOKEN': 'test_token'}, clear=True)
    def test_create_github_handler_missing_repository(self):
        """Test error when GITHUB_REPOSITORY is missing."""
        from src.github_handler import create_github_handler
        
        with pytest.raises(EnvironmentError, match="GITHUB_REPOSITORY environment variable must be set"):
            create_github_handler() 

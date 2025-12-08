# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

"""
Tests for Slack handler functionality.
"""
import pytest
import os
from unittest.mock import patch, Mock
from src.slack_handler import SlackHandler, SlackMessage, SlackError
from src.github_handler import GithubIssue


class TestSlackHandler:
    """Test cases for SlackHandler class."""
    
    def setup_method(self):
        """Set up test fixtures."""
        self.handler = SlackHandler("https://hooks.slack.com/test")
        self.test_issue = GithubIssue(
            number=123,
            title="Test Issue",
            body="Test body",
            user="testuser",
            html_url="https://github.com/test/issues/123"
        )
    
    def test_build_github_url_success(self):
        """Test successful GitHub URL building."""
        with patch.dict(os.environ, {'GITHUB_REPOSITORY': 'DataDog/dd-sdk-ios'}):
            result = self.handler._build_github_url(self.test_issue)
            assert result == "https://github.com/DataDog/dd-sdk-ios/issues/123"
    
    def test_build_github_url_missing_repository(self):
        """Test error when GITHUB_REPOSITORY is missing."""
        with patch.dict(os.environ, {}, clear=True):
            with pytest.raises(EnvironmentError, match="GITHUB_REPOSITORY environment variable must be set"):
                self.handler._build_github_url(self.test_issue)
    
    def test_sanitize_analysis_normal_content(self):
        """Test that normal content is not modified."""
        analysis = {
            'summary': 'This is a normal summary',
            'suggested_response': 'This is a normal response',
            'confidence_level': 'high',
            'feature_docs_used': {
                'consulted': ['RUM'],
                'helpful': True,
                'relevant_sections': ['Troubleshooting']
            }
        }
        
        result = self.handler._sanitize_analysis(analysis)
        
        assert result['summary'] == 'This is a normal summary'
        assert result['suggested_response'] == 'This is a normal response'
        assert result['confidence_level'] == 'high'
        assert result['feature_docs_used']['consulted'] == ['RUM']
        assert result['feature_docs_used']['helpful'] is True
        assert result['feature_docs_used']['relevant_sections'] == ['Troubleshooting']
    
    def test_sanitize_analysis_markdown_links(self):
        """Test that markdown links are removed."""
        analysis = {
            'summary': 'Summary with [link text](https://example.com)',
            'suggested_response': 'Response with [click here](https://malicious.com)',
            'confidence_level': 'high'
        }
        
        result = self.handler._sanitize_analysis(analysis)
        
        assert result['summary'] == 'Summary with link text'
        # "click here" is removed as suspicious content, not just as a markdown link
        assert '[CONTENT REMOVED]' in result['suggested_response']
        assert 'click here' not in result['suggested_response']
    
    def test_sanitize_analysis_urls(self):
        """Test that URLs are removed."""
        analysis = {
            'summary': 'Summary with http://example.com and https://test.com',
            'suggested_response': 'Response with http://malicious.com',
            'confidence_level': 'high'
        }
        
        result = self.handler._sanitize_analysis(analysis)
        
        assert '[URL REMOVED]' in result['summary']
        assert 'http://example.com' not in result['summary']
        assert 'https://test.com' not in result['summary']
        assert '[URL REMOVED]' in result['suggested_response']
        assert 'http://malicious.com' not in result['suggested_response']
    
    def test_sanitize_analysis_html_tags(self):
        """Test that HTML tags are removed."""
        analysis = {
            'summary': 'Summary with <b>bold</b> and <i>italic</i>',
            'suggested_response': 'Response with <script>alert("xss")</script>',
            'confidence_level': 'high'
        }
        
        result = self.handler._sanitize_analysis(analysis)
        
        assert '<b>' not in result['summary']
        assert '<i>' not in result['summary']
        assert 'bold' in result['summary']
        assert 'italic' in result['summary']
        assert '<script>' not in result['suggested_response']
        assert 'alert("xss")' in result['suggested_response']
    
    def test_sanitize_analysis_suspicious_content(self):
        """Test that suspicious content patterns are removed."""
        analysis = {
            'summary': 'Summary with click here and download',
            'suggested_response': 'Response with free and urgent',
            'confidence_level': 'high'
        }
        
        result = self.handler._sanitize_analysis(analysis)
        
        assert '[CONTENT REMOVED]' in result['summary']
        assert 'click here' not in result['summary']
        assert 'download' not in result['summary']
        assert '[CONTENT REMOVED]' in result['suggested_response']
        assert 'free' not in result['suggested_response']
        assert 'urgent' not in result['suggested_response']
    
    def test_sanitize_analysis_script_content(self):
        """Test that script-like content is removed."""
        analysis = {
            'summary': 'Summary with javascript:alert("xss")',
            'suggested_response': 'Response with onload=alert("xss")',
            'confidence_level': 'high'
        }
        
        result = self.handler._sanitize_analysis(analysis)
        
        assert '[SCRIPT REMOVED]' in result['summary']
        assert 'javascript:alert("xss")' not in result['summary']
        assert '[SCRIPT REMOVED]' in result['suggested_response']
        assert 'onload=alert("xss")' not in result['suggested_response']
    
    def test_sanitize_analysis_content_truncation(self):
        """Test that long content is truncated."""
        long_summary = "A" * 2500  # Longer than 2000 character limit for summary
        long_response = "B" * 3500  # Longer than 3000 character limit for response
        
        analysis = {
            'summary': long_summary,
            'suggested_response': long_response,
            'confidence_level': 'high'
        }
        
        result = self.handler._sanitize_analysis(analysis)
        
        # Summary should be truncated at 2000 characters
        assert len(result['summary']) == 2000 + len("\n[Content truncated]")
        assert result['summary'].endswith("[Content truncated]")
        
        # Response should be truncated at 3000 characters
        assert len(result['suggested_response']) == 3000 + len("\n[Content truncated]")
        assert result['suggested_response'].endswith("[Content truncated]")
    
    def test_sanitize_analysis_multiple_sanitizations(self):
        """Test that multiple sanitizations work together."""
        analysis = {
            'summary': 'Summary with <b>bold</b> and [link](http://example.com) and click here',
            'suggested_response': 'Response with javascript:alert("xss")',
            'confidence_level': 'high'
        }
        
        result = self.handler._sanitize_analysis(analysis)
        
        # Should have multiple sanitizations applied
        assert '<b>' not in result['summary']
        assert '[link](http://example.com)' not in result['summary']
        assert 'click here' not in result['summary']
        assert 'javascript:alert("xss")' not in result['suggested_response']
        
        # Should contain sanitized content
        assert 'bold' in result['summary']
        assert 'link' in result['summary']
        assert '[CONTENT REMOVED]' in result['summary']
        assert '[SCRIPT REMOVED]' in result['suggested_response']
    
    @patch('src.slack_handler.requests.post')
    def test_post_issue_with_analysis_success(self, mock_post):
        """Test successful posting to Slack."""
        # Mock successful response
        mock_response = Mock()
        mock_response.raise_for_status.return_value = None
        mock_post.return_value = mock_response
        
        # Test analysis with feature_docs_used
        analysis = {
            'summary': 'Test summary',
            'suggested_response': 'Test response',
            'confidence_level': 'high',
            'feature_docs_used': {
                'consulted': ['RUM'],
                'helpful': True,
                'relevant_sections': ['Troubleshooting']
            }
        }
        
        # Mock environment for URL building
        with patch.dict(os.environ, {'GITHUB_REPOSITORY': 'DataDog/dd-sdk-ios'}):
            self.handler.post_issue_with_analysis(self.test_issue, analysis)
        
        # Verify Slack API call
        mock_post.assert_called_once()
        call_args = mock_post.call_args
        
        # Verify webhook URL
        assert call_args[0][0] == "https://hooks.slack.com/test"
        
        # Verify headers
        assert call_args[1]["headers"]["Content-Type"] == "application/json"
        
        # Verify payload structure
        payload = call_args[1]["json"]
        assert "blocks" in payload
        
        # Verify blocks contain expected content
        blocks = payload["blocks"]
        assert len(blocks) >= 6  # Should have multiple blocks including docs badge
        
        # Check for issue notification
        issue_block = blocks[0]
        assert "testuser" in issue_block["text"]["text"]
        assert "123" in issue_block["text"]["text"]
        assert "Test Issue" in issue_block["text"]["text"]
        
        # Check for analysis
        analysis_block = blocks[3]  # Summary block
        assert "Test summary" in analysis_block["text"]["text"]
        
        # Check for feature docs badge (context block after main badges)
        # Find the docs badge block
        docs_badge_found = False
        for block in blocks:
            if block.get("type") == "context":
                elements = block.get("elements", [])
                for elem in elements:
                    text = elem.get("text", "")
                    if "Docs:" in text and "RUM" in text:
                        docs_badge_found = True
                        assert "✅" in text  # helpful indicator
                        assert "Troubleshooting" in text  # relevant sections in parentheses
                        break
        assert docs_badge_found, "Feature docs badge not found in Slack message"
    
    @patch('src.slack_handler.requests.post')
    def test_post_issue_with_analysis_no_docs_consulted(self, mock_post):
        """Test posting to Slack when no feature docs were consulted."""
        # Mock successful response
        mock_response = Mock()
        mock_response.raise_for_status.return_value = None
        mock_post.return_value = mock_response
        
        # Test analysis without feature_docs_used
        analysis = {
            'summary': 'Test summary',
            'suggested_response': 'Test response',
            'confidence_level': 'high'
        }
        
        # Mock environment for URL building
        with patch.dict(os.environ, {'GITHUB_REPOSITORY': 'DataDog/dd-sdk-ios'}):
            self.handler.post_issue_with_analysis(self.test_issue, analysis)
        
        # Verify Slack API call
        mock_post.assert_called_once()
        call_args = mock_post.call_args
        payload = call_args[1]["json"]
        blocks = payload["blocks"]
        
        # Check for "none" docs badge
        docs_badge_found = False
        for block in blocks:
            if block.get("type") == "context":
                elements = block.get("elements", [])
                for elem in elements:
                    text = elem.get("text", "")
                    if "Docs:" in text and "none" in text:
                        docs_badge_found = True
                        break
        assert docs_badge_found, "Docs: none badge not found in Slack message"

    @patch('src.slack_handler.requests.post')
    def test_post_issue_with_analysis_slack_error(self, mock_post):
        """Test handling of Slack API errors."""
        # Mock Slack API error
        mock_response = Mock()
        mock_response.raise_for_status.side_effect = Exception("Slack API Error")
        mock_post.return_value = mock_response
        
        # Test analysis
        analysis = {
            'summary': 'Test summary',
            'suggested_response': 'Test response',
            'confidence_level': 'high'
        }
        
        # Mock environment for URL building
        with patch.dict(os.environ, {'GITHUB_REPOSITORY': 'DataDog/dd-sdk-ios'}):
            with pytest.raises(SlackError, match="Failed to post to Slack"):
                self.handler.post_issue_with_analysis(self.test_issue, analysis)


class TestSlackMessage:
    """Test cases for SlackMessage dataclass."""
    
    def test_slack_message_creation(self):
        """Test SlackMessage object creation."""
        blocks = [{"type": "section", "text": {"type": "mrkdwn", "text": "Test"}}]
        message = SlackMessage(blocks=blocks)
        
        assert message.blocks == blocks


class TestSlackHandlerFactory:
    """Test cases for create_slack_handler factory function."""
    
    @patch.dict(os.environ, {'SLACK_WEBHOOK_URL': 'https://hooks.slack.com/test'})
    def test_create_slack_handler_success(self):
        """Test successful handler creation."""
        from src.slack_handler import create_slack_handler
        
        handler = create_slack_handler()
        assert handler.webhook_url == 'https://hooks.slack.com/test'
    
    @patch.dict(os.environ, {}, clear=True)
    def test_create_slack_handler_missing_webhook(self):
        """Test error when SLACK_WEBHOOK_URL is missing."""
        from src.slack_handler import create_slack_handler
        
        with pytest.raises(EnvironmentError, match="SLACK_WEBHOOK_URL environment variable must be set"):
            create_slack_handler() 
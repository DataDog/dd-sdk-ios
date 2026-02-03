# GitHub Issue Handler

Automated GitHub issue analyzer that uses OpenAI to analyze new issues and posts summaries to Slack.

## Features

- 🔍 Fetches GitHub issue details via API
- 🤖 Analyzes issues using OpenAI
- 💬 Posts analysis to Slack
- 🔄 Runs automatically on new issues via GitHub Actions
- 🛠️ Can be run manually for specific issues

## Setup

### 1. Create Virtual Environment

```bash
# Create a virtual environment
python3 -m venv venv

# Activate the virtual environment
source venv/bin/activate
```

### 2. Install Dependencies

```bash
pip install -r requirements.txt
```

### 3. Configure Environment

First, create your local environment file:
```bash
# Create .env file from template
./setup_env.sh
```

This creates a `.env` file that you will need to fill with the required tokens and optional configuration. The file includes:

**Required variables:**
- `GITHUB_TOKEN` - GitHub token with repo access
- `OPENAI_TOKEN` - OpenAI API token
- `OPENAI_SYSTEM_PROMPT` - Prompt for OpenAI to analyze issues
- `SLACK_WEBHOOK_URL` - Slack webhook URL for posting notifications
- `SLACK_CHANNEL_ID` - Slack channel ID
- `GITHUB_REPOSITORY` - Repository in format `owner/repo`

**Optional variables** (override defaults):
- `OPENAI_MODEL` - Model to use (default: `chatgpt-4o-latest`)
- `OPENAI_TEMPERATURE` - Response creativity 0.0-1.0 (default: `0.4`)
- `OPENAI_MAX_RESPONSE_TOKENS` - Max response length (default: `500`)

## Usage

### Run Manually

Activate your virtual environment and analyze a specific issue:
```bash
python -m src.analyze_issue ISSUE_NUMBER
```

Example:
```bash
python -m src.analyze_issue 1234
```

### GitHub Action

The tool runs:
1. Automatically when a new issue is opened
2. Manually via workflow dispatch with an issue number

**Required GitHub Secrets** (configured in protected environment):
- `OPENAI_TOKEN` - OpenAI API key
- `SLACK_WEBHOOK_URL` - Slack webhook URL
- `SLACK_CHANNEL_ID` - Slack channel ID (for reference, not currently used in code)

**Required GitHub Variables** (configured in protected environment):
- `OPENAI_SYSTEM_PROMPT` - OpenAI analysis prompt (stored as variable for easier updates)

**Optional GitHub Variables** (override defaults if needed):
- `OPENAI_MODEL` - Model to use (default: `chatgpt-4o-latest`)
- `OPENAI_TEMPERATURE` - Response creativity 0.0-1.0 (default: `0.4`)
- `OPENAI_MAX_RESPONSE_TOKENS` - Max response length (default: `500`)

**Automatically Provided**:
- `GITHUB_TOKEN` - Provided by GitHub Actions
- `GITHUB_REPOSITORY` - Repository name (e.g., `DataDog/dd-sdk-ios`)

## Output

For each issue, the tool does the following:
1. Analyze the issue using OpenAI
2. Post a message to Slack containing:
   - GitHub issue notification
   - Analysis summary
   - Suggested response
   - Confidence level

## Development

### Project structure

- Source code is in `src/`
- Tests are in `tests/`
- Environment variables are managed via `.env`

### Architecture

Main Components:
- analyze_issue.py - Main entry point that orchestrates the workflow
- github_handler.py - Fetches GitHub issue details via API
- openai_handler.py - Analyzes issues using OpenAI
- slack_handler.py - Posts notifications and analysis to Slack

### Workflow 

- GitHub issue is opened → triggers GitHub Action
- Fetches issue details from GitHub API
- Analyzes issue with OpenAI using a custom prompt
- Posts Github issue notification and analysis on Slack

## Security

### Protection Mechanisms

**Content Limits**
- GitHub issue content: Configurable limit (default 4,000 characters)
- OpenAI responses: Configurable token limit (default 500 tokens)
- Slack messages: Configurable character limits (default 2,000-3,000 characters)
- GitHub Action timeout: 5 minutes

**Input Sanitization**
- Removes HTML comments and system instructions
- Filters prompt injection attempts
- Validates issue numbers (must be integers)

**Output Sanitization**
- Removes markdown links and URLs from AI-generated content
- Strips HTML tags and suspicious patterns
- Filters script-like content before posting to Slack

**Dependencies**
- All Python dependencies pinned to exact versions
- Dependabot configured for automated security updates
- Third-party GitHub Actions pinned to commit SHAs

### Best Practices

- Never commit `.env` files (git-ignored by default)
- Store tokens in GitHub Secrets
- Store prompts in GitHub Variables (for easier updates)
- Use protected environments for workflow execution

## Running Tests

Make sure your virtual environment is activated before running tests.

### Unit Tests

Run unit tests (no API calls required):

```bash
pytest tests/
```

Or using make:
```bash
make issue-handler-test
```

### Integration Tests

These tests make real API calls. Ensure your `.env` file is configured before running:

```bash
# Test full workflow with a real issue
PYTHONPATH=. python integration_tests/test_analysis.py --issue 1234

# Test GitHub API connectivity
PYTHONPATH=. python integration_tests/test_real_issue.py --issue 1

# Test Slack webhook
PYTHONPATH=. python test_slack_webhook.py
```

Or use make:
```bash
make issue-handler-integration-test
```

# GitHub Issue Handler

A tool that automatically analyzes new GitHub issues for the Datadog iOS SDK using OpenAI and posts summaries to Slack.

## Features

- 🔍 Fetches GitHub issue details
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

This creates a `.env` file that you will need to fill with the required tokens. The file looks like the following:
```bash
# GitHub token with repo access
GITHUB_TOKEN=

# OpenAI API token
OPENAI_TOKEN=

# Prompt for OpenAI to analyze GitHub issues
OPENAI_SYSTEM_PROMPT=

# Slack webhook URL (for posting notifications)
SLACK_WEBHOOK_URL=

# Slack channel ID (where to post notifications)
SLACK_CHANNEL_ID=

# Github repository (optional, defaults to DataDog/dd-sdk-ios)
GITHUB_REPOSITORY=
```

### 4. Required Tokens

You need several tokens to use the tool locally. See the instructions below to get each token:

#### GitHub Token
1. Go to [GitHub Settings > Developer Settings > Personal Access Tokens](https://github.com/settings/tokens)
2. Generate a new token with `repo` scope
3. Copy the token

#### OpenAI Token
1. Go to [OpenAI API Keys](https://platform.openai.com/api-keys)
2. Create a new API key
3. Copy the key (starts with `sk-`)

#### OpenAI System Prompt
1. Create your AI prompt for analyzing GitHub issues
2. This prompt is used to guide the AI's analysis and response generation

#### Slack Access
The iOS SDK team already has a Slack app configured for this tool. You need:

1. **Slack Webhook URL**:
   - Create a webhook in your Slack workspace: https://api.slack.com/apps
   - Go to "Incoming Webhooks", and create a new webhook
   - Copy the webhook URL (starts with `https://hooks.slack.com/services/`)
   - Store it securely, and never commit it

2. **Slack Channel Setup**:
   - Get the channel ID by clicking the channel's details in Slack, and copy the ID at the bottom
   - The ID starts with "C" (for example, "C12345678")
   - Invite the bot to your channel: `/invite @bot-name`

Note: If you need to post to a new channel, make sure to:
1. Invite the bot to that channel first
2. Use that channel's ID in your `.env` file

## Usage

### Run Manually

Make sure your virtual environment is activated, then analyze a specific issue:
```bash
python src/analyze_issue.py ISSUE_NUMBER
```

For example:
```bash
python src/analyze_issue.py 1234
```

### GitHub Action

The tool runs:
1. Automatically when a new issue is opened in the repository
2. Manually when triggered through GitHub Actions with an issue number

The GitHub Action uses repository secrets for authentication. These are already configured in the repository settings:
- `GITHUB_TOKEN` (automatically provided)
- `OPENAI_TOKEN`
- `OPENAI_SYSTEM_PROMPT`
- `SLACK_WEBHOOK_URL`
- `SLACK_CHANNEL_ID`
- `GITHUB_REPOSITORY` (defaults to `DataDog/dd-sdk-ios`)

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

## Security Notes

- Never commit your `.env` file
- Keep all tokens secure and private
- Use GitHub Secrets for CI/CD
- The `.env` file is git-ignored by default

## Running Tests

Make sure your virtual environment is activated, then run all tests:
```bash
pytest tests/
```

### CI Integration

The issue handler tests are automatically run in the CI pipeline:

**GitLab CI**: Tests run as part of the `tools-test` target when changes are made to the `tools/` directory. The CI environment automatically sets up Python 3 and runs the tests as part of the existing tools testing pipeline.

#### Running Tests Locally

You can run tests locally using this command:

```bash
make issue-handler-test
```

### Integration Tests (manual execution)

These integration tests verify the tool works with real APIs and should be run manually when needed. They require proper environment variables and API tokens:

```bash
cd tools/issue_handler
source venv/bin/activate  # if not already active

# Test full workflow: fetch real GitHub issue + analyze with OpenAI
PYTHONPATH=. python integration_tests/test_analysis.py --issue 1234

# Test GitHub API connectivity with real issues
PYTHONPATH=. python integration_tests/test_real_issue.py --issue 1

# Slack webhook quick checks (requires env vars: SLACK_WEBHOOK_URL and GITHUB_REPOSITORY)
PYTHONPATH=. python test_local.py
PYTHONPATH=. python test_slack_webhook.py
```

**Quick integration test**: You can also use the make command:
```bash
make issue-handler-integration-test
```

**Note**: These are integration tests. They make real API calls and should only be run when you want to verify the tool works with actual services.

## Development Notes

- Always activate your virtual environment before running the tool: `source venv/bin/activate`
- The virtual environment is already git-ignored by default
- If you need to recreate the virtual environment, delete the `venv/` folder and run the setup steps again

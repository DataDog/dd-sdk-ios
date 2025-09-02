#!/bin/bash
# Creates .env template with default prompt for local development

# Check if .env already exists
if [ -f .env ]; then
    echo "⚠️  .env file already exists. Please edit it manually or remove it first."
    exit 1
fi

# Create .env file
cat > .env << EOL
# Required environment variables for the issue handler

# GitHub token with repo access
GITHUB_TOKEN=

# OpenAI API token
OPENAI_TOKEN=

# OpenAI system prompt
OPENAI_SYSTEM_PROMPT=You are an assistant that analyzes GitHub issues. Respond in JSON: {"summary": "brief summary", "suggested_response": "helpful response", "confidence_level": "high|medium|low"}

# Slack webhook URL (for posting notifications)
SLACK_WEBHOOK_URL=

# Slack channel ID (starts with C)
SLACK_CHANNEL_ID=

# Optional: Override the default repository
GITHUB_REPOSITORY=DataDog/dd-sdk-ios
EOL

echo "✨ Created .env file"
echo "📝 Please edit .env and fill in your tokens"
echo "💡 You can find these values in GitHub Secrets under the repository settings"
echo "🔒 Make sure to keep this file private and never commit it to the repository" 

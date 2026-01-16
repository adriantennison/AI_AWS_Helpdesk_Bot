# Deployment Guide - Bedrock Agents

## Prerequisites

1. **AWS Account** with Bedrock access enabled
2. **Slack App** created at api.slack.com/apps
3. **Terraform** >= 1.5 installed
4. **AWS CLI** configured

## Step 1: Enable Bedrock Access

```bash
# Check Bedrock access
aws bedrock list-foundation-models --region us-east-1

# If needed, request Claude 3 Haiku access:
# AWS Console → Bedrock → Model access → Request access
```

## Step 2: Create Slack App

1. Go to https://api.slack.com/apps
2. Click "Create New App" → "From scratch"
3. Name: "Helpdesk Bot"
4. Add Bot Token Scopes:
   - `chat:write`
   - `channels:history`
   - `groups:history`
   - `im:history`
5. Install to workspace
6. Copy "Bot User OAuth Token" (starts with `xoxb-`)

## Step 3: Configure & Deploy

```bash
cd /Users/adrian/Projects/Linkedin/personal/AI_agents_bots

# Configure
cd infrastructure
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars  # Add your slack_bot_token

# Deploy
cd ..
./deploy.sh
```

## Step 4: Prepare Bedrock Agents

```bash
# Get agent IDs
cd infrastructure
terraform output infrastructure_agent_id
terraform output access_agent_id

# In AWS Console:
# 1. Go to Bedrock → Agents
# 2. Select "helpdesk-infrastructure-agent"
# 3. Click "Prepare"
# 4. Repeat for "helpdesk-access-agent"
```

## Step 5: Configure Slack

```bash
# Get webhook URL
terraform output slack_webhook_url
```

1. Go to Slack App → "Event Subscriptions"
2. Enable Events
3. Paste webhook URL in "Request URL"
4. Wait for verification ✓
5. Subscribe to bot events:
   - `message.channels`
   - `message.groups`
   - `message.im`
6. Save Changes

## Step 6: Test

```
/invite @Helpdesk Bot

You: "Is prod-db-01 running?"
Bot: "I checked prod-db-01 and it's currently available..."
```

## Monitoring

```bash
# Slack handler logs
aws logs tail /aws/lambda/helpdesk-slack-handler --follow

# Tool logs
aws logs tail /aws/lambda/helpdesk-infrastructure-tools --follow

# Bedrock metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/Bedrock \
  --metric-name TokensUsed
```

## Cleanup

```bash
cd infrastructure
terraform destroy -auto-approve
```

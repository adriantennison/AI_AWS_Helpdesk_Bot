#!/bin/bash
set -e

echo "🚀 Deploying Multi-Agent Helpdesk Bot (Bedrock Agents)"

# Package Lambda functions
echo "📦 Packaging Lambda functions..."

cd lambda/infrastructure_tools
zip -r ../../infrastructure/infrastructure_tools.zip lambda_function.py
cd ../..

cd lambda/access_tools
zip -r ../../infrastructure/access_tools.zip lambda_function.py
cd ../..

cd lambda/slack_handler
zip -r ../../infrastructure/slack_handler.zip lambda_function.py
cd ../..

# Deploy with Terraform
echo "🏗️  Deploying infrastructure..."
cd infrastructure
terraform init
terraform plan
terraform apply -auto-approve

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📋 Next steps:"
echo "1. Get Slack webhook URL:"
echo "   terraform output slack_webhook_url"
echo ""
echo "2. Prepare agents (in AWS Console):"
echo "   - Go to Bedrock → Agents"
echo "   - Select 'helpdesk-infrastructure-agent'"
echo "   - Click 'Prepare'"
echo "   - Repeat for 'helpdesk-access-agent'"
echo ""
echo "3. Configure Slack Event Subscriptions with webhook URL"
echo ""
echo "4. Test in Slack: 'I can't access prod-db-01'"

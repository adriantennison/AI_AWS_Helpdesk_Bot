terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# IAM Role for Bedrock Agents
resource "aws_iam_role" "bedrock_agent_role" {
  name = "bedrock-helpdesk-agent-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "bedrock.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "bedrock_agent_policy" {
  role = aws_iam_role.bedrock_agent_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["bedrock:InvokeModel"]
        Resource = "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-haiku-20240307-v1:0"
      },
      {
        Effect = "Allow"
        Action = ["lambda:InvokeFunction"]
        Resource = [
          aws_lambda_function.infrastructure_tools.arn,
          aws_lambda_function.access_tools.arn
        ]
      }
    ]
  })
}

# Lambda Role
resource "aws_iam_role" "lambda_role" {
  name = "helpdesk-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  role = aws_lambda_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = ["rds:DescribeDBInstances", "ec2:DescribeInstances"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["iam:ListUserPolicies", "iam:ListAttachedUserPolicies", "iam:PutUserPolicy"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["bedrock:InvokeAgent"]
        Resource = "*"
      }
    ]
  })
}

# Lambda Functions
resource "aws_lambda_function" "infrastructure_tools" {
  filename      = "infrastructure_tools.zip"
  function_name = "helpdesk-infrastructure-tools"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"
  timeout       = 60
}

resource "aws_lambda_function" "access_tools" {
  filename      = "access_tools.zip"
  function_name = "helpdesk-access-tools"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"
  timeout       = 60
}

resource "aws_lambda_function" "slack_handler" {
  filename      = "slack_handler.zip"
  function_name = "helpdesk-slack-handler"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"
  timeout       = 30
  
  environment {
    variables = {
      AGENT_ID        = aws_bedrockagent_agent.infrastructure.agent_id
      AGENT_ALIAS_ID  = "TSTALIASID"
      SLACK_BOT_TOKEN = var.slack_bot_token
    }
  }
}

# Bedrock Agent - Infrastructure
resource "aws_bedrockagent_agent" "infrastructure" {
  agent_name              = "helpdesk-infrastructure-agent"
  agent_resource_role_arn = aws_iam_role.bedrock_agent_role.arn
  foundation_model        = "anthropic.claude-3-haiku-20240307-v1:0"
  
  instruction = <<-EOT
    You are an Infrastructure specialist for AWS helpdesk.
    
    Your responsibilities:
    - Check status of RDS databases
    - Check status of EC2 instances
    - List available databases
    - Investigate infrastructure issues
    
    When tools fail, tell the user the check failed. Never guess results.
    Be specific about what you checked and what you found.
  EOT
}

# Action Group for Infrastructure
resource "aws_bedrockagent_agent_action_group" "infrastructure_tools" {
  agent_id          = aws_bedrockagent_agent.infrastructure.agent_id
  agent_version     = "DRAFT"
  action_group_name = "infrastructure-tools"
  
  action_group_executor {
    lambda = aws_lambda_function.infrastructure_tools.arn
  }
  
  api_schema {
    payload = file("${path.module}/../lambda/infrastructure_tools/openapi_schema.json")
  }
}

# Bedrock Agent - Access
resource "aws_bedrockagent_agent" "access" {
  agent_name              = "helpdesk-access-agent"
  agent_resource_role_arn = aws_iam_role.bedrock_agent_role.arn
  foundation_model        = "anthropic.claude-3-haiku-20240307-v1:0"
  
  instruction = <<-EOT
    You are an Access specialist for AWS helpdesk.
    
    Your responsibilities:
    - Check IAM permissions for users
    - Grant database access (after validation)
    - Validate user authorization
    
    CRITICAL: Always validate before granting access.
    Never grant access to restricted resources without approval.
  EOT
}

# Action Group for Access
resource "aws_bedrockagent_agent_action_group" "access_tools" {
  agent_id          = aws_bedrockagent_agent.access.agent_id
  agent_version     = "DRAFT"
  action_group_name = "access-tools"
  
  action_group_executor {
    lambda = aws_lambda_function.access_tools.arn
  }
  
  api_schema {
    payload = file("${path.module}/../lambda/access_tools/openapi_schema.json")
  }
}

# Lambda permissions for Bedrock
resource "aws_lambda_permission" "bedrock_infrastructure" {
  statement_id  = "AllowBedrockInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.infrastructure_tools.function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = aws_bedrockagent_agent.infrastructure.agent_arn
}

resource "aws_lambda_permission" "bedrock_access" {
  statement_id  = "AllowBedrockInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.access_tools.function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = aws_bedrockagent_agent.access.agent_arn
}

# API Gateway for Slack
resource "aws_apigatewayv2_api" "slack_api" {
  name          = "helpdesk-slack-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.slack_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "slack_integration" {
  api_id           = aws_apigatewayv2_api.slack_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.slack_handler.invoke_arn
}

resource "aws_apigatewayv2_route" "slack_route" {
  api_id    = aws_apigatewayv2_api.slack_api.id
  route_key = "POST /slack/events"
  target    = "integrations/${aws_apigatewayv2_integration.slack_integration.id}"
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.slack_api.execution_arn}/*/*"
}

# Outputs
output "slack_webhook_url" {
  value       = "${aws_apigatewayv2_api.slack_api.api_endpoint}/slack/events"
  description = "URL to configure in Slack Event Subscriptions"
}

output "infrastructure_agent_id" {
  value = aws_bedrockagent_agent.infrastructure.agent_id
}

output "access_agent_id" {
  value = aws_bedrockagent_agent.access.agent_id
}

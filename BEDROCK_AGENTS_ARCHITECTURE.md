# Multi-Agent Helpdesk Bot - AWS Bedrock Agents Architecture

## Why Use Bedrock Agents (Managed Services)

### What Bedrock Agents Gives You (Out of the Box)

1. **Agent Orchestration** - No custom coordinator needed
2. **Context Management** - Automatic conversation memory
3. **Tool Calling** - Built-in function calling
4. **Observability** - CloudWatch traces automatically
5. **Guardrails** - Built-in safety controls
6. **Session Management** - Handles state for you

### What You Still Build

1. **Action Groups** (Lambda functions for tools)
2. **Agent Instructions** (prompts for specialists)
3. **Slack Integration** (event handling)

## New Architecture

```
┌─────────┐
│  Slack  │
└────┬────┘
     │
     ▼
┌─────────────────┐
│  API Gateway    │
└────┬────────────┘
     │
     ▼
┌──────────────────────┐
│ Slack Handler Lambda │
└────┬─────────────────┘
     │
     ▼
┌─────────────────────────────────────┐
│   AWS Bedrock Agents (Managed)      │
│                                     │
│  ┌─────────────────────────────┐   │
│  │  Supervisor Agent           │   │
│  │  (Routes to specialists)    │   │
│  └──────┬──────────────┬───────┘   │
│         │              │            │
│    ┌────▼────┐    ┌───▼─────┐     │
│    │ Infra   │    │ Access  │     │
│    │ Agent   │    │ Agent   │     │
│    └────┬────┘    └───┬─────┘     │
│         │             │            │
│         └──────┬──────┘            │
│                │                   │
│         ┌──────▼──────┐            │
│         │ Action      │            │
│         │ Groups      │            │
│         └──────┬──────┘            │
└────────────────┼───────────────────┘
                 │
                 ▼
        ┌────────────────┐
        │ Lambda Tools   │
        │ - check_db     │
        │ - check_iam    │
        │ - grant_access │
        └────────────────┘
```

## Components

### 1. Bedrock Agents (Managed)

**Supervisor Agent**:
```yaml
Name: helpdesk-supervisor
Model: Claude 3 Haiku
Instructions: |
  You are a helpdesk supervisor. Route requests to:
  - infrastructure-agent: AWS resources, databases, EC2
  - access-agent: IAM permissions, access requests
  
Sub-agents:
  - infrastructure-agent
  - access-agent
```

**Infrastructure Agent**:
```yaml
Name: infrastructure-agent
Model: Claude 3 Haiku
Instructions: |
  You handle AWS infrastructure queries.
  Use tools to check database and EC2 status.
  
Action Groups:
  - check_database_status
  - check_ec2_status
  - list_databases
```

**Access Agent**:
```yaml
Name: access-agent
Model: Claude 3 Haiku
Instructions: |
  You handle IAM and permissions.
  Always validate before granting access.
  
Action Groups:
  - check_iam_permissions
  - grant_database_access
  - validate_user_access
```

### 2. Action Groups (Lambda Functions)

Each action group is a Lambda that Bedrock Agents calls:

```python
# Lambda: check_database_status
def lambda_handler(event, context):
    db_identifier = event['parameters'][0]['value']
    
    rds = boto3.client('rds')
    response = rds.describe_db_instances(DBInstanceIdentifier=db_identifier)
    
    return {
        'response': {
            'actionGroup': 'infrastructure-tools',
            'function': 'check_database_status',
            'functionResponse': {
                'responseBody': {
                    'TEXT': {
                        'body': json.dumps({
                            'status': response['DBInstances'][0]['DBInstanceStatus'],
                            'endpoint': response['DBInstances'][0]['Endpoint']['Address']
                        })
                    }
                }
            }
        }
    }
```

### 3. Slack Integration

```python
# Lambda: slack_handler
def lambda_handler(event, context):
    body = json.loads(event['body'])
    
    if body['type'] == 'url_verification':
        return {'statusCode': 200, 'body': json.dumps({'challenge': body['challenge']})}
    
    slack_event = body['event']
    user_message = slack_event['text']
    user_id = slack_event['user']
    thread_id = slack_event.get('thread_ts', slack_event['ts'])
    
    # Call Bedrock Agent (managed orchestration)
    bedrock_agent = boto3.client('bedrock-agent-runtime')
    
    response = bedrock_agent.invoke_agent(
        agentId='SUPERVISOR_AGENT_ID',
        agentAliasId='PROD',
        sessionId=f"{user_id}_{thread_id}",  # Bedrock manages context
        inputText=user_message
    )
    
    # Bedrock handles routing, context, tool calls automatically
    agent_response = response['completion']
    
    # Post to Slack
    post_to_slack(slack_event['channel'], thread_id, agent_response)
    
    return {'statusCode': 200}
```

## How The 4 Problems Are Solved (Managed)

### Problem 1: Context Passing
**Solution**: Bedrock Agents manages sessions automatically
- Pass `sessionId` to `invoke_agent()`
- Bedrock stores conversation history
- No DynamoDB needed for context

### Problem 2: Tool Validation
**Solution**: Bedrock Agents handles tool errors
- If Lambda fails, Bedrock tells agent "tool failed"
- Agent prompts include error handling instructions
- Built-in retry logic

### Problem 3: Permission Boundaries
**Solution**: IAM policies + Lambda validation
- Each action group has specific IAM permissions
- Lambda validates user authorization before executing
- Bedrock Guardrails filter sensitive outputs

### Problem 4: Cost Tracking
**Solution**: CloudWatch + Bedrock metrics
- Bedrock logs token usage automatically
- CloudWatch metrics for invocations
- Set budget alarms on Bedrock usage

## Terraform Configuration (Managed Services)

```hcl
# Bedrock Agent - Supervisor
resource "aws_bedrockagent_agent" "supervisor" {
  agent_name              = "helpdesk-supervisor"
  agent_resource_role_arn = aws_iam_role.bedrock_agent_role.arn
  foundation_model        = "anthropic.claude-3-haiku-20240307-v1:0"
  
  instruction = <<-EOT
    You are a helpdesk supervisor. Route requests to specialist agents:
    - infrastructure-agent: AWS resources, databases, EC2
    - access-agent: IAM permissions, access requests
  EOT
}

# Bedrock Agent - Infrastructure
resource "aws_bedrockagent_agent" "infrastructure" {
  agent_name              = "infrastructure-agent"
  agent_resource_role_arn = aws_iam_role.bedrock_agent_role.arn
  foundation_model        = "anthropic.claude-3-haiku-20240307-v1:0"
  
  instruction = <<-EOT
    You handle AWS infrastructure queries.
    Use tools to check database and EC2 status.
  EOT
}

# Action Group for Infrastructure
resource "aws_bedrockagent_agent_action_group" "infrastructure_tools" {
  agent_id             = aws_bedrockagent_agent.infrastructure.id
  agent_version        = "DRAFT"
  action_group_name    = "infrastructure-tools"
  action_group_executor {
    lambda = aws_lambda_function.infrastructure_tools.arn
  }
  
  api_schema {
    payload = jsonencode({
      openapi = "3.0.0"
      info = {
        title   = "Infrastructure Tools"
        version = "1.0.0"
      }
      paths = {
        "/check_database_status" = {
          post = {
            description = "Check RDS database status"
            parameters = [{
              name     = "db_identifier"
              in       = "query"
              required = true
              schema   = { type = "string" }
            }]
          }
        }
      }
    })
  }
}

# Bedrock Agent - Access
resource "aws_bedrockagent_agent" "access" {
  agent_name              = "access-agent"
  agent_resource_role_arn = aws_iam_role.bedrock_agent_role.arn
  foundation_model        = "anthropic.claude-3-haiku-20240307-v1:0"
  
  instruction = <<-EOT
    You handle IAM and permissions.
    Always validate before granting access.
  EOT
}

# Bedrock Guardrails
resource "aws_bedrock_guardrail" "helpdesk" {
  name                      = "helpdesk-guardrails"
  blocked_input_messaging   = "This request contains sensitive information."
  blocked_outputs_messaging = "I cannot provide that information."
  
  content_policy_config {
    filters_config {
      input_strength  = "HIGH"
      output_strength = "HIGH"
      type            = "HATE"
    }
  }
  
  sensitive_information_policy_config {
    pii_entities_config {
      action = "BLOCK"
      type   = "EMAIL"
    }
  }
}
```

## Cost Comparison

### Custom Implementation (My Initial Approach)
- Lambda: $5/month
- DynamoDB: $2/month (context storage)
- Bedrock API: $15/month
- **Total: $22/month**

### Managed Services (Bedrock Agents)
- Lambda: $3/month (just tools)
- Bedrock Agents: $20/month (includes orchestration + context)
- **Total: $23/month**

**Difference**: $1/month more, but you get:
- ✅ No context management code
- ✅ No coordinator logic
- ✅ Built-in observability
- ✅ Automatic retries
- ✅ Session management
- ✅ Guardrails included

## Why Bedrock Agents Is Better

| Feature | Custom Implementation | Bedrock Agents |
|---------|----------------------|----------------|
| Context Management | Build DynamoDB logic | ✅ Built-in |
| Agent Orchestration | Build coordinator | ✅ Built-in |
| Tool Calling | Build parser | ✅ Built-in |
| Error Handling | Build wrapper | ✅ Built-in |
| Observability | Setup CloudWatch | ✅ Built-in |
| Retries | Build logic | ✅ Built-in |
| Guardrails | Build filters | ✅ Built-in |
| Code to Maintain | ~1000 lines | ~200 lines |

## What About Strands SDK?

**Strands SDK** is mentioned in your reference but:
- Not publicly available yet (as of Jan 2025)
- Appears to be AWS internal tooling
- Bedrock Agents is the public equivalent

If Strands becomes available, migration would be:
```python
# Current: Bedrock Agents
bedrock_agent.invoke_agent(agentId='...', inputText='...')

# Future: Strands SDK (hypothetical)
from strands import Agent
agent = Agent.from_bedrock('agent-id')
agent.invoke(message='...')
```

## Should I Rebuild With Bedrock Agents?

**YES** - Here's why:

1. **Less code to maintain** (200 vs 1000 lines)
2. **AWS manages complexity** (context, orchestration, retries)
3. **Better observability** (built-in traces)
4. **Easier to scale** (AWS handles infrastructure)
5. **Same cost** (~$23/month)

**I can rebuild this in 30 minutes using Bedrock Agents.**

Do you want me to:
1. ✅ Rebuild using Bedrock Agents (recommended)
2. ❌ Keep custom implementation
3. 🤔 Show both side-by-side for comparison

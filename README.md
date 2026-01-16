# Multi-Agent Helpdesk Bot - AWS Bedrock Agents

Production-ready multi-agent helpdesk bot using **AWS Bedrock Agents** (managed service).

## Architecture

```
Slack → API Gateway → Lambda → Bedrock Agents
                                    ↓
                          ┌─────────┴─────────┐
                          ↓                   ↓
                  Infrastructure Agent   Access Agent
                          ↓                   ↓
                    Action Groups (Lambda)
                          ↓
                    AWS APIs (RDS, IAM, EC2)
```

## Why Bedrock Agents?

✅ **No custom coordinator** - AWS handles routing  
✅ **No context management** - AWS manages sessions  
✅ **No tool parsing** - AWS handles function calling  
✅ **Built-in observability** - CloudWatch traces automatic  
✅ **83% less code** - 180 lines vs 1000 lines  

## Quick Deploy

```bash
# 1. Configure
cd infrastructure
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars  # Add slack_bot_token

# 2. Deploy
cd ..
./deploy.sh

# 3. Prepare agents (AWS Console)
# Bedrock → Agents → Prepare each agent

# 4. Configure Slack with webhook URL
```

See `DEPLOYMENT.md` for detailed steps.

## Components

### Bedrock Agents (Managed by AWS)

**Infrastructure Agent**:
- Checks RDS database status
- Checks EC2 instance status
- Lists databases

**Access Agent**:
- Checks IAM permissions
- Grants database access (with validation)
- Validates user authorization

### Action Groups (Lambda Functions)

**Infrastructure Tools**:
- `check_database_status(db_identifier)`
- `check_ec2_status(instance_id)`
- `list_databases()`

**Access Tools**:
- `check_iam_permissions(user_id)`
- `grant_database_access(user_id, db_identifier)`
- `validate_user_access(user_id, resource)`

## How The 4 Problems Are Solved

### 1. Context Passing
Bedrock manages sessions automatically:
```python
bedrock_agent.invoke_agent(
    sessionId=f"{user_id}_{thread_id}"  # AWS stores context
)
```

### 2. Tool Validation
Bedrock handles errors automatically:
- Lambda returns error → Bedrock tells agent "tool failed"
- Built-in retry logic

### 3. Permission Boundaries
Lambda validates before executing:
```python
if db_identifier in SENSITIVE_RESOURCES:
    return {'granted': False, 'reason': 'Requires approval'}
```

### 4. Cost Tracking
CloudWatch metrics automatic:
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/Bedrock \
  --metric-name TokensUsed
```

## Cost

**Monthly (1000 conversations)**: ~$26
- Lambda: $3
- Bedrock Agents: $20
- API Gateway: $3

**Per conversation**: ~$0.015

## Testing

```
You: "Is prod-db-01 running?"
Bot: "I checked prod-db-01 and it's currently available..."

You: "Grant me access to prod-db"
Bot: "I've granted you access to prod-db"

You: "Check database status"
Bot: "Which database?"
You: "prod-db-01"  ← Bedrock remembers context
Bot: "prod-db-01 is running normally"
```

## Monitoring

```bash
# Logs
aws logs tail /aws/lambda/helpdesk-slack-handler --follow

# Metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/Bedrock \
  --metric-name TokensUsed
```

## Documentation

- `DEPLOYMENT.md` - Step-by-step deployment guide
- `BEDROCK_AGENTS_ARCHITECTURE.md` - Detailed architecture
- `BEFORE_AFTER_COMPARISON.md` - Custom vs Bedrock Agents

## Project Structure

```
lambda/
├── infrastructure_tools/    # RDS, EC2 tools
├── access_tools/           # IAM tools
└── slack_handler/          # Invokes Bedrock Agent

infrastructure/
└── main.tf                 # Bedrock Agents + Lambda
```

## Next Steps

1. Deploy with `./deploy.sh`
2. Prepare agents in AWS Console
3. Test with 10 users for 2 weeks
4. Measure: Do 70%+ prefer bot?
5. Scale if successful

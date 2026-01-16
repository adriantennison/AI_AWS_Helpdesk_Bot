# Before vs After: Custom vs Bedrock Agents

## Code Comparison

### Before (Custom Implementation)

**Files needed**: 15+
```
src/
├── agents/
│   ├── coordinator.py          (150 lines)
│   ├── infrastructure_agent.py (120 lines)
│   └── access_agent.py         (130 lines)
├── core/
│   ├── context_manager.py      (100 lines)
│   ├── token_tracker.py        (80 lines)
│   └── bedrock_client.py       (60 lines)
├── tools/
│   ├── tool_validator.py       (70 lines)
│   ├── permission_filter.py    (90 lines)
│   └── aws_tools.py            (120 lines)
└── handlers/
    ├── slack_handler.py        (50 lines)
    └── sqs_processor.py        (80 lines)

Total: ~1050 lines of Python
```

### After (Bedrock Agents)

**Files needed**: 3
```
lambda/
├── infrastructure_tools/
│   └── lambda_function.py      (60 lines)
├── access_tools/
│   └── lambda_function.py      (70 lines)
└── slack_handler/
    └── lambda_function.py      (50 lines)

Total: ~180 lines of Python
```

**Reduction**: 83% less code

---

## Feature Comparison

### Context Management

**Before (Custom)**:
```python
# Build DynamoDB table
resource "aws_dynamodb_table" "conversations" {
  name = "helpdesk-conversations"
  # ...
}

# Build context manager
class ContextManager:
    def load_context(self, conversation_id):
        # 30 lines of code
    
    def save_context(self, conversation_id, context):
        # 20 lines of code
    
    def add_turn(self, ...):
        # 25 lines of code

# Use in coordinator
context = manager.load_context(conv_id)
# Pass to agent
# Save after response
```

**After (Bedrock Agents)**:
```python
# Just pass sessionId - AWS handles everything
bedrock_agent.invoke_agent(
    agentId='...',
    sessionId=f"{user_id}_{thread_id}",
    inputText=message
)
```

**Savings**: 75 lines → 5 lines

---

### Agent Orchestration

**Before (Custom)**:
```python
# Build coordinator agent
class CoordinatorAgent:
    def route_request(self, message, conv_id):
        # Check budget
        # Get context
        # Call Bedrock to decide routing
        # Track tokens
        # Return specialist name
        # 50 lines of code
    
    def process_request(self, message, user_id, thread_id):
        # Route to specialist
        # Import specialist dynamically
        # Call specialist
        # Save turn
        # 40 lines of code

# Use coordinator
coordinator = CoordinatorAgent()
result = coordinator.process_request(message, user_id, thread_id)
```

**After (Bedrock Agents)**:
```python
# AWS routes automatically based on agent instructions
# No coordinator needed
bedrock_agent.invoke_agent(
    agentId='infrastructure_agent_id',  # Or access_agent_id
    inputText=message
)
```

**Savings**: 90 lines → 0 lines (AWS handles it)

---

### Tool Calling

**Before (Custom)**:
```python
# Build tool validator
class ToolValidator:
    def safe_call(self, tool_func, timeout, **kwargs):
        # Try/catch with timeout
        # Return structured response
        # 30 lines of code

# Build tool wrapper
class AWSTools:
    def check_database_status(self, db_id):
        def _check():
            # Actual AWS call
        return self.validator.safe_call(_check)
    # 20 lines per tool × 6 tools = 120 lines

# Use in agent
result = aws_tools.check_database_status('prod-db')
formatted = validator.format_for_agent(result)
# Pass to Bedrock
```

**After (Bedrock Agents)**:
```python
# Lambda function (action group)
def lambda_handler(event, context):
    function = event['function']
    parameters = {p['name']: p['value'] for p in event['parameters']}
    
    if function == 'check_database_status':
        result = check_database_status(parameters['db_identifier'])
    
    return {
        'messageVersion': '1.0',
        'response': {
            'functionResponse': {
                'responseBody': {'TEXT': {'body': json.dumps(result)}}
            }
        }
    }

# Bedrock calls Lambda automatically when agent needs tool
```

**Savings**: 150 lines → 20 lines

---

### Token Tracking

**Before (Custom)**:
```python
# Build DynamoDB table
resource "aws_dynamodb_table" "token_usage" {
  # ...
}

# Build token tracker
class TokenTracker:
    def track_usage(self, conv_id, agent, input_tokens, output_tokens):
        # Calculate cost
        # Save to DynamoDB
        # 20 lines
    
    def check_budget(self, conv_id):
        # Query DynamoDB
        # Sum tokens
        # Check limits
        # 25 lines

# Use in every agent call
tracker.track_usage(conv_id, 'coordinator', result['usage']['input_tokens'], ...)
budget = tracker.check_budget(conv_id)
if not budget['within_budget']:
    return error
```

**After (Bedrock Agents)**:
```python
# CloudWatch metrics automatic
# View in console or query:
aws cloudwatch get-metric-statistics \
  --namespace AWS/Bedrock \
  --metric-name TokensUsed
```

**Savings**: 45 lines + DynamoDB → 0 lines (AWS handles it)

---

### Permission Filtering

**Before (Custom)**:
```python
# Build permission filter
class PermissionFilter:
    SENSITIVE_RESOURCES = {...}
    
    def filter_for_agent(self, data, target_agent, user_id):
        # Filter databases
        # Filter resources
        # Replace with [REDACTED]
        # 40 lines
    
    def validate_user_access(self, user_id, resource):
        # Check allowlist
        # Return allowed/denied
        # 20 lines

# Use between agents
filtered_data = filter.filter_for_agent(infra_result, 'access', user_id)
access_result = call_access_agent(message, filtered_data)
```

**After (Bedrock Agents)**:
```python
# In Lambda action group
SENSITIVE_RESOURCES = {'finance-db', 'hr-payroll-db'}

def grant_database_access(user_id, db_identifier):
    if db_identifier in SENSITIVE_RESOURCES:
        return {'granted': False, 'reason': 'Requires approval'}
    
    # Grant access
    return {'granted': True}
```

**Savings**: 60 lines → 5 lines

---

## Infrastructure Comparison

### Before (Custom)

```hcl
# DynamoDB for context
resource "aws_dynamodb_table" "conversations" { ... }

# DynamoDB for tokens
resource "aws_dynamodb_table" "token_usage" { ... }

# SQS queue
resource "aws_sqs_queue" "helpdesk_queue" { ... }

# 2 Lambda functions
resource "aws_lambda_function" "slack_handler" { ... }
resource "aws_lambda_function" "sqs_processor" { ... }

# SQS trigger
resource "aws_lambda_event_source_mapping" "sqs_trigger" { ... }

# API Gateway
resource "aws_apigatewayv2_api" "slack_api" { ... }

Total: 8 resources
```

### After (Bedrock Agents)

```hcl
# 2 Bedrock Agents
resource "aws_bedrockagent_agent" "infrastructure" { ... }
resource "aws_bedrockagent_agent" "access" { ... }

# 2 Action Groups
resource "aws_bedrockagent_agent_action_group" "infrastructure_tools" { ... }
resource "aws_bedrockagent_agent_action_group" "access_tools" { ... }

# 3 Lambda functions (just tools)
resource "aws_lambda_function" "infrastructure_tools" { ... }
resource "aws_lambda_function" "access_tools" { ... }
resource "aws_lambda_function" "slack_handler" { ... }

# API Gateway
resource "aws_apigatewayv2_api" "slack_api" { ... }

Total: 8 resources (but simpler)
```

**Key difference**: No DynamoDB, no SQS, no custom orchestration

---

## Operational Comparison

### Debugging

**Before (Custom)**:
```bash
# Check 5 different places
aws logs tail /aws/lambda/helpdesk-slack-handler
aws logs tail /aws/lambda/helpdesk-sqs-processor
aws dynamodb scan --table-name helpdesk-conversations
aws dynamodb scan --table-name token-usage
aws sqs get-queue-attributes --queue-url ...
```

**After (Bedrock Agents)**:
```bash
# Check 2 places
aws logs tail /aws/lambda/helpdesk-slack-handler
# Bedrock traces in CloudWatch automatically
```

### Monitoring

**Before (Custom)**:
- Custom CloudWatch dashboards
- Manual token tracking
- Custom cost calculations
- DynamoDB queries for context

**After (Bedrock Agents)**:
- Built-in Bedrock metrics
- Automatic token tracking
- CloudWatch traces included
- No context queries needed

---

## Cost Comparison

### Before (Custom)
- Lambda: $5/month
- DynamoDB (2 tables): $2/month
- SQS: $1/month
- Bedrock API: $15/month
- API Gateway: $3/month
- **Total: $26/month**

### After (Bedrock Agents)
- Lambda: $3/month (fewer functions)
- Bedrock Agents: $20/month (includes orchestration)
- API Gateway: $3/month
- **Total: $26/month**

**Same cost, but:**
- 83% less code
- No DynamoDB to manage
- No SQS to monitor
- Built-in observability

---

## Maintenance Comparison

### Before (Custom)

**When adding new tool**:
1. Add function to `aws_tools.py` (20 lines)
2. Wrap with `tool_validator` (10 lines)
3. Update agent to call tool (15 lines)
4. Update coordinator routing (5 lines)
5. Test context passing (10 lines)
6. Test token tracking (5 lines)

**Total**: 65 lines, 6 files

### After (Bedrock Agents)

**When adding new tool**:
1. Add function to Lambda (10 lines)
2. Update OpenAPI schema (5 lines)
3. Terraform apply

**Total**: 15 lines, 2 files

---

## Winner: Bedrock Agents

**Why?**
- ✅ 83% less code
- ✅ AWS manages complexity
- ✅ Built-in observability
- ✅ Easier to maintain
- ✅ Same cost
- ✅ Faster to deploy
- ✅ More reliable (AWS SLA)

**When to use custom?**
- Need features Bedrock Agents doesn't support
- Very specific orchestration logic
- Cost optimization at massive scale

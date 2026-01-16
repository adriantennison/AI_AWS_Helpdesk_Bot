import json
import boto3
import os

bedrock_agent = boto3.client('bedrock-agent-runtime')
AGENT_ID = os.environ['AGENT_ID']
AGENT_ALIAS_ID = os.environ['AGENT_ALIAS_ID']
SLACK_BOT_TOKEN = os.environ['SLACK_BOT_TOKEN']

def lambda_handler(event, context):
    """Slack event handler - invokes Bedrock Agent"""
    
    body = json.loads(event.get('body', '{}'))
    
    # Slack URL verification
    if body.get('type') == 'url_verification':
        return {
            'statusCode': 200,
            'body': json.dumps({'challenge': body['challenge']})
        }
    
    # Handle message events
    if body.get('type') == 'event_callback':
        slack_event = body.get('event', {})
        
        # Ignore bot messages
        if slack_event.get('bot_id'):
            return {'statusCode': 200}
        
        user_id = slack_event.get('user')
        channel = slack_event.get('channel')
        text = slack_event.get('text')
        thread_ts = slack_event.get('thread_ts', slack_event.get('ts'))
        
        # Invoke Bedrock Agent (handles routing, context, tools)
        session_id = f"{user_id}_{thread_ts}"
        
        response = bedrock_agent.invoke_agent(
            agentId=AGENT_ID,
            agentAliasId=AGENT_ALIAS_ID,
            sessionId=session_id,
            inputText=text
        )
        
        # Extract response from event stream
        agent_response = ""
        for event in response['completion']:
            if 'chunk' in event:
                chunk = event['chunk']
                if 'bytes' in chunk:
                    agent_response += chunk['bytes'].decode('utf-8')
        
        # Post to Slack
        post_to_slack(channel, thread_ts, agent_response)
    
    return {'statusCode': 200}

def post_to_slack(channel, thread_ts, text):
    """Post message to Slack using Web API"""
    import urllib3
    http = urllib3.PoolManager()
    
    response = http.request(
        'POST',
        'https://slack.com/api/chat.postMessage',
        headers={
            'Authorization': f'Bearer {SLACK_BOT_TOKEN}',
            'Content-Type': 'application/json'
        },
        body=json.dumps({
            'channel': channel,
            'thread_ts': thread_ts,
            'text': text
        })
    )

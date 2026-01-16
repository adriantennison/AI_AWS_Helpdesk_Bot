import json
import boto3

iam = boto3.client('iam')

SENSITIVE_RESOURCES = {'finance-db', 'hr-payroll-db'}

def lambda_handler(event, context):
    """Action group for Access Agent"""
    
    action_group = event['actionGroup']
    function = event['function']
    parameters = {p['name']: p['value'] for p in event.get('parameters', [])}
    
    try:
        if function == 'check_iam_permissions':
            result = check_iam_permissions(parameters['user_id'])
        elif function == 'grant_database_access':
            result = grant_database_access(
                parameters['user_id'],
                parameters['db_identifier']
            )
        elif function == 'validate_user_access':
            result = validate_user_access(
                parameters['user_id'],
                parameters['resource']
            )
        else:
            result = {'error': f'Unknown function: {function}'}
        
        return {
            'messageVersion': '1.0',
            'response': {
                'actionGroup': action_group,
                'function': function,
                'functionResponse': {
                    'responseBody': {
                        'TEXT': {'body': json.dumps(result)}
                    }
                }
            }
        }
    except Exception as e:
        return {
            'messageVersion': '1.0',
            'response': {
                'actionGroup': action_group,
                'function': function,
                'functionResponse': {
                    'responseBody': {
                        'TEXT': {'body': json.dumps({'error': str(e)})}
                    }
                }
            }
        }

def check_iam_permissions(user_id):
    inline = iam.list_user_policies(UserName=user_id)
    attached = iam.list_attached_user_policies(UserName=user_id)
    
    return {
        'user': user_id,
        'inline_policies': inline.get('PolicyNames', []),
        'attached_policies': [p['PolicyName'] for p in attached.get('AttachedPolicies', [])]
    }

def grant_database_access(user_id, db_identifier):
    # Validate user should have access
    if db_identifier in SENSITIVE_RESOURCES:
        return {
            'granted': False,
            'reason': f'{db_identifier} requires manager approval'
        }
    
    policy_name = f'DatabaseAccess-{db_identifier}'
    policy_doc = {
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Action": ["rds:DescribeDBInstances", "rds:Connect"],
            "Resource": f"arn:aws:rds:*:*:db:{db_identifier}"
        }]
    }
    
    iam.put_user_policy(
        UserName=user_id,
        PolicyName=policy_name,
        PolicyDocument=json.dumps(policy_doc)
    )
    
    return {
        'granted': True,
        'user': user_id,
        'resource': db_identifier,
        'policy': policy_name
    }

def validate_user_access(user_id, resource):
    if resource in SENSITIVE_RESOURCES:
        return {
            'allowed': False,
            'reason': f'{resource} is restricted. Requires manager approval.'
        }
    return {'allowed': True, 'reason': 'Public resource'}

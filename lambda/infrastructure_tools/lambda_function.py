import json
import boto3

rds = boto3.client('rds')
ec2 = boto3.client('ec2')

def lambda_handler(event, context):
    """Action group for Infrastructure Agent"""
    
    agent = event['agent']
    action_group = event['actionGroup']
    function = event['function']
    parameters = {p['name']: p['value'] for p in event.get('parameters', [])}
    
    try:
        if function == 'check_database_status':
            result = check_database_status(parameters['db_identifier'])
        elif function == 'check_ec2_status':
            result = check_ec2_status(parameters['instance_id'])
        elif function == 'list_databases':
            result = list_databases()
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

def check_database_status(db_identifier):
    response = rds.describe_db_instances(DBInstanceIdentifier=db_identifier)
    db = response['DBInstances'][0]
    return {
        'identifier': db['DBInstanceIdentifier'],
        'status': db['DBInstanceStatus'],
        'endpoint': db.get('Endpoint', {}).get('Address', 'N/A'),
        'engine': db['Engine']
    }

def check_ec2_status(instance_id):
    response = ec2.describe_instances(InstanceIds=[instance_id])
    instance = response['Reservations'][0]['Instances'][0]
    return {
        'instance_id': instance['InstanceId'],
        'state': instance['State']['Name'],
        'type': instance['InstanceType']
    }

def list_databases():
    response = rds.describe_db_instances()
    return {
        'databases': [
            {
                'identifier': db['DBInstanceIdentifier'],
                'status': db['DBInstanceStatus'],
                'engine': db['Engine']
            }
            for db in response['DBInstances']
        ]
    }

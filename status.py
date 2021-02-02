import json
import socket
import os


def lambda_handler(event, context):

    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    result = sock.connect_ex((os.environ['prv_ip'], 22))
    if result == 0:
        print("Port is open")
    else:
        print("Port is not open")
    sock.close()

    return {
        'statusCode': 200,
        'body': json.dumps('Hello from Lambda!')
    }

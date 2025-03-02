import json
import boto3
import random
import string
import os
import traceback

# Initialize DynamoDB client
# When running inside Lambda in LocalStack, we need to use the internal endpoint
endpoint_url = "http://localhost.localstack.cloud:4566" if os.environ.get("AWS_EXECUTION_ENV") else "http://localhost:4566"
dynamodb = boto3.resource("dynamodb", endpoint_url=endpoint_url)
table = dynamodb.Table("url_mappings")


def generate_short_code(length=6):
    """Generate a random short code of specified length"""
    chars = string.ascii_letters + string.digits
    return "".join(random.choice(chars) for _ in range(length))


def lambda_handler(event, context):
    try:
        print(f"Received event: {json.dumps(event)}")
        
        # Parse the request body
        if "body" in event:
            try:
                body = json.loads(event["body"])
                print(f"Parsed body: {json.dumps(body)}")
            except Exception as e:
                print(f"Error parsing body: {str(e)}")
                print(f"Body content: {event['body']}")
                return {
                    "statusCode": 400,
                    "headers": {"Content-Type": "application/json"},
                    "body": json.dumps({"error": f"Invalid JSON in request body: {str(e)}"}),
                }
        else:
            print("No body in event")
            return {
                "statusCode": 400,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"error": "Missing request body"}),
            }
        
        # Get the URL from the request
        long_url = body.get("url")
        if not long_url:
            print("No URL in body")
            return {
                "statusCode": 400,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"error": "URL is required"}),
            }
        
        print(f"Creating short URL for: {long_url}")
        
        # Generate a unique short code
        short_code = generate_short_code()
        print(f"Generated short code: {short_code}")
        
        # Store the mapping in DynamoDB
        try:
            table.put_item(Item={"short_code": short_code, "long_url": long_url})
            print("Successfully stored in DynamoDB")
        except Exception as e:
            print(f"DynamoDB error: {str(e)}")
            return {
                "statusCode": 500,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"error": f"Database error: {str(e)}"}),
            }
        
        # Construct the short URL
        api_id = event.get("requestContext", {}).get("apiId", "local")
        stage = event.get("requestContext", {}).get("stage", "prod")
        short_url = f"http://localhost:4566/restapis/{api_id}/{stage}/_user_request_/{short_code}"
        
        print(f"Created short URL: {short_url}")
        
        return {
            "statusCode": 201,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"short_code": short_code, "short_url": short_url, "long_url": long_url}),
        }
    except Exception as e:
        print(f"Unexpected error: {str(e)}")
        print(traceback.format_exc())
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": str(e), "trace": traceback.format_exc()}),
        }

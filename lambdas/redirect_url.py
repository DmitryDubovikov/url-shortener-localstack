import json
import boto3
from botocore.exceptions import ClientError
import os
import traceback

# Initialize DynamoDB client
# When running inside Lambda in LocalStack, we need to use the internal endpoint
endpoint_url = "http://localhost.localstack.cloud:4566" if os.environ.get("AWS_EXECUTION_ENV") else "http://localhost:4566"
dynamodb = boto3.resource("dynamodb", endpoint_url=endpoint_url)
table = dynamodb.Table("url_mappings")


def lambda_handler(event, context):
    try:
        print(f"Received event: {json.dumps(event)}")
        
        # Get the short code from the path parameter
        short_code = event.get("pathParameters", {}).get("code")

        if not short_code:
            print("No short code in request")
            return {
                "statusCode": 400,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"error": "Short code is required"}),
            }
        
        print(f"Looking up short code: {short_code}")

        # Look up the long URL in DynamoDB
        try:
            response = table.get_item(Key={"short_code": short_code})
            print(f"DynamoDB response: {json.dumps(response)}")
        except Exception as e:
            print(f"DynamoDB error: {str(e)}")
            return {
                "statusCode": 500,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"error": f"Database error: {str(e)}"}),
            }

        # Check if the item exists
        if "Item" not in response:
            print("Short URL not found")
            return {
                "statusCode": 404,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"error": "Short URL not found"}),
            }

        # Get the long URL
        long_url = response["Item"]["long_url"]
        print(f"Found long URL: {long_url}")

        # Return a redirect response
        return {
            "statusCode": 302,
            "headers": {"Location": long_url, "Content-Type": "text/plain"},
            "body": f"Redirecting to {long_url}",
        }
    except ClientError as e:
        print(f"AWS client error: {str(e)}")
        print(traceback.format_exc())
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": str(e)}),
        }
    except Exception as e:
        print(f"Unexpected error: {str(e)}")
        print(traceback.format_exc())
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": str(e), "trace": traceback.format_exc()}),
        }

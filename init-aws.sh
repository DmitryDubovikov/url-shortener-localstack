#!/bin/bash

set -e

echo "Initializing AWS resources in LocalStack..."

# Create DynamoDB table (ignore error if it already exists)
echo "Creating DynamoDB table..."
aws --endpoint-url=http://localhost:4566 dynamodb create-table \
    --table-name url_mappings \
    --attribute-definitions AttributeName=short_code,AttributeType=S \
    --key-schema AttributeName=short_code,KeyType=HASH \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 || echo "Table already exists, continuing..."

# Create ZIP files for Lambda functions
echo "Creating Lambda deployment packages..."
cd /lambdas
zip -r create_url.zip create_url.py
zip -r redirect_url.zip redirect_url.py

# Create Lambda functions (delete if they already exist)
echo "Creating Lambda functions..."
aws --endpoint-url=http://localhost:4566 lambda delete-function --function-name create-url || echo "Function doesn't exist yet"
aws --endpoint-url=http://localhost:4566 lambda create-function \
    --function-name create-url \
    --runtime python3.9 \
    --handler create_url.lambda_handler \
    --zip-file fileb:///lambdas/create_url.zip \
    --role arn:aws:iam::000000000000:role/lambda-role

aws --endpoint-url=http://localhost:4566 lambda delete-function --function-name redirect-url || echo "Function doesn't exist yet"
aws --endpoint-url=http://localhost:4566 lambda create-function \
    --function-name redirect-url \
    --runtime python3.9 \
    --handler redirect_url.lambda_handler \
    --zip-file fileb:///lambdas/redirect_url.zip \
    --role arn:aws:iam::000000000000:role/lambda-role

# Delete existing API if it exists
echo "Checking for existing API..."
EXISTING_API_ID=$(aws --endpoint-url=http://localhost:4566 apigateway get-rest-apis --query 'items[?name==`url-shortener-api`].id' --output text)
if [ ! -z "$EXISTING_API_ID" ]; then
    echo "Deleting existing API..."
    aws --endpoint-url=http://localhost:4566 apigateway delete-rest-api --rest-api-id $EXISTING_API_ID
fi

# Create API Gateway
echo "Creating API Gateway..."
API_ID=$(aws --endpoint-url=http://localhost:4566 apigateway create-rest-api \
    --name url-shortener-api \
    --query 'id' \
    --output text)

echo "API ID: $API_ID"

# Get the root resource ID
ROOT_RESOURCE_ID=$(aws --endpoint-url=http://localhost:4566 apigateway get-resources \
    --rest-api-id $API_ID \
    --query 'items[0].id' \
    --output text)

echo "Root resource ID: $ROOT_RESOURCE_ID"

# Create /url resource
URL_RESOURCE_ID=$(aws --endpoint-url=http://localhost:4566 apigateway create-resource \
    --rest-api-id $API_ID \
    --parent-id $ROOT_RESOURCE_ID \
    --path-part url \
    --query 'id' \
    --output text)

# Create POST method for /url
aws --endpoint-url=http://localhost:4566 apigateway put-method \
    --rest-api-id $API_ID \
    --resource-id $URL_RESOURCE_ID \
    --http-method POST \
    --authorization-type NONE

# Create integration for POST /url
aws --endpoint-url=http://localhost:4566 apigateway put-integration \
    --rest-api-id $API_ID \
    --resource-id $URL_RESOURCE_ID \
    --http-method POST \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:000000000000:function:create-url/invocations

# Create /{code} resource
CODE_RESOURCE_ID=$(aws --endpoint-url=http://localhost:4566 apigateway create-resource \
    --rest-api-id $API_ID \
    --parent-id $ROOT_RESOURCE_ID \
    --path-part "{code}" \
    --query 'id' \
    --output text)

# Create GET method for /{code}
aws --endpoint-url=http://localhost:4566 apigateway put-method \
    --rest-api-id $API_ID \
    --resource-id $CODE_RESOURCE_ID \
    --http-method GET \
    --authorization-type NONE \
    --request-parameters "method.request.path.code=true"

# Create integration for GET /{code}
aws --endpoint-url=http://localhost:4566 apigateway put-integration \
    --rest-api-id $API_ID \
    --resource-id $CODE_RESOURCE_ID \
    --http-method GET \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:000000000000:function:redirect-url/invocations \
    --request-parameters "integration.request.path.code=method.request.path.code"

# Deploy the API
aws --endpoint-url=http://localhost:4566 apigateway create-deployment \
    --rest-api-id $API_ID \
    --stage-name prod

# Add Lambda permissions
aws --endpoint-url=http://localhost:4566 lambda add-permission \
    --function-name create-url \
    --statement-id apigateway-test \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:us-east-1:000000000000:$API_ID/*/POST/url"

aws --endpoint-url=http://localhost:4566 lambda add-permission \
    --function-name redirect-url \
    --statement-id apigateway-test \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:us-east-1:000000000000:$API_ID/*/GET/*"

echo "API Gateway URL: http://localhost:4566/restapis/$API_ID/prod/_user_request_/"
echo "To create a short URL: curl -X POST http://localhost:4566/restapis/$API_ID/prod/_user_request_/url -d '{\"url\":\"https://example.com\"}'"
echo "To access a short URL: curl -v http://localhost:4566/restapis/$API_ID/prod/_user_request_/YOUR_SHORT_CODE" 
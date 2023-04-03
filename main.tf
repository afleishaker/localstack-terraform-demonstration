resource "aws_sqs_queue" "queue" {
  name = "input_queue"
}

resource "aws_lambda_event_source_mapping" "lambda_sqs_esm" {
  event_source_arn = aws_sqs_queue.queue.arn
  function_name    = aws_lambda_function.lambda.arn
}

data "archive_file" "lambda_code" {
  type        = "zip"
  output_path = "/tmp/lambda_code.zip"
  source {
    content  = <<EOF
    const AWS = require('aws-sdk');
    const client = new AWS.DynamoDB.DocumentClient({
      endpoint: `http://localstack:4566`,
    });

    exports.handler = async (event, context) => {
        const transactions = event.Records.map((record, index) => {
            const { body } = record;
            console.log("Received event: " + JSON.stringify(body));

            const dynamoItem = {
              TableName: 'output_table',
              Item: {
                 EventId: `$${context.awsRequestId}-$${index}`,
                 Timestamp: `$${Date.now()}`,
                 Body: `$${body}`
              }
            }

            return {Put: dynamoItem}
        });

        const transactItems = {TransactItems: transactions}

        console.log("Persisting with the following transactions: " + JSON.stringify(transactItems));

        client.transactWrite(transactItems, function(err, data) {
          if (err) console.log("Persistence failed: " + JSON.stringify(err));
          else console.log("Persistence succeeded: " + JSON.stringify(data));
        });

        return {};
    }
    EOF
    filename = "lambda_code.js"
  }
}

resource "aws_lambda_function" "lambda" {
  filename         = data.archive_file.lambda_code.output_path
  source_code_hash = data.archive_file.lambda_code.output_base64sha256
  function_name    = "lambda"
  runtime          = "nodejs12.x"
  handler          = "lambda_code.handler"
  role             = aws_iam_role.role.arn
}

resource "aws_iam_role" "role" {
  name = "role"
  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_dynamodb_table" "table" {
  name         = "output_table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "EventId"

  attribute {
    name = "EventId"
    type = "S"
  }
}
output "lambda_execution_role_arn" {
  description = "ARN of Lambda execution role"
  value       = aws_iam_role.lambda_execution.arn
}

output "github_actions_role_arn" {
  description = "ARN of GitHub Actions deploy role (set this as AWS_ROLE_ARN secret)"
  value       = aws_iam_role.github_actions_lambda_deploy.arn
}

output "oidc_provider_arn" {
  description = "ARN of GitHub OIDC provider"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "sqs_queue_url" {
  description = "URL of SQS queue for Lambda trigger"
  value       = aws_sqs_queue.lambda_trigger.url
}

output "sqs_queue_arn" {
  description = "ARN of SQS queue"
  value       = aws_sqs_queue.lambda_trigger.arn
}

# API Gateway outputs
output "api_gateway_url" {
  description = "API Gateway endpoint URL (このURLでLambdaを呼び出せます)"
  value       = aws_apigatewayv2_api.lambda_api.api_endpoint
}

output "api_gateway_id" {
  description = "API Gateway ID"
  value       = aws_apigatewayv2_api.lambda_api.id
}

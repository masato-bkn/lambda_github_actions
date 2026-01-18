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

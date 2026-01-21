terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

# GitHub OIDC Provider
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["ffffffffffffffffffffffffffffffffffffffff"]
}

# Lambda execution role
resource "aws_iam_role" "lambda_execution" {
  name = "lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_sqs_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"
}

# GitHub Actions deploy role
resource "aws_iam_role" "github_actions_lambda_deploy" {
  name = "github-actions-lambda-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:*"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "github_actions_lambda_deploy" {
  name = "lambda-deploy-policy"
  role = aws_iam_role.github_actions_lambda_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:GetFunctionConfiguration"
        ]
        Resource = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.lambda_function_name}"
      }
    ]
  })
}

# SQS Queue
resource "aws_sqs_queue" "lambda_trigger" {
  name                       = "${var.lambda_function_name}-queue"
  visibility_timeout_seconds = 30
}

# Lambda event source mapping (SQS -> Lambda)
# エイリアスではなくLambda関数本体を呼び出す（エイリアスはGitHub Actionsで管理）
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.lambda_trigger.arn
  function_name    = var.lambda_function_name
  batch_size       = 10
}

# =============================================================================
# API Gateway HTTP API
# HTTP APIはREST APIよりもシンプルで低コスト
#
# リクエストの流れ:
#   クライアント → API Gateway → route(URLマッチング) → integration(転送設定) → Lambda
# =============================================================================

# API Gateway本体の作成
resource "aws_apigatewayv2_api" "lambda_api" {
  name          = "${var.lambda_function_name}-api"
  protocol_type = "HTTP"
}

# デフォルトステージ（自動デプロイ有効）
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.lambda_api.id
  name        = "$default"
  auto_deploy = true
}

# Lambda統合設定
# - integration_type: AWS_PROXY = リクエストをそのままLambdaに渡し、レスポンスもそのまま返す方式
# - integration_uri: 転送先のLambda関数のARN（HTTP APIではシンプルなARN形式でOK）
# - payload_format_version: 2.0 = HTTP API用の新しいイベント形式
resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.lambda_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.lambda_function_name}"
  payload_format_version = "2.0"
}

# 全パス・全メソッドをLambdaにルーティング
# /{proxy+} は「1つ以上のパスセグメント」を意味する
# 例: /foo, /foo/bar, /a/b/c などにマッチ
# 注意: /{proxy+} はルートパス（/）にはマッチしないため、別途 ANY / のルートが必要
resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.lambda_api.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# ルートパス（/）へのルーティング
# /{proxy+} がルートパスにマッチしないため、これがないと / へのアクセスが404になる
resource "aws_apigatewayv2_route" "root" {
  api_id    = aws_apigatewayv2_api.lambda_api.id
  route_key = "ANY /"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# API GatewayにLambdaを呼び出す「許可」を与える
# Lambdaはデフォルトで外部からの呼び出しを拒否するため、この設定がないと403エラーになる
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.lambda_api.execution_arn}/*/*"
}

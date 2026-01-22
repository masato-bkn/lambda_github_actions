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

# =============================================================================
# GitHub OIDC Provider
# GitHub ActionsがAWSリソースにアクセスするための認証基盤
#
# 【なぜOIDCを使うか】
# - アクセスキー（シークレット）をGitHubに保存しなくて済む
# - 短期トークン（15分〜1時間）で認証するため、漏洩リスクが低い
#
# 【認証フロー】
# 1. GitHub ActionsがGitHubからOIDCトークンを取得
# 2. そのトークンをAWS STSに渡して「私はこのリポジトリです」と証明
# 3. AWSがトークンを検証し、IAMロールの一時クレデンシャルを発行
# 4. GitHub Actionsがそのクレデンシャルでデプロイ実行
# =============================================================================
resource "aws_iam_openid_connect_provider" "github" {
  # GitHubのOIDCトークン発行エンドポイント
  url = "https://token.actions.githubusercontent.com"
  # このトークンを受け入れるサービス（AWS STS）
  client_id_list = ["sts.amazonaws.com"]
  # thumbprint_listは2023年以降AWS側で検証されなくなったため、ダミー値でOK
  thumbprint_list = ["ffffffffffffffffffffffffffffffffffffffff"]
}

# =============================================================================
# Lambda実行ロール
# Lambda関数が実行時に使用するIAMロール
# CloudWatch LogsへのログとSQSからのメッセージ読み取り権限を付与
# =============================================================================
resource "aws_iam_role" "lambda_execution" {
  name = "lambda-execution-role"

  # 信頼ポリシー: Lambdaサービスがこのロールを引き受けることを許可
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

# CloudWatch Logsへのログ書き込み権限（AWS管理ポリシー）
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# SQSキューからのメッセージ読み取り権限（AWS管理ポリシー）
resource "aws_iam_role_policy_attachment" "lambda_sqs_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"
}

# =============================================================================
# GitHub Actionsデプロイロール
# GitHub ActionsからLambdaをデプロイするためのIAMロール
# OIDC認証により、特定のリポジトリからのみアクセスを許可
# =============================================================================
resource "aws_iam_role" "github_actions_lambda_deploy" {
  name = "github-actions-lambda-deploy"

  # 信頼ポリシー: 特定のGitHubリポジトリからのOIDC認証のみ許可
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
          # aud: 対象サービス（AWS STS）を検証
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          # sub: リポジトリを検証（このリポジトリからのみ許可）
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:*"
          }
        }
      }
    ]
  })
}

# lambrollデプロイに必要な権限ポリシー
resource "aws_iam_role_policy" "github_actions_lambda_deploy" {
  name = "lambda-deploy-policy"
  role = aws_iam_role.github_actions_lambda_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:CreateAlias",           # エイリアス作成
          "lambda:CreateFunction",        # 関数作成
          "lambda:GetFunction",           # 関数情報取得
          "lambda:GetFunctionConfiguration", # 関数設定取得
          "lambda:ListTags",              # タグ一覧取得
          "lambda:UpdateAlias",           # エイリアス更新
          "lambda:UpdateFunctionCode",    # コード更新
          "lambda:UpdateFunctionConfiguration" # 設定更新
        ]
        Resource = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.lambda_function_name}"
      },
      {
        # iam:PassRole = 「IAMロールを他のサービスに渡す」権限
        #
        # 【なぜ必要か】
        # lambrollがLambda関数の設定を更新する際、
        # 「この関数はlambda-execution-roleを使って実行する」と指定する。
        # その"ロールを渡す"行為にこの権限が必要。
        #
        # 【セキュリティ上の意味】
        # もしこの権限がなかったら、誰でも強力な権限を持つロールを
        # Lambdaに割り当てて権限昇格できてしまう。
        # Resourceで「渡せるロール」を限定することで安全性を確保。
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = aws_iam_role.lambda_execution.arn  # このロールだけ渡せる
      }
    ]
  })
}

# =============================================================================
# SQSキュー（Lambdaトリガー用）
# SQSにメッセージが届くとLambda関数が自動的に起動する
# =============================================================================
resource "aws_sqs_queue" "lambda_trigger" {
  name = "${var.lambda_function_name}-queue"
  # Lambdaの処理時間を考慮したタイムアウト設定
  # この時間内に処理が完了しないとメッセージが再度キューに戻る
  visibility_timeout_seconds = 30
}

# SQSとLambdaの接続設定（イベントソースマッピング）
# SQSにメッセージが届くと自動的にLambdaを起動する
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.lambda_trigger.arn
  # Lambda関数本体（$LATEST）を呼び出す
  function_name    = var.lambda_function_name
  # 一度に処理するメッセージ数（1〜10000）
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

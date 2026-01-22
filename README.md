# AWS Lambda GitHub Actions Demo

GitHub Actionsを使用してAWS Lambdaにデプロイするサンプルプロジェクト。

## 構成

```
├── .github/workflows/deploy.yml  # GitHub Actionsワークフロー
├── src/
│   ├── index.js                  # Lambda関数
│   └── function.json             # lambroll設定ファイル
├── terraform/                    # インフラ管理
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
└── package.json
```

## セットアップ手順

### 1. Terraformでインフラを作成

まずTerraformでIAMロールなどのインフラを作成します。

```bash
cd terraform

# 変数ファイルを作成
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars を編集（github_org, github_repo を設定）

# 実行
terraform init
terraform plan
terraform apply
```

Terraformで作成されるリソース：
- GitHub OIDC プロバイダー
- Lambda実行ロール（`lambda-execution-role`）
- GitHub Actions用ロール（`github-actions-lambda-deploy`）
- SQSキュー（Lambdaトリガー用）
- イベントソースマッピング（SQS → Lambda）
- API Gateway HTTP API（Lambda呼び出し用エンドポイント）

### 2. Lambda関数を作成

Terraformで作成されたロールを使ってLambda関数を作成します。

```bash
# srcディレクトリ内をzip化（index.jsがルートに来るように）
cd src && zip -r ../function.zip . && cd ..

# Terraformで作成されたロールARNを取得
cd terraform
ROLE_ARN=$(terraform output -raw lambda_execution_role_arn)
cd ..

# Lambda関数を作成
aws lambda create-function \
  --function-name my-lambda-function \
  --runtime nodejs20.x \
  --handler index.handler \
  --role $ROLE_ARN \
  --zip-file fileb://function.zip
```

**注意**: Lambda関数はCommonJS形式（`exports.handler`）で記述してください。ESモジュール形式（`export const handler`）はエラーになります。

### 3. GitHub側の設定

リポジトリの Settings > Secrets and variables > Actions で設定：

| 種類 | 名前 | 値 |
|------|------|-----|
| Secret | `AWS_ROLE_ARN` | `terraform output github_actions_role_arn` の値 |
| Secret | `AWS_ACCOUNT_ID` | AWSアカウントID（12桁の数字） |
| Variable | `AWS_REGION` | `ap-northeast-1` |

### 4. デプロイ

GitHub Actions タブ → 「Run workflow」ボタンで手動実行。

## API Gatewayのテスト

```bash
cd terraform

# エンドポイントURLを取得
terraform output api_gateway_url

# curlでテスト
curl $(terraform output -raw api_gateway_url)
```

## SQSトリガーのテスト

```bash
cd terraform

# SQSにメッセージ送信
aws sqs send-message \
  --queue-url $(terraform output -raw sqs_queue_url) \
  --message-body '{"test": "hello"}'

# CloudWatch Logsでログ確認
aws logs tail /aws/lambda/my-lambda-function --follow
```

## ロールバック

古いコードに戻したい場合は、該当するコミットをチェックアウトして再デプロイします。

```bash
# 特定のコミットに戻す
git checkout <commit-hash>

# GitHub Actionsで再デプロイ
git push origin main
```


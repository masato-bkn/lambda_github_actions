# AWS Lambda GitHub Actions Demo

GitHub Actionsを使用してAWS Lambdaにデプロイするサンプルプロジェクト。

## 構成

```
├── .github/workflows/deploy.yml  # GitHub Actionsワークフロー
├── src/index.js                  # Lambda関数
├── terraform/                    # インフラ管理
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
└── package.json
```

## 使用するGitHub Actions

- [aws-actions/configure-aws-credentials](https://github.com/aws-actions/configure-aws-credentials) - AWS認証（OIDC）
- [aws-actions/aws-lambda-deploy](https://github.com/aws-actions/aws-lambda-deploy) - Lambdaデプロイ

## セットアップ手順

### 1. Lambda関数を作成

```bash
# srcディレクトリをzip化
zip -r function.zip src/

# Lambda関数を作成
aws lambda create-function \
  --function-name my-lambda-function \
  --runtime nodejs20.x \
  --handler index.handler \
  --role arn:aws:iam::ACCOUNT_ID:role/lambda-execution-role \
  --zip-file fileb://function.zip
```

**注意**: Lambda関数はCommonJS形式（`exports.handler`）で記述してください。ESモジュール形式（`export const handler`）はエラーになります。

### 2. Terraformでインフラを作成

```bash
cd terraform

# 変数ファイルを作成
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars を編集

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
- Lambdaエイリアス（`prod`）
- イベントソースマッピング（SQS → Lambda）
- API Gateway HTTP API（Lambda呼び出し用エンドポイント）

### 3. GitHub側の設定

リポジトリの Settings > Secrets and variables > Actions で設定：

| 種類 | 名前 | 値 |
|------|------|-----|
| Secret | `AWS_ROLE_ARN` | `terraform output github_actions_role_arn` の値 |
| Variable | `AWS_REGION` | `ap-northeast-1` |
| Variable | `LAMBDA_FUNCTION_NAME` | Lambda関数名 |

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

エイリアス（`prod`）を使用しているため、バージョンを切り替えるだけでロールバックできます。

### Terraformで変更

```bash
# バージョン3にロールバック
terraform apply -var="lambda_version=3"
```

### AWS CLIで変更

```bash
# バージョン一覧を確認
aws lambda list-versions-by-function --function-name my-lambda-function

# エイリアスの向き先を変更
aws lambda update-alias \
  --function-name my-lambda-function \
  --name prod \
  --function-version 3
```

### AWSコンソールで変更

1. Lambda → 関数を選択
2. 「エイリアス」タブ → `prod` をクリック
3. 「編集」→ バージョンを変更 → 「保存」

## 参考リンク

- [Using GitHub Actions to deploy Lambda functions - AWS Docs](https://docs.aws.amazon.com/lambda/latest/dg/deploying-github-actions.html)
- [aws-actions/aws-lambda-deploy](https://github.com/aws-actions/aws-lambda-deploy)

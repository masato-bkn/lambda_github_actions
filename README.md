# AWS Lambda GitHub Actions Demo

GitHub Actionsを使用してAWS Lambdaに自動デプロイするサンプルプロジェクト。

## 構成

```
├── .github/workflows/deploy.yml  # GitHub Actionsワークフロー
├── src/index.js                  # Lambda関数
└── package.json
```

## 使用するGitHub Actions

- [aws-actions/configure-aws-credentials](https://github.com/aws-actions/configure-aws-credentials) - AWS認証（OIDC）
- [aws-actions/aws-lambda-deploy](https://github.com/aws-actions/aws-lambda-deploy) - Lambdaデプロイ

## セットアップ手順

### 1. AWS側の設定

#### Lambda関数を作成

```bash
aws lambda create-function \
  --function-name my-lambda-function \
  --runtime nodejs20.x \
  --handler src/index.handler \
  --role arn:aws:iam::ACCOUNT_ID:role/lambda-execution-role \
  --zip-file fileb://function.zip
```

#### GitHub OIDC プロバイダーを追加

IAM > Identity providers で以下を設定：
- Provider URL: `https://token.actions.githubusercontent.com`
- Audience: `sts.amazonaws.com`

#### IAM ロールを作成

信頼ポリシー：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/YOUR_REPO:*"
        }
      }
    }
  ]
}
```

必要な権限：
- `lambda:UpdateFunctionCode`
- `lambda:UpdateFunctionConfiguration`
- `lambda:GetFunctionConfiguration`

### 2. GitHub側の設定

リポジトリの Settings > Secrets and variables > Actions で設定：

| 種類 | 名前 | 値 |
|------|------|-----|
| Secret | `AWS_ROLE_ARN` | IAMロールのARN |
| Variable | `AWS_REGION` | `ap-northeast-1` |
| Variable | `LAMBDA_FUNCTION_NAME` | Lambda関数名 |

### 3. デプロイ

`main`ブランチにプッシュすると自動的にデプロイが実行されます。

## 参考リンク

- [Using GitHub Actions to deploy Lambda functions - AWS Docs](https://docs.aws.amazon.com/lambda/latest/dg/deploying-github-actions.html)
- [aws-actions/aws-lambda-deploy](https://github.com/aws-actions/aws-lambda-deploy)

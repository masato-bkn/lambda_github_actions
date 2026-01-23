# =============================================================================
# AWS Lambda用Dockerイメージ
#
# AWS公式のLambdaベースイメージを使用することで：
# - Lambda Runtime Interface Client (RIC) が事前に含まれている
# - Lambda Runtime Interface Emulator (RIE) でローカルテストが可能
# - AWS Lambda実行環境と同じ環境で動作することが保証される
# =============================================================================

# AWS公式のNode.js 20ランタイムベースイメージ
# public.ecr.aws/lambda/ は AWS が提供する公開ECRリポジトリ
FROM public.ecr.aws/lambda/nodejs:20

# アプリケーションコードをLambdaタスクルートにコピー
# LAMBDA_TASK_ROOT は /var/task を指す環境変数（ベースイメージで定義済み）
COPY index.js ${LAMBDA_TASK_ROOT}/

# Lambdaハンドラーを指定
# 形式: ファイル名.エクスポートされた関数名
CMD ["index.handler"]

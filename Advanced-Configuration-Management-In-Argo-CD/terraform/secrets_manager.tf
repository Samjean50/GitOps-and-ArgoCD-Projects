resource "aws_secretsmanager_secret" "app_secret" {
  name        = "my-app/password"
  description = "Application password for GitOps module3"
}

resource "aws_secretsmanager_secret_version" "app_secret_value" {
  secret_id     = aws_secretsmanager_secret.app_secret.id
  secret_string = jsonencode({ password = "mypassword" })
}

module "irsa_external_secrets" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "external-secrets-irsa"

  attach_external_secrets_policy        = true
  external_secrets_secrets_manager_arns = [aws_secretsmanager_secret.app_secret.arn]

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets-sa"]
    }
  }
}
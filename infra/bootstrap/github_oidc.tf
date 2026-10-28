resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_iam_role" "github_deploy" {
  name        = "baby-sweepstake-github-deploy"
  description = "Assumed by GitHub Actions in ${local.github_repository} to deploy the app stacks."

  # GitHub's sub claim is repo:<owner>/<repo>:<context>, where the context is
  # pull_request, ref:refs/heads/<branch> or environment:<name>. The wildcard
  # admits all three, for this repository only.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "sts:AssumeRoleWithWebIdentity"
        Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${local.github_repository}:*"
          }
        }
      }
    ]
  })
}

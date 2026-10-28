mock_provider "aws" {
  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }

  # Role policy attachments validate that policy_arn looks like an ARN.
  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/mock"
    }
  }
}

variables {
  budget_alert_email = "maintainer@example.com"
}

run "deploy_role_trusts_only_this_repository" {
  command = apply

  assert {
    condition = alltrue([
      for statement in jsondecode(aws_iam_role.github_deploy.assume_role_policy).Statement :
      statement.Condition.StringLike["token.actions.githubusercontent.com:sub"] == "repo:MickleByte/baby-sweepstake:*"
    ])
    error_message = "Every trust policy statement must limit the OIDC sub claim to repo:MickleByte/baby-sweepstake:*."
  }

  assert {
    condition = alltrue([
      for statement in jsondecode(aws_iam_role.github_deploy.assume_role_policy).Statement :
      statement.Principal.Federated == aws_iam_openid_connect_provider.github.arn
    ])
    error_message = "The deploy role must only be assumable through the GitHub OIDC provider."
  }
}

run "state_bucket_is_versioned_and_private" {
  command = apply

  assert {
    condition     = aws_s3_bucket.state.bucket == "baby-sweepstake-tfstate-123456789012"
    error_message = "The state bucket name must include the account id."
  }

  assert {
    condition = (
      aws_s3_bucket_versioning.state.bucket == aws_s3_bucket.state.id &&
      aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled"
    )
    error_message = "The state bucket must have versioning enabled."
  }

  assert {
    condition = (
      aws_s3_bucket_public_access_block.state.bucket == aws_s3_bucket.state.id &&
      aws_s3_bucket_public_access_block.state.block_public_acls &&
      aws_s3_bucket_public_access_block.state.block_public_policy &&
      aws_s3_bucket_public_access_block.state.ignore_public_acls &&
      aws_s3_bucket_public_access_block.state.restrict_public_buckets
    )
    error_message = "The state bucket must block all four kinds of public access."
  }
}

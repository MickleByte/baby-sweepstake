data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  github_repository = "MickleByte/baby-sweepstake"
  domain_name       = "baby-sweepstake.com"

  # Every resource the app stacks create is named with this prefix, so the
  # deploy role's permissions can be scoped to it. Bootstrap's own resources
  # deliberately don't use it, which keeps them out of the deploy role's reach.
  resource_prefix = "bs-"
}

output "github_deploy_role_arn" {
  description = "Set as the AWS_ROLE_ARN secret in each GitHub environment."
  value       = aws_iam_role.github_deploy.arn
}

output "state_bucket_name" {
  description = "Set as the TF_STATE_BUCKET secret in each GitHub environment."
  value       = aws_s3_bucket.state.bucket
}

output "service_role_boundary_arn" {
  description = "Permissions boundary the app stacks must attach to every service role they create."
  value       = aws_iam_policy.service_role_boundary.arn
}

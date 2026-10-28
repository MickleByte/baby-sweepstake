# What the deploy role may do. Wherever a service lets IAM scope by resource
# name, access is limited to names starting with local.resource_prefix. The
# broad grants, and why each one is broad, are listed in
# docs/setup/aws-bootstrap.md under "What the deploy role can do".

locals {
  arn_prefix = {
    lambda     = "arn:aws:lambda:*:${local.account_id}"
    dynamodb   = "arn:aws:dynamodb:*:${local.account_id}"
    logs       = "arn:aws:logs:*:${local.account_id}"
    cloudwatch = "arn:aws:cloudwatch:*:${local.account_id}"
    sns        = "arn:aws:sns:*:${local.account_id}"
    ses        = "arn:aws:ses:*:${local.account_id}"
    iam        = "arn:aws:iam::${local.account_id}"
  }

  app_bucket_arns = ["arn:aws:s3:::${local.resource_prefix}*", "arn:aws:s3:::${local.resource_prefix}*/*"]
  app_table_arns = [
    "${local.arn_prefix.dynamodb}:table/${local.resource_prefix}*",
    "${local.arn_prefix.dynamodb}:table/${local.resource_prefix}*/*",
  ]
  app_role_arn = "${local.arn_prefix.iam}:role/${local.resource_prefix}*"
}

resource "aws_iam_policy" "deploy_services" {
  name        = "baby-sweepstake-github-deploy-services"
  description = "App services the GitHub deploy role manages."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AppBuckets"
        Effect   = "Allow"
        Action   = "s3:*"
        Resource = local.app_bucket_arns
      },
      {
        # Distributions, origin access controls and cache policies get
        # generated ids, so they can't be scoped by name.
        Sid      = "CloudFront"
        Effect   = "Allow"
        Action   = "cloudfront:*"
        Resource = "*"
      },
      {
        # Certificates get generated ids.
        Sid      = "Certificates"
        Effect   = "Allow"
        Action   = "acm:*"
        Resource = "*"
      },
      {
        # Records only, and only under the app's domain. Hosted zones
        # themselves can't be created or deleted.
        Sid      = "DnsRecords"
        Effect   = "Allow"
        Action   = "route53:ChangeResourceRecordSets"
        Resource = "arn:aws:route53:::hostedzone/*"
        Condition = {
          "ForAllValues:StringLike" = {
            "route53:ChangeResourceRecordSetsNormalizedRecordNames" = [local.domain_name, "*.${local.domain_name}"]
          }
        }
      },
      {
        Sid    = "DnsRead"
        Effect = "Allow"
        Action = [
          "route53:GetChange",
          "route53:GetHostedZone",
          "route53:ListHostedZones",
          "route53:ListHostedZonesByName",
          "route53:ListResourceRecordSets",
          "route53:ListTagsForResource",
          "route53:ListTagsForResources",
        ]
        Resource = "*"
      },
      {
        # HTTP APIs, stages, routes and integrations get generated ids.
        Sid      = "ApiGateway"
        Effect   = "Allow"
        Action   = ["apigateway:GET", "apigateway:POST", "apigateway:PUT", "apigateway:PATCH", "apigateway:DELETE"]
        Resource = "arn:aws:apigateway:*::/*"
      },
      {
        Sid    = "Functions"
        Effect = "Allow"
        Action = "lambda:*"
        Resource = [
          "${local.arn_prefix.lambda}:function:${local.resource_prefix}*",
          "${local.arn_prefix.lambda}:layer:${local.resource_prefix}*",
        ]
      },
      {
        Sid      = "FunctionsRead"
        Effect   = "Allow"
        Action   = ["lambda:GetAccountSettings", "lambda:ListFunctions", "lambda:ListLayers"]
        Resource = "*"
      },
      {
        Sid      = "Tables"
        Effect   = "Allow"
        Action   = "dynamodb:*"
        Resource = local.app_table_arns
      },
      {
        Sid      = "TablesRead"
        Effect   = "Allow"
        Action   = ["dynamodb:DescribeLimits", "dynamodb:ListTables"]
        Resource = "*"
      },
      {
        # User pools get generated ids, and CreateUserPool takes no resource.
        Sid      = "UserPools"
        Effect   = "Allow"
        Action   = "cognito-idp:*"
        Resource = "*"
      },
      {
        Sid    = "Email"
        Effect = "Allow"
        Action = "ses:*"
        Resource = [
          "${local.arn_prefix.ses}:identity/*",
          "${local.arn_prefix.ses}:configuration-set/${local.resource_prefix}*",
        ]
      },
      {
        # The SES v1 verify actions take no resource.
        Sid      = "EmailReadAndVerify"
        Effect   = "Allow"
        Action   = ["ses:Get*", "ses:List*", "ses:VerifyDomainDkim", "ses:VerifyDomainIdentity", "ses:VerifyEmailIdentity"]
        Resource = "*"
      },
      {
        Sid    = "LogGroups"
        Effect = "Allow"
        Action = "logs:*"
        Resource = [
          "${local.arn_prefix.logs}:log-group:/aws/lambda/${local.resource_prefix}*",
          "${local.arn_prefix.logs}:log-group:${local.resource_prefix}*",
        ]
      },
      {
        # API Gateway access logging and log resource policies are
        # account-level, so these actions take no resource.
        Sid    = "LogDelivery"
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:DeleteResourcePolicy",
          "logs:DescribeLogGroups",
          "logs:DescribeResourcePolicies",
          "logs:GetLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:UpdateLogDelivery",
        ]
        Resource = "*"
      },
      {
        Sid    = "Alarms"
        Effect = "Allow"
        Action = "cloudwatch:*"
        Resource = [
          "${local.arn_prefix.cloudwatch}:alarm:${local.resource_prefix}*",
          "arn:aws:cloudwatch::${local.account_id}:dashboard/${local.resource_prefix}*",
        ]
      },
      {
        Sid      = "AlarmsRead"
        Effect   = "Allow"
        Action   = ["cloudwatch:DescribeAlarms", "cloudwatch:GetMetricData", "cloudwatch:ListDashboards", "cloudwatch:ListMetrics"]
        Resource = "*"
      },
      {
        Sid      = "Topics"
        Effect   = "Allow"
        Action   = "sns:*"
        Resource = "${local.arn_prefix.sns}:${local.resource_prefix}*"
      },
      {
        Sid      = "TopicsRead"
        Effect   = "Allow"
        Action   = "sns:ListTopics"
        Resource = "*"
      },
    ]
  })
}

# Split from deploy_services only to keep each policy well under IAM's
# 6,144-character limit for a managed policy.
resource "aws_iam_policy" "deploy_iam_and_state" {
  name        = "baby-sweepstake-github-deploy-iam-and-state"
  description = "Terraform state access and service-role management for the GitHub deploy role."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "StateList"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.state.arn
      },
      {
        # Delete is for the S3 backend's lockfile.
        Sid      = "StateObjects"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.state.arn}/*"
      },
      {
        # A service role can only be created, or have its boundary changed,
        # with the service-role boundary attached. Without this, the deploy
        # role could create an admin role and escalate through it.
        Sid      = "CreateBoundedServiceRoles"
        Effect   = "Allow"
        Action   = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"]
        Resource = local.app_role_arn
        Condition = {
          StringEquals = { "iam:PermissionsBoundary" = aws_iam_policy.service_role_boundary.arn }
        }
      },
      {
        Sid    = "ManageServiceRoles"
        Effect = "Allow"
        Action = [
          "iam:AttachRolePolicy",
          "iam:DeleteRole",
          "iam:DeleteRolePolicy",
          "iam:DetachRolePolicy",
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfilesForRole",
          "iam:ListRolePolicies",
          "iam:ListRoleTags",
          "iam:PutRolePolicy",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:UpdateAssumeRolePolicy",
          "iam:UpdateRole",
          "iam:UpdateRoleDescription",
        ]
        Resource = local.app_role_arn
      },
      {
        Sid      = "PassServiceRoles"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = local.app_role_arn
        Condition = {
          StringEquals = {
            "iam:PassedToService" = ["apigateway.amazonaws.com", "cognito-idp.amazonaws.com", "lambda.amazonaws.com"]
          }
        }
      },
      {
        Sid    = "ManageServicePolicies"
        Effect = "Allow"
        Action = [
          "iam:CreatePolicy",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicy",
          "iam:DeletePolicyVersion",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyTags",
          "iam:ListPolicyVersions",
          "iam:TagPolicy",
          "iam:UntagPolicy",
        ]
        Resource = "${local.arn_prefix.iam}:policy/${local.resource_prefix}*"
      },
      {
        Sid      = "ReadAwsManagedPolicies"
        Effect   = "Allow"
        Action   = ["iam:GetPolicy", "iam:GetPolicyVersion"]
        Resource = "arn:aws:iam::aws:policy/*"
      },
    ]
  })
}

# The ceiling for every role the app stacks create. A service role's
# effective permissions are the intersection of this and its own policies,
# so it can never reach IAM, STS or anything outside the app's resources.
resource "aws_iam_policy" "service_role_boundary" {
  name        = "baby-sweepstake-service-role-boundary"
  description = "Permissions boundary required on every ${local.resource_prefix}* service role."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AppData"
        Effect   = "Allow"
        Action   = "dynamodb:*"
        Resource = local.app_table_arns
      },
      {
        Sid      = "AppBuckets"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = local.app_bucket_arns
      },
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      },
      {
        Sid      = "Metrics"
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData", "xray:PutTelemetryRecords", "xray:PutTraceSegments"]
        Resource = "*"
      },
      {
        Sid      = "SendEmail"
        Effect   = "Allow"
        Action   = ["ses:SendEmail", "ses:SendRawEmail", "ses:SendTemplatedEmail"]
        Resource = "*"
      },
      {
        Sid      = "PublishToTopics"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = "*"
      },
      {
        Sid      = "UserPools"
        Effect   = "Allow"
        Action   = "cognito-idp:*"
        Resource = "arn:aws:cognito-idp:*:${local.account_id}:userpool/*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_deploy_services" {
  role       = aws_iam_role.github_deploy.name
  policy_arn = aws_iam_policy.deploy_services.arn
}

resource "aws_iam_role_policy_attachment" "github_deploy_iam_and_state" {
  role       = aws_iam_role.github_deploy.name
  policy_arn = aws_iam_policy.deploy_iam_and_state.arn
}

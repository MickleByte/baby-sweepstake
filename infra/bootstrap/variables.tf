variable "aws_region" {
  description = "Region for the state bucket and the app's regional resources."
  type        = string
  default     = "eu-west-2"
}

variable "budget_alert_email" {
  description = "Email address that receives AWS Budgets alerts."
  type        = string

  validation {
    condition     = can(regex("^[^@ ]+@[^@ ]+[.][^@ ]+$", var.budget_alert_email))
    error_message = "budget_alert_email must be an email address."
  }
}

variable "budget_monthly_limit_usd" {
  description = "Monthly cost budget for the whole account, in US dollars."
  type        = number
  default     = 10

  validation {
    condition     = var.budget_monthly_limit_usd > 0
    error_message = "budget_monthly_limit_usd must be greater than zero."
  }
}

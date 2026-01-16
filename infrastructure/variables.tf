variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "poc"
}

variable "slack_bot_token" {
  description = "Slack Bot OAuth Token"
  type        = string
  sensitive   = true
}

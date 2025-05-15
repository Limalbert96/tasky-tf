variable "github_username" {
  description = "GitHub username for container registry authentication"
  type        = string
  default     = "limalbert96"  # Default value, but should be overridden in CI/CD
}

variable "github_pat" {
  description = "GitHub Personal Access Token for container registry authentication"
  type        = string
  sensitive   = true
  # No default value for security reasons - must be provided via environment variable
}

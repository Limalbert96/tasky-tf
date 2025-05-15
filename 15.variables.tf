variable "USERNAME" {
  description = "GitHub username for Container Registry authentication"
  type        = string
  default     = ""
  sensitive   = true
}

variable "PAT" {
  description = "GitHub Personal Access Token for Container Registry authentication"
  type        = string
  default     = ""
  sensitive   = true
}

variable "google_credentials" {
  description = "Google Cloud Service Account credentials JSON"
  type        = string
  default     = ""
  sensitive   = true
}

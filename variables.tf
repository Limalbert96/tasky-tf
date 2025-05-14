variable "github_config" {
  description = "GitHub configuration including username and PAT"
  type = object({
    username = string
    pat     = string
  })
  sensitive = true  # This marks the variable as sensitive in Terraform logs
}

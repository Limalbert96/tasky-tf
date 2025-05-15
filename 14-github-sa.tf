# Service Account for GitHub Actions
resource "google_service_account" "github_actions" {
  account_id   = "github-actions-sa"
  display_name = "GitHub Actions Service Account"
  project      = local.project_id
  description  = "Service account used by GitHub Actions for CI/CD"
}

# Grant necessary roles to the service account
resource "google_project_iam_member" "github_actions_roles" {
  for_each = toset([
    "roles/container.developer",     # Manage GKE resources
    "roles/storage.admin",           # Access to GCS buckets
    "roles/compute.admin",           # Manage compute resources
    "roles/iam.serviceAccountUser",  # Use service accounts
  ])
  
  project = local.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# Create a key for the service account
resource "google_service_account_key" "github_actions_key" {
  service_account_id = google_service_account.github_actions.name
}

# Output the key (this will be sensitive)
output "github_actions_sa_key" {
  value       = google_service_account_key.github_actions_key.private_key
  description = "The private key for the GitHub Actions service account (base64-encoded)"
  sensitive   = true
}

# Instructions for GitHub Actions setup
output "github_actions_setup_instructions" {
  value = <<-EOT
    To set up GitHub Actions with this service account:
    
    1. Go to GitHub repository settings
    2. Navigate to Secrets and Variables > Actions
    3. Add a new repository secret named GCP_SA_KEY
    4. Paste the base64-decoded content of the service account key
    
    The key is available in the Terraform state and can be viewed with:
    terraform output -raw github_actions_sa_key | base64 --decode
  EOT
}


# GitHub Secrets Management
# This file manages GitHub secrets using the GitHub CLI

# Set the GCP_SA_KEY secret in GitHub using the service account key
resource "null_resource" "set_github_secret" {
  triggers = {
    service_account_key = google_service_account_key.github_actions_key.id
  }

  # Use GitHub CLI to set the secret
  provisioner "local-exec" {
    command = <<-EOT
      echo "${google_service_account_key.github_actions_key.private_key}" | gh secret set GCP_SA_KEY --repo Limalbert96/tasky-tf
      echo "${google_service_account_key.github_actions_key.private_key}" | gh secret set GCP_SA_KEY --repo Limalbert96/tasky
    EOT
  }

  depends_on = [google_service_account_key.github_actions_key]
}

# Output confirmation message
output "github_secret_status" {
  value = "GitHub secret GCP_SA_KEY has been set for the repository. It will be used by GitHub Actions workflows."
}
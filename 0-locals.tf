# Project Configuration Variables
# This file contains global variables used throughout the infrastructure

locals {
  # Basic GCP Project Configuration
  project_id = "wiz-demo1"          # Unique project identifier
  region     = "us-central1"            # Primary deployment region

  # Required Google Cloud APIs
  # Security Note: Follow principle of least privilege
  # Only enable APIs that are actually needed
  apis = [
    "compute.googleapis.com",           # For VMs and networking
    "container.googleapis.com",         # For GKE
    "logging.googleapis.com",           # For centralized logging
    "secretmanager.googleapis.com",     # For secrets management
    "storage.googleapis.com",           # For GCS buckets
    "networkservices.googleapis.com",   # For network services
    "iamcredentials.googleapis.com",    # For IAM Service Account credentials
  ]

  # GitHub Configuration
  # Security Anti-Pattern: Credentials in version control
  # Critical Issues:
  # 1. PAT exposed in code
  # 2. No encryption
  # 3. No rotation policy
  # 
  # Production Recommendations:
  # 1. Use Secret Manager or environment variables
  # 2. Implement regular credential rotation
  # 3. Use workload identity when possible
  github_config = {
    username = "xxx"
    # This is intentionally insecure for demonstration
    # NEVER store credentials in version control
    pat = "xxx"
  }
}

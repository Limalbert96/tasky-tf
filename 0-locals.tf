# Project Configuration Variables
# This file contains global variables used throughout the infrastructure

locals {
  # Basic GCP Project Configuration
  project_id = "turing-energy-457000-j5"          # Unique project identifier
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


}

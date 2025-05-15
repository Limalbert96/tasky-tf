#!/bin/bash

# Script to detach the security policy from all backend services
# Run this script before terraform destroy to avoid dependency issues

PROJECT_ID="wiz-demo1"
POLICY_NAME="tasky-security-policy"

echo "Starting security policy detachment process..."

# List all backend services
BACKEND_SERVICES=$(gcloud compute backend-services list --format="value(name)" --project=${PROJECT_ID} 2>/dev/null || echo "")

if [ -z "$BACKEND_SERVICES" ]; then
  echo "No backend services found. Skipping detachment."
  exit 0
fi

# For each backend service, check if it's using our security policy and remove it
for BS in $BACKEND_SERVICES; do
  echo "Checking backend service: $BS"
  # Check if this backend service is using our security policy
  POLICY=$(gcloud compute backend-services describe $BS --project=${PROJECT_ID} --format="value(securityPolicy)" 2>/dev/null || echo "")
  
  if [[ "$POLICY" == *"${POLICY_NAME}"* ]]; then
    echo "Removing security policy from backend service: $BS"
    gcloud compute backend-services update $BS --project=${PROJECT_ID} --security-policy="" || echo "Failed to update $BS, but continuing"
    sleep 5  # Add a small delay to allow the update to propagate
  fi
done

echo "Security policy detachment process completed."

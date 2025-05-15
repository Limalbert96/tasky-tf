# Add a cleanup step to detach the security policy from backend services before destroying it
resource "null_resource" "detach_security_policy" {
  triggers = {
    policy_name = "tasky-security-policy"
    project_id = local.project_id
  }

  # This will run before the security policy is destroyed
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "Starting security policy detachment process..."
      # List all backend services
      BACKEND_SERVICES=$(gcloud compute backend-services list --format="value(name)" --project=${self.triggers.project_id} 2>/dev/null || echo "")
      
      if [ -z "$BACKEND_SERVICES" ]; then
        echo "No backend services found. Skipping detachment."
        exit 0
      fi
      
      # For each backend service, check if it's using our security policy and remove it
      for BS in $BACKEND_SERVICES; do
        echo "Checking backend service: $BS"
        # Check if this backend service is using our security policy
        POLICY=$(gcloud compute backend-services describe $BS --project=${self.triggers.project_id} --format="value(securityPolicy)" 2>/dev/null || echo "")
        
        if [[ "$POLICY" == *"${self.triggers.policy_name}"* ]]; then
          echo "Removing security policy from backend service: $BS"
          gcloud compute backend-services update $BS --project=${self.triggers.project_id} --security-policy="" || echo "Failed to update $BS, but continuing"
          sleep 5  # Add a small delay to allow the update to propagate
        fi
      done
      echo "Security policy detachment process completed."
    EOT
  }
}

# Cloud Armor Security Policy
resource "google_compute_security_policy" "tasky" {
  provider = google
  project  = local.project_id
  name     = "tasky-security-policy"
  
  # Ensure this resource is destroyed after the detach_security_policy resource
  depends_on = [null_resource.detach_security_policy]
  
  # Make sure the security policy is recreated before being destroyed
  lifecycle {
    create_before_destroy = false
  }

  # Rate limiting rule - 100 requests per minute per IP
  rule {
    action   = "rate_based_ban"
    priority = "1000"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      rate_limit_threshold {
        count        = 100
        interval_sec = 60
      }
      conform_action   = "allow"
      exceed_action   = "deny(429)"
      enforce_on_key  = "IP"
      ban_duration_sec = 60  # 1-minute ban if exceeded
    }
    description = "Rate limiting rule - 100 requests per minute per IP"
  }

  # Default rule (required)
  rule {
    action   = "allow"
    priority = "2147483647"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default rule, allows all traffic"
  }

  # Enable verbose logging
  advanced_options_config {
    log_level = "VERBOSE"
  }
}
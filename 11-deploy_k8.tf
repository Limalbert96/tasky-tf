# Setup k8s secret for ghcr image
resource "kubernetes_secret" "ghcr_secret" {
  metadata {
    name = "ghcr-secret"
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "ghcr.io" = {
          # Using actual GitHub credentials from tfvars file
          auth = base64encode("${var.USERNAME}:${var.PAT}")
        } 
      }
    })
  }
  
  # This ensures the resource can be destroyed even if the cluster is gone
  lifecycle {
    ignore_changes = all
  }
  
  depends_on = [
    google_container_cluster.gke,
    google_container_node_pool.general
  ]
}

# Create ConfigMap for MongoDB connection to retrieve host name
resource "kubernetes_config_map" "mongo_config" {
  metadata {
    name = "mongo-config"
  }

  data = {
    MONGODB_HOST = google_compute_instance.mongo_vm.network_interface[0].network_ip
  }
  
  # This ensures the resource can be destroyed even if the cluster is gone
  lifecycle {
    ignore_changes = all
  }
  
  depends_on = [
    google_container_cluster.gke,
    google_container_node_pool.general
  ]
}

# Create Secret for MongoDB credentials
resource "kubernetes_secret" "mongo_creds" {
  metadata {
    name = "mongo-creds"
  }

  data = {
    MONGODB_USER = "tasky_user"
    MONGODB_PASSWORD = "tasky123"
    MONGODB_DATABASE = "taskydb"
  }
  
  # This ensures the resource can be destroyed even if the cluster is gone
  lifecycle {
    ignore_changes = all
  }
  
  depends_on = [
    google_container_cluster.gke,
    google_container_node_pool.general
  ]
}

# 1. Service Account
resource "kubernetes_service_account" "tasky_admin" {
  metadata {
    name = "tasky-admin"
  }
  
  # This ensures the resource can be destroyed even if the cluster is gone
  lifecycle {
    ignore_changes = all
  }
  
  depends_on = [
    google_container_cluster.gke,
    google_container_node_pool.general
  ]
}

# 2. RBAC ClusterRoleBinding
resource "kubernetes_cluster_role_binding" "tasky_admin_binding" {
  metadata {
    name = "tasky-admin-binding"
  }
  
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.tasky_admin.metadata[0].name
    namespace = "default"
  }
  
  # This ensures the resource can be destroyed even if the cluster is gone
  lifecycle {
    ignore_changes = all
  }
  
  depends_on = [
    google_container_cluster.gke,
    google_container_node_pool.general,
    kubernetes_service_account.tasky_admin
  ]
}

# 3. Deployment
resource "kubernetes_deployment" "tasky" {
  metadata {
    name = "tasky"
    annotations = {
      "kubernetes.io/change-cause" = "Initial deployment by Terraform"
    }
  }
  
  timeouts {
    create = "10m"
    update = "10m"
    delete = "5m"
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "tasky"
      }
    }

    template {
      metadata {
        labels = {
          app = "tasky"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.tasky_admin.metadata[0].name
        
        image_pull_secrets {
          name = "ghcr-secret"
        }
        
        container {
          name  = "tasky"
          # Using the GitHub Container Registry image with hardcoded username for local testing
          # In GitHub Actions, this will be replaced with the value from secrets
          image = "ghcr.io/limalbert96/tasky:latest"
          
          env {
            name  = "MONGODB_URI"
            value = "mongodb://$(MONGODB_USER):$(MONGODB_PASSWORD)@$(MONGODB_HOST):27017/$(MONGODB_DATABASE)?authSource=$(MONGODB_DATABASE)"
          }
          
          env_from {
            config_map_ref {
              name = kubernetes_config_map.mongo_config.metadata[0].name
            }
          }
          
          env_from {
            secret_ref {
              name = kubernetes_secret.mongo_creds.metadata[0].name
            }
          }
          
          port {
            container_port = 8080
          }
          
          readiness_probe {
            http_get {
              path = "/"
              port = 8080
            }
            initial_delay_seconds = 10
            period_seconds = 5
            timeout_seconds = 2
            success_threshold = 1
            failure_threshold = 3
          }
          
          liveness_probe {
            http_get {
              path = "/"
              port = 8080
            }
            initial_delay_seconds = 30
            period_seconds = 10
            timeout_seconds = 5
            failure_threshold = 5
          }
          
          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }
          
          security_context {
            privileged = true
            run_as_user = 0
          }
        }
      }
    }
  }
  
  # This ensures the resource can be destroyed even if the cluster is gone
  lifecycle {
    ignore_changes = all
  }
  
  depends_on = [
    google_container_cluster.gke,
    google_container_node_pool.general,
    kubernetes_service_account.tasky_admin,
    kubernetes_secret.ghcr_secret,
    kubernetes_config_map.mongo_config,
    kubernetes_secret.mongo_creds
  ]
}

# 4. Backend Config for Cloud Armor
# Using local-exec provisioner instead of kubernetes_manifest to avoid provider issues
resource "null_resource" "tasky_backend_config" {
  triggers = {
    cluster_name = google_container_cluster.gke.name
    cluster_zone = google_container_cluster.gke.location
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Get credentials for the cluster
      gcloud container clusters get-credentials ${google_container_cluster.gke.name} --zone ${google_container_cluster.gke.location} --project ${local.project_id}
      
      # Create the BackendConfig using kubectl
      cat <<EOF | kubectl apply -f -
      apiVersion: cloud.google.com/v1beta1
      kind: BackendConfig
      metadata:
        name: tasky-backend-config
        namespace: default
      spec:
        securityPolicy:
          name: tasky-security-policy
      EOF
    EOT
  }
  
  depends_on = [
    google_container_cluster.gke,
    google_container_node_pool.general
  ]
}

# 5. Service
resource "kubernetes_service" "tasky" {
  metadata {
    name = "tasky"
    annotations = {
      "cloud.google.com/neg" = jsonencode({"ingress" = true})
      "cloud.google.com/backend-config" = jsonencode({"default" = "tasky-backend-config"})
    }
  }

  spec {
    type = "NodePort"
    
    port {
      port        = 80
      target_port = 8080
      protocol    = "TCP"
    }
    
    selector = {
      app = "tasky"
    }
  }
  
  # This ensures the resource can be destroyed even if the cluster is gone
  lifecycle {
    ignore_changes = all
  }
  
  depends_on = [
    google_container_cluster.gke,
    google_container_node_pool.general,
    null_resource.tasky_backend_config
  ]
}

# 6. Ingress
resource "kubernetes_ingress_v1" "tasky_ingress" {
  metadata {
    name = "tasky-ingress"
    annotations = {
      "kubernetes.io/ingress.class" = "gce"
      "kubernetes.io/ingress.allow-http" = "true"
    }
  }

  spec {
    rule {
      http {
        path {
          path = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.tasky.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    google_container_cluster.gke,
    google_container_node_pool.general,
    kubernetes_service.tasky
  ]
  
  # This ensures the resource can be destroyed even if the cluster is gone
  lifecycle {
    ignore_changes = all
  }
}

# 7. Cleanup resources on destroy
# This ensures network endpoint groups are cleaned up before other resources
resource "null_resource" "cleanup_neg" {
  # Only run this on destroy
  triggers = {
    cluster_name = google_container_cluster.gke.name
    cluster_zone = google_container_cluster.gke.location
    project_id = local.project_id
  }

  # This will run before the cluster is destroyed
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      # List and delete all network endpoint groups in the zone
      NEGS=$(gcloud compute network-endpoint-groups list --filter="zone:${self.triggers.cluster_zone}" --format="value(name)")
      for NEG in $NEGS; do
        echo "Deleting network endpoint group $NEG"
        gcloud compute network-endpoint-groups delete "$NEG" --zone=${self.triggers.cluster_zone} --quiet || true
      done

      # List and delete any backend services that might be using the security policy
      BACKENDS=$(gcloud compute backend-services list --format="value(name)")
      for BACKEND in $BACKENDS; do
        echo "Deleting backend service $BACKEND"
        gcloud compute backend-services delete "$BACKEND" --global --quiet || true
      done
    EOT
  }

  depends_on = [
    kubernetes_ingress_v1.tasky_ingress
  ]
}

# Manual cleanup script for when the cluster is already gone
resource "null_resource" "manual_cleanup" {
  # This will run during apply to clean up any leftover resources
  provisioner "local-exec" {
    command = <<-EOT
      # List and delete all network endpoint groups in the zone
      NEGS=$(gcloud compute network-endpoint-groups list --filter="zone:us-central1-a" --format="value(name)")
      for NEG in $NEGS; do
        echo "Deleting network endpoint group $NEG"
        gcloud compute network-endpoint-groups delete "$NEG" --zone=us-central1-a --quiet || true
      done

      # List and delete any backend services that might be using the security policy
      BACKENDS=$(gcloud compute backend-services list --format="value(name)")
      for BACKEND in $BACKENDS; do
        echo "Deleting backend service $BACKEND"
        gcloud compute backend-services delete "$BACKEND" --global --quiet || true
      done
    EOT
  }
}

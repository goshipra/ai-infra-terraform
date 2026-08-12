# ------------------------------------------------------------------------------------
# ai-infra-terraform / examples/local
#
# This is the root module a user actually runs `terraform apply` against. It wires up
# the docker provider and calls modules/local-docker with paths appropriate for the
# conventional side-by-side checkout layout:
#
#   ~/GitHub/rag-mlops-pipeline
#   ~/GitHub/llm-observability-stack
#   ~/GitHub/ai-infra-terraform/examples/local   <-- you run terraform here
#
# See variables.tf to override paths/ports, or copy terraform.tfvars.example.
# ------------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "docker" {}

module "ai_infra" {
  source = "../../modules/local-docker"

  rag_repo_path           = var.rag_repo_path
  observability_repo_path = var.observability_repo_path

  rag_service_build_from_source = var.rag_service_build_from_source
  rag_service_image             = var.rag_service_image

  qdrant_port      = var.qdrant_port
  rag_service_port = var.rag_service_port
  prometheus_port  = var.prometheus_port
  grafana_port     = var.grafana_port
}

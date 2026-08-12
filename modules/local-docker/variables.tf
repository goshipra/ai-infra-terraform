# ------------------------------------------------------------------------------------
# Sibling repo paths
#
# This module provisions the stack defined by two sibling repos. Defaults assume all
# three repos are checked out side by side, e.g.:
#
#   ~/GitHub/rag-mlops-pipeline
#   ~/GitHub/llm-observability-stack
#   ~/GitHub/ai-infra-terraform   <-- this repo
#
# Paths are resolved relative to whatever root module calls this one (see
# examples/local/variables.tf for the concrete relative paths used there).
# ------------------------------------------------------------------------------------

variable "rag_repo_path" {
  description = "Path to the rag-mlops-pipeline checkout, used as the Docker build context for rag-service when rag_service_build_from_source is true."
  type        = string
  default     = "../rag-mlops-pipeline"
}

variable "observability_repo_path" {
  description = "Path to the llm-observability-stack checkout. Its grafana/provisioning/ and grafana/dashboards/ directories are bind-mounted into the Grafana container."
  type        = string
  default     = "../llm-observability-stack"
}

# ------------------------------------------------------------------------------------
# Networking
# ------------------------------------------------------------------------------------

variable "docker_network_name" {
  description = "Name of the shared Docker bridge network all services join."
  type        = string
  default     = "ai-infra"
}

# ------------------------------------------------------------------------------------
# rag-service
# ------------------------------------------------------------------------------------

variable "rag_service_build_from_source" {
  description = "If true, build the rag-service image locally from rag_repo_path using Docker. If false, pull rag_service_image instead (e.g. a pre-built tag from a registry)."
  type        = bool
  default     = true
}

variable "rag_service_image" {
  description = "Image reference to pull when rag_service_build_from_source is false (e.g. \"ghcr.io/you/rag-service:latest\"). Ignored when building from source."
  type        = string
  default     = "rag-service:latest"
}

variable "rag_service_image_tag" {
  description = "Tag applied to the image built from source when rag_service_build_from_source is true."
  type        = string
  default     = "local"
}

variable "rag_service_dockerfile_name" {
  description = "Dockerfile name (relative to rag_repo_path) used when building rag-service from source."
  type        = string
  default     = "Dockerfile"
}

variable "rag_service_port" {
  description = "Host port mapped to rag-service's container port 3000."
  type        = number
  default     = 3000
}

variable "rag_service_env" {
  description = "Extra environment variables passed to the rag-service container, as \"KEY=VALUE\" strings."
  type        = list(string)
  default     = []
}

# ------------------------------------------------------------------------------------
# Qdrant
# ------------------------------------------------------------------------------------

variable "qdrant_image_tag" {
  description = "Tag for the official qdrant/qdrant image."
  type        = string
  default     = "v1.11.0"
}

variable "qdrant_port" {
  description = "Host port mapped to Qdrant's REST API (container port 6333)."
  type        = number
  default     = 6333
}

variable "qdrant_grpc_port" {
  description = "Host port mapped to Qdrant's gRPC API (container port 6334)."
  type        = number
  default     = 6334
}

variable "persist_qdrant_data" {
  description = "If true, create a named Docker volume for Qdrant storage so data survives container recreation."
  type        = bool
  default     = true
}

# ------------------------------------------------------------------------------------
# Prometheus
# ------------------------------------------------------------------------------------

variable "prometheus_image_tag" {
  description = "Tag for the prom/prometheus image. Matches the pin used in llm-observability-stack's docker-compose.yml for consistency."
  type        = string
  default     = "v2.54.1"
}

variable "prometheus_port" {
  description = "Host port mapped to Prometheus's UI/API (container port 9090)."
  type        = number
  default     = 9090
}

variable "prometheus_scrape_interval" {
  description = "Scrape interval Prometheus uses when scraping rag-service:3000/metrics."
  type        = string
  default     = "15s"
}

# ------------------------------------------------------------------------------------
# Grafana
# ------------------------------------------------------------------------------------

variable "grafana_image_tag" {
  description = "Tag for the grafana/grafana image. Matches the pin used in llm-observability-stack's docker-compose.yml for consistency."
  type        = string
  default     = "11.2.0"
}

variable "grafana_port" {
  description = "Host port mapped to Grafana's UI (container port 3000 internally)."
  type        = number
  default     = 3001
}

variable "grafana_admin_user" {
  description = "Grafana admin username. Defaults only suitable for local/demo use."
  type        = string
  default     = "admin"
}

variable "grafana_admin_password" {
  description = "Grafana admin password. Defaults only suitable for local/demo use — override for anything reachable outside localhost."
  type        = string
  default     = "admin"
  sensitive   = true
}

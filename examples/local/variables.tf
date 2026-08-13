# Defaults here are relative to THIS directory (examples/local), which sits two levels
# below ai-infra-terraform. Assuming the conventional side-by-side layout described in
# the repo root README, that means going up three levels to reach the sibling repos.

variable "rag_repo_path" {
  description = "Path to the rag-mlops-pipeline checkout."
  type        = string
  default     = "../../../rag-mlops-pipeline"
}

variable "observability_repo_path" {
  description = "Path to the llm-observability-stack checkout."
  type        = string
  default     = "../../../llm-observability-stack"
}

variable "rag_service_build_from_source" {
  description = "Build rag-service from rag_repo_path (true) or pull rag_service_image (false)."
  type        = bool
  default     = true
}

variable "rag_service_image" {
  description = "Pre-built rag-service image reference, used only when rag_service_build_from_source is false."
  type        = string
  default     = "rag-service:latest"
}

variable "qdrant_port" {
  type    = number
  default = 6333
}

variable "rag_service_port" {
  type    = number
  default = 3000
}

variable "prometheus_port" {
  type    = number
  default = 9090
}

variable "grafana_port" {
  type    = number
  default = 3001
}

# Docker Desktop on macOS does not listen on the provider's default
# unix:///var/run/docker.sock — `terraform apply` fails at the very first
# resource with "Cannot connect to the Docker daemon" until this is set
# explicitly. Verified by an actual `terraform apply` run, not just
# `validate` (which cannot catch this — it never talks to a Docker daemon).
# Find yours with:
#   docker context inspect $(docker context show) --format '{{.Endpoints.docker.Host}}'
# then pass it via terraform.tfvars or -var, e.g.:
#   docker_host = "unix:///Users/<you>/.docker/run/docker.sock"
# Leave blank on Linux / Docker Desktop for Windows / anywhere the provider
# default already resolves correctly.
variable "docker_host" {
  description = "Docker daemon socket. Required on macOS Docker Desktop; see comment above for how to find yours."
  type        = string
  default     = ""
}

# ------------------------------------------------------------------------------------
# This module is NOT applied by default (see modules/aws/README.md for why). It
# assumes an existing VPC — bring your own network via vpc_id/subnet_ids rather than
# having this module create one, to keep the blast radius (and the diff a reviewer has
# to read) limited to the AI stack itself.
# ------------------------------------------------------------------------------------

variable "name_prefix" {
  description = "Prefix applied to all resource names, e.g. \"ai-infra\"."
  type        = string
  default     = "ai-infra"
}

variable "vpc_id" {
  description = "Existing VPC to deploy into."
  type        = string
}

variable "subnet_ids" {
  description = "Existing subnet IDs (at least 2, in different AZs) for the ECS service and ALB."
  type        = list(string)
}

variable "aws_region" {
  description = "AWS region, used for AMP/log group ARNs and the Grafana workspace."
  type        = string
  default     = "us-east-1"
}

# --------------------------------------------------------------------------------
# rag-service (ECS Fargate)
# --------------------------------------------------------------------------------

variable "rag_service_image" {
  description = "Container image URI for rag-service, e.g. \"<account>.dkr.ecr.<region>.amazonaws.com/rag-service:latest\". Push the image built from rag-mlops-pipeline here first (see README)."
  type        = string
  default     = "PLACEHOLDER_ECR_IMAGE_URI"
}

variable "rag_service_port" {
  type    = number
  default = 3000
}

variable "rag_service_cpu" {
  description = "Fargate task CPU units for rag-service."
  type        = number
  default     = 512
}

variable "rag_service_memory" {
  description = "Fargate task memory (MiB) for rag-service."
  type        = number
  default     = 1024
}

variable "rag_service_desired_count" {
  type    = number
  default = 1
}

variable "rag_service_env" {
  description = "Extra environment variables for the rag-service container."
  type        = map(string)
  default     = {}
}

variable "create_ecr_repository" {
  description = "If true, create an ECR repository for rag-service. Set false if you already have one and are only passing its URI via rag_service_image."
  type        = bool
  default     = true
}

# --------------------------------------------------------------------------------
# Qdrant
# --------------------------------------------------------------------------------

variable "qdrant_deployment" {
  description = "How Qdrant is deployed: \"ec2\" (self-hosted on a single EC2 instance with an attached EBS volume) or \"cloud\" (skip provisioning; use Qdrant Cloud and pass its URL to rag-service via rag_service_env instead)."
  type        = string
  default     = "ec2"

  validation {
    condition     = contains(["ec2", "cloud"], var.qdrant_deployment)
    error_message = "qdrant_deployment must be either \"ec2\" or \"cloud\"."
  }
}

variable "qdrant_instance_type" {
  type    = string
  default = "t3.small"
}

variable "qdrant_ami_id" {
  description = "AMI for the Qdrant EC2 instance (Amazon Linux 2023 recommended). Required when qdrant_deployment = \"ec2\"."
  type        = string
  default     = ""
}

variable "qdrant_volume_size_gb" {
  description = "Size in GB of the EBS volume backing Qdrant storage."
  type        = number
  default     = 20
}

variable "qdrant_key_pair_name" {
  description = "Existing EC2 key pair for SSH access to the Qdrant instance. Leave empty to disable SSH key injection."
  type        = string
  default     = ""
}

# --------------------------------------------------------------------------------
# Observability
# --------------------------------------------------------------------------------

variable "use_managed_observability" {
  description = "If true, use Amazon Managed Prometheus (AMP) + Amazon Managed Grafana (AMG) — no servers to patch. If false, run self-hosted Prometheus + Grafana as ECS Fargate services, mirroring modules/local-docker's shape on AWS."
  type        = bool
  default     = true
}

variable "grafana_admin_user" {
  type    = string
  default = "admin"
}

variable "grafana_admin_password" {
  description = "Admin password for self-hosted Grafana (only used when use_managed_observability = false; AMG uses SSO/IAM Identity Center instead)."
  type        = string
  default     = "changeme-before-applying"
  sensitive   = true
}

variable "prometheus_image_tag" {
  type    = string
  default = "v2.54.1"
}

variable "grafana_image_tag" {
  type    = string
  default = "11.2.0"
}

# --------------------------------------------------------------------------------
# Storage
# --------------------------------------------------------------------------------

variable "create_corpus_bucket" {
  description = "If true, create an S3 bucket for RAG source-document ingestion. No RDS is provisioned — Qdrant is this stack's stateful backend, so a relational database isn't part of this shape; add one only if your pipeline needs relational metadata beyond what Qdrant's payload fields cover."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default = {
    Project   = "ai-infra-terraform"
    ManagedBy = "terraform"
  }
}

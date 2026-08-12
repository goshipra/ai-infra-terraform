output "rag_service_url" {
  description = "Public URL of the rag-service ALB."
  value       = "http://${aws_lb.rag_service.dns_name}"
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "ecr_repository_url" {
  description = "Push rag-service images here (or set create_ecr_repository = false and point rag_service_image elsewhere)."
  value       = var.create_ecr_repository ? aws_ecr_repository.rag_service[0].repository_url : null
}

output "qdrant_private_ip" {
  description = "Private IP of the self-hosted Qdrant instance (null when qdrant_deployment = \"cloud\")."
  value       = var.qdrant_deployment == "ec2" ? aws_instance.qdrant[0].private_ip : null
}

output "amp_workspace_id" {
  description = "Amazon Managed Prometheus workspace ID (null when use_managed_observability = false)."
  value       = var.use_managed_observability ? aws_prometheus_workspace.this[0].id : null
}

output "amp_prometheus_endpoint" {
  description = "AMP query endpoint (null when use_managed_observability = false)."
  value       = var.use_managed_observability ? aws_prometheus_workspace.this[0].prometheus_endpoint : null
}

output "grafana_workspace_endpoint" {
  description = "Amazon Managed Grafana workspace URL (null when use_managed_observability = false)."
  value       = var.use_managed_observability ? aws_grafana_workspace.this[0].endpoint : null
}

output "self_hosted_observability_note" {
  description = "Reminder shown when running the self-hosted (non-managed) observability path."
  value = var.use_managed_observability ? null : (
    "Self-hosted Prometheus/Grafana ECS services are running but their EFS access " +
    "points start empty — copy prometheus.yml and the Grafana provisioning/dashboard " +
    "files onto the EFS volume before the UIs will show data. See README.md."
  )
}

output "corpus_bucket_name" {
  value = var.create_corpus_bucket ? aws_s3_bucket.corpus[0].id : null
}

output "network_name" {
  description = "Name of the shared Docker network joining all four services."
  value       = docker_network.ai_infra.name
}

output "qdrant_url" {
  description = "Qdrant REST API, reachable from the host."
  value       = "http://localhost:${var.qdrant_port}"
}

output "rag_service_url" {
  description = "rag-service base URL."
  value       = "http://localhost:${var.rag_service_port}"
}

output "rag_service_healthz_url" {
  description = "rag-service health check endpoint."
  value       = "http://localhost:${var.rag_service_port}/healthz"
}

output "rag_service_metrics_url" {
  description = "rag-service Prometheus metrics endpoint."
  value       = "http://localhost:${var.rag_service_port}/metrics"
}

output "rag_service_query_url" {
  description = "rag-service query endpoint."
  value       = "http://localhost:${var.rag_service_port}/query"
}

output "prometheus_url" {
  description = "Prometheus UI."
  value       = "http://localhost:${var.prometheus_port}"
}

output "grafana_url" {
  description = "Grafana UI. Default credentials are admin/admin unless overridden."
  value       = "http://localhost:${var.grafana_port}"
}

output "service_urls" {
  description = "All service URLs in one map, for convenience."
  value = {
    qdrant      = "http://localhost:${var.qdrant_port}"
    rag_service = "http://localhost:${var.rag_service_port}"
    prometheus  = "http://localhost:${var.prometheus_port}"
    grafana     = "http://localhost:${var.grafana_port}"
  }
}

output "qdrant_url" {
  value = module.ai_infra.qdrant_url
}

output "rag_service_url" {
  value = module.ai_infra.rag_service_url
}

output "rag_service_healthz_url" {
  value = module.ai_infra.rag_service_healthz_url
}

output "rag_service_metrics_url" {
  value = module.ai_infra.rag_service_metrics_url
}

output "rag_service_query_url" {
  value = module.ai_infra.rag_service_query_url
}

output "prometheus_url" {
  value = module.ai_infra.prometheus_url
}

output "grafana_url" {
  value = module.ai_infra.grafana_url
}

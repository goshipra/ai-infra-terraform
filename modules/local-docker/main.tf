# ------------------------------------------------------------------------------------
# ai-infra-terraform / modules/local-docker
#
# Provisions the RAG + observability stack entirely on the local Docker daemon, at
# zero cloud cost:
#
#   qdrant  --\
#               > rag-service --\
#   (vector db)                  > prometheus --> grafana
#                                (scrapes /metrics)  (dashboards)
#
# All four containers join one shared bridge network so they can reach each other by
# container name (the interface rag-service, qdrant, prometheus and grafana all
# expect). See variables.tf for every knob; see outputs.tf for the URLs printed after
# `terraform apply`.
# ------------------------------------------------------------------------------------

resource "docker_network" "ai_infra" {
  name = var.docker_network_name
}

# --------------------------------------------------------------------------------
# Qdrant — vector database
# --------------------------------------------------------------------------------

resource "docker_image" "qdrant" {
  name = "qdrant/qdrant:${var.qdrant_image_tag}"
}

resource "docker_volume" "qdrant_data" {
  count = var.persist_qdrant_data ? 1 : 0
  name  = "${var.docker_network_name}-qdrant-data"
}

resource "docker_container" "qdrant" {
  name    = "qdrant"
  image   = docker_image.qdrant.image_id
  restart = "unless-stopped"

  networks_advanced {
    name = docker_network.ai_infra.name
  }

  ports {
    internal = 6333
    external = var.qdrant_port
  }

  ports {
    internal = 6334
    external = var.qdrant_grpc_port
  }

  dynamic "volumes" {
    for_each = var.persist_qdrant_data ? [1] : []
    content {
      volume_name    = docker_volume.qdrant_data[0].name
      container_path = "/qdrant/storage"
    }
  }
}

# --------------------------------------------------------------------------------
# rag-service — built from source (rag-mlops-pipeline) or pulled pre-built
# --------------------------------------------------------------------------------

resource "docker_image" "rag_service" {
  name = var.rag_service_build_from_source ? "rag-service:${var.rag_service_image_tag}" : var.rag_service_image

  dynamic "build" {
    for_each = var.rag_service_build_from_source ? [1] : []
    content {
      context    = var.rag_repo_path
      dockerfile = var.rag_service_dockerfile_name
    }
  }

  # Re-pull/re-build whenever the caller flips the build toggle or points at a
  # different sibling checkout, instead of silently reusing a stale local image.
  triggers = {
    build_from_source = tostring(var.rag_service_build_from_source)
    rag_repo_path     = var.rag_repo_path
    image_ref         = var.rag_service_build_from_source ? var.rag_service_image_tag : var.rag_service_image
  }
}

resource "docker_container" "rag_service" {
  name    = "rag-service"
  image   = docker_image.rag_service.image_id
  restart = "unless-stopped"
  env     = var.rag_service_env

  networks_advanced {
    name = docker_network.ai_infra.name
  }

  ports {
    internal = 3000
    external = var.rag_service_port
  }

  depends_on = [docker_container.qdrant]
}

# --------------------------------------------------------------------------------
# Prometheus — scrapes rag-service:3000/metrics
#
# The scrape config is rendered from templates/prometheus.yml.tpl and bind-mounted
# in, rather than sourced from llm-observability-stack, so this module can
# `terraform apply` on its own even before that sibling repo's prometheus/ directory
# is populated. Point observability_repo_path at a real checkout for Grafana below.
# --------------------------------------------------------------------------------

resource "local_file" "prometheus_config" {
  filename = "${path.module}/.generated/prometheus.yml"
  content = templatefile("${path.module}/templates/prometheus.yml.tpl", {
    rag_service_container_name = docker_container.rag_service.name
    rag_service_port           = 3000
    scrape_interval            = var.prometheus_scrape_interval
  })
}

resource "docker_image" "prometheus" {
  name = "prom/prometheus:${var.prometheus_image_tag}"
}

resource "docker_container" "prometheus" {
  name    = "prometheus"
  image   = docker_image.prometheus.image_id
  restart = "unless-stopped"
  command = [
    "--config.file=/etc/prometheus/prometheus.yml",
    "--storage.tsdb.path=/prometheus",
  ]

  networks_advanced {
    name = docker_network.ai_infra.name
  }

  ports {
    internal = 9090
    external = var.prometheus_port
  }

  volumes {
    host_path      = abspath(local_file.prometheus_config.filename)
    container_path = "/etc/prometheus/prometheus.yml"
    read_only      = true
  }

  depends_on = [docker_container.rag_service]
}

# --------------------------------------------------------------------------------
# Grafana — dashboards/datasources provisioned from llm-observability-stack
# --------------------------------------------------------------------------------

resource "docker_image" "grafana" {
  name = "grafana/grafana:${var.grafana_image_tag}"
}

resource "docker_container" "grafana" {
  name    = "grafana"
  image   = docker_image.grafana.image_id
  restart = "unless-stopped"

  env = [
    "GF_SECURITY_ADMIN_USER=${var.grafana_admin_user}",
    "GF_SECURITY_ADMIN_PASSWORD=${var.grafana_admin_password}",
    "GF_USERS_ALLOW_SIGN_UP=false",
  ]

  networks_advanced {
    name = docker_network.ai_infra.name
  }

  ports {
    internal = 3000
    external = var.grafana_port
  }

  volumes {
    host_path      = abspath("${var.observability_repo_path}/grafana/provisioning")
    container_path = "/etc/grafana/provisioning"
    read_only      = true
  }

  volumes {
    host_path      = abspath("${var.observability_repo_path}/grafana/dashboards")
    container_path = "/var/lib/grafana/dashboards"
    read_only      = true
  }

  depends_on = [docker_container.prometheus]
}

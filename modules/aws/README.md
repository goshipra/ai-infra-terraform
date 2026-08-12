# modules/aws

## Status: syntax-validated, not applied

**This module demonstrates the AWS deployment shape and is validated for syntax; it
has not been applied against a live AWS account to avoid incurring cost. Review
before applying.**

Concretely, that means:

- `terraform init` and `terraform validate` were run against this module and both
  succeed (see the repo root README for the actual output). `validate` checks HCL
  syntax, type-checks arguments against each resource's provider schema, and resolves
  references between resources — all without needing AWS credentials.
- `terraform plan` / `terraform apply` were **not** run. Doing so would require real
  AWS credentials and would create real, billable resources (an ALB, an EC2 instance,
  an EFS filesystem, and — on the managed path — an AMP workspace and AMG workspace
  all carry an hourly cost even at rest).
- Treat this as a design artifact: read it the way you'd read a well-commented
  architecture doc, not something to `apply` blind. `qdrant_ami_id` is deliberately
  left blank (no default) and `vpc_id`/`subnet_ids` have no default either — both are
  required inputs precisely so this module cannot be applied by accident.

Not spending money to keep a portfolio demo "live" is itself the engineering
judgment call being demonstrated here, not a shortcut around it — see the root
README's "Why the AWS module isn't applied" section for the fuller argument.

## What it provisions (same shape as `modules/local-docker`, reproduced on AWS)

| Local (`modules/local-docker`)        | AWS (`modules/aws`)                                                             |
|----------------------------------------|-----------------------------------------------------------------------------------|
| `docker_container.rag_service`         | ECS Fargate service + task definition, behind an ALB, image from ECR             |
| `docker_container.qdrant`               | EC2 instance running the `qdrant/qdrant` image via `user_data`, EBS-backed (or point at Qdrant Cloud — see `qdrant_deployment`) |
| `docker_container.prometheus`           | Amazon Managed Prometheus (default) **or** a self-hosted Prometheus ECS service  |
| `docker_container.grafana`              | Amazon Managed Grafana (default) **or** a self-hosted Grafana ECS service        |
| shared `docker_network`                 | shared VPC (bring your own — see `vpc_id`/`subnet_ids`) + security groups        |
| bind-mounted `prometheus.yml`           | ADOT collector sidecar (managed path) or an EFS-mounted config (self-hosted path) |
| bind-mounted Grafana provisioning dirs | EFS access point (self-hosted path) or AMG's own provisioning (managed path)     |
| —                                       | S3 bucket for RAG source documents (`create_corpus_bucket`); no RDS — see `storage.tf` for why |

## Key design decisions

- **AMP + AMG by default (`use_managed_observability = true`).** No Prometheus/Grafana
  servers to patch or scale. The trade-off: Amazon Managed Grafana's
  `authentication_providers = ["AWS_SSO"]` default requires IAM Identity Center
  enabled in the account — swap to `["SAML"]` if you use an external IdP instead.
- **Self-hosted alternative (`use_managed_observability = false`)** runs Prometheus
  and Grafana as their own ECS Fargate services, config/dashboards held on EFS access
  points, mirroring `modules/local-docker`'s container-for-container shape as closely
  as AWS's primitives allow. The EFS volume starts empty — populate
  `/prometheus/prometheus.yml` and the `/grafana` provisioning tree once (e.g. via a
  one-off `aws efs`-mounted EC2/Cloud9 session, or a bootstrap ECS task) before the
  services will show data.
- **Qdrant on EC2, not ECS**, because Qdrant is stateful and EBS-backed EC2 is the
  simplest way to give it persistent, low-latency local storage without standing up
  EFS-for-a-database or a StatefulSet-equivalent. `qdrant_deployment = "cloud"` is the
  documented escape hatch if you'd rather not run infrastructure for the vector store
  at all — point `rag_service_env` at your Qdrant Cloud cluster URL and this module
  skips provisioning it.
- **No RDS.** Qdrant is this stack's only stateful backend, same as in
  `modules/local-docker`. Adding a relational database here would be scope creep, not
  "the same stack on AWS."
- **Bring your own VPC.** `vpc_id`/`subnet_ids` are required inputs with no default,
  so this module's blast radius stays limited to the AI stack itself rather than
  also owning (and being able to misconfigure) the network underneath it.

## If you do want to apply this

1. Provide real values for `vpc_id`, `subnet_ids`, and `qdrant_ami_id` (an Amazon
   Linux 2023 AMI ID for your region).
2. Build and push a `rag-service` image to the ECR repo this module creates (or set
   `create_ecr_repository = false` and pass an existing image URI via
   `rag_service_image`).
3. Change `grafana_admin_password` from its placeholder default (self-hosted path
   only — AMG uses SSO/IAM Identity Center, not a local admin password).
4. Run `terraform plan` and read every line before `terraform apply`. Tear down with
   `terraform destroy` promptly after — an ALB, EC2 instance, and EFS filesystem all
   bill by the hour.

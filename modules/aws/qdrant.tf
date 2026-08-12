# --------------------------------------------------------------------------------
# Qdrant
#
# Self-hosted on a single EC2 instance running the qdrant/qdrant Docker image via
# user_data, with a dedicated EBS volume for storage — the cheapest way to reproduce
# the local module's Qdrant container shape on AWS.
#
# Alternative: set qdrant_deployment = "cloud" to skip provisioning entirely and
# point rag-service at a Qdrant Cloud cluster instead (see README.md). Qdrant Cloud
# removes the operational burden of patching/scaling a self-hosted node, at the cost
# of an external dependency — a reasonable trade for a small team.
# --------------------------------------------------------------------------------

resource "aws_security_group" "qdrant" {
  count = var.qdrant_deployment == "ec2" ? 1 : 0

  name_prefix = "${var.name_prefix}-qdrant-"
  description = "Qdrant EC2 instance: allow REST/gRPC from rag-service only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Qdrant REST API from rag-service"
    from_port       = 6333
    to_port         = 6333
    protocol        = "tcp"
    security_groups = [aws_security_group.rag_service.id]
  }

  ingress {
    description     = "Qdrant gRPC API from rag-service"
    from_port       = 6334
    to_port         = 6334
    protocol        = "tcp"
    security_groups = [aws_security_group.rag_service.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

resource "aws_instance" "qdrant" {
  count = var.qdrant_deployment == "ec2" ? 1 : 0

  ami                    = var.qdrant_ami_id
  instance_type          = var.qdrant_instance_type
  subnet_id              = var.subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.qdrant[0].id]
  key_name               = var.qdrant_key_pair_name != "" ? var.qdrant_key_pair_name : null

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    dnf install -y docker
    systemctl enable --now docker

    # Wait for the EBS data volume to attach, then format it on first boot only.
    until [ -e /dev/xvdf ]; do sleep 2; done
    if ! blkid /dev/xvdf; then
      mkfs -t xfs /dev/xvdf
    fi
    mkdir -p /var/lib/qdrant-storage
    mount /dev/xvdf /var/lib/qdrant-storage
    echo '/dev/xvdf /var/lib/qdrant-storage xfs defaults,nofail 0 2' >> /etc/fstab

    docker run -d --name qdrant --restart unless-stopped \
      -p 6333:6333 -p 6334:6334 \
      -v /var/lib/qdrant-storage:/qdrant/storage \
      qdrant/qdrant:v1.11.0
  EOF

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-qdrant"
  })
}

resource "aws_ebs_volume" "qdrant_data" {
  count = var.qdrant_deployment == "ec2" ? 1 : 0

  availability_zone = aws_instance.qdrant[0].availability_zone
  size              = var.qdrant_volume_size_gb
  type              = "gp3"
  encrypted         = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-qdrant-data"
  })
}

resource "aws_volume_attachment" "qdrant_data" {
  count = var.qdrant_deployment == "ec2" ? 1 : 0

  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.qdrant_data[0].id
  instance_id = aws_instance.qdrant[0].id
}

# --------------------------------------------------------------------------------
# Storage
#
# S3 bucket for RAG source-document ingestion (what rag-mlops-pipeline chunks and
# embeds into Qdrant). No RDS: Qdrant is this stack's stateful backend, and the
# local-docker module has no relational database either — adding one here would be
# a shape mismatch, not "the same stack on AWS." Add RDS only if a future pipeline
# stage needs relational metadata beyond what Qdrant's point payloads can hold.
# --------------------------------------------------------------------------------

resource "aws_s3_bucket" "corpus" {
  count = var.create_corpus_bucket ? 1 : 0

  bucket_prefix = "${var.name_prefix}-corpus-"

  tags = var.tags
}

resource "aws_s3_bucket_versioning" "corpus" {
  count = var.create_corpus_bucket ? 1 : 0

  bucket = aws_s3_bucket.corpus[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "corpus" {
  count = var.create_corpus_bucket ? 1 : 0

  bucket = aws_s3_bucket.corpus[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "corpus" {
  count = var.create_corpus_bucket ? 1 : 0

  bucket = aws_s3_bucket.corpus[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

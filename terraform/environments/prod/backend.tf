# INTERVIEW NOTE: This file tells Terraform where to store its
# state file. By default, Terraform stores state locally on your
# machine (terraform.tfstate). That is fine for solo work but
# breaks in a team because everyone has a different local copy.

terraform {
  backend "s3" {
    # WHY S3: Remote state means every engineer and every CI/CD
    # pipeline run reads from and writes to the same single source
    # of truth. No more "works on my machine" state drift.
    bucket = "octa-byte-terraform-state"

    # KEY: acts like a file path inside the bucket.
    # Using "prod/terraform.tfstate" means we could store a
    # "staging/terraform.tfstate" in the same bucket for another env.
    key = "prod/terraform.tfstate"

    region = "us-east-1"

    # WHY use_lockfile instead of DynamoDB:
    # Before Terraform 1.10, the only way to prevent two concurrent
    # "terraform apply" runs from corrupting state was to create a
    # separate DynamoDB table just for locking.
    # From 1.10+, Terraform can lock using S3's own conditional write
    # feature (no DynamoDB table needed at all).
    # This project is pinned to >= 1.11.0 (see versions.tf), so
    # DynamoDB is unnecessary here — using it would be cargo-culting
    # an old pattern that the ecosystem has moved past.
    #
    # CROSS-QUESTION: "What happens without locking?"
    # Two concurrent applies both read state, plan against it, and
    # write back — the second write overwrites the first, silently
    # corrupting infrastructure state.
    use_lockfile = true
  }
}

# Bucket is passed at init time: terraform init -backend-config="bucket=<PROJECT_ID>-tfstate"
terraform {
  backend "gcs" {
    prefix = "infra"
  }
}

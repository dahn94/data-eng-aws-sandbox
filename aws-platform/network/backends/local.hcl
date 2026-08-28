# State dentro do S3 do LocalStack.
bucket = "sandbox-lake-configs"
key    = "terraform/dataeng-sandbox/network/local/terraform.tfstate"
region = "us-east-1"

access_key = "test"
secret_key = "test"

endpoints = {
  s3 = "http://localhost:4566"
}

use_path_style              = true
skip_credentials_validation = true
skip_metadata_api_check     = true
skip_region_validation      = true
skip_requesting_account_id  = true
use_lockfile                = true

module "vpc_public" {
  source               = "../../../modules/vpc"
  project_name         = "dataeng-sandbox"
  vpc_name             = "dataeng-sandbox-vpc-${var.environment}"
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
}

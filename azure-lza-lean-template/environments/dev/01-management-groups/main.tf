# environments/dev/01-management-groups/main.tf
module "management_groups" {
  source = "../../../modules/management-groups"

  org_prefix               = var.org_prefix
  org_name                 = var.org_name
  platform_subscription_id = var.platform_subscription_id
  nonprod_subscription_id  = var.nonprod_subscription_id
  prod_subscription_id     = var.prod_subscription_id
  tags = { ManagedBy = "Terraform", Layer = "01-management-groups" }
}

output "root_mg_id"    { value = module.management_groups.root_mg_id }
output "nonprod_mg_id" { value = module.management_groups.nonprod_mg_id }
output "prod_mg_id"    { value = module.management_groups.prod_mg_id }

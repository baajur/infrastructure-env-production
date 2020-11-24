#####################################################################
# settings for production
#####################################################################
locals {
  domain  = "serlo.org"
  project = "serlo-production"

  credentials_path = "secrets/serlo-production-terraform-af6ce169abd8.json"
  service_account  = "terraform@serlo-production.iam.gserviceaccount.com"

  region = "europe-west3"
  zone   = "europe-west3-a"

  cluster_machine_type = "n1-highcpu-4"

  athene2_database_instance_name = "${local.project}-mysql-2020-01-26"
  kpi_database_instance_name     = "${local.project}-postgres-2020-01-26"
}

#####################################################################
# modules
#####################################################################
module "cluster" {
  source   = "github.com/serlo/infrastructure-modules-gcloud.git//cluster?ref=8e08ef09c2dca491cad4afa0406520ac210641c6"
  name     = "${local.project}-cluster"
  location = local.zone
  region   = local.region

  node_pool = {
    machine_type       = local.cluster_machine_type
    preemptible        = false
    initial_node_count = 2
    min_node_count     = 2
    max_node_count     = 10
  }
}

module "gcloud_mysql" {
  source                     = "github.com/serlo/infrastructure-modules-gcloud.git//gcloud_mysql?ref=8e08ef09c2dca491cad4afa0406520ac210641c6"
  database_instance_name     = local.athene2_database_instance_name
  database_connection_name   = "${local.project}:${local.region}:${local.athene2_database_instance_name}"
  database_region            = local.region
  database_name              = "serlo"
  database_tier              = "db-n1-standard-4"
  database_private_network   = module.cluster.network
  database_password_default  = var.athene2_database_password_default
  database_password_readonly = var.athene2_database_password_readonly
}

module "gcloud_postgres" {
  source                   = "github.com/serlo/infrastructure-modules-gcloud.git//gcloud_postgres?ref=8e08ef09c2dca491cad4afa0406520ac210641c6"
  database_instance_name   = local.kpi_database_instance_name
  database_connection_name = "${local.project}:${local.region}:${local.kpi_database_instance_name}"
  database_region          = local.region
  database_names           = ["kpi", "hydra"]
  database_private_network = module.cluster.network

  database_password_postgres = var.kpi_kpi_database_password_postgres
  database_username_default  = module.kpi.kpi_database_username_default
  database_password_default  = var.kpi_kpi_database_password_default
  database_username_readonly = module.kpi.kpi_database_username_readonly
  database_password_readonly = var.kpi_kpi_database_password_readonly
}

module "athene2-dbdump" {
  source    = "github.com/serlo/infrastructure-modules-serlo.org.git//dbdump?ref=777314d6f13f4877b056421c71069838bafff679"
  image     = "eu.gcr.io/serlo-shared/athene2-dbdump-cronjob:2.0.0"
  namespace = kubernetes_namespace.serlo_org_namespace.metadata.0.name
  schedule  = "0 0 * * *"
  database = {
    host     = module.gcloud_mysql.database_private_ip_address
    port     = "3306"
    username = "serlo_readonly"
    password = var.athene2_database_password_readonly
    name     = "serlo"
  }

  bucket = {
    url                 = "gs://anonymous-data"
    service_account_key = module.gcloud_dbdump_writer.account_key
  }
}

module "gcloud_dbdump_writer" {
  source = "github.com/serlo/infrastructure-modules-gcloud.git//gcloud_dbdump_writer?ref=8e08ef09c2dca491cad4afa0406520ac210641c6"
}

module "ingress-nginx" {
  source      = "github.com/serlo/infrastructure-modules-shared.git//ingress-nginx?ref=146b864cb2d5d91373bbf493e7954051faaab15d"
  namespace   = kubernetes_namespace.ingress_nginx_namespace.metadata.0.name
  ip          = module.cluster.address
  domain      = "*.${local.domain}"
  nginx_image = "quay.io/kubernetes-ingress-controller/nginx-ingress-controller:0.24.1"
}

module "cloudflare" {
  source  = "github.com/serlo/infrastructure-modules-env-shared.git//cloudflare?ref=0274b754c05cc028e83d3ad8aa39638b0e2044d7"
  domain  = local.domain
  ip      = module.cluster.address
  zone_id = "1a4afa776acb2e40c3c8a135248328ae"
}

#####################################################################
# namespaces
#####################################################################
resource "kubernetes_namespace" "ingress_nginx_namespace" {
  metadata {
    name = "ingress-nginx"
  }
}

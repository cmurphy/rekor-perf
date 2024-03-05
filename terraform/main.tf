provider "google" {
    project = var.project
    zone = var.zone
    region = var.region
}

module "network" {
    source = "git::https://github.com/sigstore/scaffolding.git//terraform/gcp/modules/network?ref=36131f6dd57a0b1d9eaad0f7dd17b11c3ab0eeee"

    region = var.region
    project_id = var.project
    cluster_name = "rekor"
}

module "bastion" {
    source = "git::https://github.com/sigstore/scaffolding.git//terraform/gcp/modules/bastion?ref=36131f6dd57a0b1d9eaad0f7dd17b11c3ab0eeee"

    project_id = var.project
    region = var.region
    zone = var.zone
    network = module.network.network_name
    subnetwork = module.network.subnetwork_self_link
    tunnel_accessor_sa = "serviceAccount:ga-206@colleenmurphy-testing-410318.iam.gserviceaccount.com"

    depends_on = [
        module.network,
    ]
}

module "mysql" {
    source = "git::https://github.com/sigstore/scaffolding.git//terraform/gcp/modules/mysql?ref=36131f6dd57a0b1d9eaad0f7dd17b11c3ab0eeee"

    project_id = var.project
    region = var.region
    cluster_name = "rekor"
    database_version = "MYSQL_8_0"
    availability_type = "ZONAL"
    network = module.network.network_self_link
    instance_name = "rekor-perf-tf"
    require_ssl = false

    depends_on = [
        module.network
    ]
}

module "gke_cluster" {
    source = "git::https://github.com/sigstore/scaffolding.git//terraform/gcp/modules/gke_cluster?ref=36131f6dd57a0b1d9eaad0f7dd17b11c3ab0eeee"

    region = var.region
    project_id = var.project
    cluster_name = "rekor"
    network = module.network.network_self_link
    subnetwork = module.network.subnetwork_self_link
    cluster_secondary_range_name = module.network.secondary_ip_range.0.range_name
    services_secondary_range_name = module.network.secondary_ip_range.1.range_name
    cluster_network_tag = "cmurphy-rekor-network"
    #initial_node_count = 1
    #autoscaling_min_node = 1
    #autoscaling_max_node = 1
    bastion_ip_address = module.bastion.ip_address
    security_group = "gke-security-groups@${var.project}.iam.gserviceaccount.com"

    depends_on = [
        module.network,
        module.bastion,
    ]
}

module "rekor" {
    source = "git::https://github.com/sigstore/scaffolding.git//terraform/gcp/modules/rekor?ref=36131f6dd57a0b1d9eaad0f7dd17b11c3ab0eeee"

    region = var.region
    project_id = var.project
    cluster_name = "rekor"

    attestation_bucket = "cmurphy-sigstore-attestations"
    attestation_region = var.region

    redis_cluster_memory_size_gb = "16"

    network = module.network.network_self_link
    dns_zone_name = "cmurphysandbox-xyz"
    dns_domain_name = "cmurphysandbox.xyz."

    depends_on = [
        module.network,
        module.gke_cluster
    ]
}

module "oslogin" {
    source = "git::https://github.com/sigstore/scaffolding.git//terraform/gcp/modules/oslogin?ref=36131f6dd57a0b1d9eaad0f7dd17b11c3ab0eeee"

    project_id = var.project
    count = 1
    oslogin = {
        enabled = true
        enabled_with_2fa = false
    }
    instance_os_login_members = {
        bastion = {
            instance_name = module.bastion.name
            zone = module.bastion.zone
            members = [
                "serviceAccount:ga-206@colleenmurphy-testing-410318.iam.gserviceaccount.com",
                "user:colleenmurphy@google.com"
            ]
        }
    }

    depends_on = [
        module.bastion,
    ]
}

output "mysql_pass" {
    value = module.mysql.mysql_pass
    sensitive = true
}

### Initilizing Project ###

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}

provider "google" {
    project = "devops-343007"
}


#####################################
########### Creating VPCs ###########
#####################################

# Defining Image that will be used
data "google_compute_image" "debian_image" {
  family  = "debian-9"
  project = "debian-cloud"
}

#######################
#### Managment VPC ####
#######################

# VPC 
resource "google_compute_network" "mngt-vpc" {
    name = "mngt-vpc"
    auto_create_subnetworks = false
}

# Subnet 
resource "google_compute_subnetwork" "mngt-subnet" {
name = "mngt-subnet"
ip_cidr_range = "172.16.0.0/24"
region = "europe-west3"
network = google_compute_network.mngt-vpc.id
}

# VMs
resource "google_compute_instance" "mngt-vm" {
  name         = "mngt-vm"
  machine_type = "e2-medium"
  zone         = "europe-west3-a"
  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian_image.self_link
    }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.mngt-subnet.id
  }
}

#########################
#### Development VPC ####
#########################

# VPC
resource "google_compute_network" "dev-vpc" {
    name = "dev-vpc-omar-dont-delete"
    auto_create_subnetworks = false
}

# Subnets
resource "google_compute_subnetwork" "dev-subnet-1" {
name = "dev-subnet-1-omar"
ip_cidr_range = "10.0.1.0/24"
region = "europe-west2"
network = google_compute_network.dev-vpc.id
}

resource "google_compute_subnetwork" "dev-subnet-2" {
name = "dev-subnet-2-omar"
ip_cidr_range = "10.0.2.0/24"
region = "europe-west2"
network = google_compute_network.dev-vpc.id
}


# VMs

#WebServer 1 
resource "google_compute_instance" "dev-webserver-1" {
  name         = "dev-webserver-1-omar"
  machine_type = "e2-medium"
  zone         = "europe-west2-b"
  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian_image.self_link
    }
  }

 network_interface {
    subnetwork = google_compute_subnetwork.dev-subnet-1.id
      access_config {
      // Ephemeral public IP
    }
  }
  metadata_startup_script = "sudo apt install apache2 -y"

}

#WebServer 2 
resource "google_compute_instance" "dev-webserver-2" {
  name         = "dev-webserver-2-omar"
  machine_type = "e2-medium"
  zone         = "europe-west2-b"
  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian_image.self_link
    }
  }

 network_interface {
    subnetwork = google_compute_subnetwork.dev-subnet-2.id
      access_config {
      // Ephemeral public IP
    }
  }

  metadata_startup_script = "sudo apt install apache2 -y"
}

#SqlServer 1 
resource "google_compute_instance" "dev-sqlserver-1" {
  name         = "dev-sqlserver-1-omar"
  machine_type = "e2-medium"
  zone         = "europe-west2-b"
  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian_image.self_link
    }
  }

 network_interface {
    subnetwork = google_compute_subnetwork.dev-subnet-1.id
      access_config {
      // Ephemeral public IP
    }
  }
}

#SqlServer 2 
resource "google_compute_instance" "dev-sqlserver-2" {
  name         = "dev-sqlserver-2-omar"
  machine_type = "e2-medium"
  zone         = "europe-west2-b"
  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian_image.self_link
    }
  }
 network_interface {
    subnetwork = google_compute_subnetwork.dev-subnet-2.id
      access_config {
      // Ephemeral public IP
    }
  }

}

# Load Balencer 

# Instance Gruop 
resource "google_compute_instance_group" "instance-group-dev-omar" {
  name      = "instance-group-dev-omar"
  zone        = "europe-west2-b"
  instances = [google_compute_instance.dev-webserver-1.id,
                google_compute_instance.dev-webserver-2.id]

  named_port {
    name = "http"
    port = "80"
  }
}

# Health Check
resource "google_compute_health_check" "my-health-check" {
  name = "tcp-health-check-omar"
  timeout_sec        = 1
  check_interval_sec = 1

  tcp_health_check {
    port = "80"
  }
}

# Backend
resource "google_compute_backend_service" "backend-dev-omar" {
  name      = "backend-dev-omar"
  port_name = "http"
  protocol  = "HTTP"
  load_balancing_scheme  = "EXTERNAL"
  timeout_sec   = 10

  backend {
    group = google_compute_instance_group.instance-group-dev-omar.id
    max_utilization = 1.0
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 0.8
  }
  health_checks = [
    google_compute_health_check.my-health-check.id,
  ]
}


# reserved IP address
resource "google_compute_global_address" "default-ip-dev" {
  name = "lb-static-ip"
}

# url map
resource "google_compute_url_map" "default-url-dev" {
  name            = "lb-test-url-map"
  default_service = google_compute_backend_service.backend-dev-omar.id
}

# http proxy
resource "google_compute_target_http_proxy" "lb-dev-http-proxy" {
  name     = "lb-dev-http-proxy"
  url_map  = google_compute_url_map.default-url-dev.id
}

# Forwarding rule / Frontend
resource "google_compute_global_forwarding_rule" "lb-dev-forwarding-rule" {
  name                  = "lb-dev-forwarding-rule"
  ip_protocol           = "HTTP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "80"
  target                = google_compute_target_http_proxy.lb-dev-http-proxy.id
  ip_address            = google_compute_global_address.default-ip-dev.id
}

# Firewall Allow only port 80 from mangment vpc (172.16.0.0/24)
resource "google_compute_firewall" "allow-http-80-ingress-dev" {
  name    = "allow-http-80-ingress-dev"
  network = google_compute_network.dev-vpc.name
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
  source_ranges = ["172.16.0.0/24"]
}


########################
#### Production VPC ####
########################

# VPC
resource "google_compute_network" "prod-vpc" {
    name = "prod-vpc"
    auto_create_subnetworks = false
}

# Subnets
resource "google_compute_subnetwork" "prod-subnet-1" {
name = "prod-subnet-1"
ip_cidr_range = "192.168.1.0/24"
region = "us-west2"
network = google_compute_network.prod-vpc.id
}

resource "google_compute_subnetwork" "prod-subnet-2" {
name = "prod-subnet-2"
ip_cidr_range = "192.168.2.0/24"
region = "us-west2"
network = google_compute_network.prod-vpc.id
}


# VMs

#WebServer 1 
resource "google_compute_instance" "prod-webserver-1" {
  name         = "prod-webserver-1-omar"
  machine_type = "e2-medium"
  zone         = "us-west2-c"
  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian_image.self_link
    }
  }

 network_interface {
    subnetwork = google_compute_subnetwork.prod-subnet-1.id
      access_config {
      // Ephemeral public IP
    }
  }
  metadata_startup_script = "sudo apt install apache2 -y"

}

#WebServer 2 
resource "google_compute_instance" "prod-webserver-2" {
  name         = "prod-webserver-2-omar"
  machine_type = "e2-medium"
  zone         = "us-west2-c"
  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian_image.self_link
    }
  }

 network_interface {
    subnetwork = google_compute_subnetwork.prod-subnet-2.id
      access_config {
      // Ephemeral public IP
    }
  }

  metadata_startup_script = "sudo apt install apache2 -y"
}

#SqlServer 1 
resource "google_compute_instance" "prod-sqlserver-1" {
  name         = "prod-sqlserver-1-omar"
  machine_type = "e2-medium"
  zone         = "us-west2-c"
  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian_image.self_link
    }
  }

 network_interface {
    subnetwork = google_compute_subnetwork.prod-subnet-1.id
      access_config {
      // Ephemeral public IP
    }
  }
}

#SqlServer 2 
resource "google_compute_instance" "prod-sqlserver-2" {
  name         = "prod-sqlserver-2-omar"
  machine_type = "e2-medium"
  zone         = "us-west2-c"
  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian_image.self_link
    }
  }
 network_interface {
    subnetwork = google_compute_subnetwork.prod-subnet-2.id
      access_config {
      // Ephemeral public IP
    }
  }

}

# Load Balencer 

# Instance Gruop 
resource "google_compute_instance_group" "instance-group-prod-omar" {
  name      = "instance-group-prod-omar"
  zone        = "us-west2-c"
  instances = [google_compute_instance.prod-webserver-1.id,
                google_compute_instance.prod-webserver-2.id]

  named_port {
    name = "http"
    port = "80"
  }
}

# Health Check
resource "google_compute_health_check" "my-health-check-prod" {
  name = "tcp-health-check"
  timeout_sec        = 1
  check_interval_sec = 1

  tcp_health_check {
    port = "80"
  }
}

# Backend
resource "google_compute_backend_service" "backend-prod-omar" {
  name      = "backend-prod-omar"
  port_name = "http"
  protocol  = "HTTP"
  load_balancing_scheme  = "EXTERNAL"
  timeout_sec   = 10

  backend {
    group = google_compute_instance_group.instance-group-prod-omar.id
    max_utilization = 1.0
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 0.8
  }
  health_checks = [
    google_compute_health_check.my-health-check-prod.id,
  ]
}


# reserved IP address
resource "google_compute_global_address" "default-ip-prod" {
  name = "lb-static-ip"
}

# url map
resource "google_compute_url_map" "default-url-prod" {
  name            = "lb-test-url-map"
  default_service = google_compute_backend_service.backend-dev-omar.id
}

# http proxy
resource "google_compute_target_http_proxy" "lb-prod-http-proxy" {
  name     = "lb-prod-http-proxy"
  url_map  = google_compute_url_map.default-url-prod.id
}

# Forwarding rule / Frontend
resource "google_compute_global_forwarding_rule" "lb-prod-forwarding-rule" {
  name                  = "lb-prod-forwarding-rule"
  ip_protocol           = "HTTP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "80"
  target                = google_compute_target_http_proxy.lb-prod-http-proxy.id
  ip_address            = google_compute_global_address.default-ip-prod.id
}

# Firewall Allow all (0.0.0.0/24) at port 80 
resource "google_compute_firewall" "allow-http-80-ingress-prod" {
  name    = "allow-http-80-ingress-prod"
  network = google_compute_network.prod-vpc.name
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
  source_ranges = ["0.0.0.0/0"]
}

###############
### Peering ###
###############

# Peering Managment & Development 
resource "google_compute_network_peering" "peer-mngt-dev-vpc" {
  name         = "peer-mngt-dev-vpc"
  network      = google_compute_network.mngt-vpc.self_link
  peer_network = google_compute_network.dev-vpc.self_link
}

resource "google_compute_network_peering" "peer-dev-mngt-vpc" {
  name         = "peer-dev-mngt-vpc"
  network      = google_compute_network.dev-vpc.self_link
  peer_network = google_compute_network.mngt-vpc.self_link
}

# Peering Managment & Production 
resource "google_compute_network_peering" "peer-mngt-prod-vpc" {
  name         = "peer-mngt-prod-vpc"
  network      = google_compute_network.mngt-vpc.self_link
  peer_network = google_compute_network.prod-vpc.self_link
}

resource "google_compute_network_peering" "peer-prod-mngt-vpc" {
  name         = "peer-prod-mngt-vpc"
  network      = google_compute_network.prod-vpc.self_link
  peer_network = google_compute_network.mngt-vpc.self_link
}
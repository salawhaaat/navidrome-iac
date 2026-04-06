data "openstack_networking_network_v2" "public_net" {
  name = "sharednet1"
}

data "openstack_networking_subnet_v2" "public_net_subnet" {
  name = "sharednet1-subnet"
}





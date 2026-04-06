output "floating_ip_out" {
  description = "Floating IP assigned to node1"
  value       = openstack_networking_floatingip_v2.floating_ip.address
}

output "node1_internal_ip_out" {
  description = "Node1 internal IP on sharednet1 (used as externalIP for K8s services)"
  value       = openstack_networking_port_v2.public_net_ports["node1"].all_fixed_ips[0]
}



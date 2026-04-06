variable "suffix" {
  description = "Suffix for resource names (use net ID + proj05)"
  type        = string
  default     = "proj05"
  nullable    = false
}

variable "key" {
  description = "Name of key pair"
  type        = string
  default     = "id_rsa_chameleon"
}

variable "reservation_id" {
  description = "Blazar reservation ID from KVM@TACC lease — used as flavor_id for flavor:instance reservations"
  type        = string
}


variable "nodes" {
  type = map(string)
  default = {
    "node1" = "192.168.1.11"
  }
}

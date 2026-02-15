variable "cluster_name" {
  description = "The name of the Kubernetes cluster to create."
  type        = string
}

variable "domain" {
  description = "The domain name for external-dns public DNS records in the cluster."
  type        = string
}

variable "auto_sync" {
  description = "Whether to automatically sync the cluster with the bootstrap repository on every apply."
  type        = bool
  default     = false
}

variable "linode_token" {
  description = "The Linode API token to use for provisioning the cluster."
  type        = string
}

variable "ssh_key_file" {
  description = "The path to the SSH private key file to use for ArgoCD to access GitHub repositories."
  type        = string
}

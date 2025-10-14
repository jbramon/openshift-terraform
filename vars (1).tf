variable "region" {
  default = "us-west-1"
}

variable "zone1" {
  default = "us-west-1b"
}

variable "webuser" {
  default = "ec2-user"
}

variable "amiID" {
  type = map(any)
  default = {
    us-west-1 = "ami-0d9e15a8edf01ec21" // Amazon Linux 2023 kernel-6.1 AMI
  }
}

variable "openshift_url" {
  description = "OpenShift API server URL"
  type        = string
}

variable "openshift_token" {
  description = "OpenShift login token"
  type        = string
}

variable "ec2_private_key" {
  description = "Private key for EC2 SSH access"
  type        = string
  sensitive   = true
}

variable "gh_pat" {
  description = "GitHub Personal Access Token"
  type        = string
  sensitive   = true
}





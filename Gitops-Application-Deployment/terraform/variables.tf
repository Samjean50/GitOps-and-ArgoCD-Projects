variable "region" {
  default = "us-east-1"
}

variable "cluster_name" {
  default = "gitops-eks-cluster"
}

variable "cluster_version" {
  default = "1.29"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}
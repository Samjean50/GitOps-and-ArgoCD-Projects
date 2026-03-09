output "primary_cluster_name" {
  value = module.eks_primary.cluster_name
}

output "secondary_cluster_name" {
  value = module.eks_secondary.cluster_name
}
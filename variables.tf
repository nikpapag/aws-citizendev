variable "aws_account_id" {
    description = "AWS account the cluster is deployed in"
}

variable "region" {
    description = "AWS region"
}

variable "vpc_cidr" {
    default = "10.0.0.0/16"
    description = "VPC CIDR block"
}

variable "environment" {
    default = "dev" 
    description = "env"
}

variable "cost_center" {
    default = "INF"
    description = "Cost Center for domain"
}

variable "public_eks_subnet_1_cidr" {
    default = "10.0.1.0/24"
    description = "CIDR Block for Public Subnet 1"
}

variable "public_eks_subnet_2_cidr" {
    default = "10.0.2.0/24"
    description = "CIDR Block for Public Subnet 2"
}

variable "public_eks_subnet_3_cidr" {
    default = "10.0.5.0/24"
    description = "CIDR Block for Public Subnet 3"
}

variable "private_eks_subnet_1_cidr" {
    default  = "10.0.3.0/24"
    description = "CIDR Block for Private Subnet 1"
}

variable "private_eks_subnet_2_cidr" {
    default = "10.0.4.0/24"
    description = "CIDR Block for Private Subnet 2"
}

variable "private_eks_subnet_3_cidr" {
    default = "10.0.6.0/24"
    description = "CIDR Block for Private Subnet 3"
}

variable "tag_owner" {
    description = "resource owner"
}

variable "eks_cluster_name" {
    default = "harness-workshop-cluster"
}


variable "internet_cidr_blocks" {
    default = "0.0.0.0/0"
}


variable "accountid" {
    type = string
    description = "harness account id"
}

variable "apikey" {
    type = string
    descriptionn = "harness api key"

}

variable "domain_name" {
    default = "citizendev.co.uk"
    description = "Domain hosted in Route 53 for the cluster"
}

variable "squarespace_site_ips" {
    type = list(string)
    default = []
    description = "Apex A records for the existing Squarespace website, kept when DNS moves to Route 53"
}

variable "allowed_ingress_cidrs" {
    type = list(string)
    default = []
    description = "Client IPs allowed to reach the NGINX ingress load balancer"
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    harness = {
      source = "harness/harness"
    }
    helm = {
      source = "hashicorp/helm"
      version = "2.9.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.10"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "${var.region}"
}

# Configure the Harness Provider
provider "harness" {
  endpoint         = "https://app.harness.io/gateway"
  account_id       = var.accountid
  platform_api_key = var.apikey

}


# ------------------------------------------------------------------------------
#  IAM Role
# ------------------------------------------------------------------------------
resource "aws_iam_role" "eks_nodes_role" {
  name = "${var.eks_cluster_name}-eks-nodes-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.eks_cluster_name}-eks-nodes-role"
    Environment = var.environment
    Owner       = var.tag_owner
    Project     = "EKS Deployment"
    Terraform   = "true"
  }
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes_role.name
}

resource "aws_iam_role_policy_attachment" "ecr_read_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes_role.name
}

resource "aws_iam_policy" "aws_load_balancer_controller_policy" {
  name        = "AWSLoadBalancerControllerIAMPolicy-${var.eks_cluster_name}"
  description = "IAM policy for AWS Load Balancer Controller"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "ec2:DescribeInstances",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = [
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:ModifyListener"
        ]
        Resource = "*"
      }
    ]
  })
}

#Attach custom policy
resource "aws_iam_role_policy_attachment" "eks_worker_alb_policy" {
  policy_arn = aws_iam_policy.aws_load_balancer_controller_policy.arn
  role       = aws_iam_role.eks_nodes_role.name
}


# ------------------------------------------------------------------------------
# VPC
# ------------------------------------------------------------------------------

resource "aws_vpc" "harness_workshop_prod" {
    cidr_block           = "${var.vpc_cidr}"
    enable_dns_hostnames = true

    tags = {
        name  = "harness_workshop_prod_vpc"
        owner = "${var.tag_owner}"
        Name        = var.eks_cluster_name
        Environment = "dev"
        cost_center = "INF"
        Owner       = var.tag_owner
        Project     = "EKS Deployment"
        Terraform   = "true"
    }
}


resource "aws_subnet" "public_eks_subnet_1" {
  cidr_block        = "${var.public_eks_subnet_1_cidr}"
  vpc_id            = aws_vpc.harness_workshop_prod.id
  availability_zone = "${var.region}a"

  tags = {
    name  = "public_eks_subnet_1"
    owner = "${var.tag_owner}"
    "kubernetes.io/role/elb" = "1"
  }
}


resource "aws_subnet" "public_eks_subnet_2" {
  cidr_block        = "${var.public_eks_subnet_2_cidr}"
  vpc_id            = aws_vpc.harness_workshop_prod.id
  availability_zone = "${var.region}b"

  tags = {
    name  = "public_eks_subnet_2"
    owner = "${var.tag_owner}"
    "kubernetes.io/role/elb" = "1"
  }
}


resource "aws_subnet" "public_eks_subnet_3" {
  cidr_block        = "${var.public_eks_subnet_3_cidr}"
  vpc_id            = aws_vpc.harness_workshop_prod.id
  availability_zone = "${var.region}c"

  tags = {
    name  = "public_eks_subnet_3"
    owner = "${var.tag_owner}"
    "kubernetes.io/role/elb" = "1"
  }
}


resource "aws_subnet" "private_eks_subnet_1" {
    cidr_block        = "${var.private_eks_subnet_1_cidr}"
    vpc_id            = aws_vpc.harness_workshop_prod.id
    availability_zone = "${var.region}a"

    tags = {
        name  = "Private Subnet _1"
        owner = "${var.tag_owner}"
        "kubernetes.io/role/internal-elb" = "1"
    }
}

resource "aws_subnet" "private_eks_subnet_2" {
    cidr_block        = "${var.private_eks_subnet_2_cidr}"
    vpc_id            = aws_vpc.harness_workshop_prod.id
    availability_zone = "${var.region}b"

    tags = {
        name  = "Private Subnet _2"
        owner = "${var.tag_owner}"
        "kubernetes.io/role/internal-elb" = "1"
    }
}



resource "aws_subnet" "private_eks_subnet_3" {
    cidr_block        = "${var.private_eks_subnet_3_cidr}"
    vpc_id            = aws_vpc.harness_workshop_prod.id
    availability_zone = "${var.region}c"

    tags = {
        name  = "Private Subnet _3"
        owner = "${var.tag_owner}"
        "kubernetes.io/role/internal-elb" = "1"
    }
}


resource "aws_route_table" "public_eks_route_table" {
    vpc_id  = aws_vpc.harness_workshop_prod.id

    tags = {
        name  = "harness_workshop_prod_public_route"
        owner = "${var.tag_owner}"
    }
}


resource "aws_route_table" "private_eks_route_table" {
    vpc_id  = aws_vpc.harness_workshop_prod.id

    tags = {
        name  = "harness_workshop_prod_private_route"
        owner = "${var.tag_owner}"
    }
}


resource "aws_route_table_association" "public_eks_route_table_1_association"{
    route_table_id = "${aws_route_table.public_eks_route_table.id}"
    subnet_id      = "${aws_subnet.public_eks_subnet_1.id}"
}
resource "aws_route_table_association" "public_eks_route_table_2_association"{
    route_table_id = "${aws_route_table.public_eks_route_table.id}"
    subnet_id      = "${aws_subnet.public_eks_subnet_2.id}"
}
resource "aws_route_table_association" "public_eks_route_table_3_association"{
    route_table_id = "${aws_route_table.public_eks_route_table.id}"
    subnet_id      = "${aws_subnet.public_eks_subnet_3.id}"
}



resource "aws_route_table_association" "private_eks_route_table_1_association"{
    route_table_id = "${aws_route_table.private_eks_route_table.id}"
    subnet_id      = "${aws_subnet.private_eks_subnet_1.id}"
}


resource "aws_route_table_association" "private_eks_route_table_2_association"{
    route_table_id = "${aws_route_table.private_eks_route_table.id}"
    subnet_id      =  "${aws_subnet.private_eks_subnet_2.id}"
}

resource "aws_route_table_association" "private_eks_route_table_3_association"{
    route_table_id = "${aws_route_table.private_eks_route_table.id}"
    subnet_id      = "${aws_subnet.private_eks_subnet_3.id}"
}


resource "aws_eip" "elastic_eks_ip_for_nat_gw" {
    associate_with_private_ip = "10.0.0.5"

    tags = {
        name  = "demo-production"
        owner = "${var.tag_owner}"
    }
}


resource "aws_nat_gateway" "nat_gw_eks" {
    allocation_id = "${aws_eip.elastic_eks_ip_for_nat_gw.id}"
    subnet_id     = "${aws_subnet.public_eks_subnet_1.id}"
    tags = {
            name  = "harness demo nat gw"
            owner = "${var.tag_owner}"
    }
    depends_on = [ aws_eip.elastic_eks_ip_for_nat_gw ]
}

#Allow outbound traffic from private resources
resource "aws_route" "nat_gw_eks_route" {
    route_table_id          = "${aws_route_table.private_eks_route_table.id}"
    nat_gateway_id          = "${aws_nat_gateway.nat_gw_eks.id}"
    destination_cidr_block  = "0.0.0.0/0"
}


resource "aws_internet_gateway" "production_eks_igw" {
    vpc_id = "${aws_vpc.harness_workshop_prod.id}"

    tags = {
        name  = "production internet gateway"
        owner = "${var.tag_owner}"
    }
}


resource "aws_route" "public_internet_eks_gw_route" {
    route_table_id         = "${aws_route_table.public_eks_route_table.id}"
    gateway_id             = "${aws_internet_gateway.production_eks_igw.id}"
    destination_cidr_block = "0.0.0.0/0"
}


output "vpc_id" {
    value = "${aws_vpc.harness_workshop_prod.id}"
}


output "vpc_cidr_block" {
    value = "${aws_vpc.harness_workshop_prod.cidr_block}"
}

output "public_eks_subnet_1" {
    value = "${aws_subnet.public_eks_subnet_1.id}"
}

output "public_eks_subnet_2" {
    value = "${aws_subnet.public_eks_subnet_2.id}"
}
output "public_eks_subnet_3" {
    value = "${aws_subnet.public_eks_subnet_3.id}"
}

output "private_eks_subnet_1" {
    value = "${aws_subnet.private_eks_subnet_1.id}"
}

output "private_eks_subnet_2" {
    value = "${aws_subnet.private_eks_subnet_2.id}"
}

output "private_eks_subnet_3" {
    value = "${aws_subnet.private_eks_subnet_3.id}"
}

resource "aws_security_group" "eks_alb_security_group" {
    name = "${var.eks_cluster_name}_alb_sg"
    description = "security group for eks cluster"
    vpc_id = "${aws_vpc.harness_workshop_prod.id}"

    ingress {
        from_port   = 80
        protocol    = "TCP"
        to_port     = 80
        cidr_blocks = ["${var.internet_cidr_blocks}"]
    }


    ingress {
        from_port   = 8080
        protocol    = "TCP"
        to_port     = 8080
        cidr_blocks = ["${var.internet_cidr_blocks}"]
    }

    ingress {
        from_port   = 8085
        protocol    = "TCP"
        to_port     = 8090
        cidr_blocks = ["${var.internet_cidr_blocks}"]
    }

    ingress {
        from_port   = 8090
        protocol    = "TCP"
        to_port     = 8090
        cidr_blocks = ["${var.internet_cidr_blocks}"]
    }

    egress {
        from_port   = 0
        protocol    = "-1"
        to_port     = 0
        cidr_blocks = ["${var.internet_cidr_blocks}"]
    }

    depends_on = [ aws_vpc.harness_workshop_prod ]
}

output "eks_security_group" {
    value = "${aws_security_group.eks_alb_security_group.id}"
}



# Security group for EKS nodes
resource "aws_security_group" "eks_nodes" {
  vpc_id = aws_vpc.harness_workshop_prod.id

  # Allow outbound internet traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# ------------------------------------------------------------------------------
#  EKS Cluster with Private Nodes
# ------------------------------------------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.0.0"

  cluster_name    = "${var.eks_cluster_name}"
  cluster_version = "1.35"

  vpc_id                         = aws_vpc.harness_workshop_prod.id
  subnet_ids                     = [aws_subnet.private_eks_subnet_1.id, aws_subnet.private_eks_subnet_2.id, aws_subnet.private_eks_subnet_3.id]
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true
  iam_role_arn  = "arn:aws:iam::${var.aws_account_id}:role/AWSServiceRoleForAmazonEKSNodegroup"

  # Default node rules only allow ports 1025-65535 between nodes, which blocks pod-to-pod traffic on e.g. port 80
  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all traffic"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
  }

  eks_managed_node_groups = {
    private_nodes = {
      min_size     = 1
      max_size     = 6
      # Only used at creation; the module ignores later changes, so scale with
      # aws eks update-nodegroup-config --scaling-config desiredSize=N
      desired_size = 6

      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.medium"]
      subnet_ids     = [aws_subnet.private_eks_subnet_1.id, aws_subnet.private_eks_subnet_2.id, aws_subnet.private_eks_subnet_3.id]
      iam_role_arn = "arn:aws:iam::${var.aws_account_id}:role/AWSServiceRoleForAmazonEKSNodegroup"
      security_group_ids = [aws_security_group.eks_nodes.id]
    }
  }
  tags = {
    Name        = var.eks_cluster_name
    Environment = var.environment
    cost_center = var.cost_center
    Owner       = var.tag_owner
    Project     = "EKS Deployment"
    Terraform   = "true"
  }
}



# ------------------------------------------------------------------------------
#  Outputs
# ------------------------------------------------------------------------------
output "eks_cluster_id" {
  value = module.eks.cluster_id
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}



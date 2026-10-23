# ------------------------------------------------------------------------------
#  Kubernetes / Helm providers (authenticate against the EKS cluster)
# ------------------------------------------------------------------------------
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
    }
  }
}


# ------------------------------------------------------------------------------
#  Route 53 hosted zone
# ------------------------------------------------------------------------------
resource "aws_route53_zone" "main" {
  name = var.domain_name

  tags = {
    Owner     = var.tag_owner
    Terraform = "true"
  }
}

# Keep the existing Squarespace website working once the name servers move to Route 53
resource "aws_route53_record" "apex_squarespace" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"
  ttl     = 300
  records = var.squarespace_site_ips
}

# Cache "not found" answers for 60s instead of 15 minutes, so a hostname opened
# before ExternalDNS creates its record recovers quickly
resource "aws_route53_record" "soa" {
  zone_id         = aws_route53_zone.main.zone_id
  name            = var.domain_name
  type            = "SOA"
  ttl             = 60
  records         = ["${aws_route53_zone.main.primary_name_server}. awsdns-hostmaster.amazon.com. 1 7200 900 1209600 60"]
  allow_overwrite = true
}

output "route53_name_servers" {
  description = "Set these as custom name servers for the domain in Squarespace"
  value       = aws_route53_zone.main.name_servers
}


# ------------------------------------------------------------------------------
#  ACM wildcard certificate (TLS terminated at the NLB)
# ------------------------------------------------------------------------------
resource "aws_acm_certificate" "wildcard" {
  domain_name               = "*.${var.domain_name}"
  subject_alternative_names = [var.domain_name]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.wildcard.domain_validation_options : dvo.domain_name => dvo
  }

  zone_id         = aws_route53_zone.main.zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  ttl             = 60
  records         = [each.value.resource_record_value]
  allow_overwrite = true
}

# Blocks until the Squarespace name servers point at Route 53
resource "aws_acm_certificate_validation" "wildcard" {
  certificate_arn         = aws_acm_certificate.wildcard.arn
  validation_record_fqdns = [for r in aws_route53_record.acm_validation : r.fqdn]
}


# ------------------------------------------------------------------------------
#  ExternalDNS (creates Route 53 records from Ingress hosts)
# ------------------------------------------------------------------------------
locals {
  # module.eks.oidc_provider is always null in module v19.0.0, so derive it from the issuer URL
  oidc_provider = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
}

resource "aws_iam_role" "external_dns" {
  name = "${var.eks_cluster_name}-external-dns"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Federated = module.eks.oidc_provider_arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_provider}:sub" = "system:serviceaccount:kube-system:external-dns"
            "${local.oidc_provider}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "external_dns" {
  name = "external-dns-route53"
  role = aws_iam_role.external_dns.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["route53:ChangeResourceRecordSets"]
        Resource = [aws_route53_zone.main.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets",
          "route53:ListTagsForResources"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = "1.23.0"
  namespace  = "kube-system"

  values = [yamlencode({
    provider      = { name = "aws" }
    sources       = ["ingress"]
    domainFilters = [var.domain_name]
    policy        = "upsert-only"
    txtOwnerId    = var.eks_cluster_name
    serviceAccount = {
      name        = "external-dns"
      annotations = { "eks.amazonaws.com/role-arn" = aws_iam_role.external_dns.arn }
    }
    env = [{ name = "AWS_DEFAULT_REGION", value = var.region }]
  })]

  depends_on = [module.eks, aws_iam_role_policy.external_dns]
}


# ------------------------------------------------------------------------------
#  NGINX Ingress Controller (F5 NGINX) behind an AWS NLB
# ------------------------------------------------------------------------------
resource "helm_release" "nginx_ingress" {
  name             = "nginx-ingress"
  repository       = "oci://ghcr.io/nginx/charts"
  chart            = "nginx-ingress"
  version          = "2.8.0"
  namespace        = "nginx-ingress"
  create_namespace = true

  values = [yamlencode({
    controller = {
      replicaCount = 2
      ingressClass = { name = "nginx", setAsDefaultIngress = true }
      service = {
        annotations = {
          "service.beta.kubernetes.io/aws-load-balancer-type"             = "nlb"
          "service.beta.kubernetes.io/aws-load-balancer-ssl-cert"         = aws_acm_certificate_validation.wildcard.certificate_arn
          "service.beta.kubernetes.io/aws-load-balancer-ssl-ports"        = "https"
          "service.beta.kubernetes.io/aws-load-balancer-backend-protocol" = "tcp"
        }
        # TLS ends at the NLB, so HTTPS traffic reaches NGINX as plain HTTP
        httpsPort = { targetPort = 80 }
        # Only these client IPs can reach the NLB (enforced on the node security group)
        loadBalancerSourceRanges = var.allowed_ingress_cidrs
      }
    }
  })]

  depends_on = [module.eks]
}


# ------------------------------------------------------------------------------
#  Sample nginx app at nginx.<domain>
# ------------------------------------------------------------------------------
resource "kubernetes_namespace_v1" "demo" {
  metadata {
    name = "demo"
  }

  depends_on = [module.eks]
}

resource "kubernetes_deployment_v1" "nginx" {
  metadata {
    name      = "nginx"
    namespace = kubernetes_namespace_v1.demo.metadata[0].name
  }

  spec {
    replicas = 2

    selector {
      match_labels = { app = "nginx" }
    }

    template {
      metadata {
        labels = { app = "nginx" }
      }

      spec {
        container {
          name  = "nginx"
          image = "nginx:stable"

          port {
            container_port = 80
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "nginx" {
  metadata {
    name      = "nginx"
    namespace = kubernetes_namespace_v1.demo.metadata[0].name
  }

  spec {
    selector = { app = "nginx" }

    port {
      port        = 80
      target_port = 80
    }
  }
}

resource "kubernetes_ingress_v1" "nginx" {
  metadata {
    name      = "nginx"
    namespace = kubernetes_namespace_v1.demo.metadata[0].name
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = "nginx.${var.domain_name}"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.nginx.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.nginx_ingress, helm_release.external_dns]
}

output "nginx_url" {
  value = "https://nginx.${var.domain_name}"
}

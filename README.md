# eks-new

Step-by-step guide to building an EKS cluster in AWS that serves apps on HTTPS subdomains of a domain registered at Squarespace, with access limited to an IP allowlist.

When you finish, you will have:

- an EKS cluster in `eu-west-1` with private worker nodes
- the domain's DNS hosted in Route 53, with the existing Squarespace website still working on the bare domain
- a wildcard HTTPS certificate (`*.yourdomain`)
- every app you deploy reachable at `https://<name>.yourdomain` with no manual DNS or certificate work
- only the IP addresses you list able to reach the apps

The examples use `citizendev.co.uk`. Replace it with your own domain.

```
browser ──DNS──> Route 53 (record created automatically by ExternalDNS)
browser ──HTTPS──> AWS Network Load Balancer (wildcard certificate, TLS ends here,
                   only allowed IPs get through)
        ──HTTP──> NGINX Ingress Controller (on the nodes)
        ──HTTP──> your app's pods (picked by hostname)
```

---

## Before you start

You need:

- **Tools:** Terraform, AWS CLI v2, `kubectl`, `helm` and `dig`.
- **AWS access** to the account you'll deploy into, with admin-level permissions (the code creates a VPC, EKS, IAM roles, Route 53 and ACM).
- **A domain registered at Squarespace** that you can log in to.
- **About an hour.** Most of it is waiting for EKS and DNS.

Check you're in the right AWS account. Every command below assumes this profile:

```sh
export AWS_PROFILE=default
aws sts get-caller-identity
```

> If `terraform plan` ever says most resources "have been deleted", you're in the wrong account. Stop, fix `AWS_PROFILE` and don't apply.

---

## Step 1: Gather your values

**Your Squarespace website's IPs.** Run this *before* changing anything at Squarespace:

```sh
dig +short citizendev.co.uk
```

You'll get the bare domain's A records (four IPs for Squarespace sites).

**Your public IP**, so you can reach the apps yourself:

```sh
curl https://checkip.amazonaws.com
```

If you're behind a VPN or proxy, also run `curl https://api.ipify.org`. If the two commands return different IPs, use both.

**Other records in Squarespace's DNS panel.** Open **Domains → your domain → DNS** and note any records you rely on, such as `www`, email (MX) or verification TXT records. Only the bare-domain A records are copied over by this code. Anything else needs adding to Route 53 in `dns-ingress.tf`, or it stops working when DNS moves.

## Step 2: Set the variables

Edit `variables.tf`:

| Variable | Set it to |
|---|---|
| `aws_account_id` | Your AWS account ID (from `aws sts get-caller-identity`) |
| `region` | AWS region (default `eu-west-1`) |
| `eks_cluster_name` | Name for the cluster |
| `domain_name` | Your domain, e.g. `citizendev.co.uk` |
| `squarespace_site_ips` | The IPs from `dig` in step 1 |
| `allowed_ingress_cidrs` | Every IP allowed to reach the apps, as `"x.x.x.x/32", # who` |
| `accountid`, `apikey` | Harness account ID and API key. Pass them as `TF_VAR_accountid` / `TF_VAR_apikey` rather than writing them in the file |

## Step 3: Initialise

```sh
cd eks-new
helm repo update      # avoids "no cached repo found" errors from the Helm provider
terraform init
```

## Step 4: Create the Route 53 hosted zone

Create only the zone and the website records first, because Squarespace has to point at the zone before the rest can finish:

```sh
terraform apply -target=aws_route53_zone.main -target=aws_route53_record.apex_squarespace
terraform output route53_name_servers
```

Note the four `awsdns` name servers in the output.

## Step 5: Point the domain at Route 53 in Squarespace

1. Log in to Squarespace and go to **Domains → citizendev.co.uk → DNS → Nameservers**.
2. Choose **Use custom nameservers**.
3. Enter the four name servers from step 4, without trailing dots.
4. Save. If DNSSEC is on, Squarespace may ask you to turn it off first.

The domain stays registered at Squarespace. From now on, all of its DNS records live in Route 53.

## Step 6: Wait for the switch

Usually minutes, occasionally a few hours. It's done when both commands list the four `awsdns` servers:

```sh
dig +short NS citizendev.co.uk
dig +short NS citizendev.co.uk @8.8.8.8
```

Check the website still loads at `https://citizendev.co.uk`.

## Step 7: Build everything else

```sh
terraform apply
```

This takes about 20 minutes. It creates the VPC, EKS cluster and nodes, the certificate, ExternalDNS, the NGINX ingress controller and a demo `nginx` app.

The certificate step waits until AWS can validate it through Route 53. If it fails with **`CAA_ERROR`**, AWS saw Squarespace's old DNS. Once step 6 passes, recreate the certificate and apply again:

```sh
terraform apply -replace=aws_acm_certificate.wildcard
```

## Step 8: Check it works

Connect `kubectl`:

```sh
aws eks update-kubeconfig --name harness-workshop-cluster --region eu-west-1
kubectl get nodes                  # all Ready
kubectl get ingress -A             # ADDRESS shows the load balancer hostname
```

Wait a minute or two for ExternalDNS to create the record, then:

```sh
dig +short nginx.citizendev.co.uk  # returns IPs
curl -I https://nginx.citizendev.co.uk
```

You should get `HTTP/1.1 200 OK` and, in a browser, the "Welcome to nginx!" page.

> **Don't open the URL before `dig` returns IPs.** If you do, your DNS resolver caches "not found" for up to a minute and the site seems broken. If it happens, wait a minute and retry.

## Step 9: Deploy your own app

Create a Deployment, a Service of type **`ClusterIP`**, and an Ingress with your hostname:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp
spec:
  ingressClassName: nginx
  rules:
    - host: myapp.citizendev.co.uk
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myapp
                port:
                  number: 80
```

Wait about a minute, then open `https://myapp.citizendev.co.uk`. DNS and HTTPS are handled for you.

- **Use `ClusterIP`, not `LoadBalancer`.** A `LoadBalancer` Service creates an extra load balancer you pay for but never use.
- **Old records stay behind.** If you rename or delete an Ingress, its old Route 53 record isn't deleted. Remove it by hand if you want.

---

## Day-to-day tasks

### Allow another IP

1. Add `"x.x.x.x/32", # who` to `allowed_ingress_cidrs` in `variables.tf`.
2. Run `terraform apply`. The plan shows 1 change to `helm_release.nginx_ingress`.

Kubernetes writes the matching rules onto the node security group (`<cluster>-node-*`). Don't add them by hand: the ports are random and Kubernetes manages them.

Home and proxy IPs change. If the sites suddenly time out for you, check `curl https://checkip.amazonaws.com` and update the list.

### Change the number of nodes

The EKS module ignores `desired_size` after the node group is created, so scale with the AWS CLI:

```sh
aws eks update-nodegroup-config --region eu-west-1 \
  --cluster-name harness-workshop-cluster \
  --nodegroup-name $(aws eks list-nodegroups --region eu-west-1 --cluster-name harness-workshop-cluster --query 'nodegroups[0]' --output text) \
  --scaling-config minSize=1,maxSize=6,desiredSize=N
```

To go above `max_size` (currently 6), raise it in `main.tf` and apply first.

### Tear it all down

1. Switch the name servers in Squarespace back to the defaults first, or the domain (including the website) stops resolving once the zone is gone.
2. Delete anything you deployed outside Terraform, especially `type: LoadBalancer` Services. Their load balancers otherwise block the VPC from being deleted:
   ```sh
   kubectl get svc -A | grep LoadBalancer
   ```
3. Delete the records ExternalDNS created in Route 53 (everything except NS, SOA, the apex A record and the `_` validation CNAMEs). Terraform can't delete a zone that still has records it doesn't manage.
4. Run `terraform destroy`.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Site times out | Your IP isn't in `allowed_ingress_cidrs`. Check it with `curl https://checkip.amazonaws.com`. |
| "Site can't be reached" / "could not resolve host" | A DNS resolver has cached "not found". Compare `dig +short host @1.1.1.1` with `dig +short host @8.8.8.8` and wait a minute. |
| Some requests work and others fail | Usually the same caching: one of your DNS servers is stale. If it persists, check the `ingress_self_all` rule in `main.tf` is still there. Without it, pods on different nodes can't reach each other. |
| 404 from NGINX | No Ingress matches that host. Check with `kubectl get ingress -A`. |
| `kubectl`: "Unauthorized" | Wrong or expired AWS profile. Re-run `aws eks update-kubeconfig` with `AWS_PROFILE=default`. |
| Certificate `CAA_ERROR` | See step 7. |
| Helm "no cached repo found" | Run `helm repo update` and apply again. |

## Known issues

- **Unused open security group:** `<cluster>_alb_sg` is open to `0.0.0.0/0` on ports 80, 8080 and 8085–8090. It isn't used by the NGINX ingress path. Check whether anything is attached to it before removing it.
- **Unused IAM policy:** `AWSLoadBalancerControllerIAMPolicy-*` is a minimal policy attached to an unused role. The AWS Load Balancer Controller is not installed; the NLB is managed by Kubernetes' built-in AWS integration.
- **Local state:** state is kept in `terraform.tfstate` in this folder. Don't delete it, and only run Terraform from one machine at a time.

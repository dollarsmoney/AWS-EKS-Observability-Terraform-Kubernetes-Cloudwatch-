# Lab guide: hands-on CloudWatch with EKS, RDS and ElastiCache

This lab builds a small, realistic AWS stack with plain Terraform resources and no community modules. Its real purpose is **CloudWatch practice**: you'll create metrics, alarms, logs, queries and dashboards, then break things on purpose and watch the alerts fire.

```
                         Internet
                            │
                      ┌─────┴─────┐
                      │    IGW    │
┌─────────────────────┴───────────┴──────────────────────── VPC 10.0.0.0/16 ┐
│  Public 10.0.0.0/24 (AZ-a)  [NAT GW]       Public 10.0.1.0/24 (AZ-b)       │
│ ────────────────────────────┼──────────────────────────────────────────── │
│  Private 10.0.10.0/24 (AZ-a)│               Private 10.0.11.0/24 (AZ-b)    │
│     ┌──────────────┐  ┌─────┴──────┐  ┌───────────────┐                    │
│     │ EKS nodes x2 │─▶│ RDS PG 17  │  │ Redis 7 (TLS) │◀─ only from EKS SG │
│     │ CW agent +   │─────────────────▶│               │                    │
│     │ Fluent Bit   │  └────────────┘  └───────────────┘                    │
│     └──────────────┘                                                       │
│                            VPC Flow Logs ─────────────┐                    │
└───────────────────────────────────────────────────────┼────────────────────┘
                                                        ▼
   CloudWatch:  Metrics ─▶ Alarms ─▶ SNS ─▶ your email
                Logs ─▶ Metric filters ─▶ custom metrics ─▶ Alarms
                Logs Insights saved queries · Dashboard
```

## Project layout

| Path | What it teaches |
|---|---|
| `modules/vpc` | `for_each` + `cidrsubnet()`, NAT, route tables, **Flow Logs → CloudWatch** with a least-privilege IAM role |
| `modules/eks` | EKS from raw resources, access entries, **control-plane logs**, **Container Insights add-on via Pod Identity** |
| `modules/rds` | Postgres in private subnets, Secrets Manager password, **log exports, Enhanced Monitoring, Performance Insights** |
| `modules/elasticache` | Redis with TLS and **slow-log / engine-log delivery** to CloudWatch |
| `modules/monitoring` | **SNS, alarms (static, M-of-N, metric math, Metrics Insights, anomaly detection, composite), metric filters, saved queries, dashboard** |
| `k8s/` | Workloads that deliberately trigger the alarms |

---

## 1. CloudWatch concepts (read this first)

- **Metric**: a time series identified by a **namespace** (`AWS/RDS`), a **name** (`CPUUtilization`) and **dimensions** (`DBInstanceIdentifier=...`). Change any one of those and it's a *different* metric. Most "my alarm has no data" bugs come from a wrong dimension.
- **Statistic + period**: how raw points get aggregated (`Average`, `Sum`, `Maximum`, `p99`) and over what window (60s, 300s).
- **Alarm states**: `OK`, `ALARM` and `INSUFFICIENT_DATA`. `treat_missing_data` decides what a gap means: `missing`, `notBreaching`, `breaching` or `ignore`.
- **Evaluation**: `evaluation_periods = 5` with `datapoints_to_alarm = 3` means "3 of the last 5 points breached". That filters out spikes. See `eks_node_cpu`.
- **Metric math**: an alarm or graph on an *expression* such as `bytes / 1073741824`. See `rds_free_storage` and the RDS latency widget.
- **Metrics Insights**: SQL over metrics, like `SELECT SUM(...) FROM SCHEMA(...) WHERE ... GROUP BY ...`. One alarm can cover every pod. See `eks_pod_restarts`.
- **Anomaly detection**: CloudWatch learns a band of normal values, and the alarm fires outside it. It needs about a day of data first. See `redis_connections_anomaly`.
- **Composite alarm**: boolean logic over other alarms (`ALARM(a) OR ALARM(b)`). It cuts alert noise. See `app_tier`.
- **Log group / stream / retention**: always set retention. The default is *never expire*, and you keep paying for those logs forever. Every log group here is created by Terraform **before** the service that writes to it, so the retention setting wins.
- **Metric filter**: a pattern that turns log lines into a custom metric you can alarm on. There are two syntaxes: space-delimited `[a, b, action="REJECT", ...]` for Flow Logs and JSON `{ $.responseStatus.code >= 500 }` for EKS audit logs.
- **Logs Insights**: a query language (`fields | filter | parse | stats | sort`). Saved queries are under *Logs Insights → Saved queries*.
- **Container Insights**: the `amazon-cloudwatch-observability` add-on runs a CloudWatch agent (metrics, `ContainerInsights` namespace) and Fluent Bit (logs, `/aws/containerinsights/<cluster>/application`).

## 2. Run it

```bash
cp terraform.tfvars.example terraform.tfvars   # set alert_email + my_ip_cidr
echo "$(curl -s https://checkip.amazonaws.com)/32"  # your IP

terraform init -backend-config="bucket=<state_bucket from ./bootstrap>"
terraform plan            # expect ~83 resources
terraform apply           # ~20 min (EKS ~10, RDS ~8)
```

Then:

1. **Confirm the SNS email** ("AWS Notification - Subscription Confirmation"). Without that click, no alerts arrive.
2. Connect kubectl:
   ```bash
   $(terraform output -raw configure_kubectl)
   kubectl get nodes
   kubectl get pods -n amazon-cloudwatch     # cloudwatch-agent + fluent-bit should be Running
   ```
3. Open the dashboard: `terraform output -raw dashboard_url`. Container Insights metrics show up within about 5 minutes.

> If your IP changes, `kubectl` will time out. Update `my_ip_cidr` and run `terraform apply` again.

### Credentials for the exercises
```bash
kubectl apply -f k8s/00-namespace.yaml

DB_PASS=$(aws secretsmanager get-secret-value \
  --secret-id "$(terraform output -raw rds_master_secret_arn)" \
  --query SecretString --output text | jq -r .password)

kubectl -n lab create secret generic db-creds \
  --from-literal=PGHOST="$(terraform output -raw rds_address)" \
  --from-literal=PGUSER="$(terraform output -raw rds_username)" \
  --from-literal=PGDATABASE="$(terraform output -raw rds_db_name)" \
  --from-literal=PGPASSWORD="$DB_PASS"

kubectl -n lab create configmap redis-endpoint \
  --from-literal=REDIS_HOST="$(terraform output -raw redis_endpoint)"
```

---

## 3. Hands-on exercises

Work through these in order. Each one builds on the one before.

1. **Test the alert pipeline without breaking anything.**
   `aws cloudwatch set-alarm-state --alarm-name eks-cw-lab-dev-redis-evictions --state-value ALARM --state-reason "test"`
   You should get an email. The alarm then flips back to OK on its next evaluation, and you get a second email because of `ok_actions`.
2. **CPU alarm, then the composite alarm.** `kubectl apply -f k8s/cpu-stress.yaml`. Watch the node CPU widget. After about 3–5 minutes, `eks-node-cpu-high` and then `app-tier-unhealthy` go to ALARM. Delete the deployment and watch both recover.
   *Bonus:* why did the composite alarm fire? Open it in the console and look at its rule.
3. **Crash loops.** `kubectl apply -f k8s/crashloop.yaml`. Watch the restarts widget, run the saved query `eks/container-errors`, and wait for the `eks-pod-restarts` alarm.
4. **Database load.** `kubectl apply -f k8s/pgbench-job.yaml` and follow it with `kubectl -n lab logs -f job/pgbench`.
   - Watch CPU, connections and latency on the dashboard.
   - Run the saved query `rds/slow-queries`, which should show the `pg_sleep` statements.
   - Open **RDS → Performance Insights** and find the top SQL by wait time.
   - Open the log group `RDSOSMetrics` (Enhanced Monitoring) and find per-process CPU.
5. **Redis load.** `kubectl apply -f k8s/redis-benchmark-job.yaml`. Watch EngineCPU and Get/Set commands, then run the `redis/slow-commands` query, which should show `KEYS` near the top.
6. **Security-group rejects in Flow Logs.** Hit a port that isn't allowed:
   ```bash
   kubectl -n lab run nettest --rm -it --image=busybox:1.36 --restart=Never -- \
     nc -zv -w 3 $(terraform output -raw rds_address) 3306
   ```
   Then run `vpc/top-rejected-sources` and find your pod IP against port 3306.
7. **Write your own metric filter.** Count `FATAL` lines in the Postgres log (`/aws/rds/instance/.../postgresql`), alarm on it, then trigger it with a wrong password (`psql` with a bad `PGPASSWORD`).
8. **Extend the dashboard.** Add a widget in the console, export its JSON (*Actions → View/edit source*), port it into `dashboard.tf`, and confirm `terraform plan` shows only the dashboard changing.
9. **Remove the alert noise.** Delete `alarm_actions` from the three CPU child alarms so only the composite alarm notifies. That's the real-world pattern.
10. **Tune the anomaly detection.** After a day, look at the band on `redis-connections-anomaly`, change the band width from `2` to `3`, and compare.
11. **Use Spot nodes.** Set `capacity_type = "SPOT"`, apply, and watch `cluster_node_count` while the nodes get replaced.
12. **Detect drift.** Change an alarm threshold in the console, run `terraform plan`, and see the drift. Revert it with `apply`.

---

## 4. Best practices used here (and why)

- **Pinned provider** (`~> 6.0`) and `required_version`, so upgrades happen on purpose.
- **`default_tags`**: every resource is tagged for cost reports and cleanup.
- **Log retention on every log group**, created before the service writes to it.
- **No secrets in state.** `manage_master_user_password` keeps the DB password in Secrets Manager.
- **Least-privilege networking.** RDS and Redis accept traffic only from the EKS cluster security group, the EKS API is reachable only from your IP, and nodes sit in private subnets.
- **Pod Identity for the CloudWatch agent** instead of granting CloudWatch permissions to every pod through the node role.
- **`upgrade_policy = STANDARD`**, so EKS never silently moves into paid extended support.
- **Encryption** at rest and in transit for RDS and Redis.
- **Small modules** that pass data only through inputs and outputs. Monitoring depends only on IDs.
- **Data-driven resources** (`for_each` over a map in `alarms_rds.tf`). Adding an alarm means adding one map entry.
- Run `terraform fmt -recursive && terraform validate` before every commit, and add `tflint` and `checkov -d .` for linting and security scanning.

**Lab shortcuts you should reverse in production:** one NAT gateway, single-AZ RDS, a single Redis node, `skip_final_snapshot = true`, `deletion_protection = false`, local state, and a public EKS endpoint.

## 5. Suggested next steps

1. **Remote state.** Create an S3 bucket and uncomment the `backend "s3"` block (`use_lockfile = true`).
2. **CI/CD.** A GitHub Actions workflow that runs `fmt`, `validate`, `tflint` and `checkov`, posts `plan` on PRs, and runs `apply` on merge, using OIDC for AWS credentials.
3. **Environments.** Separate `dev` and `prod` tfvars, or workspaces, each with its own state.
4. **Better observability:** CloudWatch **Synthetics** canaries, **Application Signals** and X-Ray tracing (ADOT), **Amazon Managed Prometheus and Grafana**, and **Contributor Insights** on Flow Logs.
5. **Automated responses.** EventBridge rules on alarm state changes that trigger a Lambda to remediate (restart something, scale something).
6. **Production hardening:** Multi-AZ RDS, a Redis replica with failover, a NAT gateway per AZ, Karpenter or Cluster Autoscaler, and a private-only EKS endpoint behind a VPN or bastion.
7. **Cost alarms.** An AWS Budgets alert, or a CloudWatch billing alarm on `EstimatedCharges` (us-east-1).

## 6. Cost and cleanup ⚠️

Roughly **$8–10 per day** while running: EKS control plane about $2.40, NAT gateway about $1.10 plus data, 2× t3.small about $1, RDS micro about $0.40, Redis micro about $0.40, plus logs, metrics and Container Insights.

```bash
kubectl delete namespace lab   # removes the test workloads first
terraform destroy
```

Fluent Bit can recreate a Container Insights log group in the last seconds before the nodes go away. If `/aws/containerinsights/...` groups remain after `destroy`, delete them in the console.

# Camunda 8 Deployment and Backup with OpenSearch

The purpose of this document is to show how to integrate OpenSearch with Camunda 8 and enable backups.

## Create and Verify Camunda 8 on EKS

### Create an EKS Cluster with Terraform
Follow the guide:
[Camunda Docs - Deploy on Amazon EKS with Terraform](https://docs.camunda.io/docs/self-managed/setup/deploy/amazon/amazon-eks/eks-terraform/)

### Install Camunda 8 on EKS
Follow the guide:
[Camunda Docs - Install Camunda 8 on EKS](https://docs.camunda.io/docs/self-managed/setup/deploy/amazon/amazon-eks/eks-helm/)

### Verify Camunda 8 Installation
Use port-forwarding and token authentication:
[Verify Connectivity](https://docs.camunda.io/docs/self-managed/setup/deploy/amazon/amazon-eks/eks-helm/#verify-connectivity-to-camunda-8)

## Enable AWS OpenSearch Access

### Enable OpenSearch Access from Localhost
1. Create Kubernetes services with ExternalName type `opensearch-external` pointing to AWS OpenSearch:
   - **File:** `opensearch-external-service.yaml`

2. Create a Kubernetes pod as a proxy `opensearch-proxy` with an Nginx container to handle AWS OpenSearch requests:
   - **Files:** `nginx.conf`, `opensearch-proxy.yaml`

### Execute Commands
```bash
kubectl create configmap nginx-opensearch-proxy-config --from-file=nginx.conf
kubectl apply -f opensearch-external-service.yaml
kubectl apply -f opensearch-proxy.yaml
```
Find them with:
```bash
kubectl get services
kubectl get pods
```

### Execute Port-Forward to AWS OpenSearch
```bash
kubectl port-forward pod/opensearch-proxy 9200:80
```

### Access AWS OpenSearch from Browser
[http://localhost:9200/_dashboards](http://localhost:9200/_dashboards)

## Kubernetes Port-Forwarding Commands (just for the information)
```bash
# Identity
kubectl port-forward services/camunda-identity 8080:80 --namespace camunda

# Keycloak
kubectl port-forward services/camunda-keycloak 18080:80 --namespace camunda

# Operate
kubectl port-forward services/camunda-operate 8081:80 --namespace camunda

# Tasklist
kubectl port-forward services/camunda-tasklist 8082:80 --namespace camunda

# Optimize
kubectl port-forward services/camunda-optimize 8083:80 --namespace camunda

# Zeebe
kubectl port-forward services/camunda-zeebe-gateway 26500:26500

# OpenSearch
kubectl port-forward pod/opensearch-proxy 9200:80
```

## Deploy and Run Workflows (skip if it is not needed)
### Setup Access to Zeebe from Local Camunda Desktop
Execute:
```bash
kubectl port-forward services/camunda-zeebe-gateway 26500:26500
```

### Camunda 8 Desktop - Create Deploy Diagram
**Create token via Zeebe Authorization Server URL:**
```
http://localhost:18080/auth/realms/camunda-platform/protocol/openid-connect/token
```

### Steps
- Create a BPMN example
- Deploy Diagram. Follow the [guide](https://docs.camunda.io/docs/self-managed/modeler/desktop-modeler/deploy-to-self-managed/?auth=oauth).
- Run
- Test

## Create OpenSearch Snapshot Repository
### Create S3 Bucket and AWS Role
Follow the guide:
[AWS OpenSearch Snapshot Prerequisites](https://docs.aws.amazon.com/opensearch-service/latest/developerguide/managedomains-snapshots.html#managedomains-snapshot-prerequisites)

### Create OpenSearch repository using the Sample Python Client
Follow the guide:
[Using the sample Python client](https://docs.aws.amazon.com/opensearch-service/latest/developerguide/managedomains-snapshot-registerdirectory.html)
1. If it is needed, check guide: [How to Fix Error: Externally-Managed-Environment in Pip, section "Use a Virtual Environment"
](https://builtin.com/articles/error-externally-managed-environment)
2. Install required packages :
```bash
python3 -m venv ~/py_envs
source ~/py_envs/bin/activate
python3 -m pip install boto3 requests requests-aws4auth
```
3. Register repository:
```bash
python3 register_repo.py
```
**Expected Response:**
```
200
{"acknowledged":true}
```

### Verify in OpenSearch Dashboard
Go to the OpenSearch [dashboard](http://localhost:9200/_dashboards) and check if the repository is created.

## Configure Operate, Tasklist, and Optimize for Backup
### Update `generated-values.yml` with OpenSaerch repository name. Follow the guides:
- [Operate & Tasklist Backup Prerequisites](https://docs.camunda.io/docs/self-managed/operational-guides/backup-restore/operate-tasklist-backup/#prerequisites)
- [Optimize Backup Prerequisites](https://docs.camunda.io/docs/self-managed/operational-guides/backup-restore/optimize-backup/#prerequisites)

### Update Pods with Helm
```bash
helm upgrade --install \
  camunda camunda-platform \
  --repo https://helm.camunda.io \
  --version "$CAMUNDA_HELM_CHART_VERSION" \
  --namespace camunda \
  -f generated-values.yml
```

## Check if Backup Works

### Optimize (Not Supported in 8.6 for GET Backups)
```bash
kubectl port-forward services/camunda-optimize 8092:8092 --namespace camunda
```
URL: [http://localhost:8092/actuator/backups](http://localhost:8092/actuator/backups)

### Operate
```bash
kubectl port-forward services/camunda-operate 9700:9600 --namespace camunda
```
URL: [http://localhost:9700/actuator/backups](http://localhost:9700/actuator/backups)

### Tasklist
```bash
kubectl port-forward services/camunda-tasklist 9600:9600 --namespace camunda
```
URL: [http://localhost:9600/actuator/backups](http://localhost:9600/actuator/backups)

## Perform Backup and Cleaning

### Generate Backup ID
```bash
./backup/create-backupId-as-secret.sh
```

### Edit `camunda-backup-job.yaml`
Update ports for Tasklist and Operate, and disable Optimize (if using version 8.6).

### Trigger Backup for Operate, Tasklist, and Optimize (?)
```bash
kubectl apply -f ./backup/camunda-backup-job.yaml
```
Monitor logs to ensure the job completes successfully. For more information, check [Backup and Restore Instructions](https://github.com/camunda-consulting/c8-devops-workshop/blob/main/03%20-%20Lab%203%20-%20Backup%20and%20Restore/Instructions.md#perform-backup).

### Create new Backup and remove all previosly created Backups
Use the script:
```bash
./backup/camunda-backup-and-cleanup.sh
```
Ensure Tasklist and Operate are port-forwarded before execution.

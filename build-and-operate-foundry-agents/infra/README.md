# Deploy the Build and Operate workshop infrastructure

This Terraform configuration deploys a self-contained Microsoft Foundry Standard
Agent environment for the Build and Operate Foundry Agents workshop with public
network access. It uses Microsoft Entra ID and a user-assigned managed identity;
local keys are disabled, but every data-plane endpoint is reachable over the
public internet, so a client can run the workshop without a VPN, ExpressRoute,
or Bastion host.

## Resources

- Azure resource group
- Microsoft Foundry resource, project, capability host, and model deployments
- Azure Managed Identities user-assigned managed identity
- Azure Storage account and Blob containers
- Azure Cosmos DB for NoSQL account
- Azure AI Search service
- Azure Key Vault
- Azure Container Registry
- Azure Monitor Log Analytics workspace
- Azure role assignments and Microsoft Foundry project connections

## Prerequisites

1. Install Terraform `1.12` or later and Azure CLI.
2. Sign in with Azure CLI and select the deployment subscription:

   ```bash
   az login --use-device-code --tenant '<tenant-id>'
   az account set --subscription '<subscription-id>'
   az account show --query '{subscription:id,tenant:tenantId,user:user.name}' --output table
   ```

3. Use an identity that can create the listed resources and role assignments.
   `Owner`, or `Contributor` plus `User Access Administrator`, at the target
   subscription or resource-group scope is sufficient.
4. Choose a region that supports Microsoft Foundry Agent Service, the requested
   model versions, Azure AI Search semantic ranker, and your required quota.
5. Because every data-plane endpoint is public, treat your Microsoft Entra
   credentials as the only access boundary. Local authentication keys stay
   disabled on every resource; only Microsoft Entra-authorized identities can
   read or write data.

Microsoft documents the resource model in
[Microsoft Foundry architecture](https://learn.microsoft.com/azure/foundry/concepts/architecture),
the Standard Agent setup in
[Set up standard agent resources for Foundry Agent Service](https://learn.microsoft.com/azure/foundry/agents/concepts/standard-agent-setup),
and the Terraform control-plane workflow in
[Use Terraform to create Microsoft Foundry](https://learn.microsoft.com/azure/foundry/how-to/create-resource-terraform).

## Configure

From this directory, copy the tracked example to Terraform's conventional local
variables file:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit every placeholder in `terraform.tfvars`. At minimum, set:

- `subscription_id` and `tenant_id`
- `location`
- `operator_principal_id` and `operator_principal_type`
- `name_prefix` and globally unique `resource_suffix`
- model names, versions, SKUs, and capacities available in the selected region

For an interactive user, get the operator object ID with:

```bash
az ad signed-in-user show --query id --output tsv
```

For a service principal, use its Microsoft Entra object ID and set
`operator_principal_type = "ServicePrincipal"`.

Check model availability and quota before planning:

```bash
LOCATION='eastus2'
SUBSCRIPTION_ID="$(az account show --query id --output tsv)"

az cognitiveservices model list \
  --location "$LOCATION" \
  --subscription "$SUBSCRIPTION_ID" \
  --output table

az cognitiveservices usage list \
  --location "$LOCATION" \
  --subscription "$SUBSCRIPTION_ID" \
  --output table
```

The supplied model values mirror the source deployment. They are examples, not a
promise of regional availability or quota. Remove deployments the workshop does
not need, but keep the entries selected by `chat_model_deployment_key` and
`embedding_model_deployment_key`.

## Deploy

Run the whole workflow — `init -upgrade`, `fmt`, `validate`, then `apply` with its normal
interactive plan review and "yes" confirmation prompt — with one command:

```bash
bash tf-apply.sh
```

It stops immediately if any step fails. On a successful apply, it also automatically patches
`/etc/hosts` from the deployment's real outputs (a workaround for corporate DNS gaps on some
networks — see the troubleshooting section in `NON-DOCKER-SETUP.md`), writes those outputs
into the repository-root `.env`, and scans the output for known failure patterns from this
workshop's setup, printing the specific fix for each one found.

(Plain `terraform init`/`validate`/`apply` still work individually if you'd rather run each
step, or handle DNS/`.env` yourself.)

The AzureRM provider registers the resource providers used by this template. If
your organization restricts provider registration, have an administrator register
`Microsoft.Authorization`, `Microsoft.CognitiveServices`,
`Microsoft.ContainerRegistry`, `Microsoft.ContainerService`,
`Microsoft.DocumentDB`, `Microsoft.Insights`, `Microsoft.KeyVault`,
`Microsoft.ManagedIdentity`,
`Microsoft.OperationalInsights`, `Microsoft.Search`, and `Microsoft.Storage`
before deployment.

The default local Terraform state is appropriate only for an individual
workshop deployment. Configure a protected remote backend before using this
configuration from a team or CI/CD system.

## Configure the workshop

After apply, inspect the nonsecret outputs:

```bash
terraform output
```

If you applied with `tf-apply.sh`, the repository-root `.env` already has these values (in an
auto-managed block that's safe to delete — rerunning `tf-apply.sh` regenerates it, and nothing
else in `.env` is touched). Otherwise, write them in yourself:

```bash
terraform output -raw workshop_env > workshop.env
```

Merge those values into the repository-root `.env` without removing the other
workshop settings. The output includes:

- `FOUNDRY_PROJECT_ENDPOINT`
- `PROJECT_RESOURCE_ID`
- `AZURE_AI_MODEL_DEPLOYMENT_NAME` and `FOUNDRY_MODEL`
- `EMBEDDING_MODEL_DEPLOYMENT_NAME`
- `AZURE_OPENAI_ENDPOINT`
- `AZURE_AI_SEARCH_ENDPOINT`
- `MARKETPLACE_BLOB_STORAGE_URL`
- `MARKETPLACE_BLOB_STORAGE_CONTAINER`
- Azure tenant, subscription, resource group, project, and workshop suffix values

Run the workshop preflight from the repository root:

```bash
python build-and-operate-foundry-agents/tools/preflight.py
```

Run the post-deployment management-plane and model smoke tests from this
directory:

```bash
bash tf-post-deploy-validation.sh
```

The script reads tenant, subscription, location, naming, project, and model
values from `terraform.tfvars`. It reuses an existing Azure CLI session when
possible, selects the configured subscription, and starts device-code login only
when usable cached credentials are unavailable.

Hosted agents receive a platform-assigned identity that is separate from the
project identity. After each first hosted-agent deployment, grant that identity
access to optional external resources it uses, such as `Search Index Data Reader`
on Azure AI Search or `Storage Blob Data Contributor` on the history container.

## Verify

Management-plane checks can run from any authenticated machine:

```bash
RESOURCE_GROUP="$(terraform output -raw resource_group_name)"

az resource list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[].{name:name,type:type,state:properties.provisioningState}" \
  --output table
```

Every provisioning state should be `Succeeded`. Because every data-plane
endpoint is public, Foundry, Azure AI Search, Blob Storage, Azure Cosmos DB, Key
Vault, and Azure Container Registry host names resolve to public IP addresses;
Microsoft Entra ID role assignments remain the access boundary.

## Destroy

Run the whole teardown — `init -upgrade`, `validate`, a DNS patch for the current
deployment's hostnames (needed so `destroy` can refresh/read each resource before
deleting it), then `destroy` with its normal interactive plan review and typed
confirmation — with one command:

```bash
bash tf-destroy.sh
```

It stops immediately if any step fails. On a successful destroy, it also clears the
auto-managed `workshop_env` block from the repository-root `.env` (those endpoints
no longer exist), and scans the output for known failure patterns from this
workshop's setup, printing the specific fix for each one found.

(Plain `terraform plan -destroy` / `terraform apply` still work individually if
you'd rather run each step yourself.)

Destroy includes a short cooldown and purge action so a re-deployment can reuse
the same Microsoft Foundry resource name immediately after the soft-deleted
account is removed.

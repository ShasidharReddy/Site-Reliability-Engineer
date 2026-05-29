# Lab 03: GCP IAM Best Practices

## Audit Current IAM
```bash
# Who has what roles
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --format="table(bindings.role,bindings.members)"

# Find over-privileged accounts
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --format="table(bindings.role,bindings.members)" | grep -E "roles/owner|roles/editor"
```

## Create Least-Privilege SA for SRE
```bash
# Create SA
gcloud iam service-accounts create sre-readonly \
  --display-name="SRE Read-Only Access"

# Grant only what's needed
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member=serviceAccount:sre-readonly@$PROJECT_ID.iam.gserviceaccount.com \
  --role=roles/monitoring.viewer

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member=serviceAccount:sre-readonly@$PROJECT_ID.iam.gserviceaccount.com \
  --role=roles/logging.viewer

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member=serviceAccount:sre-readonly@$PROJECT_ID.iam.gserviceaccount.com \
  --role=roles/container.viewer
```

## Remove Over-Privileged Bindings
```bash
gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member=user:someone@company.com \
  --role=roles/owner
```

## Verify No Key-based SA
```bash
# List SA keys
for sa in $(gcloud iam service-accounts list --format='value(email)'); do
  keys=$(gcloud iam service-accounts keys list --iam-account=$sa --format='value(name)' | grep -v 'SYSTEM_MANAGED' | wc -l)
  if [ $keys -gt 0 ]; then
    echo "Key found for: $sa ($keys keys)"
  fi
done
```

## Verification
- [ ] No owner/editor bindings to user accounts
- [ ] SRE service account has only required roles
- [ ] No user-managed SA keys exist

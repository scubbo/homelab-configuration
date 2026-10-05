# Grafana CloudWatch Datasource

This stack creates the dedicated, read-only AWS IAM user used by Grafana to display the Jellyfin proxy's CloudWatch metrics and alarm state. It intentionally does not create an access key: CloudFormation would expose that secret in stack state and outputs.

## Permissions

`grafana-cloudwatch` can only read CloudWatch metrics/alarm metadata, the dedicated `/aws/events/jellyfin-proxy` alert-event log group, and EC2 instances, tags, and regions. It cannot change alarms, create or stop EC2 instances, access SSM parameters, read AWS Backup recovery points, or publish SNS messages.

The proxy stack writes EC2 status-alarm state transitions, AWS Backup failures, and Tailscale auth-key expiry events to this log group with 90-day retention. Its SNS email notifications remain the immediate alert path.

## Deploy the IAM user

Review a change set, then deploy the stack:

```bash
aws cloudformation deploy \
  --region us-east-1 \
  --stack-name grafana-cloudwatch \
  --template-file non-k8s-iac/aws-cloudformation/grafana-cloudwatch/template.json \
  --capabilities CAPABILITY_IAM
```

## Create and install the access key

Create one active access key. Do not print it, save it to a file, put it in CloudFormation, or commit it to Git.

```bash
read -r -s "AWS_ACCESS_KEY_ID?Grafana CloudWatch access key ID: "
printf '\n'
read -r -s "AWS_SECRET_ACCESS_KEY?Grafana CloudWatch secret access key: "
printf '\n'

kubectl create secret generic grafana-cloudwatch \
  --namespace prometheus \
  --from-literal=AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
  --from-literal=AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
```

The Grafana deployment imports this Secret through `envFromSecret`. Create it before merging the Grafana datasource configuration so the pod does not fail to start on a missing Secret.

## Rotate the key

1. Create a second access key for `grafana-cloudwatch` in AWS IAM.
2. Replace the values in the `prometheus/grafana-cloudwatch` Secret with the new key.
3. Restart the Grafana Deployment and confirm the CloudWatch datasource and dashboard work.
4. Delete the former AWS access key.

IAM permits at most two active access keys, which supports this overlap.

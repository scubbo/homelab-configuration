# Alertmanager Telegram Integration

This directory contains the configuration for Telegram notifications from Alertmanager.

## Setup Instructions

### 1. Create a Telegram Bot

1. Open Telegram and search for `@BotFather`
2. Send `/newbot` and follow the prompts
3. Copy the bot token (looks like `123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11`)

### 2. Get Your Chat ID

To get your chat ID (personal or group):

1. Add the bot to your chat/group
2. Send a message to the bot or in the group
3. Visit: `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates`
4. Look for `"chat":{"id":` - that number is your chat ID
   - Personal chats are positive numbers
   - Group chats are negative numbers

### 3. Create the Kubernetes Secret

```bash
kubectl create secret generic alertmanager-telegram \
  --namespace prometheus \
  --from-literal=bot-token='YOUR_BOT_TOKEN_HERE'
```

### 4. Update the Chat ID in Config

Edit `app-of-apps/o11y/prometheus.jsonnet` and replace `chat_id: -1` with your actual chat ID.

For example:
```jsonnet
chat_id: 123456789,  // Your personal chat ID
// or
chat_id: -987654321,  // A group chat ID (negative number)
```

### 5. Deploy

Commit and push. ArgoCD will sync the changes.

## Testing

Once deployed, you can test by triggering a dummy alert:

```bash
# Port forward to alertmanager
kubectl port-forward -n prometheus svc/prometheus-kube-prometheus-alertmanager 9093:9093

# Send a test alert
curl -XPOST -H "Content-Type: application/json" http://localhost:9093/api/v1/alerts -d '[
  {
    "labels": {
      "alertname": "TestAlert",
      "severity": "warning"
    },
    "annotations": {
      "summary": "This is a test alert from Alertmanager"
    }
  }
]'
```

You should receive a Telegram message within a few minutes.

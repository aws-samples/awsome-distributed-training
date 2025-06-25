# Setting Up Slack Alerts for Amazon Managed Grafana Workspace

This guide walks you through configuring Slack notifications for your Amazon Managed Grafana (AMG) workspace alerts.

## Prerequisites
- Access to a Slack workspace with administrative privileges
- An Amazon Managed Grafana workspace
- Appropriate AWS permissions to modify AMG workspace settings

## Step 1: Configure Slack Workspace

1. Visit [Slack API Quickstart](https://api.slack.com/quickstart)
2. Click "Create New App" and select "From scratch"
3. Configure the app:
   - Name your app (e.g., "GPU Cluster Alerts")
   - Select your target workspace
   - Click "Create App"

![Create slack app](assets/create-slack-app.png)

## Step 2: Configure App Permissions

1. Navigate to "OAuth & Permissions" in your Slack app settings
2. Under "Bot Token Scopes", add the following scopes:
   - `chat:write` - Enables message posting
   - `channels:read` - Enables public channel access
   
> **Note**: For posting in public channels without joining, request the `chat:write.public` scope instead.

![Slack scopes configuration](assets/slack-scopes.png)

## Step 3: Install App to Workspace

1. Return to "Basic Information"
2. Click "Install to Workspace"
3. Authorize the app through the OAuth flow
4. Copy the provided Bot User OAuth Token (starts with "xoxb-")

![Slack app in workspace](assets/slack-app-workspace.png)

Add the app to your desired Slack channel:
1. Open the target channel
2. Tag the app
3. Select "Add to channel"

![Add to channel](assets/add-to-channel.png)

## Step 4: Enable Grafana Alerting

1. Navigate to [Amazon Managed Grafana Console](console.aws.amazon.com/grafana/home)
2. Select your workspace
3. Go to "Workspace Configuration Options"
4. Enable "Grafana Alerting"

![Enable Grafana alerting](assets/enable_grafana_alerting.png)

## Step 5: Create Alert Rule

1. Select your data source and dashboard
2. Create a new alert rule:
   - Name: "GPU Health"
   - Query (for GPU health monitoring):
```promql
100 * count(
  DCGM_FI_DEV_GPU_UTIL unless 
  (DCGM_FI_DEV_XID_ERRORS > 0 or DCGM_FI_DEV_ECC_DBE_VOL_TOTAL > 0)
)
/
count(DCGM_FI_DEV_GPU_UTIL)
```

![gpu-health alert rule](assets/gpu-health-alert.png)


For this query, we want Grafana Alert to fire when the query threshold is below 100%, meaning not all GPUs are reporting healthy from the above query. Select preview to preview this alert rule.

![alert threshold](assets/alert-threshold.png)

Create a new folder, lets call it "slack alerts", and add a new evaluation period. For this "GPU health" rule, we will use default of 5 min. 

![eval threshold](assets/eval-threshold.png)

## Step 6: Configure Contact Point in Grafana

1. Navigate to **Alerts** -> **Alerting** -> **Contact points**
2. Click **+ Add contact point**
3. Configure the following settings:
   - Enter a contact point name (e.g., "Slack-GPU-Alerts")
   - From the Integration list, select **Slack**
   - For Slack API token configuration:
     - In **Recipient** field: Enter your channel ID
     - In **Token** field: Enter the Bot User OAuth Token (starts with "xoxb-")
   - For Webhook configuration:
     - In **Webhook** field: Enter your Slack app Webhook URL

![Configure contact point](assets/configure-contact-point.png)

## Step 7: Test Alert Configuration

1. Click **Test** to verify your integration
2. You should see a test message appear in your configured Slack channel

![Alert Test](assets/alert-test.png)

3. To trigger a real alert, you can temporarily modify the alert threshold to below 100%

![Alert Firing](assets/alert-firing.png)

## Next Steps

Congratulations! You have successfully configured Slack alerts for GPU health monitoring. Consider setting up additional alert rules for:

- File System Utilization (>100%)
- GPU Thermal Throttling Errors
- CPU Usage (100% for extended periods)
- Memory Usage thresholds
- Network performance metrics

These alerts will help you maintain optimal performance of your GPU cluster and prevent potential issues before they impact your workloads.

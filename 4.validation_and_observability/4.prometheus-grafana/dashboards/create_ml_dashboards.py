#!/usr/bin/env python3

import boto3
from grafana_client import GrafanaApi, HeaderAuth, TokenAuth
from grafanalib._gen import DashboardEncoder
from grafanalib.core import Dashboard
import json
from typing import Dict
import urllib.request

from grafana_client.knowledge import datasource_factory
from grafana_client.model import DatasourceModel

import os

PROM_DASHBOARDS_URL = [
    'https://grafana.com/api/dashboards/12239/revisions/latest/download',
    'https://grafana.com/api/dashboards/1860/revisions/latest/download',
    'https://grafana.com/api/dashboards/20579/revisions/latest/download'
]


def create_prometheus_datasource(grafana, url, aws_region):
    jsonData = {
        'sigV4Auth': True,
        'sigV4AuthType': 'ec2_iam_role',
        'sigV4Region': aws_region,
        'httpMethod': 'GET'
    }

    datasource = DatasourceModel(name="Prometheus",
                                 type="prometheus",
                                 url=url,
                                 access="proxy",
                                 jsonData=jsonData)
    datasource = datasource_factory(datasource)
    datasource = datasource.asdict()
    datasource = grafana.datasource.create_datasource(datasource)["datasource"]
    r = grafana.datasource.health(datasource['uid'])
    return datasource


def encode_dashboard(entity) -> Dict:
    """
	Encode grafanalib `Dashboard` entity to dictionary.

	TODO: Optimize without going through JSON marshalling.
	"""
    return json.loads(json.dumps(entity, sort_keys=True, cls=DashboardEncoder))


def mk_dash(datasource_uid, url):
    url = urllib.request.urlopen(url)
    dashboard = json.load(url)
    for i in dashboard['panels']:
        i["datasource"] = {"type": "prometheus", "uid": datasource_uid}

    for i in dashboard['templating']['list']:
        i["datasource"] = {"type": "prometheus", "uid": datasource_uid}

    return {"dashboard": dashboard, "overwrite": True}


def lambda_handler(event, context):
    aws_region = os.environ['REGION']
    grafana_key_name = "CreateDashboards"
    grafana_url = os.environ['GRAFANA_WORKSPACE_URL']
    workspace_id = os.environ['GRAFANA_WORKSPACE_ID']
    prometheus_url = os.environ['PROMETHEUS_URL']

    client = boto3.client('grafana')
    response = client.create_workspace_api_key(keyName=grafana_key_name,
                                               keyRole='ADMIN',
                                               secondsToLive=60,
                                               workspaceId=workspace_id)

    try:
        grafana = GrafanaApi.from_url(
            url=grafana_url,
            credential=TokenAuth(token=response['key']),
        )

        prometheus_datasource = create_prometheus_datasource(
            grafana, prometheus_url, aws_region)

        for i in PROM_DASHBOARDS_URL:
            dashboard_payload = mk_dash(prometheus_datasource['uid'], i)
            response = grafana.dashboard.update_dashboard(dashboard_payload)

    except Exception as e:
        print(e)

    response = client.delete_workspace_api_key(keyName=grafana_key_name,
                                               workspaceId=workspace_id)


def main():
    aws_region = 'ap-southeast-2'
    grafana_key_name = "CreateDashpa01"
    grafana_url = 'https://g-182a00efff.grafana-workspace.ap-southeast-2.amazonaws.com'
    workspace_id = 'g-182a00efff'
    prometheus_url = 'https://aps-workspaces.ap-southeast-2.amazonaws.com/workspaces/ws-e4384558-d586-46ec-bd12-173d7019119e/'

    client = boto3.client('grafana')
    response = client.create_workspace_api_key(keyName=grafana_key_name,
                                               keyRole='ADMIN',
                                               secondsToLive=60,
                                               workspaceId=workspace_id)

    try:
        grafana = GrafanaApi.from_url(
            url=grafana_url,
            credential=TokenAuth(token=response['key']),
        )

        prometheus_datasource = create_prometheus_datasource(
            grafana, prometheus_url, aws_region)

        for i in PROM_DASHBOARDS_URL:
            dashboard_payload = mk_dash(prometheus_datasource['uid'], i)
            response = grafana.dashboard.update_dashboard(dashboard_payload)

    except Exception as e:
        print(e)

    response = client.delete_workspace_api_key(keyName=grafana_key_name,
                                               workspaceId=workspace_id)


if __name__ == '__main__':
    main()
#!/usr/bin/env bash
. config.env

set_options
pcluster ssh --region ${REGION} --dry-run --cluster-name pcluster-${NAME}
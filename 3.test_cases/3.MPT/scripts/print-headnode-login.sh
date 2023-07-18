#!/usr/bin/env bash
. config.env

set_options
pcluster ssh --region ${REGION} --cluster-name pcluster-${NAME} -i ~/.ssh/${SSH_KEY} --dryrun True
#!/usr/bin/env bash
. config.env
set_options
run docker build -t llm-foundry .
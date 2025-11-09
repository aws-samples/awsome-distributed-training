#!/bin/bash

./ray-expose.sh

# Check if the submission_id is passed as an argument
if [ -z "$1" ]; then
    echo "Error: No submission_id provided."
    echo "Usage: ./job-status.sh <submission_id>"
    echo "List of jobs to choose from:"
    echo ""
    ray job list --address http://localhost:8266 | sed -n "s/.*submission_id='\([^']*\)'.*entrypoint='\([^']*\)'.*/submission_id: \1, entrypoint: \2/p"
    echo -e "\n"
    exit 1
fi

# Assign the user's input to a variable
submission_id=$(ray job list --address http://localhost:8266 | sed -n "s/.*submission_id='\([^']*\)'.*entrypoint='\([^']*\)'.*/submission_id: \1, entrypoint: \2/p" | grep $1 | head -n 1 | cut -d ' ' -f 2 | cut -d ',' -f 1)

# submission_id=$1

CMD="ray job stop --address http://localhost:8266 $submission_id"

if [ ! "$VERBOSE" == "false" ]; then echo -e "\n${CMD}\n"; fi
eval "$CMD"

echo -e "\n"
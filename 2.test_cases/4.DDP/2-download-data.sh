#!/bin/bash

mkdir data
cd data

echo ""
echo "Downloading Deep Phenotyping PMBC Image Set Data ..."
wget https://www.research-collection.ethz.ch/bitstream/handle/20.500.11850/343106/DeepPhenotype_PBMC_ImageSet_YSeverin.zip
unzip DeepPhenotype_PBMC_ImageSet_YSeverin.zip -d ./data

rm DeepPhenotype_PBMC_ImageSet_YSeverin.zip

# Make S3 bucket
aws s3 mb s3://pcluster-ml-workshop

# Upload Data to S3
aws s3 cp ./data s3://pcluster-ml-workshop/ --recursive

import os
import sys
import timeit


from pyspark.sql import SparkSession
from pyspark.sql.types import *
spark = SparkSession.builder.getOrCreate()
spark.sparkContext.setLogLevel("WARN")

CORE_schema=StructType([
    StructField('abstract', StringType(), True), 
    StructField('authors', ArrayType(StringType(), True), True), 
    StructField('contributors', ArrayType(StringType(), True), True), 
    StructField('coreId', StringType(), True), 
    StructField('datePublished', StringType(), True), 
    StructField('doi', StringType(), True), 
    StructField('downloadUrl', StringType(), True), 
    StructField('enrichments', 
                StructType([
                    StructField('citationCount', StringType(), True), 
                    StructField('documentType', 
                                StructType([
                                    StructField('confidence', StringType(), True), 
                                    StructField('type', StringType(), True)]), True), 
                                    StructField('references', ArrayType(StringType(), True), True)]), True), 
    StructField('fullText', StringType(), True), 
    StructField('fullTextIdentifier', StringType(), True), 
    StructField('identifiers', ArrayType(StringType(), True), True), 
    StructField('issn', StringType(), True), 
    StructField('journals', ArrayType(StringType(), True), True), 
    StructField('language', 
                StructType([StructField('code', StringType(), True), 
                            StructField('id', LongType(), True), 
                            StructField('name', StringType(), True)]), 
                True), 
    StructField('magId', StringType(), True), 
    StructField('oai', StringType(), True), 
    StructField('pdfHashValue', StringType(), True), 
    StructField('publisher', StringType(), True), 
    StructField('relations', ArrayType(StringType(), True), True), 
    StructField('subjects', ArrayType(StringType(), True), True), 
    StructField('title', StringType(), True), 
    StructField('topics', ArrayType(StringType(), True), True), 
    StructField('urls', ArrayType(StringType(), True), True), 
    StructField('year', LongType(), True)])

#df = spark.read.option("multiline","true").json("core-EN", schema=CORE_schema)
df = spark.read.json("core-EN", schema=CORE_schema)
print("Number of rows: {}".format(df.count()))

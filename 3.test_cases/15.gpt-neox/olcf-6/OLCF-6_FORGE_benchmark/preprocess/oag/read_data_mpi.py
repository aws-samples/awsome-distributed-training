import jsonlines as jl
import json
from mpi4py import MPI
import sys
import os

comm = MPI.COMM_WORLD
rank = comm.Get_rank()

#def list_files(root_dir):


count = 0
total = 0
abstract = 0
abstract_buffer = []
if not os.path.isfile("mag/mag_papers_" + str(rank) + ".txt"):
    exit()

json_writer = jl.open("cleandata/mag_abstracts_" + str(rank) + ".json", mode="w")
err_count = 0

with jl.open("mag/mag_papers_" + str(rank) + ".txt") as reader:
    for obj in reader:
        if "indexed_abstract" in obj.keys():
            abstract += 1
            if abstract % 2000 == 0:
                #print("Writing 2000 objects")
                json_writer.write_all(abstract_buffer)
                abstract_buffer = []
            try:
                plain_text = json.loads(obj["indexed_abstract"])
                plain_text = " ".join(plain_text["InvertedIndex"].keys())
                abstract_buffer.append({"id" : obj["id"], "title": obj["title"], "abstract" : plain_text})
            except:
                err_count += 1
        total += 1

json_writer.close()
print("Processing summary:", rank, total, abstract, err_count)

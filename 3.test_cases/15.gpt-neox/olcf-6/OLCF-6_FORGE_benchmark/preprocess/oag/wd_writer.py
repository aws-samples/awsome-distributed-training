import webdataset as wd
import jsonlines as jl
from tqdm import tqdm

paper_counter = {}
with open("paper_counter.csv", "r") as reader:
    for line in reader:
        tokens = line.split(",")
        paper_counter[tokens[0]] = int(tokens[1])


with wd.ShardWriter('./webdata_abstracts/part-%06d.tar', maxcount=10000, compress=True) as sink:
    for pid in range(42):
        obj_reader = jl.open("cleandata/mag_abstracts_" + str(pid) + ".json", 'r')
        count = 0
        paper = "mag_abstracts_" + str(pid) + ".json"
        for obj in tqdm(obj_reader, total=paper_counter[paper]):
            row_idx = count
            count += 1            
            paper_id = obj["id"]
            abstract = obj["abstract"]
            sink.write({
                '__key__': "%08d" % paper_id,
                'abstract': abstract 
            })
        obj_reader.close()

print(count)


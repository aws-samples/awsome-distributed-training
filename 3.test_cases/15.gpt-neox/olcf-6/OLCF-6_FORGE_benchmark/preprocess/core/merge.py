#
# process CORE dataset, make it ready for Spark 
#
# fwang2@ornl.gov
#

import tarfile
import os
import sys
import tempfile
import shutil
import json
import datetime
import logging
from multiprocessing import Pool
from langdetect import detect
import argparse

try:
    from tqdm import tqdm 
except:
    raise ImportError('Run -> module load miniconda3/python')
        

# logging.basicConfig(format='%(asctime)s:%(levelname)s:%(message)s', datefmt='%m/%d/%Y-%I:%M:%S',
#                     level=logging.INFO)


logging.basicConfig(format='%(process)d -> %(message)s', level=logging.INFO)
parser = argparse.ArgumentParser(prog="merge")
parser.add_argument("--input", dest="SRCDIR", default="core-2020-12-20", help="dataset source directory")
parser.add_argument("--output", dest="DESTDIR", default="core-EN", help="output destination")
parser.add_argument("--tmpdir", dest="TEMPDIR", default="core-tmpdir", help="temporary directory")
parser.add_argument("--poolsize", dest="POOLSIZE", type=int, default=16, help="the size of multiprocess poool")
parser.add_argument("--file", dest="SRCFILE", help="process a single tar.xz")
args = parser.parse_args()

DESTDIR = args.DESTDIR
TEMPDIR = args.TEMPDIR
SRCDIR = args.SRCDIR

# the following is a list of corrupted file found during the pre-processing
# 
EXCLUDE=[
    "1005.tar.xz",  "1251.tar.xz", "14979.tar.xz",  "172.tar.xz", "11646.tar.xz",
    "2394.tar.xz",  "3203.tar.xz", "340.tar.xz", "4843.tar.xz",  "57.tar.xz",
    "895.tar.xz", "10757.tar.xz" , "12776.tar.xz", "153.tar.xz", "201.tar.xz", 
    "2396.tar.xz", "3225.tar.xz", "3472.tar.xz", "548.tar.xz", "636.tar.xz",  
    "910.tar.xz", "10784.tar.xz", "13869.tar.xz", "15400.tar.xz",  "2042.tar.xz",
    "2612.tar.xz",  "3226.tar.xz",  "3641.tar.xz",  "5518.tar.xz", "7745.tar.xz",
    "964.tar.xz", "10821.tar.xz",  "14338.tar.xz",  "1720.tar.xz",  "2142.tar.xz",
    "292.tar.xz", "3376.tar.xz"  "380.tar.xz",  "5624.tar.xz", "893.tar.xz",  "983.tar.xz"]

def scantree(path):
    """Recursively yield DirEntry objects for given directory."""
    for entry in os.scandir(path):
        if entry.is_dir(follow_symlinks=False):
            yield from scantree(entry.path)  # see below for Python 2.x
        else:
            if entry.name.endswith(".json"):
                yield entry

def bytes_fmt(n):
    d = {'1mb': 1048576,
         '1gb': 1073741824,
         '1tb': 1099511627776}
    if n < d['1mb']:
        return "%.2f KiB" % (float(n) / 1024)

    if n < d['1gb']:
        return "%.2f MiB" % (float(n) / d['1mb'])

    if n < d['1tb']:
        return "%.2f GiB" % (float(n) / d['1gb'])

    return "%.2f TiB" % (float(n) / d['1tb'])

def do_tarfile(infile):
    basename = os.path.basename(infile).split(".")[0]
    outfile_full = os.path.join(DESTDIR, basename +".json")
    outfile_part = os.path.join(DESTDIR, basename +".part")
    tempdir = os.path.join(TEMPDIR, basename + "-tmp")
    os.makedirs(tempdir, exist_ok=True)

    if os.path.exists(outfile_full):
        logging.debug("Detect existing json: {}, moving on.".format(outfile_full))
        return 

    if os.path.exists(outfile_part):
        logging.info("Detect broken json: {}, delete and reprocess.".format(outfile_part))
        os.remove(outfile_part)

    file_size = os.path.getsize(infile)
    logging.info("Begin processing {}, {}".format(infile, bytes_fmt(file_size)))
    with tarfile.open(infile) as f, open(outfile_part, "w") as of:
        statusfile = os.path.join(tempdir, "_SUCCESS")
        if not os.path.exists(statusfile):        
            try:
                f.extractall(tempdir)
                with open(statusfile, "w") as empty:
                    pass
            except EOFError:
                logging.warning("EOFError, skipping {}".format(infile))
                return
            except Exception as ex:
                logging.warning("Extract error: {}, skipping {}".format(ex, infile))
                return  
            logging.info("Extracting {} is finished".format(infile))        
        else:
            logging.info("Detect existing extracted files: {}".format(tempdir))

        all_jsonfiles = []
        logging.info("Collecting json files from: {}".format(tempdir))
        for file in scantree(tempdir):
           all_jsonfiles.append(file)
        if len(all_jsonfiles) > 200000:
            all_jsonfiles = tqdm(all_jsonfiles)
        tot_cnt = len(all_jsonfiles); tot_keep = 0; tot_err = 0
        for item in all_jsonfiles:
            # for item in f.getmembers():
            #   if os.path.splitext(item.name)[1] == '.json':
            with open(item.path, "r") as jsonfile:
                js = jsonfile.read()
                jd = json.loads(js)
                try:
                    if jd['abstract'] is not None and detect(jd['abstract'])=='en':
                        tot_keep += 1
                        of.write(js+"\n")
                except Exception as ex:
                    tot_err += 1
                    #logging.warning("Lanuage Dection Error: {}, ref. {}".format(ex, item.name))

        logging.info("Finish {}: tot={}, keep={}, error={}.".format(infile, tot_cnt, tot_keep, tot_err))

    os.rename(outfile_part, outfile_full)

def check_valid(workitems):
    """ return a list of work items """
    valid = []

    for file in workitems:
        basename = os.path.basename(file).split(".")[0]
        outfile_full = os.path.join(DESTDIR, basename +".json")
        if not os.path.exists(outfile_full):
            valid.append(file)        

    return valid

if __name__ == '__main__':
    if not os.path.exists(DESTDIR):
        os.makedirs(DESTDIR)

    all_workitems = []

    logging.info("Analyzing the remaining work items ... ")
    if args.SRCFILE:
        do_tarfile(args.SRCFILE)
    else: # directory        
        for file in os.listdir(SRCDIR):
            if file.endswith(".xz"):
                file = os.path.join(SRCDIR, file)
                all_workitems.append(file)

    remain_items = check_valid(all_workitems)
    logging.info("Remaining work items: [{}] files.".format(len(remain_items)))
    # distribute

    with Pool(processes=args.POOLSIZE) as p:
        p.map(do_tarfile, remain_items)

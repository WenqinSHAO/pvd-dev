#!/usr/bin/python3
import subprocess
import json
import time
from filelock import FileLock, Timeout

OPER_DIR = "/tmp"
NEIGHBOURS_LOCK_FILE = OPER_DIR + "/neighbours.lock"
NEIGHBOURS_FILE = OPER_DIR + "/neighbours.json"
IP_DB = OPER_DIR + "/ips.json"

cur_neighbours = set()

def pipe_neighbours():
    result=subprocess.Popen(['ip', 'neighbor'], stdout=subprocess.PIPE).stdout.read()    
    resultStr=result.decode("ascii")
    neighbours = dict()
    # each neighbour is on a new line
    for neighbour in map(lambda x : x.split(), resultStr.split("\n")):
        if len(neighbour) < 5:
            continue
        # 10.0.2.2 dev enp0s3 lladdr 52:54:00:12:35:02 REACHABLE
        neighbours[neighbour[0]] = neighbour[4]

    return neighbours

def read_neighbours():
    lock = FileLock(NEIGHBOURS_LOCK_FILE, timeout=5)

    # Note, by having an empty result by default, we fail closed if there is an issue
    # reading the file. We could probably make this a little more elegant.
    result=list()
    try:
        with lock:
            result=json.load(open(NEIGHBOURS_FILE, "r"))
    except Timeout:
        print("Unable to aquite lock to read neighbour cache '%s'" % NEIGHBOURS_LOCK_FILE)
    except:
        print("Unable to read neighbour cache '%s'" % NEIGHBOURS_FILE)
    
    return set(map(lambda l : (l[0], l[1]), result)) 

def remove_ips(ips_to_remove):
    # fake database of ips allowed
    try:
        with open(IP_DB, "r+") as ip_db:
            existing_ips=set(json.load(ip_db))
            new_set = existing_ips - ips_to_remove
            ip_db.seek(0)
            ip_db.truncate()
            json.dump(list(new_set), ip_db)
    except FileNotFoundError:
        pass # if the file isn't there, it can't have anything in it!
    except json.decoder.JSONDecodeError:
        pass # file is corrupt. Sad.

while True:
    neighbours_to_process = read_neighbours()
    
    # a neighbour is only in both if the ip and mac are the same. So, we cover the following cases:
    # 1) It aged out/went away (in old, but not new)
    # 2) A new device has an IP that was there before (mac changed)
    # 3) The same device has a new IP (same mac, but IP changed)
    # 4) It's simply just new (in new, but not old)
    neighbours_to_remove = neighbours_to_process ^ cur_neighbours

    # we only care about the IPs, so extract them now. There may be duplicates, so
    # make it yet another set

    ips_to_remove = set([neighbour[0] for neighbour in neighbours_to_remove])
    if len(ips_to_remove) > 0:
        remove_ips(ips_to_remove)

    cur_neighbours = neighbours_to_process

    time.sleep(1)

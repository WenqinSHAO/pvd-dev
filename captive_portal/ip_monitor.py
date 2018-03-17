#!/usr/bin/python3
import subprocess
import json
from filelock import FileLock, Timeout

OPER_DIR = "/tmp"
NEIGHBOURS_LOCK_FILE = OPER_DIR + "/neighbours.lock"
NEIGHBOURS_FILE = OPER_DIR + "/neighbours.json"
DOWNSTREAM_IF="test_br"

def read_neighbours():
    result=subprocess.Popen(['ip', 'neighbor'], stdout=subprocess.PIPE).stdout.read()    
    resultStr=result.decode("ascii")
    neighbours = list()
    # each neighbour is on a new line
    for neighbour in map(lambda x : x.split(), resultStr.split("\n")):
        # if it doesn't match the format, or it isn't a neighbour we care about, skip it.
        if len(neighbour) < 5 or neighbour[2] != DOWNSTREAM_IF:
            continue
        # ip           device        mac
        # 10.0.2.2 dev enp0s3 lladdr 52:54:00:12:35:02 REACHABLE
        neighbours.append((neighbour[0], neighbour[4]))

    return neighbours

import time
def write_neighbours(neighbours):
    jsonStr = json.dumps(neighbours) 
    lock = FileLock(NEIGHBOURS_LOCK_FILE, timeout=5)

    try:
        with lock:
            open(NEIGHBOURS_FILE, "w").write(jsonStr)
    except Timeout:
        print("Unable to aquite lock to update neighbour cache '%s'" % NEIGHBOURS_LOCK_FILE)
    except:
        print("Unable to write to neighbour cache '%s'" % NEIGHBOURS_FILE)


while True:
    write_neighbours(read_neighbours())
    time.sleep(1)

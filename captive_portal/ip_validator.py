#!/usr/bin/python3
import subprocess
import json
import time
from filelock import FileLock, Timeout

OPER_DIR = "/tmp"
NEIGHBOURS_LOCK_FILE = OPER_DIR + "/neighbours.lock"
NEIGHBOURS_FILE = OPER_DIR + "/neighbours.json"
IP_DB = OPER_DIR + "/ips.json"
REQUEST_LOCK_FILE = OPER_DIR + "/login_requests.lock"
REQUEST_FILE = OPER_DIR + "/login_requests.json"
DOWNSTREAM_IF="test_br"

cur_neighbours = set()

def build_allow_command(direction, interface, ip):
    ip_tables_cmd=['iptables',
                   '-I',
                   'FORWARD']
    if direction == "upstream":
        ip_tables_cmd.append("-i")
        ip_tables_cmd.append(interface)
        ip_tables_cmd.append("-s")
        ip_tables_cmd.append(ip)
    else:
        ip_tables_cmd.append("-o")
        ip_tables_cmd.append(interface)
        ip_tables_cmd.append("-d")
        ip_tables_cmd.append(ip)

    ip_tables_cmd.append("-j")
    ip_tables_cmd.append("ACCEPT")
    return ip_tables_cmd

def build_remove_command(direction, interface, ip):
    ip_tables_cmd=['iptables',
                   '-D',
                   'FORWARD']
    if direction == "upstream":
        ip_tables_cmd.append("-i")
        ip_tables_cmd.append(interface)
        ip_tables_cmd.append("-s")
        ip_tables_cmd.append(ip)
    else:
        ip_tables_cmd.append("-o")
        ip_tables_cmd.append(interface)
        ip_tables_cmd.append("-d")
        ip_tables_cmd.append(ip)

    ip_tables_cmd.append("-j")
    ip_tables_cmd.append("ACCEPT")
    return ip_tables_cmd

def allow_ip(ip):
    allow_up=build_allow_command("upstream", DOWNSTREAM_IF, ip);
    allow_down=build_allow_command("downstream", DOWNSTREAM_IF, ip);

    subprocess.Popen(allow_up, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    subprocess.Popen(allow_down, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

def remove_ip(ip):
    remove_up=build_remove_command("upstream", DOWNSTREAM_IF, ip);
    remove_down=build_remove_command("downstream", DOWNSTREAM_IF, ip);

    subprocess.Popen(remove_up, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    subprocess.Popen(remove_down, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

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
    for ip in ips_to_remove:
        remove_ip(ip)

def remove_stale_ips():
    global cur_neighbours

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

def allow_requests(request_list):
    for ip in request_list:
        allow_ip(ip)

def process_requests_unlocked():
    try:
        with open(REQUEST_FILE, "r+") as request_file:
            result = json.load(request_file)
            allow_requests(result)
            request_file.seek(0)
            request_file.truncate()
    except FileNotFoundError:
        print("File not found")
        pass # if the file isn't there, it can't have anything in it!
    except json.decoder.JSONDecodeError:
        pass # file is corrupt. Sad. Should probably do something to indicate
             # an error back to the requestor.

def process_requests():
    lock = FileLock(REQUEST_LOCK_FILE, timeout=1)

    try:
        with lock:
            process_requests_unlocked()
    except Timeout:
        print("Unable to aquite lock to read requests: '%s'" % REQUEST_LOCK_FILE)
    except:
        print("Unable to handle requests '%s'" % REQUEST_FILE)

while True:
    remove_stale_ips()
    process_requests()
    time.sleep(1)

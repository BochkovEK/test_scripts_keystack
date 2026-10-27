#!/usr/bin/env python3

# get pools for pub_net
# python3 ~/free_pools.py ebochkov-installer-v2-external

# set for pub_net subnet:
# openstack subnet set pub_net \
#   --no-allocation-pool \
#   --allocation-pool start=10.224.138.163,end=10.224.138.164 \
#   --allocation-pool start=10.224.138.166,end=10.224.138.167 \
#   --allocation-pool start=10.224.138.170,end=10.224.138.174 \
#   --allocation-pool start=10.224.138.176,end=10.224.138.177 \
#   --allocation-pool start=10.224.138.180,end=10.224.138.182 \
#   --allocation-pool start=10.224.138.184,end=10.224.138.185 \
#   --allocation-pool start=10.224.138.188,end=10.224.138.188 \
#   --allocation-pool start=10.224.138.190,end=10.224.138.190

import argparse, ipaddress as ip, json, subprocess

def osj(*a):
    return json.loads(subprocess.check_output(["openstack", *a, "-f", "json"]))

def toint(x): return int(ip.ip_address(x))

p = argparse.ArgumentParser()
p.add_argument("subnet", help="external subnet (name or ID)")
p.add_argument("--exclude", default="", help="additional occupied addresses separated by comma (configured on hosts, Neutron is unaware of them)")
p.add_argument("--inner", default="", help="check internal pools like a-b,c-d")
a = p.parse_args()

s = osj("subnet", "show", a.subnet)
sid, netid = s["id"], s["network_id"]

universe = set()
for pool in s["allocation_pools"]:
    universe |= set(range(toint(pool["start"]), toint(pool["end"]) + 1))

used = set()
if s.get("gateway_ip"):
    used.add(toint(s["gateway_ip"]))
for port in osj("port", "list", "--network", netid, "-c", "Fixed IP Addresses"):
    for f in port["Fixed IP Addresses"]:
        if f.get("subnet_id") == sid:
            used.add(toint(f["ip_address"]))
for x in filter(None, a.exclude.split(",")):
    used.add(toint(x.strip()))

frags = []
for x in sorted(universe - used):
    if frags and frags[-1][1] == x - 1: frags[-1][1] = x
    else: frags.append([x, x])

print(f"# external CIDR {s['cidr']}, occupied {len(used & universe)} out of {len(universe)}")
print("allocation_pools = [")
for lo, hi in frags:
    print(f'  {{ start = "{ip.ip_address(lo)}", end = "{ip.ip_address(hi)}" }},')
print("]")
print(f"# free addresses: {sum(h - l + 1 for l, h in frags)}")

if a.inner:
    bad = set()
    for part in a.inner.split(","):
        lo, hi = part.split("-")
        bad |= set(range(toint(lo), toint(hi) + 1)) & used
    print("\nCHECK inner:", "OK, no intersections" if not bad else
          "INTERSECTION: " + ", ".join(str(ip.ip_address(x)) for x in sorted(bad)))
"""Print the subnet plan for the library VPC: 10.20.0.0/16 cut into /24s."""
import ipaddress

vpc = ipaddress.ip_network("10.20.0.0/16")
print(f"VPC {vpc}: {vpc.num_addresses} addresses")
plan = {"public-a": 1, "public-b": 2, "private-a": 11, "private-b": 12}
subnets = list(vpc.subnets(new_prefix=24))
for name, idx in plan.items():
    net = subnets[idx]
    # AWS reserves 5 addresses in every subnet: network, router, DNS, future use, broadcast
    print(f"{name:10} {str(net):15} usable={net.num_addresses - 5:3}  first host={net[4]}  last={net[-2]}")

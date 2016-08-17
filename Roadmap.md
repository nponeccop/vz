# Long-term Vision

VZ strives to become a  management middleware for secure libertarian enterprise universal lightweight WAN clusters.

## Secure cluster

### Damage localization

There is a general secure design principle that once the system is compromised in one place, the design 
should prevent further spreading of the attack. It's easy to see that for example CoreOS Fleet is the opposite of that. 
If a single node is hacked the attacker gets the addresses of all other nodes in the cluster and can install arbitrary privileged malware 
everywhere.

### No management components to attack

Another principle is minimization of attack surface. All cluster management systems on the market expose the central 
manager and in many cases node management interface to the attacker. Think of buffer overflow or a vulnerable TLS implementation 
in CoreOS etcd, or attacks on centralized logging  server or monitoring/management agents on cluster nodes.

## Libertarian cluster

Basically it means a cluster resistant to shutdown by governments. Imagine something white-hat like 
WikiLeaks running multiple mirrors in a CoreOS cluster. Once one node is discovered and imaged by FBI, all the nodes can 
be discovered, imaged and shut down by confiscation orders to respective providers.

Note that this is essentially just strenghtening of the Damage Localization principle. It is not purely anti-government feature
which many may regard as shady, but also serves damage localization for mainstream pro-government security-savvy enterprise users.

## WAN cluster

All the management software on the market is designed for contention and latency-free datacenters and fails miserably when
failover consensus protocols or even message queues are run over WAN. And these days WAN distribution is essential for disaster
recovery and high availability. Think of a web site running in different Amazon datacenters, or availability zones in their parlance.

## Enterprise Cluster

### Stability over Cutting Edge

For enterprises stability is important, so they run software commonly considered outdated, such as CentOS 6 and even 5, and their
RHEL flavours. This prevents them from using modern technologies such as Docker and other LXC-based containers.

### Fixed Dictated Platforms

### Wide-scale Automated Management



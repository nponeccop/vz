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

## Enterprise Cluster

### Stability over Cutting Edge

For enterprises stability is important, so they run software commonly considered outdated, such as CentOS 6 and even 5, and their
RHEL flavours. This generally prevents them from using modern technologies such as Docker and other LXC-based containers, but once stable and widely approved, features get backported.

### Fixed Dictated Platforms

We can't force an enterprise to change the platform it has been running. For example, we can't invent our own distribution of Linux, or can't drop support for hypervisors and architectures considered exotic by the open-source community, such as 32-bit systems, VMware ESXi, Citrix XenServer, Microsoft Hyper-V.

### Wide-scale Automated Management

Enterpises typically deploy some form of automated management (e.g. configuration management). So we can't just drop their solution and invent our own management framework, but must piggyback on what they have. 

### Legacy, RedHat, Microsoft-friendly

They may go as far (in the eyes of Linux/GNU fanboys) as using Microsoft OMI to control their RHEL installations from Microsoft SysCenter. OpenPegasus mentions OpenVMS (a non-UNIX OS) in the list of supported systems etc. 

### High Chances of Acquisition

In the long run we want to become a part of central management portfolio of an enterprise vendor such as HPE, Oracle or RedHat.

## Universal Lightweight Cluster

### Lightweight Management

### Weak Containers for LTS Versions of Linux

## WAN cluster

All the management software on the market is designed for contention and latency-free datacenters and fails miserably when
failover consensus protocols or even message queues are run over WAN. And these days WAN distribution is essential for disaster
recovery and high availability. Think of a web site running in different Amazon datacenters, or availability zones in their parlance.


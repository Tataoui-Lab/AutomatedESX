### ESXi Kickstart Script
### Hostname: NA
### Author: Dominic Chan
### Date: 2020-10-17
### Tested Patform Version: ESXi 6.7U3 and ESXi 7.0
### ESX Installation Use Case - Boot Menu Option 1
###	IP Addressing	- Static
###	Switch Type	- VSS
###	
### Addressed by Kickstart
###	Typical Kickstart - Clear Partition, Install to USB, Static IP / DNS assignment on vmk0, root password
###	Post Installation
###	  - Disable annoying first time CEIP pop-up
###	  - Add ESX local account
###	  - Enable local users to have full access to DCUI even if they don't have admin permssions on ESXi host
###	  - Enable & start SSH
###	  - Disable & stop ESXi Shell (TSM)
###	  - ESXi Shell interactive idle time logout
###	  - Suppress ESXi Shell warning
###	  - Copy SSH authorized keys & overwrite existing
###	  - NTP configuration
###	  - Set NTP to auto start
###	  - vSwitch configuration
###	     -- Creation
###	     -- Setting MTU and CDP
###	     -- Attach Uplinks
###	     -- Attach portgroups
###	     -- Configure NIC teaming
###	     -- Configure Load Balancing and failover
###	     -- Configure security
###	     -- Set traffic shaping
###	     -- VMKernel traffic tagging - (Future)
###	     -- Set VMkernal routes - (Future)
###	  - Disable IPV6
###	  - Enable ESX firewall and set firewall rules
###	  - Create local VM datastore - (edit require based on hardware)
###	  - Mount NFS datastore - (Future)
###	  - Advance NFS configuration (tweak)
###	  - Advance network configuration (tweak)
###	  - Syslog Configuration and rotation
###	  - Set shared VMTools location
###	  - Redirect Scatch Disk
###	  - Set Network Coredump location to VCSA
###	  - Assign VMware license
###	  - Enable maintaince mode

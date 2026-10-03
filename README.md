# Terraform_Testing

I want to test deployments using Terraform to multiple platforms. 

The basic setup is a RHEL 9 server with multiple disks attached. I am also testing methods to setup the disks per vendor standards using a [cloud-init](https://cloud-init.io/) script. 

## Current Test Platforms

[AWS](./AWS/)  
- AWS is the largest vendor in this space and has the most options when deploying infrastructure. 
- Getting the disk volume id from the OS and matching it to what is shown as deployed is a nice feature. 
    - use this command from the OS to the the AWS VolumeID: `lsblk -o +serial |sed s/vol/vol\-/g` 

[Azure](./Azure/)  
- Most large orgainzations already use Microsoft products and might want to use Azure for their cloud platform.
- I found it difficult to align disk volumes from the OS to what is shown by Azure for NVME devices.
    - This may have changed since the last time I used this service. 

**Others will be added as they are tested.**

## Terraform Code

I chose to use Terraform for these project to allow me to quickly deploy and teardown test devices.  Microsoft's Bicep IaC would allow me to quickly deploy devices but then required that I use the console or command line to remove them. 

The HCL language is used for setting up the `main.tf` files, but the syntax and usage of the language between providers isn't fully consistent.  Having written the code for Azure it was not a simple copy to the AWS platform.  

To maintain behavior of how disks are attached the the VM's, allowing the cloud-init script to work, I had to add a `depends_on` code to the attach section for the disks I'm creating.  I found that deploying the infrastructure was inconsistent until I added this feature. 

I also had to add a `lifecycle` block to some resources with a `ignore_changes` section for testing increases in disk performance and capacity.  Otherwise this would break the state of the system. 

## Cloud-Init

I had attempted to use cloud config on the AWS platform but found that some configuration items were not available.  The cloud-init script was developed to try and simplify setup issues our team was seeing consistently.  

In my testing I found that AWS and Azure use different method for naming NVME devices. AWS will change the digit after `nvme[3-6]n1` where Azure will change it at the end `nvme0n[4-7]`. This may change in the future and updates will need to be made as needed. 


[Start Page](./README.md)  
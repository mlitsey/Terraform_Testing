# AWS testing zone

# Table Of Contents
[AWS CLI](#install-aws-cli)  
[Terraform](#terraform)  



# Install AWS cli

[LINK](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)  

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
which aws
aws --version

# login with root credentials or create IAM account and setup access key
aws login

aws configure set region <NEW_REGION>
```

Setup AWS cli
[LINK](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-quickstart.html)  

```bash
aws login

# IAM SSO
aws configure sso

# others 
```

# Terraform
```bash
aws configure list
aws configure list-profiles
export AWS_PROFILE=<your-profile-name>

# or create access keys in the aws portal and set them on .bashrc
AWS_ACCESS_KEY_ID="<id goes here>"
AWS_SECRET_ACCESS_KEY="<key goes here>"
AWS_DEFAULT_REGION=us-east-2
source ~/.bashrc

```

# import ssh key to different regions

```bash
aws ec2 import-key-pair \
    --key-name epicadmin \
    --public-key-material fileb://epicadmin.pub \
    --region us-east-1

aws ec2 import-key-pair \
    --key-name epicadmin \
    --public-key-material fileb://epicadmin.pub \
    --region us-west-2
```
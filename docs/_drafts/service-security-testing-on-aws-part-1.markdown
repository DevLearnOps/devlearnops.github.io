---
layout: post
title:  "Embracing Chaos Week: Real World Chaos Engineering for Resilient Services on AWS"
description: |
    todo> add SEO description metatag
date:   2023-05-30
categories: "chaos-engineering"
tags: chaos-engineering chaostoolkit aws
author: "Manuel Castellin"
# permalink: "/mastering-chaostoolkit-experiment-configuration"
excerpt: ""
---

## 1. Overview

Welcome to the "Embracing Chaos" week - a week of content here on [DevLearnOps](/) completely dedicated to helping you create and deploy a real-world chaos engineering experiment on AWS to improve service resiliency.

This is the first of many theme based weeks that take a deeper dive into topics that are relevant to Chaos Engineering. This series will help you dip your toe into the water and work on a real-world chaos engineering experiment that you can then implement in your own projects.

### Here's what we'll cover in this series

* Create and deploy a test infrastructure on AWS using Terraform
* How to design a chaos engineering experiment to verify service ingress security
* Automate test resources creation using chaostoolkit and terraform
* Deploy and run your chaos experiment with AWS Batch
* Automate the experiment execution to check every service deployment


## 2. Introduction

Chaos engineering is an innovative discipline that advocates for intentionally introducing controlled failures and disruptions into systems to identify weaknesses and improve their overall resilience. By simulating real-world scenarios, chaos engineering allows engineers to gain valuable insights into system behavior, identify points of failure, and ultimately build more resilient and reliable architectures.




The infrastructure and the experiment verification

Install prerequisites, chaos terraform docker


## Create The VPC With Terraform

To deploy any application on AWS we first need to setup a Virtual Private Cloud (or VPC) to provide
the necessary networking infrastructure that will host our services.

Luckily, since we're using Terraform we can create all the necessary resources by using the **terraform-aws-modules/vpc**. This is part of a larger collection of modules called [terraform-aws-modules](https://registry.terraform.io/namespaces/terraform-aws-modules){:target="_blank"} available in the Terraform registry that can help you setup complex infrastructures with just a few lines of code.

We'll create a new directory to store the Terraform code for the networking infrastructure called `0-networking`, and create a new file `main.tf`:

```shell
mkdir 0-networking
touch 0-networking/main.tf
```

To define new infrastructure we need to create modules. A module in Terraform is any directory containing one or more `*.tf` files that define resources we want Terraform to create.

We'll start by adding the following content to the **0-networking/main.tf** file:

```terraform
# 0-networking/main.tf

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.37"
    }
  }
}

provider "aws" {
  default_tags {
    tags = {
      Project = "EmbracingChaosWeek"
    }
  }
}

data "aws_availability_zones" "available" {}

locals {
  name     = "embracing-chaos"
  vpc_cidr = "10.0.0.0/16"
  num_azs  = 2
  azs      = slice(data.aws_availability_zones.available.names, 0, local.num_azs)
}

#############################################################
# Create the VPC                                            #
#############################################################
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 4)]

  single_nat_gateway = true
  enable_nat_gateway = true
}

#############################################################
# Save VPC information in SSM parameters                    #
#############################################################
resource "aws_ssm_parameter" "vpc_id" {
  name  = "/vpc/id"
  value = module.vpc.vpc_id
  type  = "String"
}
resource "aws_ssm_parameter" "public_subnets" {
  name  = "/vpc/public_subnets"
  value = join(",", module.vpc.public_subnets)
  type  = "StringList"
}
resource "aws_ssm_parameter" "private_subnets" {
  name  = "/vpc/private_subnets"
  value = join(",", module.vpc.private_subnets)
  type  = "StringList"
}
```

This template will allow us to deploy a new VPC into our AWS account and store some parameters in *AWS Systems Manager* so that we can reference them later to deploy the service cluster.

### Deploy the networking stack

Now that our networking template is ready, let's deploy the VPC in AWS using Terraform.

Before we start running Terraform commands we need to set some context for the deployment as we haven't specified a default region in the template:

```shell
export AWS_DEFAULT_REGION=us-east-1
```

| If you have stored your AWS credentials using an aws-cli profile other than default, you also need to set the **AWS_PROFILE** environment variable with `export AWS_PROFILE="<profile_name>"`

To deploy the networking infrastructure with Terraform we move into the *networking* directory and run the following commands:

```shell
cd 0-networking/
terraform init
```

The `terraform init` command is responsible for downloading all the necessary modules and providers that we used in the infrastructure template. We need to run *init* the first time we deploy the infrastructure module or if we modify the template using additional modules, though, it doesn't hurt even if you run it every time.

We're now ready to create the infrastructure:

```shell
terraform apply
# Plan: 19 to add, 0 to change, 0 to destroy.
# 
# Do you want to perform these actions?
#   Terraform will perform the actions described above.
#   Only 'yes' will be accepted to approve.
# 
#   Enter a value: yes
```

With the `apply` command, Terraform will analyse your current resources on AWS and plan what changes needs to be applied to match the state described in the template.
In this case I don't have any resource yet, so the plan will add 19 new resources.

When asked, reply **yes** to tell Terraform to go ahead and create the resources. Creating the VPC and subnets will take a few minutes, in the meantime, let's move on and deploy a test application.

## Create And Deploy a Test Service on ECS

Naturally, if we want to create a chaos experiment we need a service to play with. We'll now create and deploy a new Python application on Amazon ECS (Elastic Container Service). Let's start by creating a new directory for the application:

```shell
mkdir 1-service/
cd 1-service/
```

### 1. Create the application

We'll now build a minimal Python application to serve some HTML content. Create a new file called `app.py` and add the following:

```python
# 1-service/app.py

from starlette.applications import Starlette
from starlette.responses import Response
from starlette.routing import Route


async def homepage(request):
    html = """<html>
    <body> <h1>Let's do some chaos!</h1> </body>
    </html>"""
    return Response(html, media_type="text/html")


app = Starlette(
    debug=True,
    routes=[
        Route("/", homepage),
    ],
)
```

And then create a `Dockerfile` to package up our application in a container:

```Dockerfile
# 1-service/Dockerfile

FROM python:3.11

RUN pip3 install -U \
    uvicorn requests starlette structlog

WORKDIR /app
COPY app.py .
EXPOSE 8000

CMD ["uvicorn", "--port", "8000", "--host", "0.0.0.0", "app:app"]
```

To test if the application works correctly, let's build and run the container:

```shell
cd 1-service/
docker build -t hello-chaos .
docker run -p 8000:8000 hello-chaos
# ...
# INFO:     Application startup complete.
# INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
```

### 2. Build and push the application to AWS Container Registry

```shell
docker build -t hello-chaos:v1 --platform linux/amd64 .

export AWS_DEFAULT_REGION="us-east-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
export ECR_REPO_NAME=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/hello-chaos

aws ecr create-repository --repository-name "hello-chaos"

docker tag hello-chaos:v1 $ECR_REPO_NAME:v1

aws ecr get-login-password --region $AWS_DEFAULT_REGION \
    | docker login --username AWS \
    --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com

docker push $ECR_REPO_NAME:v1
```

### 3. Deploy the application to Amazon ECS

## Create The Experiment Structure

```shell
APP_URL=$(terraform -chdir=../1-service output -raw app_url)
chaos run \
    --var "app_url=${APP_URL}" \
    check-service.yaml
```

## Conclusion

In this article, we looked at ...

As always, all examples used in this post and more are available
<a href="https://github.com/DevLearnOps/tutorials/tree/main/chaos-engineering/" target="_blank">over on GitHub</a>

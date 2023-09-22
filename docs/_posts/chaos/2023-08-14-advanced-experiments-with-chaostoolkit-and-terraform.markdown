---
layout: post
title:  "Orchestrating Advanced Experiments with ChaosToolkit and Terraform"
description: >-
    Learn how to use the chaostoolkit-terraform extension to create advanced chaos experiments.
date:   2023-08-14
categories: "chaos-engineering"
tags: chaos-engineering chaostoolkit terraform
author: "Manuel Castellin"
permalink: "/advanced-experiments-with-chaostoolkit-and-terraform"
excerpt: >-
    Learn how to use the chaostoolkit-terraform extension to create advanced chaos experiments that require supporting infrastructure resources.
---

## 1. Overview

In this article, we'll learn how to use the **chaostoolkit-terraform** extension to deploy supporting resources for our chaos experiments.

Most people, myself included, learned about Chaos Engineering from some article online talking about tech giants like Netflix or Google building reliable services by randomly terminating
instances on their production accounts.

This sounds simple enough, but as soon as you dig a bit deeper, you'll find that orchestrating an experiment
often requires a lot more thought, planning and preparation.

**One key aspect of running advanced experiments against live systems is creating and maintaining supporting resources for chaotic events**. These resources could be, for instance, HTTP proxies to simulate faulty network connections, an EC2 instance that generates synthetic user traffic or even a whole replica of a service.


## 2. ChaosToolkit + Terraform = ❤️

Tools like [Terraform][]{:target="_blank"} are designed specifically for this purpose: **create and maintain infrastructure resources using code**.

The [chaostoolkit-terraform][]{:target="_blank"} module allows us to extend Chaos Toolkit's functionality by deploying an infrastructure template at the start
of the experiment and tear it down after it is finished.

This feature is helpful in many scenarios. To name a few:

#### Create supporting resources for the experiment

Like deploying an HTTP proxy that sits between two services and simulate all kinds of network conditions or spin up an instance that simulates users load.

Being able to create resources before an experiment execution opens up many possibilities.

#### Replicate existing resources before fault injection

Services and resources on production accounts are not always safe to attack with chaos experiments, especially if we simulate destructive actions like deleting databases or storage volumes.

**If data loss is not an acceptable side-effect for your experiment, how about attacking a replica?** Often, you can validate the experiment hypothesis just as well by experimenting
on a copy.

#### Deploy a "control group" to measure the effects of an attack

The use of a **control group** is a pillar of [the scientific method][]{:target="_blank"}. Researchers use them to test the effectiveness of new drugs by administering treatments to a subset of the population called the *experimental group* and a placebo to a second subset called the *control group*.

In chaos engineering, we can employ the same strategy by deploying two copies of the same resource and only injecting faults into one of them. We can then measure how the chaos variable affects our system by comparing the differences between the experimental and control group.


## 3. Benefits

It's true, you don't need fancy plugins to create some resources for experiments. We could do it manually if it's just a one-off use like for a Chaos Game Day, or deploy them once with the rest of the infrastructure and never destroy them.

Though, I firmly believe there are several benefits in using **chaostoolkit-terraform** to manage resource creation in the context of the experiment instead:

* **Cost saving**: supporting resources only exist for the duration of the experiment to minimize infrastructure cost
* **Security**: chaos experiments often need higher privileges to be able to introduce faults. Imagine the damage a hacker could do if we leave those resources around!
* **Reusability**: if the organization already uses Terraform, we can reuse existing modules and share the new ones we create, speeding up development
* **Zero touch operations**: no human interaction is necessary to run experiments. Verifications are truly repeatable and with no human error.

<div class="cta-placeholder"></div>


## 4. How To Manage Resources With ChaosToolkit-Terraform

We'll now learn how to use the **chaostoolkit-terraform** module to deploy the resources we need for our chaos experiments automatically.

In this example, we'll create an experiment to verify that a Docker container always restarts upon failure if the `restart=always` option is set.

First, let's define the chaos experiment in Chaos Toolkit. Create a new file called **experiment.yaml** with the following content:


```yaml
# ./experiment.yaml

title: Container restart policy
description: >-
  Verify that a Docker container running with a restart policy set to `always`
  will automatically restart every time the container fails.

steady-state-hypothesis:
  title: "service-is-running"
  probes:
    - name: "nginx-is-running"
      type: probe
      tolerance: 200
      provider:
        type: http
        url: "http://localhost:8080"
        method: "GET"
        timeout: 2

method:
  - name: "terminate-nginx"
    type: action
    provider:
      type: process
      path: "docker"
      arguments: "exec webserver nginx -s quit"
    pauses:
      # Allow 5 seconds for the service to recover
      after: 5
```

For now, the experiment template defines a hypothesis and a method.

The hypothesis verification has one probe to check the Nginx service running in the container is responding with a status code `200`. The experiment method introduces a fault for a container called **webserver** using the `nginx -s quit` command.

To test the experiment is working as expected, we now create the **webserver** container in Docker with the restart policy using the following command:

```shell
docker run -d --name webserver -p 8080:80 --restart=always nginx:latest
```

And run the chaos experiment:

```shell
chaos run experiment.yaml
# ...
# [INFO] Playing your experiment's method now...
# [INFO] Action: terminate-nginx
# [INFO] Pausing after activity for 5s...
# [INFO] Steady state hypothesis: service-is-running
# [INFO] Probe: nginx-is-running
# [INFO] Steady state hypothesis is met!
# [INFO] Experiment ended with status: completed
```

Nice! Now that the experiment is working correctly, let's clean up the *webserver* container and use Terraform to create it instead:

```shell
docker stop webserver
docker rm webserver
```

## 5. Define Infrastructure Using Terraform

We'll now create a new Terraform template to run the *webserver* container for us before the experiment starts.

Let's create a new file called `main.tf` and add the following infrastructure code:

```terraform
# ./main.tf

terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "docker" {
  host = "unix:///var/run/docker.sock"
}

resource "docker_image" "nginx" {
  name = "nginx:latest"
}

resource "docker_container" "nginx" {
  image = docker_image.nginx.image_id
  name  = "webserver"

  restart = "always"

  ports {
    internal = 80
    external = 8080
  }
}
```

#### Docker Provider on Windows

Unfortunately, if you are trying to replicate this experiment on Windows, the `unix:///var/run/docker.sock` socket will not be available.

No worries, though. You can still use the Docker provider with the TCP connection. You just need to follow a couple of additional steps.

First, we need to enable the *Expose daemon on tcp://localhost:2375 without TLS* option from the Docker configuration. Navigate to **Docker Settings > General**, enable the flag and click **Apply & Restart**.

![Enable tcp without TLS Docker](/assets/images/posts/intro-to-chaostoolkit-terraform-2.jpg)

Second, you must change the Docker provider definition in the **main.tf** file to use the TCP connection instead:

```terraform
# ./main.tf  on Windows

# ...
provider "docker" {
  host = "tcp://127.0.0.1:2375"
}
# ...
```

That's it! Now back to it.

### 5.1. Testing the Terraform code

Let's see if the infrastructure template works by applying it ourselves first.

Make sure your shell's working directory is in the same location as the *main.tf* file and run the following commands:

```shell
terraform init
terraform apply

# ...
# Plan: 2 to add, 0 to change, 0 to destroy.
#
# Do you want to perform these actions?
#   Terraform will perform the actions described above.
#   Only 'yes' will be accepted to approve.
# 
#   Enter a value: -> "yes"
```

When asked if we'd like to execute the plan, reply *yes*, and Terraform will spin up the **webserver** container for us.

We can verify the container is running with `docker ps`:

```shell
docker ps
# CONTAINER ID   CREATED         STATUS        PORTS                  NAMES
# 7fd585ed41d3   2 seconds ago   Up 1 second   0.0.0.0:8080->80/tcp   webserver
```

and if we navigate to `http://localhost:8080` we should see Nginx default homepage:

![Nginx homepage](/assets/images/posts/intro-to-chaostoolkit-terraform-1.jpg)

Next, we're going to let **chaostoolkit-terraform** handle resource creation for us, so let's remove the container we just created using Terraform:

```shell
terraform destroy
# ...
#   Enter a value: -> "yes"
```

## 6. Add The Chaosterraform Control

To use the `chaosterraform` control, we first need to install the **chaostoolkit-terraform** Python package:

```shell
pip install -U chaostoolkit-terraform
```

We'll now add the `chaosterraform` control to the experiment so that Chaos Toolkit will automatically apply the template we defined in **main.tf**.

**By default, the control will apply the template located in the same directory as the experiment file**. This behaviour can be changed, of course, but for now let's make sure our directory structure is like this:

```text
.
├── experiment.yaml
└── main.tf
```

To apply the control, modify the content of the experiment file and add a **controls** section:

```yaml
# ./experiment.yaml

...

controls:
  - name: chaosterraform
    provider:
      type: python
      module: chaosterraform.control
      arguments:
        silent: false

...
```

For demonstration, we also set the `silent: false` argument. This way we can see the output of Terraform commands being executed. This flag is not necessary to use the extension and we'll remove it later.

And to check everything is working as expected, let's rerun the experiment:

```shell
chaos run experiment.yaml
# ...
# [INFO] Terraform: creating required resources for experiment
# Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
#   + create
# 
# Terraform will perform the following actions:
# ...
# 
# [INFO] Experiment ended with status: completed
# [INFO] Terraform: removing experiment resources
# docker_image.nginx: Refreshing state... [id=sha256:ff78c7a65ec2b1fb09f58b27b0dd022ac1f4e16b9bcfe1cbdc18c36f2e0e1842nginx:latest]
# docker_container.nginx: Refreshing state... [id=495f616f70346c08b1607ffd22a65479cdd9d092c035ed7fcf1f3044686a8bcd]
# 
# Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
#   - destroy
# 
# Terraform will perform the following actions:
# ...
```

You'll notice the experiment execution now includes the output of two Terraform instructions: `terraform apply` and `terraform destroy`.

By adding the **chaosterraform** control to the template, ChaosToolkit will automatically create the experiment resources at the start and remove them once the experiment is finished.

## 7. Handle Terraform Inputs And Outputs

One major advantage of handling resource deployment with Terraform is reusing infrastructure code by creating modules. For that, we need to be able to
personalize our resources by defining input and output variables.

We'll now improve our experiment template and create a more polished version that accepts the following input variables: *container name*, *exposed port* and *restart policy*.

The first thing we need to do is modify the Terraform code. Let's create a new file **variables.tf** to define the module inputs:

```terraform
# ./variables.tf

variable "container_name" {
  description = "The name of the application container"
  type        = string
}

variable "exposed_port" {
  description = "The local port number to map for the application"
  type        = number
}

variable "restart_policy" {
  description = "(Optional) The container restart policy"
  type        = string
  default     = "no"
}
```

And now that we have some input variables let's use them in the **main.tf** Terraform file:

```terraform
# ./main.tf

# ...

resource "docker_container" "nginx" {
  image = docker_image.nginx.image_id
  name  = var.container_name     # <- use var

  restart = var.restart_policy   # <- use var

  ports {
    internal = 80
    external = var.exposed_port  # <- use var
  }
}
```

Great, all we need to do now is configure the **chaosterraform** control in the experiment and provide some values for these inputs:

```yaml
# ./experiment.yaml

...
controls:
  - name: chaosterraform
    provider:
      type: python
      module: chaosterraform.control
      arguments:
        variables:
          container_name: "webserver"
          exposed_port: 8080
          restart_policy: "always"
```

### 7.1. Read Terraform Outputs From Experiments

The **chaosterraform** control allows us to use exported outputs from the Terraform module like any other experiment variable.

By default, **the control will inject Terraform outputs into the Chaos Toolkit configuration using the same output name prefixed by** `tf_out__` (i.e. `tf_out__my_variable`).

To see this in action, let's add an output variable to our Terraform module. We create yet another file in the same directory called **outputs.tf** with the following content:

```terraform
# ./outputs.tf

output "application_url" {
  value = "http://127.0.0.1:${var.exposed_port}"
}
```

And finally, to use the output variable, we can modify the probe accordingly:

```yaml
# ./experiment.yaml

...
steady-state-hypothesis:
  title: "service-is-running"
  probes:
    - name: "nginx-is-running"
      type: probe
      tolerance: 200
      provider:
        type: http
        url: "${tf_out__application_url}" #  <- use Terraform output var
        method: "GET"
        timeout: 2
```

You can see the full example for both the experiment and Terraform module [over on GitHub][example]{:target="_blank"}.

## 8. Run The Final Experiment

Now that we polished up both our chaos experiment and Terraform module, your directory structure should look something like this:

```text
.
├── experiment.yaml
├── main.tf
├── outputs.tf
└── variables.tf
```

We can run the experiment as many times as we like and **chaosterraform** will handle resource *apply/destroy* for us:

```shell
chaos run experiment.yaml
# ...
# [INFO] Terraform: creating required resources for experiment
# [INFO] Terraform: reading configuration value for [application_url]
# ...
# [INFO] Terraform: removing experiment resources
```

Try to play around with the control inputs and, for example, change the *restart_policy* to `no`. If you do that, you'll end up with a deviated experiment, as the container will no longer auto-restart after the experiment method stops it.


## 9. Conclusion

In this article, we learned how to use Chaos Toolkit and Terraform to create supporting resources for chaos experiments automatically.

The [chaostoolkit-terraform][] module opens up many possibilities and helps us orchestrate complex experiments.

As always, you can find the working code example described in this article [over on GitHub][example]{:target="_blank"}.


[example]: https://github.com/DevLearnOps/tutorials/tree/main/chaos-engineering/advanced-experiments-with-chaostoolkit-and-terraform
[Terraform]: https://www.terraform.io/
[chaostoolkit-terraform]: https://pypi.org/project/chaostoolkit-terraform/
[the scientific method]: https://en.wikipedia.org/wiki/Scientific_method

---
layout: post
title:  "Controlled experiments with ChaosToolkit and Terraform"
description: |
    todo> add SEO description metatag
date:   2023-06-05
categories: "chaos-engineering"
tags: chaos-engineering chaostoolkit aws terraform
author: "Manuel Castellin"
# permalink: "/mastering-chaostoolkit-experiment-configuration"
excerpt: ""
---

## 1. Overview

The purpose of chaos engineering is to learn about the behaviour of a distributed system by observing it during a controlled experiment.

The controlled experiment is a pillar of the scientific method. Researchers use it to test the effect that changes applied to independent variables have on dependent variables.





The idea behind this post is to illustrate the concept of chaostoolkit-terraform.

For chaos experiments there's the concept of running the experiment against a so-called control group.
The control group can be a target for our test that we can attack without fearing the consequences.
Why is the control group important? It is required by the scientific method so that we can compare how
the attacked resource and the control group react to the introduction of the chaos condition.

Problem: we don't want to have control group resources there all the time. They're expensive and can cause security problems if
they're not cleaned-up properly.

An alternative: use chaostoolkit-terraform to handle the creation and cleanup of the control group resources.

An example of how to use chaosterraform to deploy a control group for a s3 bucket policy test or something

The big question is what I want to convey with this article. Is this just to say "hey have a look at this cool module" or
to share a new concept with chaostoolkit?

I lean more towards sharing a new concept but in this case I need to find an example.


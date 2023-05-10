---
layout: post
title:  "ChaosToolkit Steady-State Verification Strategies Explained"
description: |
    Learn how to use the right steady-state hypothesis verification strategy for ChaosToolkit experiments
    by looking at real-world examples.
date:   2023-05-08
categories: "chaos-engineering"
tags: chaos-engineering chaostoolkit
author: "Manuel Castellin"
permalink: "/chaostoolkit-hypothesis-strategies-explained"
---

## 1. Overview

Defining the right steady-state hypothesis is the first step towards a successful chaos experiment. The second step is **selecting the right verification strategy**.

The goal of a controlled chaos experiment isn't breaking random things in the system. After all, no business owner in their right mind would allocate a budget to "break" their infrastructure.

As chaos engineers, we're interested in learning how the system reacts to certain real-world events, so to avoid unwanted disruptions, when we develop an experiment **it's important to ask WHEN is the right time to bail out of an experiment**.

In this article, we'll examine the different strategies for hypothesis verifications available in ChaosToolkit so we can choose the right one for our experiments.

## 2. One-Time vs Continuous Verification

The first thing we need to decide about hypothesis verification is whether we want to run it just once or continuously. This largely depends on the type of experiment we're running and the context we're running it in. Here are some things to consider before making this choice:

* **Can we live with the consequences of a temporary failure in the target system** or it's essential to cancel the experiment as soon as an unforeseen problem arises?
* **Do the effect caused by introducing a chaotic event in the system need time to self-heal**? Or should this be transparent to an outside observer? For example: if we kill a container, we will lose some requests in the process, but if we simulate a spike in traffic, we can expect the service to scale and handle all requests correctly.

## 3. Before And After Hypothesis Verification

This type of verification is more suited when the effects of the real-world events introduced by our chaos experiment cause an observable change that is part of the verification. Take this experiment for instance:

```yaml
title: "Verify if service can recover from container loss"
description: |
  This experiment is designed to verify if an AWS ECS service can recover
  from the loss of a percentage of its running containers timely.

configuration: [...]

steady-state-hypothesis:
  title: "All container replicas should be online"
  probes:
    - type: probe
      name: "desired-tasks-should-be-running"
      tolerance: true
      provider:
        type: python
        module: chaosaws.ecs.probes
        func: are_all_desired_tasks_running
        arguments:
          cluster: "${cluster_arn}"
          service: "${service_name}"

method:
  - type: action
    name: "service-loses-half-capacity"
    provider:
      type: python
      module: chaosaws.ecs.actions
      func: stop_random_tasks
      arguments:
        cluster: "${cluster_arn}"
        service: "${service_name}"
        task_percent: 50
        reason: "${stop_reason_msg}"
    pauses:
      after: ${allowed_recovery_time_seconds}
```

In this experiment, we verify a certain application can self-heal when it loses half of its containers. Unfortunately, re-spawning the lost containers takes time, so there's no point in verifying the hypothesis during the method execution because the experiment will surely fail.

The correct verification strategy, in this case, would be the `default`. By default, ChaosToolkit verifies the hypothesis before and after the experiment's method.

```shell
chaos run experiment.yaml
# or
chaos run --hypothesis-strategy=default experiment.yaml
```

The *before* verification guarantees that the system is stable before we start experimenting with it. **We don't want to run experiments on systems that are already unstable**. So when a before verification fails, the **experiment is immediately stopped** to guarantee we're not piling on existing issues.

The *after* verification is necessary to verify the system can indeed self-heal and repair the application by spawning additional instances to match the desired container count.

Timing in this experiment is also important. We run the second verification after the `allowed_recovery_time_seconds` as this is the **maximum risk we accept for this application**.

## 4. One-Time Hypothesis Verification

There are experiments where the hypothesis should only be verified once on every experiment run. This is the case of the `before-method-only` or the `after-method-only` strategies:

```yaml
title: "Verify if service can update its container count quickly"
description: |
  This experiment is designed to verify if an AWS ECS service can update
  its containers count and spawn up new instances in the allowed start time.

configuration: [...]

steady-state-hypothesis:
  title: "All container replicas should be online"
  probes:
    - type: probe
      name: "desired-tasks-should-be-running"
      tolerance: true
      provider:
        type: python
        module: chaosaws.ecs.probes
        func: are_all_desired_tasks_running
        arguments:
          cluster: "${cluster_arn}"
          service: "${service_name}"

method:
  - type: action
    name: "update-service-container-count"
    provider:
      type: python
      module: chaosaws.ecs.actions
      func: update_desired_count
      arguments:
        cluster: "${cluster_arn}"
        service: "${service_name}"
        desired_count: ${new_desired_count}
    pauses:
      after: ${allowed_start_time_seconds}
```

This is a slight variation of the previous example. With this experiment, we want to ensure an application can scale out instances correctly.

In this case, running the verification at the start of the experiment doesn't help, as we need to first run the method to set the new desired container count for the service.

**In these cases, we only want to check the hypothesis after the method** and the correct hypothesis verification strategy to use is the following:

```shell
chaos run --hypothesis-strategy=after-method-only experiment.yaml
```

## 5. Continuous Hypothesis Verification

Being able to run continuous verifications on a system creates a lot of interesting possibilities, and in ChaosToolkit we can achieve that by using either the `continuously` or `during-method-only` strategies. Take this experiment as an example:

```yaml
title: "Verify if service can sustain increase in traffic"
description: |
  This experiment is designed to verify if an AWS ECS service can sustain an
  increase in traffic without failing.

configuration: [...]

steady-state-hypothesis:
  title: "Service must always respond"
  probes:
    - type: probe
      name: "service-must-respond"
      tolerance:
        type: "range"
        range: [200, 299]
        target: "status"
      provider:
        type: http
        url: "${service_url}/health"
        method: "GET"
        timeout: 5


# Simulate some traffic in the environment
# using Grafana K6
method:
  - type: action
    name: "stress-endpoint-with-simulated-traffic"
    provider:
      type: python
      module: chaosk6.actions
      func: stress_endpoint
      arguments:
        endpoint: ${service_url}
        vus: ${stress_users}
        duration: ${stress_duration}
```

The template will verify that the target service can handle a sudden increase in traffic spike, and the steady state hypothesis confirms that health checks return a *success HTTP status code*.

The experiment would run successfully by just running with the *default* before and after verification, though **checking the service continuously has much more value in this case** as we'll make sure the additional traffic is not affecting the application at any point during the test.

We can run the experiment using the `continuously` hypothesis strategy:

```shell
chaos run --hypothesis-strategy=continuously experiment.yaml
```

ChaosToolkit will now run the hypothesis verification every few seconds, and **if any of the verifications fail, the entire experiment will be marked as deviated**.

The frequency (in seconds) with which the experiment verification runs can be customised using the `--hypothesis-frequency` option:

```shell
chaos run --hypothesis-strategy=continuously --hypothesis-frequency=2 experiment.yaml
```

### 5.1. Continuously vs During-method-only

Yes, there are two options for continuous verification, and the difference is subtle:

|             |continuously|during-method-only|
|-------------|------------|------------------|
|**before method**|Yes|No|
|**during method**|Yes|Yes|
|**after method** |Yes|No|

The `during-method-only` strategy runs continuous verifications only throughout the method execution. This means that to use this strategy **we must accept that the experiment method will run even on an unstable system**.

In fact, the biggest difference between the two strategies is that by using **the `continuously` option, we still run a verification before and after the method**, giving us a chance to bail out of the experiment if we're already experiencing issues with the service. The `during-method-only`, on the other hand, will ALWAYS run the experiment's method.

### 5.2. Fail-fast option

Both continuous verification strategies support the additional `--fail-fast` flag. This option does exactly what it says: stop the experiment as soon as the probe verification fails for the first time. To use it:

```shell
chaos run --hypothesis-strategy=continuously --fail-fast experiment.yaml
```

A word or warning, though, you may think that using **continuously** or **during-method-only** with `--fail-fast` will ultimately have the same effect because if the first verification fails, both experiments will stop. **It DOES NOT**. ⚠️

I encourage you to try these two combinations yourself to fully understand the execution flow. Still, the key lesson is that the **during-method-only will always enter the experiment method and, at the very least, run the first step**. For this reason, we can't guarantee the `--fail-fast` and `during-method-only` combination will not affect an already unstable system.

In contrast, the **continuously** strategy will fail the experiment entirely if the first verification fails, qualifying as the **"safer"** option.


## Conclusion

In this article, we discussed the different hypothesis verification strategies for ChaosToolkit experiments and when it's appropriate to use each.

* **default** verification before and after the experiment
* **one-time** verification with `before-method-only` and `after-method-only`
* **continuous** verification with `continuously` and `during-method-only`.

The code examples used in this article are available <a href="https://github.com/DevLearnOps/tutorials/tree/main/chaos-engineering/chaostoolkit-hypothesis-strategies-explained" target="_blank">over on GitHub</a>.

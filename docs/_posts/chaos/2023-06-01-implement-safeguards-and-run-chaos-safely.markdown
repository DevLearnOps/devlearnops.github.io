---
layout: post
title:  "How to Implement Safeguards and Run Chaos Experiments Safely"
description: |
    Experimenting in production has the potential to cause unnecessary customer pain.
    In this article, we’ll learn how to use safeguards in Chaos Toolkit to immediately 
    interrupt an experiment execution before it seriously affects the target system.
date:   2023-06-01
categories: "chaos-engineering"
tags: chaos-engineering chaostoolkit
author: "Manuel Castellin"
permalink: "implement-safeguards-and-run-chaos-safely"
excerpt: |
    Experimenting in production has the potential to cause unnecessary customer pain.
    In this article, we’ll learn how to use safeguards in Chaos Toolkit to immediately 
    interrupt an experiment execution before it seriously affects the target system.
---

## 1. Overview

> Experimenting in production has the potential to cause unnecessary customer pain. [...] it is the responsibility and obligation of the Chaos Engineer to ensure the fallout from experiments are minimized and contained.
>
> <a href="http://principlesofchaos.org/" target="_blank">principlesofchaos.org</a>

In this article, we'll learn how to use **safeguards** in Chaos Toolkit to immediately interrupt an experiment execution before it seriously affects the target system.

Whether you're injecting chaos events on a production system or still experimenting with a test environment, Chaos Toolkit safeguards can be incredibly useful to stop experiments as soon as possible.

{% capture cta_text %}join the waiting list{% endcapture %}
{% include cta/chaos-starter-pack.html %}

## 2. Safeguards vs Steady-State Hypothesis

A steady-state hypothesis can also be used to bail out an experiment early. In fact, in Chaos Toolkit, we can use a verification strategy to check the steady state of the system continuously and exit as soon as the first verification fails (More on hypothesis strategies in a [previous article](/chaostoolkit-hypothesis-strategies-explained)

So how are safeguards different from a steady-state hypothesis?

#### **Safeguards are experiment controls**

Controls in Chaos Toolkit operate outside of the experiment context and can be used to modify its execution flow (like interrupting the experiment early in this case).
Because they're not part of the experiment, they can be defined in separate files and activated for multiple experiments using command line options.

#### **Safeguards can keep an eye on the system as a whole**

While a steady-state hypothesis is usually relevant to a single service or sub-system, safeguards can define probes to check the system as a whole. For instance, while we simulate a traffic spike on a frontend service, we could use a safeguard to ensure the underlying database CPU is still in check.

## 3. Using Experiment Safeguards

The **safeguards** control is part of the `chaosaddons` module, so to use it in our experiments, we first need to install it:


```shell
pip install -U chaostoolkit-addons
```

Then all we need to do is add our safeguards to the controls section, for example:


{% raw %}
```yaml
# ...

controls:
  # This safeguards control includes two probes:
  - name: "my-experiment-safeguards"
    provider:
      type: python
      module: chaosaddons.controls.safeguards
      arguments:
        probes:
          # The first probe verifies the container called `sampleapp-back`
          # is running before starting the experiment
          - type: probe
            name: "backend-container-must-be-running"
            tolerance:
              type: regex
              target: stdout
              pattern: sampleapp-back
            provider:
              type: process
              path: "docker"
              arguments: "container ps --filter name=sampleapp-back --format '{{lower .Names}}'"

          # The second probe verifies the backend application remains
          # responsive throughout the test
          - type: probe
            name: "backend-must-be-healthy"
            frequency: 2      # <<<< run continuously
            background: true  # <<<<
            tolerance: 200
            provider:
              type: http
              url: "http://localhost:8999/health"
              method: "GET"
              timeout: 2

# ...
```
{% endraw %}

Safeguards are nothing more than a list of probes that verify the system's condition. In the example above, we don't want the backend service to be affected by chaotic events and stop the experiment as soon as that happens.

Probes defined in safeguards can affect the experiment execution in different ways, depending on how we configure them using two attributes `background: bool` and `frequency: float`:

| Attribute | Execution time | Effect |
|---|---|---|
| `None` | Blocking, before the experiment begins | When no attributes are set, the probe can prevent the experiment from starting |
| `frequency:N` | Blocking, runs continuously every *N* seconds | Probe will not stop experiment start but will interrupt the execution on failure |
| `background:bool` | Non-blocking, runs as soon as possible in the background after the experiment starts | Probe will not prevent the experiment from starting but can stop execution early |
| `frequency:N` **and** `background:bool` | Non-blocking, runs continuously in the background every *N* seconds| Just like *frequency* but running activity in the background |

### 3.1. Block experiments at the start

The most dangerous thing a chaos experiment can do is introduce faults to an unstable system. We can use safeguard probes to block experiments at the start by **not setting the `frequency` and `background` attributes**.

According to the table above, the probe verification will block the experiment execution until it's done verifying:

```yaml
controls:
  - name: "my-experiment-safeguards"
    provider:
      type: python
      module: chaosaddons.controls.safeguards
      arguments:
        probes:
          - type: probe
            name: "backend-container-must-be-running"
            tolerance:
              type: regex
              target: stdout
              pattern: sampleapp-back
            provider:
              type: process
              path: "docker"
              arguments: "container ps --filter name=sampleapp-back ...
          - [...]
```

As a result, if the container called `sampleapp-back` is not running, the experiment will immediately exit and be marked as **interrupted**:

```shell
chaos run --rollback-strategy=always experiment.yaml
# ...
# [CRITICAL] Safeguard 'backend-container-must-be-running' triggered the end of the experiment
# [INFO] Steady state hypothesis: Verify server is available
# [WARNING] Received the exit signal: 20
# ...
```

### 3.2. Run safeguards continuously

We can use safeguards to verify the state of the system continuously throughout the experiment execution by defining the **frequency** attribute for a probe:

```yaml
controls:
  - name: "my-experiment-safeguards"
    provider:
      type: python
      module: chaosaddons.controls.safeguards
      arguments:
        probes:
          - [...]
          - type: probe
            name: "backend-must-be-healthy"
            frequency: 2   # <<<< run continuously
            tolerance: 200
            provider:
              type: http
              url: "http://localhost:8999/health"
              method: "GET"
              timeout: 2
```

In this example, `frequency: 2` will run a verification every 2 seconds until the end of the experiment. As soon as the verification fails, the experiment will be immediately interrupted:

```shell
chaos run --rollback-strategy=always experiment.yaml
# ...
# [CRITICAL] Safeguard 'backend-must-be-healthy' triggered the end of the experiment
# [WARNING] Received the exit signal: 20
# ...
```

### 3.3. Background verifications

In Chaos Toolkit experiments, the `background: bool` option will tell the framework to run the action in a subprocess and allow the rest of the steps to proceed concurrently.

Using this feature is sensible if your safeguard verifications can take a long time to complete. Of course, what qualifies as "a long time" entirely depends on the use case: sometimes a 10 seconds wait is acceptable, in other cases, it can make or break a test.

Generally, I avoid using background steps as much as possible to keep the execution flow simple and predictable. If I can live with the wait, I'll accept it.

## 4. Reuse Safeguards For Multiple Experiments

Like any other control, safeguards can be defined outside the experiment file and added to existing experiments at run-time using the command line. Let's see an example.


We create a new file called `safeguards.yaml` with the following content:

{% raw %}
```yaml
backend-safeguards:
  provider:
    type: python
    module: chaosaddons.controls.safeguards
    arguments:
      probes:
        - type: probe
          name: "backend-container-must-be-running"
          tolerance:
            type: regex
            target: stdout
            pattern: sampleapp-back
          provider:
            type: process
            path: "docker"
            arguments: "container ps --filter name=sampleapp-back --format '{{lower .Names}}'"
        - type: probe
          name: "backend-must-be-healthy"
          frequency: 2
          background: true
          tolerance: 200
          provider:
            type: http
            url: "http://localhost:8999/health"
            method: "GET"
            timeout: 2
```
{% endraw %}

This definition is the same as the example above but used in a control-file. We can then run the experiment and apply an external control using this syntax:

```shell
chaos run \
    --rollback-strategy=always \
    --control-file safeguards.yaml \
    experiment.yaml
```

For more information on how to apply controls defined outside of experiment templates, check out my [previous article](/apply-ctk-controls-globally-s3-bucket-upload).

## 5. Safeguards In Practice

If you're interested in testing safeguards for yourself, we'll now reproduce the experiment described in the article.

#### **Run the demo application locally**

First, we need to have an application to experiment with. You can run my sample frontend-backend application locally with Docker following the steps described <a href="https://github.com/DevLearnOps/tutorials/tree/main/sample-apps/simple-frontend-backend" target="_blank">in the GitHub repo</a>.

#### **Create the experiment file**

Here's the full example of the experiment including safeguards:

{% raw %}
```yaml
title: "ChaosToolkit experiment with Safeguards"
description: |
  This experiment is an example of how to use `safeguards` to ensure we
  bail out of an experiment early when an unwanted effect is introduced.

controls:
  - name: "backend-safeguards"
    provider:
      type: python
      module: chaosaddons.controls.safeguards
      arguments:
        probes:
          - type: probe
            name: "backend-container-must-be-running"
            tolerance:
              type: regex
              target: stdout
              pattern: sampleapp-back
            provider:
              type: process
              path: "docker"
              arguments: "container ps --filter name=sampleapp-back --format '{{lower .Names}}'"
          - type: probe
            name: "backend-must-be-healthy"
            frequency: 2
            background: true
            tolerance: 200
            provider:
              type: http
              url: "http://localhost:8999/health"
              method: "GET"
              timeout: 2

steady-state-hypothesis:
  title: "Verify server is available"
  probes:
    - type: probe
      name: "server-must-respond-200"
      tolerance: 200
      provider:
        type: http
        url: "http://localhost:8000"
        method: "GET"
        timeout: 3

method:
  # Simulate some user traffic using Grafana k6
  - type: action
    name: "stress-endpoint-with-simulated-traffic"
    provider:
      type: python
      module: chaosk6.actions
      func: stress_endpoint
      arguments:
        endpoint: "http://localhost:8000"
        vus: 1
        duration: "10s"

  # Simulate failure on backend container
  - type: action
    name: "fail-backend-container"
    provider:
      type: http
      url: "http://localhost:8999/_chaos/fail"
      method: "POST"
      timeout: 2

  # Stress the frontend application some more
  - ref: "stress-endpoint-with-simulated-traffic"

rollbacks:
  - type: action
    name: "restart-backend-container"
    provider:
      type: process
      path: docker
      arguments: "start sampleapp-back"
```
{% endraw %}

#### **Run the experiment**

To run the experiment:

```shell
chaos run --rollback-strategy=always experiment.yaml
```

## 6. Conclusion

In this article, we learned how to use **safeguards** to monitor the system's state and interrupt an experiment before it can cause pain for users.

As always, all examples used in this post and more are available
<a href="https://github.com/DevLearnOps/tutorials/tree/main/chaos-engineering/chaostoolkit-experiment-safeguards" target="_blank">over on GitHub</a>

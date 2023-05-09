---
layout: post
title:  "ChaosToolkit Steady-State Verification Strategies Explained"
description: |
    TODO
date:   2023-05-08
categories: "chaos-engineering"
tags: chaos-engineering chaostoolkit
author: "Manuel Castellin"
permalink: "/chaostoolkit-hypothesis-strategies-explained"
---
todo:
- [ ] include some snippet of command execution output when using options


## 1. Overview

Defining the right steady-state hypothesis is the first step towards a successful chaos experiment. The second step is **selecting the right verification strategy**.

The goal of a controlled chaos experiment isn't breaking random things in the system. After all, no business owner in their right mind would allocate budget to just "break" their infrastructure.

As chaos engineers we're interested in learning how the system reacts to certain real-world events, so in order to avoid unwanted disruptions, when we develop an experiment **it's important to ask WHEN is the right time to bail out of an experiment**. 

In this article we'll examine the different strategies for hypothesis verifications that are available in ChaosToolkit so we can choose the right one for our experiments.

## 2. One Time vs Continuous Verification

The first thing we need to decide about hypothesis verification is whether we want to run it just once or continuously. This largely depends on the type of experiment we're running and the context we're running it in. Here are some things to consider before making this choice:

* **Can we live with the consequences of a temporary failure in the target system** or it's important to cancel the experiment as soon as an unforeseen problem arises?
* **Do the effect caused by introducing a chaos event in the system need time to self-heal**? Or should this be transparent to an outside observer? For example: if we kill a container we will lose some requests in the process, but if we simulate a spike in traffic we can expect the service to scale and handle all requests correctly.

## 3. Before And After Hypothesis Verification

This type of verification is more suited when the effects of the real world events introduced by our chaos experiment do cause an observable change that is part of the verification. Take this experiment for instance:

```
insert here experiment that kills containers
and validates container count
```

In this experiment we verify a certain application can self-heal when it loses half of its containers. Re-spawning the lost containers can take up to 2 minutes, so there's no point to verify the hypothesis during the method execution because the experiemnt will surely fail.

The correct verification strategy in this case would be the `default`. By default Chaostoolkit verifies the hypothesis before and after the experiment.

```shell
chaos run experiment.yaml
# or
chaos run --hypothesis-strategy=default experiment.yaml
```

The before verification guarantees that the system is stable before we start experimenting with it. Remeber, we don't want to be running experiments on systems that are already unstable. First we would just pile on the root cause of the problem by adding yet one more thing for support engineer to investigate, second our experiment would be useless as we're learning absolutely nothing conclusive about the system.

When a before verification fails, the experiment is immediately stopped, before the method execution can start.

The after verification is necessary to verify the system can indeed self-heal and repair the application cluster by spawing the missing containers to match the desired container count. The timing here is also important, we run the second verification after 2 minute as this is the maximum risk we accept for this application. If we don't get the containers back in 2 minutes, then we need to figure out why: maybe there are errors on startup? container are waiting on a resource lock? are container images too large and taking a long time to transfer?

### one time verification

There are experiments where the hypothesis will only be verified once on every experiment run. This is the case of the `before-method-only` or the `after-method-only`:

```
inser here experiment that updates the desired container count
and validates all containers are online after 2 minutes
```

This is a slight variation of the first example. With this experiment we want to make sure an application can scale out correctly.

The verification is the same as the above but it will surely fail if we run it prior to the experiment execution. The method itself will update the service desired container count so the correct way to verify this experiment outcome is once and at the end of the experiment.

In this case the correct hypothesis verification strategy is:

```
# chaos run --hypothesis-strategy=after-method-only experiment.yaml
```

### continuous verification

Being able to run continuous verifications on a system opens up a lot of interesting possibilities and in ChaosToolkit we can that by using either the `continuously` or `during-method-only` strategies. Take this experiment example:

```
insert here experiment that kills half of the containers
and validates the site is responsive
```

Similarly to the first example, in this template we verify the site is up and running with an `http` probe and kill half of its containers.

Yes, the experiment would run just fine if we start it with the default verification strategy before and after method execution, but it's even more interesting if we use the `continuously` strategy:

```terminal
# chaos run --hypothesis-strategy=continuously experiment.yaml
```

ChaosToolkit will now run the hypothesis verification continuously every few seconds and if any of the verifications fail the entire experiment will be marked as deviated.

In other words, the lesson we want to learn with this experiment, is whether the service can continue to serve traffic to our users even if it loses half of its containers.

The frequency (in seconds) with which the experiment verification run can be customised in ChaosToolkit using the `--hypothesis-frequency` option:

```terminal
# chaos run --hypothesis-strategy=continuously --hypothesis-frequency=2 experiment.yaml
```

#### Continuously vs During-method-only

Yes, there are two options for continuous verification and the difference is subtle:

|             |continuously|during-method-only|
|-------------|------------|------------------|
|**before method**|Yes|No|
|**during method**|Yes|Yes|
|**after method** |Yes|No|

The `during-method-only` strategy only runs a continuous verification throughout the entire duration of the method execution. This means that in order to use this strategy **we must accept that the experiment could run even on an unstable system**.

In fact, the biggest difference between the two strategies is that by using the `continuously` option we still run a verification before and after the method giving us a chance to bail out of the experiment if we're already experiencing issues with the service. The `during-method-only` on the other hand, will ALWAYS run the experiment's method.

#### Fail-fast

Both options for continuous verification support the additional `--fail-fast` flag. This option will do exactly as promised: stop the experiment as soon as the probe verification fails for the first time. To use it:

```terminal
# chaos run --hypothesis-strategy=continuously --fail-fast experiment.yaml
```

A word or warning, though, you may think that using **continuously** or **during-method-only** with `--fail-fast` will ultimately have the same effect because if the first verification fails, both experiments will stop. It DOES NOT.

I encourage to try these two combination yourself to fully understand the execution flow, but the key lesson is that the **during-method-only** will always enter the experiment method and run the first step at the very least. So we can't guarantee this option will not affact the system if it is already in an unstable state.

In contrast, the **continuous** option will fail the experiment entirely if the first verification fails, hence qualifying as the "safer" option.


## Conclusion

In this article we discussed the different hypothesis verification strategies for ChaosToolkit experiments and when it's appropriate to use each.

* **default** verification before and after the experiment
* **one-time** verification with `before-method-only` and `after-method-only`
* **continuous** verification with `continuously` and `during-method-only`

The code examples used in this article are available <a>over on GitHub</a>.

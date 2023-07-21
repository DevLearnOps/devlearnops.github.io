---
layout: post
title:  "Mastering ChaosToolkit Experiment Configuration: A Comprehensive Guide"
description: |
    Learn how to use variables in ChaosToolkit tempates and reuse experiments in different contexts
    by providing configuration parameter overrides.
date:   2023-05-17
categories: "chaos-engineering"
tags: chaos-engineering chaostoolkit
author: "Manuel Castellin"
permalink: "/mastering-chaostoolkit-experiment-configuration"
excerpt: ""
---

## 1. Overview

Reusability is one of the most essential concepts in software engineering. The ability to reuse code and components developed by someone else allows us to easily create complex systems because we don't have to design every single detail of an application from scratch.

Libraries, SDKs, databases, and APIs all have something in common: we can modify their behaviour using *configuration parameters*. So why shouldn't we do the same with chaos experiments?

In this article, we'll look at **how we can use variables in ChaosToolkit templates and reuse experiments in different contexts**.

## 2. Before We Begin

Before we explore all the options available for configuration parameters in ChaosToolkit, let's create a simple experiment we can work with.

We create a new file called `experiment.yaml` and add the following content:

```yaml
title: "Mastering Experiment Configuration"
description: |
  This experiment contains examples of how to use configuration variables
  in ChaosToolkit experiment templates

steady-state-hypothesis:
  title: "Verify web server is available"
  probes:
    - type: probe
      name: "server-must-respond-200"
      tolerance: 200
      provider:
        type: http
        url: "http://localhost:8080"
        method: "GET"
        timeout: 3

# Simulate some traffic on the environment
# using Grafana K6
method:
  - type: action
    name: "stress-endpoint-with-simulated-traffic"
    provider:
      type: python
      module: chaosk6.actions
      func: stress_endpoint
      arguments:
        endpoint: "http://localhost:8080"
        vus: 2
        duration: "10s"
```

This template contains hardcoded values for all its probes and actions arguments, making it impossible to reuse it without modifying its content. Let's fix that right away!

<div class="post-emphasis">
    I always make sure you can try all the examples in the article yourself.
    If you're interested, the full code examples and setup instructions are available <a href="https://github.com/DevLearnOps/tutorials/tree/main/chaos-engineering/mastering-chaostoolkit-experiment-configuration" target="_blank">over on GitHub</a>
</div>

## 3. Inline Configuration

The first thing we want to do is making sure we don't hardcode any value for probes and actions and use variables instead.

To define variables in a ChaosToolkit experiment file **we need to introduce a configuration section in the template**. Let's add it to the experiment:

```yaml
title: "Mastering Experiment Configuration"
description: |
  This experiment contains examples of how to use configuration variables
  in ChaosToolkit experiment templates

# Inline configuration is provided with values for
# local development of the experiment
configuration:
  endpoint: "http://localhost:8080"
  stress_duration: "10s"
  stress_users: "2"


steady-state-hypothesis:
  title: "Verify web server is available"
  probes: [...]

# Simulate some traffic in the environment
# using Grafana K6
method: [...]
```

We can use **inline configuration to provide default values for our experiment**. Which value to use depends entirely on your use case. I prefer using inline configuration to ensure we can run experiments locally in the development phase.

We use the `${variable_name}` syntax in ChaosToolkit experiments to replace variables with their resolved value. So let's refactor the entire experiment to use variables from the configuration section:

```yaml
title: "Mastering Experiment Configuration"
description: |
  This experiment contains examples of how to use configuration variables
  in ChaosToolkit experiment templates

# Inline configuration is provided with values for
# local development of the experiment
configuration:
  endpoint: "http://localhost:8080"
  stress_duration: "10s"
  stress_users: "2"


steady-state-hypothesis:
  title: "Verify web server is available"
  probes:
    - type: probe
      name: "server-must-respond-200"
      tolerance: 200
      provider:
        type: http
        url: "${endpoint}"  # <<<<<
        method: "GET"
        timeout: 3

# Simulate some traffic on the environment
# using Grafana K6
method:
  - type: action
    name: "stress-endpoint-with-simulated-traffic"
    provider:
      type: python
      module: chaosk6.actions
      func: stress_endpoint
      arguments:
        endpoint: ${endpoint}         # <<<<<
        vus: ${stress_users}          # <<<<<
        duration: ${stress_duration}  # <<<<<
```

## 4. Variable Files

Now that we have parametrised the experiment template, we can override those default values and run the same experiment template in different contexts. One way to achieve this is **by maintaining some configuration files outside of the experiment**.

Let's create a new file called `dev-overrides.yaml` and add the following content:

```yaml
configuration:
  stress_duration: '120s'
  stress_users: 50
```

<div class="post-emphasis">
  ChaosToolkit can work with configuration files, just like experiments, in either <strong>JSON</strong> or <strong>YAML</strong> format.
  I prefer the latter as it's more compact and allows comments for better documentation.
</div>

We can tell ChaosToolkit to use the **dev-overrides.yaml** file when we're running the experiment in our **DEV** environment and execute the *stress-endpoint* action for longer and with a higher number of simulated users. To use variables override from the external configuration file, we use this command:

```shell
chaos run --var-file dev-overrides.yaml experiment.yaml
# ...
# [INFO] Stressing the endpoint "http://localhost:8080" with 50 VUs for 120s.
# ...
```

The `--var-file` option **can be used multiple times in the same chaos command**. This way, we could separate our configuration further and create more specific files that override only a few parameters.

For instance, if we want to create a configuration to absolutely hammer the dev environment with requests, we could add another configuration file `dev-heavy-load.yaml` with:

```yaml
configuration:
  stress_users: 999
```

And run the test with two configuration overrides:

```shell
chaos run \
   --var-file dev-overrides.yaml \
   --var-file dev-heavy-load.yaml  \
   experiment.yaml
# ...
# [INFO] Stressing the endpoint "http://localhost:8080" with 999 VUs for 120s.
# ...
```

<div class="post-emphasis">
  When using multiple override <strong>files order counts</strong>! Make sure you specify override files <strong>from the least specific to the more specific</strong>.
</div>

## 5. Command-Line Variables

Variable overrides can also be passed to ChaosToolkit experiments directly from the command line using the `--var KEY=VALUE` option. This is useful in many cases, whether you need to test something during development **or pass variables that are not known beforehand and need to be resolved later on**:

```shell
chaos run --var 'endpoint=https://my-test-server:443/' experiment.yaml
```

The `--var` option can also be used many times to override multiple parameters:

```shell
 chaos run \
   --var 'endpoint=https://my-test-server:443' \
   --var 'stress_duration=100s' \
   experiment.yaml
# ...
# [INFO] Stressing the endpoint "http://localhost:8080" with 50 VUs for 120s.
# ...
```

## 6. Variable Override Priority

Whenever more than one value is provided for the same variable name, ChaosToolkit will use the override from the most specific context:

|Priority|Context|
|--------|-------|
|**High**    |command-line arguments `--var KEY=VALUE`|
|**Medium**  |override config files `--var-file`. If multiple files are used, last variable files in sequence have more priority|
|**Low**     |inline configuration (experiment template)|

## 7. Replace Environment Variables

ChaosToolkit also offers the option to use environment variables in experiments. To replace environment variables in a template, we first need to define the inline experiment configuration using the following syntax:

```yaml
configuration:
  endpoint:
    type: "env"
    key: "APP_ENDPOINT"
    default: "http://localhost:8080"
```

Environment substitution can be a great way to parametrise experiments, especially if you already have a lot of context stored in environment variables.

To specify a value for our `APP_ENDPOINT`:

```shell
export APP_ENDPOINT=https://my-test-server:443
chaos run experiment.yaml
# ...
# [INFO] Stressing the endpoint "https://my-test-server:443" with 2 VUs for 10s.
# ...
```

Remember that **all variables with `type: "env"` will resolve as strings by default**. If we don't take care, this could render them incompatible with specific action attributes, like the number of virtual users in our experiment for instance.

Whenever we need to use numeric or boolean types from environment variables, we need to specify the **env_var_type** key:

```yaml
configuration:
  endpoint:
    type: "env"
    key: "APP_ENDPOINT"
    default: "http://localhost:8080"
  stress_users:
    type: "env"
    key: "STRESS_USERS"
    default: 2
    env_var_type: int
```

Using **env_var_type** will force the experiment to cast the value to the type specified before replacing it in the experiment. Supported types are: `str`, `int`, `float` and `bytes`, corresponding to Python data types.


### 7.1. How to use environment variables with existing experiments

It goes without saying that if a template is not designed to accept environment variables, we cannot use them as parameters for the experiment. Not directly, anyway.

We can, however, find clever ways to translate them into usable variable overrides. For example, we could add them as command-line overrides:

```shell
export STRESS_DURATION_MINUTES=2
chaos run --var "stress_duration=${STRESS_DURATION_MINUTES}m" experiment.yaml
# ...
# [INFO] Stressing the endpoint "http://localhost:8080" with 2 VUs for 2m.
# ...
```

## 8. Conclusion

In this article, we learned how to parametrise experiment templates in ChaosToolkit and override default values using configuration files or command-line arguments.

I hope you enjoyed it, and if you want to see the full code examples we used in this article and more you can find them <a href="https://github.com/DevLearnOps/tutorials/tree/main/chaos-engineering/mastering-chaostoolkit-experiment-configuration" target="_blank">over on GitHub</a>

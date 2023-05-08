---
layout: post
title:  "environment substitution"
description: |
    TODO
date:   2023-05-10
categories: "chaos-engineering"
tags: chaos-engineering chaostoolkit
author: "Manuel Castellin"
# permalink: "/chaostoolkit-hypothesis-strategies-explained"
---

## overview

Reusability is probably the most important concept in software engineering. The ability to reuse code and components developed by someone else just makes sense because we don't have to design every single detail of an application from scratch.

Libraries, SDKs, databases, APIs all have something in common: we can modify their behaviour using configuration parameters. Same applies for chaos engineering experiments.

In this article we'll look at how we can use configuration parameters in ChaosToolkit experiment templates so we can reuse them in different contextes.

## Before we begin

Before exploring the different options available for configuration paramters in chaostoolkit, let's create a sample experiment that we can work with.

Create a new file called `experiment.yaml` and add the following content:

```yaml
insert example experiment with hypothesis on http validation and some load generation with grafana k6
```

| I always try to make an effort to make sure you can try all the examples in the article yourself. If you're interested the full code example and setup instructions are available over on GitHub


## Inline configuration

The ChaosToolkit experiment template as it is is not very reusable. The first thing we want to do is make sure that we don't hardcode any value for probes and actions and use variables.

To define variables in a ChaosToolkit experiment file we need to introduce a **configuration** section in the template. So let's add this section to the experiment:

```yaml
title: title
description: desc

configuration:
  endpoint: "http://localhost:8080"
  stress_duration: "10s"
  stress_users: "2"

steady-state-hypothesis:
  title: title
  probes: [...]
```

We can use inline configuration to provide default values for our experiment. Which value to use depends entirely on your use case. I prefer to use inline configuration to make sure we can run experiments locally in the development phase.

We use the `${variable_name}` syntax in ChaosToolkit experiment to replace variables with their actual value. So let's refactor the entire experiment to use variables instead of hardcoded values:

```yaml
place full experiment with all parametrisation
```

## Variables From File

Now that we have parametrised the experiment template we have a few options to override those default values and run the same experiment templates in different contextes. One way to achieve this is maintain configuration files outside of the experiment.

Let's create a new file called `dev-overrides.yaml` and add the following content:

```yaml
configuration:
  stress_duration: '120s'
  stress_users: 50
```

We can tell ChaosToolkit to use this file when we're running the experiment in our **dev** environment for longer and with a higher number of simulated users. To use variables override from the external configuration file we use this command:

```terminal
# chaos run --var-file dev-overrides.yaml experiment.yaml
```

The `--var-file` option can be used multiple times in the same **chaos** command. This way we could split our configuration even further if we have a large number of configuration variables.

For instance, if we want to create a configuration to absolutely hammer the dev environment with requests, we could create another configuration `dev-heavy-load.yaml` with:

```yaml
configuration:
  stress_users: 999
```

and run the test with two configuration overrides:

```terminal
# chaos run  --var-file dev-overrides.yaml --var-file dev-heavy-load.yaml  experiment.yaml
```

| When using multiple override files order counts! Make sure you specify override files **in order from the least specific to the more specific**.

## Command-Line Variables

Variable overrides can also be passed to a ChaosToolkit experiments directly from the command line using the `--var KEY=VALUE` option. This is useful in many cases, whether you need to test something during development or pass variables that are not known beforehand and need to be resolved later on:

```terminal
# chaos run  --var 'endpoint=https://my-test-server:443/'  experiment.yaml
```

The `--var` option can also be used many time to override multiple parameters:

```terminal
# chaos run \
    --var 'endpoint=https://my-test-server:443' \
    --var 'stress_duration=100s' \
    experiment.yaml
```

## Variable Override Priority

Whenever multiple values are resolved for the same variable name, ChaosToolkit will use for the experiment execution the override that is the most specific:

|Priority|Context|
|++++++++|+++++++|
|High    |command-line arguments `--var KEY=VALUE`|
|Medium  |override config files `--var-file`. If multiple files are used, last variable files in sequence have more priority|
|Low     |inline configuration (experiment template)|

## Replace Environment Variables

ChaosToolkit also offers the option to use environment variables in experiments. To replace environment variables a template we can use the following syntax:

```yaml
configuration:
  endpoint:
    type: "env"
    key: "APP_ENDPOINT"
    default: "http://localhost:8080"
```

Environment substitution can be a great way to parametrise experiments especially if you already have a lot of context already stored in environment variables.

To specify a value for our `APP_ENDPOINT`:

```terminal
# export APP_ENDPOINT=https://my-test-server:443
# chaos run experiment.yaml
```

One thing to remember before using environment variables in a ChaosToolkit experiment, is that they're all resolved as strings by default. This could render them incompatibile with certain action attributes, like the number of virtual users in our experiment.

This is why the `env` configuration also has an `env_var_type` key:

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

Using the **env_var_type** attribute will force the experiment to cast the value to the type specified before replacing it in the experiment. Supported types are: `str`, `int`, `float` and `bytes`, corresponding to Python data types.


### How to use environment variables with existing experiments

Goes without saying that if a template is not designed to accept environment variables we cannot use them as parameters for the experiment. Not directly anyway.

We can however, find clever ways to translate them into usable variable overrides. For example we could add them as command-line overrides:

```terminal
# export STRESS_DURATION_MINUTES=2
# chaos run  --var "stress_duration=${STRESS_DURATION_MINUTES}m" experiment.yaml
```

## Conclusion

In this article we learned how we can parametrise experiment templates in ChaosToolkit and how to override default values using configuration files or command-line arguments.

Hope you enjoyed it and if want to see the full code examples we used in this articles and more you can find them over on GitHub

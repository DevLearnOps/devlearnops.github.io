---
layout: post
title:  "A Guide To Probe Tolerances In ChaosToolkit Experiment Verifications"
description: |
    TODO
date:   2023-05-06
categories: "chaos-engineering"
tags: chaos-engineering chaostoolkit
author: "Manuel Castellin"
permalink: "/set-tolerance-values-in-chaostoolkit-experiments"
---

## Table Of Contents
<!-- vim-markdown-toc Redcarpet -->

* [1. Overview](#1-overview)
* [2. Tolerance And Steady-State Verification](#2-tolerance-and-steady-state-verification)
* [3. Before we begin](#3-before-we-begin)
    * [3.1. Required ChaosToolkit modules](#3-1-required-chaostoolkit-modules)
    * [3.2. Run a local Nginx server for testing](#3-2-run-a-local-nginx-server-for-testing)
    * [3.3. Create the experiment structure](#3-3-create-the-experiment-structure)
* [4. What Are Probes Returning?](#4-what-are-probes-returning)
* [5. How To Set Tolerances For Probes](#5-how-to-set-tolerances-for-probes)
    * [5.1. Tolerance for scalar values](#5-1-tolerance-for-scalar-values)
    * [5.2. Sequences](#5-2-sequences)
    * [5.3. Ranges](#5-3-ranges)
    * [5.3. Regular expressions](#5-3-regular-expressions)
    * [5.4. Match complex objects with jsonpath](#5-4-match-complex-objects-with-jsonpath)
* [6. Conclusion](#6-conclusion)

<!-- vim-markdown-toc -->

## 1. Overview

Defining the steady-state hypothesis is the first step in creating a chaos engineering experiment.
Chaostoolkit offers a wide variety of probes to choose from to create steady-state hypothesis verifications, but the most important part is setting the correct tolerance for every verification.

> Start by defining ‘steady state’ as some **measurable output** of a system that indicates normal behaviour.
>
> <a href="https://principlesofchaos.org" target="_blank">principlesofchaos.org</a>

The **tolerance** defines the boundaries of what we consider an acceptable *measurable output* of the system. That's why it's essential to set it correctly.

In this article, we'll discuss the different ways we can set tolerance values for verifications in ChaosToolkit experiments.

## 2. Tolerance And Steady-State Verification

In a ChaosToolkit experiment, **every probe in the steady-state verification must have a tolerance**. The tolerance configuration will tell the framework whether the value returned by the probe is still acceptable to describe a **stable system**.

Here's an example of how we can set a tolerance for a ChaosToolkit probe:

```yaml
steady-state-hypothesis:
  title: "Ningx web server is available"
  probes:
    - type: probe
      name: "server-must-respond"
      tolerance: 200   # Must respond with HTTP status code 200
      provider:
        type: http
        url: "http://localhost:8080"
        method: "GET"
        timeout: 3
```

This snippet demonstrates how to implement a *health check* verification on a web server. We *probe* the URL **http://localhost:8080** and **tolerate** only a `200` HTTP response code. Any other response code is considered unacceptable by the experiment.

## 3. Before we begin

If you wish to follow along with the steps described in this article and test it by yourself, you'll need to set up a few things first.

### 3.1. Required ChaosToolkit modules

| If you don't have ChaosToolkit installed in your system, follow the installation steps described in the article [Your First Chaos Engineering Experiment With Chaostoolkit](/first-chaos-experiment-with-chaostoolkit#4-prepare-the-environment) first.

I prepared a custom ChaosToolkit module to demonstrate some tolerance verification features, so let's install it from the GitHub repository with the following command:

```shell
pip install git+https://github.com/DevLearnOps/tutorials.git@main#subdirectory=modules/chaostoolkit-tutorial
```

After installing this package, a new Python module, `chaostutorial` will be available to use in our experiments.

### 3.2. Run a local Nginx server for testing

We need something to verify if we want to create an experiment verification. Let's start a new Nginx server with Docker and bind port *8080*:

```shell
docker run -d --name webserver --publish 8080:80 nginx
```

And verify the web server is online by navigating to `http://localhost:8080` using a web browser or from the command line:

```shell
curl -I http://localhost:8080
# HTTP/1.1 200 OK
# Server: nginx/1.23.4
# Date: Sat, 06 May 2023 14:25:50 GMT
# Content-Type: text/html ...
```

### 3.3. Create the experiment structure

Create a new experiment file, `probe-tolerances.yaml` with the following content to start with:

```yaml
title: "ChaosToolkit Tolerance Examples"
description: |
  This experiment contains examples of how to set tolerance values
  for experiment probes for the steady-state hypothesis verification

steady-state-hypothesis:
  title: "A collection of probe tolerances"
  probes:
    - type: probe
      name: "server-must-respond-200"
      tolerance: 200
      provider:
        type: http
        url: "http://localhost:8080"
        method: "GET"
        timeout: 3
      
method: []
```

This simple experiment defines nothing more than the *steady-state hypothesis verification*, which we can use to test our tolerances.

## 4. What Are Probes Returning?

We learned that tolerances are evaluated against the output value of a probe. So naturally, it's important to understand the value the probe returns.

The best way to do this is to run the experiment once and then search for the probe output in the **journal.json** file. To check the output of the `http` probe defined in the experiment:

```shell
chaos run probe-tolerances.yaml
```

And then, open the **journal.json** file with our favourite editor and find the value for *steady_states > before > probes > output*.

I prefer not to leave the command line for this, so I use `jq` to print the output values in the console:

```shell
jq '.steady_states.before.probes[].output' journal.json
# 
# {
#   "status": 200,
#   "headers": {
#     "Server": "nginx/1.23.4",
#     "Date": "Sat, 06 May 2023 14:24:46 GMT",
#     "Content-Type": "text/html",
#     "Content-Length": "615",
#     "Last-Modified": "Tue, 28 Mar 2023 15:01:54 GMT",
#     "Connection": "keep-alive",
#     "ETag": "\"64230162-267\"",
#     "Accept-Ranges": "bytes"
#   },
#   "body": "<!DOCTYPE html>\n<html>\n<head>\n ..."
# }
```

But wait a minute! If this is the actual probe output, how can our `tolerance: 200` match this entire structure? 🤔

The reason is that the built-in **http** probe in ChaosToolkit has been designed to match the `status` field by default.

Though, it's interesting to see that we have much more data at our disposal, like request headers and the entire page body! We'll see how to use them later in in the article.

## 5. How To Set Tolerances For Probes

ChaosToolkit supports different ways to set tolerances and match different kinds of probes output:

* **scalar** values for exact matching of *integers*, *strings* and *booleans*
* **sequences** to check values are between lower and upper bounds or in a list of possible values
* **ranges** to match all values within a range
* **regex** to match strings using regular expressions
* **jsonpath** to set tolerances for complex object structures

### 5.1. Tolerance for scalar values

The simplest way to set a tolerance value for a probe is with an exact match of a scalar value. In the previous example, we've already seen a **scalar tolerance** in action with the *HTTP probe*.

Scalar values for tolerances support three types: **integers**, **json strings** and **booleans**.

Let's add a second probe to the steady-state hypothesis to verify that an *output.log* file does not exist:

```yaml
steady-state-hypothesis:
  title: "Scalar values verification"
  probes:
    - type: probe
      name: "server-must-respond-200"
      tolerance: 200  # exact integer match
      provider:
        type: http
        url: "http://localhost:8080"
        method: "GET"
        timeout: 3
    - type: probe
      name: "file-must-not-exist"
      tolerance: false  # exact boolean match
      provider:
        type: python
        module: os.path
        func: exists
        arguments:
          path: "./output.log"
```

### 5.2. Sequences

We can't define a steady state of a system with just scalar tolerances. For example, it's normal for an HTTP request to take between 0 and 500 milliseconds to respond or for an endpoint to respond with a JSON or an XML document.

We can define a tolerance as a **sequence** ChaosToolkit experiments using the *array* notation `[ elem1, ..., elemN]`. Depending on how many elements we include in the sequence, it can be interpreted as a **range** or a **list of exact matches**. Sounds complicated? 🤯 Let me explain:

* A sequence with **exactly two elements** `[lower, upper]` will verify that the probe value is between the **lower** and the **upper** bound
* A sequence with **three elements or more** `[ elem1, elem2, ..., elemN]` will verify the output value of the probe matches one of the elements in the list

Let's see some examples.

To verify that our web server responds in less than 500 milliseconds, we can use the sequence as a range between 0 and 500 ms:

```yaml
steady-state-hypothesis:
  title: "Sequence probe as range"
  probes:
    - type: probe
      name: "should-respond-in-500ms-or-less"
      tolerance: [0, 500]  # with two values, tolerance is a range
      provider:
        type: python
        module: chaostutorial.http.probes
        func: request_duration
        arguments:
          url: "http://localhost:8080"
          method: "GET"
          timeout: 3
```


If we need to verify that the response *mime-type* is one of the accepted values *XML* or *HTML* or *plain text*:


```yaml
steady-state-hypothesis:
  title: "Sequence probe as list"
  probes:
    - type: probe
      name: "should-be-allowed-mime-type"
      tolerance:  # with 3 or more values, tolerance is list
        - 'text/plain'
        - 'text/html'
        - 'application/xml'
      provider:
        type: python
        module: chaostutorial.http.probes
        func: response_mime_type
        arguments:
          url: "http://localhost:8080"
          method: "GET"
          timeout: 3
```

In this example, because we used **more than two** values in the sequence, the tolerance will be met if the response mime type matches any of the listed options.

| Sometimes, the fact that you need three or more options to use an exact match with a sequence can be a limitation. For instance: if you only need to match either *text/plain* or *text/html*, you can work around the problem by including a third option that is either impossible or `null`.


### 5.3. Ranges

**Range** tolerances do almost the same job as a sequence with two elements. In fact, they verify the probe output is between a lower and upper bound. To define a range, we use the following notation:

```yaml
tolerance:
  type: range
  range: [ lower, upper ]
      
# or

tolerance:
  type: range
  range:
    - lower
    - upper
```

I said almost the same job. The beauty of ranges is that they can also work with probes with an object output.

Using the **target** parameter for a range, we can specify which output attribute to match the tolerance with. For example, we already know the **http** probe returns the HTTP response as an object. We can use the **target** attribute to match any status code between `200` and `299`:

```yaml
steady-state-hypothesis:
  title: "Range tolerance with target value"
  probes:
    - type: probe
      name: "server-must-respond-2xx"
      tolerance:  # Range tolerance
        type: range
        target: status  # Will match response "status"
        range:
          - 200
          - 299
      provider:
        type: http
        url: "http://localhost:8080"
        method: "GET"
        timeout: 3
```

### 5.3. Regular expressions

Regular expressions are a powerful text-matching tool, and we can use them with our tolerances by specifying the **regex** type:

```yaml
steady-state-hypothesis:
  title: "Probe with regular expressions"
  probes:
    - type: probe
      name: "should-be-allowed-mime-type"
      tolerance:  # Tolerance match with regular expression
        type: regex
        pattern: "text\/[plain|html]"
      provider:
        type: python
        module: chaostutorial.http.probes
        func: response_mime_type
        arguments:
          url: "http://localhost:8080"
          method: "GET"
          timeout: 3
```

Like range tolerances, **regex** supports the **target** attribute to select a specific matching field from the output.

An interesting use for the *target* in combination with *regex* is to match the output of a **process** probe:

{% raw %}
```yaml
steady-state-hypothesis:
  title: "Regex matching with target"
  probes:
    - type: probe
      name: "container-must-exist"
      tolerance:
        type: regex
        pattern: "webserver"
        target: stdout
      provider:
        type: process
        path: docker
        arguments: "container ps --filter name=webserver --format '{{lower .Names}}'"
```
{% endraw %}

When using the **process** probe, the actual output of the shell command is in the `stdout` field of the returned object. This match would not have been possible using a scalar tolerance, so this is a simple way to work around the problem.

### 5.4. Match complex objects with jsonpath

Last, we'll see how to use **jsonpath** to define complex matching criteria when probes return deep JSON structures.

The **jsonpath** tolerance uses Python's `jsonpath2` library under the hood. Like RegEx, the Jsonpath syntax offers many options, and we can't possibly cover all of them in this article. If you're interested in the full specification, you can find it in <a href="https://jsonpath2.readthedocs.io/en/latest/exampleusage.html" target="_blank"> the official documentation page</a>.

To use **jsonpath**, we first need to install it:

```shell
pip install jsonpath2
```

As an example we'll use jsonpath to match some values returned by the http probe. As part of the response, we can access all header values returned. For instance, we could access the *mime-type* information directly from the headers:

```yaml
steady-state-hypothesis:
  title: "Content-type should be 'text/html'"
  probes:
    - type: probe
      name: "content-type-should-be-html"
      tolerance:  # Match json object with jsonpath2
        type: jsonpath
        path: '$["headers"]["Content-Type"]'
        expect: "text/html"
      provider:
        type: http
        url: "http://localhost:8080"
        method: "GET"
        timeout: 3
```

Another advantage of *jsonpath* is its functions. Since the probe returns the whole response body, we could add a verification to make sure the returned request is not empty, for example, by checking that the total length of the body is more than 500 characters:

```yaml
steady-state-hypothesis:
  title: "Response content should have more than 500 character"
  probes:
    - type: probe
      name: "response-must-not-be-empty"
      tolerance:  # use lenght() function to calculate body size
        type: jsonpath
        path: '$.body[length()][?(@ > 500)]'
      provider:
        type: http
        url: "http://localhost:8080"
        method: "GET"
        timeout: 3
```

Notice how we didn't use the `expect` parameter for the tolerance in this last example because jsonpath expressions like `[?(@ > 500)]` already evaluate as either a *positive* or *negative* match.

## 6. Conclusion

In this article, we looked at all the different ways to specify tolerance values for chaos experiments with ChaosToolkit as **scalar**, **sequence**, **range**, **regex** or **jsonpath**.

As always, all examples used in this post and more are available <a href="https://github.com/DevLearnOps/tutorials/tree/main/chaos-engineering/set-tolerance-values-in-chaostoolkit-experiments" target="_blank">over on GitHub</a>


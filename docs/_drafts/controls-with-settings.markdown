---
layout: post
title:  "Apply ChaosToolkit Controls Globally To All Your Experiments"
description: |
    In this article we apply ChaosToolkit controls globally to upload all our experiment
    journals into an AWS S3 bucket.
date:   2023-05-20
categories: "chaos-engineering"
tags: chaos-engineering chaostoolkit
author: "Manuel Castellin"
# permalink: "/mastering-chaostoolkit-experiment-configuration"
excerpt: ""
---

## 1. Overview

ChaosToolkit controls are an essential tool that can help us orchestrate the execution flow of chaos experiments.

Even though they're not part of the experiment method or hypothesis, they play an important role when we need to extend our templates with additional capabilities or intercept and modify certain experiment steps.

In this article we'll learn how to apply ChaosToolkit controls to all our experiments globally so we don't have to maintain them in every single template we create.

## 2. Upload Ctk Journal To An S3 Bucket

The most common reasons to apply controls to chaos experiments are observability and reporting. For every experiment we run on an environment at the very least we need to save the experiment results to track exactly what happend and when, either by saving the ChaosToolkit journal file or by sending metrics to an aggregator or database.

In this example, we'll use the S3 Upload control from the **chaostoolkit-aws** module to automatically upload the experiment journal into an S3 Bucket on AWS once the execution is finished.

For the purpose of the experiment we don't need anything complicated, so let's create an `experiment.yaml` file with the following content:

```yaml
title: "A an experiment to check if a bucket exists"
description: |
  This experiment is for demonstration purposes and it verifies
  a bucket exists in S3

configuration:
  aws_profile_name: devlearnops
  aws_region: us-east-1

# The `chaosaws.s3.controls.upload` control will upload
# the experiment journal to "s3://ctk-journals/journals"
# once the experiment is finished
controls:
  - name: upload
    provider:
      type: python
      module: chaosaws.s3.controls.upload
      arguments:
        bucket_name: "ctk-journals"
        suffix_with_timestamp: true
        dirpath: 'journals'

steady-state-hypothesis:
  title: "Bucket exists in S3"
  probes:
    - type: probe
      name: "journals-bucket-exists"
      tolerance: true
      provider:
        type: python
        module: chaosaws.s3.probes
        func: bucket_exists
        arguments:
          bucket_name: "ctk-journals"

method: []
```

This experiment will simply verify the journal buckets exists in S3 and then the **upload** module we defined in the `controls:` section will take care of uploading the execution results into the bucket.

To run the experiment let's first create the bucket with the following:

```shell
aws s3api --profile devlearnops --region us-east-1 \
    create-bucket --bucket ctk-journals
```

And once the bucket is created, let's run the experiment:

```shell
chaos --verbose run experiment.yaml
# ...
# [DEBUG] [python:196] Control 'after_experiment_control' loaded from '.../chaosaws/s3/controls/upload.py'
# [DEBUG] [__init__:76] Using AWS region 'us-east-1'
# [DEBUG] [__init__:85] Client will be using profile 'devlearnops' from boto3 session
# [DEBUG] [upload:87] Results were uploaded to 'journals/journal-2023-05-11T09:41:30.836413+00:00.json'
# ...
```

The `--verbose` option will print debug logs for the chaos experiment so we can see the control module is actually running. To verify the journal was uploaded to S3 we list the content of the bucket:

```shell
aws s3 --profile devlearnops --region us-east-1 ls --recursive ctk-journals
# 2143 journals/journal-2023-05-11T09:41:30.836413+00:00.json
```

And there's our journal file uploaded to the **ctk-journals** bucket. In the next section we'll see how to apply the **upload** control to all our experiments by default, even when it's not defined inside the ChaosToolkit template.

## 3. Apply Controls From File

In ChaosToolkit we can apply controls to existing experiments using the `--control-file <PATH>` option and store the configuration in a file.

Let's create a new experiment `http-check.yaml` with the following content:

```yaml
title: "Check service online"
description: |
  Check website responds with 200 HTTP status code

steady-state-hypothesis:
  title: "Check website online"
  probes:
    - type: probe
      name: "check-http-status"
      tolerance: 200
      provider:
        type: http
        url: "http://www.google.com/"
        method: "GET"

method: []
```

The experiment does not define any control, so we create another file called `s3-upload.yaml` and add the configuration for the journal upload:

```yaml
# The format for control-files is the following:
#
# [control_name]:
#   provider:
#     [... provider configuration]
#
s3-upload:
  provider:
    type: python
    module: chaosaws.s3.controls.upload
    arguments:
      bucket_name: "ctk-journals"
      suffix_with_timestamp: true
      dirpath: 'journals'
```

Because we no longer have the AWS region and profile configuration in the experiment, we can set those values using environment variables as described in the [AWS CLI documentation](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-envvars.html#envvars-list):

```shell
export AWS_PROFILE=devlearnops
export AWS_DEFAULT_REGION=eu-west-1
```

And execute the experiment with the *s3-upload* control:

```shell
chaos --verbose run \
    --control-file s3-upload.yaml \
    http-check.yaml
...
# [DEBUG] Applying after-control 's3-upload' on 'experiment'
# [DEBUG] Control 'after_experiment_control' loaded from '/chaosaws/s3/controls/upload.py'
# [DEBUG] The configuration key `aws_region` is not set, 
#     looking in the environment instead for `AWS_REGION` or `AWS_DEFAULT_REGION`
# [DEBUG] Using AWS region 'eu-west-1'
# [DEBUG] Results were uploaded to 'journals/journal-2023-05-11T10:10:50.251895+00:00.json'
...
```

## 4. Apply Controls Globally With ChaosToolkit Settings

We can instruct ChaosToolkit to use global configurations using the settings file. By default the framework will look apply any configuration stored under your user's home directory in the `$HOME/.chaostoolkit/settings.yaml` file.

We can use this feature to apply the s3-upload control for all experiments we run in our environment so we don't need to use the `--control-file` option.

Create or modify the `$HOME/.chaostoolkit/settings.yaml` file and make sure you add the following section:

```yaml
controls:
  s3-upload:
    provider:
      type: python
      module: chaosaws.s3.controls.upload
      arguments:
        bucket_name: "ctk-journals"
        suffix_with_timestamp: true
        dirpath: 'journals'
```

We can now run the **http-check.yaml** experiment and see the control is applied automatically:

```shell
chaos --verbose run http-check.yaml
# ...
# [DEBUG] Using settings file '/Users/manuel/.chaostoolkit/settings.yaml'
# [DEBUG] Loading global control 's3-upload'
# ...
```

If you check your debug logs, you should be able to see the s3-upload control is loaded from the global settings file.

If you can't modify the global settings file or you prefer a less invasive approach, you can still specify a different file from command line:

```shell
chaos --settings ./config/settings.yaml \
    run http-check.yaml
```

## 5. Cleanup

If you tried the steps described in this article yourself you may want to cleanup the resources created by the experiments. First we empty the *ctk-journals* bucket with:

```shell
aws s3 --profile devlearnops --region us-east-1 \
    rm s3://ctk-journals --recursive
# delete: s3://ctk-journals/journals/journal-2023-05-11T10:10:50.251895+00:00.json
# delete: s3://ctk-journals/journals/journal-2023-05-11T10:25:54.046867+00:00.json
# ...
```

And finally delete the bucket from:

```shell
aws s3api --profile devlearnops --region us-east-1 \
    delete-bucket --bucket ctk-journals
```

## 6. Conclusion

In this article, we looked at how to apply ChaosToolkit controls to all our existing chaos experiments either via the `--control-file` command-line option or using global `settings`.

As always, all examples used in this post are available
<a href="https://github.com/DevLearnOps/tutorials/tree/main/chaos-engineering/" target="_blank">over on GitHub</a>

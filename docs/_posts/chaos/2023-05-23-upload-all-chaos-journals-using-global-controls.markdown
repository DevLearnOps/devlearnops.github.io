---
layout: post
title:  "Upload All Chaos Toolkit Journals To S3 Using Global Controls"
description: >-
    In this article, we learn how to apply Chaos Toolkit controls globally for all our experiments
    using config files and upload execution journals to an S3 bucket.
date:   2023-05-23
categories: "chaos-engineering"
tags: chaos-engineering chaostoolkit
author: "Manuel Castellin"
permalink: "/apply-ctk-controls-globally-s3-bucket-upload"
excerpt: >-
    In this article, we learn how to apply Chaos Toolkit controls globally for all our experiments
    using config files and upload execution journals to an S3 bucket.
---

## 1. Overview

Chaos Toolkit controls are an essential tool that can help us orchestrate the execution flow of chaos experiments.

Even though they're not part of the experiment method or hypothesis, **controls play an essential role when we need to extend our templates with additional capabilities or intercept and modify specific experiment steps**.

In this article, we'll learn how to apply Chaos Toolkit controls to all our experiments globally so we don't have to maintain them in every template we create.

## 2. Upload Ctk Journal To An S3 Bucket

Observability and reporting are the most common reasons to apply controls to chaos experiments. For every experiment we run on an environment, at the very least, we need to save the results to track what happened during the execution, either by storing the journal file or sending metrics to an aggregator or database.

In this example, we'll use the S3 Upload control from the `chaostoolkit-aws` module to automatically **save the experiment journal into an S3 Bucket on AWS** once the execution is finished.

For this exercise we don't need anything complicated, so let's create an `experiment.yaml` file with the following content, *making sure to replace the `<ACCOUNT-ID>` with your own AWS account number to create a unique bucket name*:

```yaml
title: "An experiment to check if a bucket exists"
description: |
  This experiment is for demonstration purposes and it verifies
  a bucket exists in S3

configuration:
  aws_profile_name: devlearnops
  aws_region: us-east-1

# The `chaosaws.s3.controls.upload` control will upload
# the experiment journal to "s3://<ACCOUNT-ID>-ctk-journals/journals"
# once the experiment is finished
controls:
  - name: upload
    provider:
      type: python
      module: chaosaws.s3.controls.upload
      arguments:
        # replace with your AWS account number
        bucket_name: "<ACCOUNT-ID>-ctk-journals"
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
          bucket_name: "<ACCOUNT-ID>-ctk-journals"

method: []
```

This experiment will verify the journal buckets exist in S3, and then the **upload** module we defined in the `controls:` section will take care of uploading the execution results into the bucket.

To run the experiment, we first need to create the bucket with the following commands:

```shell
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

aws s3api --profile devlearnops --region us-east-1 \
    create-bucket --bucket "${AWS_ACCOUNT_ID}-ctk-journals"
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

The `--verbose` option will print debug logs for the chaos experiment to see if the control module is running. To verify the journal has been uploaded to S3, we list the content of the bucket:

```shell
aws s3 --profile devlearnops --region us-east-1 ls --recursive "${AWS_ACCOUNT_ID}-ctk-journals"
# 2143 journals/journal-2023-05-11T09:41:30.836413+00:00.json
```

And there's our journal file uploaded to the **ctk-journals** bucket. In the next section, we'll see how to apply the **upload** control to all our experiments by default, even when it's not defined inside the Chaos Toolkit template.

## 3. Apply Controls From File

With Chaos Toolkit, we can apply controls to existing experiments using the `--control-file <PATH>` option and store the configuration in a file.

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
      # replace with your AWS account number
      bucket_name: "<ACCOUNT-ID>-ctk-journals"
      suffix_with_timestamp: true
      dirpath: 'journals'
```

Because we no longer have the AWS region and profile configuration in the experiment, we can set those values using environment variables as described in the <a href="https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-envvars.html#envvars-list" target="_blank">AWS CLI documentation</a>:

```shell
export AWS_PROFILE=devlearnops
export AWS_DEFAULT_REGION=us-east-1
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
# [DEBUG] Using AWS region 'us-east-1'
# [DEBUG] Results were uploaded to 'journals/journal-2023-05-11T10:10:50.251895+00:00.json'
...
```

## 4. Apply Controls Globally With Chaos Toolkit Settings

We can instruct Chaos Toolkit to use global configurations using a settings file. By default, the framework will apply any configuration stored under your user's home directory in `$HOME/.chaostoolkit/settings.yaml`.

We can use this feature to include the s3-upload control for all experiments we run in our environment without adding the `--control-file` option to every command.

Create or modify the `$HOME/.chaostoolkit/settings.yaml` file, and make sure you add the following section:

```yaml
controls:
  s3-upload:
    provider:
      type: python
      module: chaosaws.s3.controls.upload
      arguments:
        bucket_name: "<ACCOUNT-ID>-ctk-journals"
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

We can see the s3-upload control was loaded from the global settings file.

If you can't modify the global settings file or prefer a less invasive approach, you can still specify a different file from the command line, for example:

```shell
chaos --settings ./config/settings.yaml \
    run http-check.yaml
```

## 5. Cleanup

If you tried the steps described in this article yourself, you may want to cleanup the resources created by the experiments. First, we empty the *ctk-journals* bucket with the following:

```shell
aws s3 --profile devlearnops --region us-east-1 \
    rm "s3://${AWS_ACCOUNT_ID}-ctk-journals" --recursive
# delete: s3://ctk-journals/journals/journal-2023-05-11T10:10:50.251895+00:00.json
# delete: s3://ctk-journals/journals/journal-2023-05-11T10:25:54.046867+00:00.json
# ...
```

And finally, delete the bucket:

```shell
aws s3api --profile devlearnops --region us-east-1 \
    delete-bucket --bucket "${AWS_ACCOUNT_ID}-ctk-journals"
```

## 6. Conclusion

In this article, we learned how to apply Chaos Toolkit controls to all our existing chaos experiments via the `--control-file` command-line option or global `settings`.

As always, all examples used in this post are available
<a href="https://github.com/DevLearnOps/tutorials/tree/main/chaos-engineering/chaostoolkit-journal-s3-upload" target="_blank">over on GitHub</a>

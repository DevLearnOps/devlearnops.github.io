---
layout: post
title:  "Install Software Packages in Alpine-Based Containers"
description: >-
    In this article we'll learn how to customize Alpine-based Docker images by installing
    additional software we need to run our applications in containers.
date:   2023-05-02
categories: "containers"
tags: docker linux
author: "Manuel Castellin"
permalink: "/install-software-alpine-docker-containers"
excerpt: ""
---

## 1. Overview

Most container images we can find in DockerHub offer an *Alpine-based* version, and for good reasons.
If you're not familiar with <a href="https://www.alpinelinux.org/about/" target="_blank">**Alpine Linux**</a> already, it's a general purpose Linux distribution built around three principles: **Small**, **Simple** and **Secure**.

In this article, we'll learn how to **customize Alpine-based Docker images by installing additional software we need to run our applications**.

## 2. *Add* Common Software Packages

Alpine Linux is built with simplicity in mind, so to keep Docker images as small as possible, you'll find that these containers lack even the most common software like `curl` or `bash`. Let's learn how to install them.

Alpine Linux uses `apk` as its package manger, and like other popular Linux distros, you'll need to run an `apk update` to build repository caches before you can search and install packages.

To **add** software to an Alpine-based container use the `apk add <package_name>` command:

```terminal
/ # apk update
/ # apk add curl
```

### 2.1. Installing software in Dockerfiles

When writing Dockerfiles it's good practice making sure the final container image is as small as it can be. The `apk` package manger can install software without using repository caches at all and it's the method I recommend:

```Dockerfile
FROM apline:3.17

# Preferred method, easier to read
RUN apk add --no-cache bash
```

The installation command above has the same effect as running an `apk update` and `rm -rf /var/cache/apk` after the package installation:

```Dockerfile
FROM alpine:3.17

# Same effect as the example above but using 3 commands
RUN apk update \
    && apk add bash \
    && rm -rf /var/cache/apk
```


## 3. Search For Available Packages

If we don't know the name of the software package in advance we can use the `apk search` command to find the correct one to install. In this example we'll install **python** and **pip** on an empty Alpine container.

First let's open a shell in a new Alpine container with:
```terminal
> docker run --rm -it alpine:3.17 /bin/sh
/ # 
```

Then run an `apk update` to build the repository cache and search for the **python3** package:

```terminal
/ # apk update
/ # apk search python3
...
postgresql15-plpython3-contrib-15.2-r0
python3-dbg-3.10.11-r0
python3-3.10.11-r0                  <<<<<<<<<<
xapian-bindings-python3-1.4.21-r0
python3-tkinter-tests-3.10.11-r0
...
```

The result is a list of all packages that match our search criteria. We install python3 with:

```terminal
/ # apk add python3-3.10.11-r0
```

You should now be able to verify the Python installation with:

```terminal
/ # python3 --version
Python 3.10.11
```

### 3.1. Show packages description when searching

Sometimes package names can be cryptic so it's useful to have a short description of what we're selecting. To see an example we'll search for the Python3 `pip` package using the `-v` flag:

```terminal
/ # apk search -v pip
...
execline-2.9.0.1-r0 - A small scripting language, to be used in p...
pipewire-spa-bluez-0.3.61-r0 - PipeWire BlueZ5 SPA plugin (Blueto...
py3-pip-22.3.1-r1 - Tool for installing and managing Python packages  <<<<<<<
vanessa_socket-0.0.13-r1 - User space TCP/IP pipe
pipr-0.0.16-r0 - A tool to interactively write shell pipelines
...
```

Now that we know the name of the package is `py3-pip`, we can install it and verify it works:

```terminal
/ # apk add py3-pip
Executing busybox-1.35.0-r29.trigger
OK: 85 MiB in 34 packages

/ # pip --version
pip 23.1.2 from /usr/lib/python3.10/site-packages/pip (python 3.10)
```

## 4. Enable Additional Package Repositories

Alpine Linux has two main package repositories:
* **main** packages are software that have direct support from the Alpine core maintainer
* **community** packages are those made and maintained by community contributors

**Apk package repositories are maintained in the `/etc/apk/repositories` file** and by default should have two entries for *main* and *community* locations:

```terminal
/ # cat /etc/apk/repositories
https://dl-cdn.alpinelinux.org/alpine/v3.17/main
https://dl-cdn.alpinelinux.org/alpine/v3.17/community
```

If you're trying to install software from a third-party repository, or for some reason the default repos are not available, all you need to do is add them to the `/etc/apk/repositories` file.

> Don't forget to run the `apk update` command after updating the repositories list to rebuild search caches

For instance, to make sure *main* and *community* repos are enabled in a Dockerfile:

```Dockerfile
# Ensure community repository is enabled
RUN VERSION="v$(cut -d'.' -f1,2 /etc/alpine-release)" \
    && echo "https://dl-cdn.alpinelinux.org/alpine/$VERSION/main/" > /etc/apk/repositories \
    && echo "https://dl-cdn.alpinelinux.org/alpine/$VERSION/community/" >> /etc/apk/repositories

# Install additional software
RUN apk update \
    && apk install nginx
```

## 5. Remove Unused Software

To keep container as small and secure as possible it's good practice to remove any software we installed and it's not used by the final application.

To remove installed packages we use the `apk del` command. For example to remove *curl*:

```terminal
/ # apk del curl
OK: 85 MiB in 34 packages
```

## 6. Conclusion

In this article, we learned how to customise Alpine-based images by installing additional software from the *main* and *community* package repositories.

A working example of a Dockerfile with the code shown in this article is available <a href="https://github.com/DevLearnOps/tutorials/tree/main/containers/install-software-alpine" target="_blank">over on GitHub</a>


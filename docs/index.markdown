---
# Feel free to add content and custom Front Matter to this file.
# To modify the layout, see https://jekyllrb.com/docs/themes/#overriding-theme-defaults

layout: homepage
title: Blog
order: 1
description: |
    A blog for engineers made by engineers.
---

```python
def dev_learn_ops(engineer, blog):
    """ a blog for engineers made by engineers """
    articles = blog.articles
    devops_engineer = engineer.deepcopy()
    while articles.has_more():
        devops_engineer.learn(
            articles.next()
        )
        devops_engineer.sleep(8 * 3600)
        devops_engineer.drink(☕️).eat(🌮)

    return devops_engineer

```

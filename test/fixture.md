# Heading 1

## Heading 2

### Heading 3

#### Heading 4

##### Heading 5

###### Heading 6

Setext Heading 1
================

Setext Heading 2
----------------

Plain paragraph with no markup at all.

Paragraph with **bold** and *italic* and ***bold italic*** text.

Paragraph with ~~strikethrough~~ and `inline code` in it.

Double backtick: ``code with ` backtick``.

Visit [Example](http://example.com) for more info.

An image: ![Alt text](http://example.com/img.png)

A [full reference][ref1] link.

A [collapsed reference][] link.

A [shortcut link] by itself.

[ref1]: http://example.com
[collapsed reference]: http://example.com

> Simple block quote.

> Block quote with **bold** and `code` inside.
>
> Second paragraph in the quote.

> > Nested block quote.

- Item with dash
* Item with star
+ Item with plus

1. First ordered
2. Second ordered

- [ ] Unchecked task
- [x] Checked task

- Parent item
  - Nested item with **bold**
  - Nested item with `code`

| Name | Type | Description |
|------|------|-------------|
| foo  | `str` | A **foo** value |
| bar  | *int* | A [link](url) |

```python
def hello():
    return "world"
```

```
plain code block
```

    indented code block
    second line

---

***

___

<div>An HTML block</div>

A stray ~tilde here should not leak.

Into ~this paragraph as strikethrough.

Long line with **bold** and *italic* and `code` and [link](url) and ~~strike~~ scattered throughout to test that face boundaries work across a wide line.

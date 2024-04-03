https://github.com/mcastellin/golang-mastery
---
layout: post
title: "Background Tasks And Cancellation In Go (lang)"
description: >-
  In this article, we'll learn how to run tasks in the background using Go and implement
  graceful termination.
date: 2024-03-28
updated: 2024-04-03
categories: "golang"
tags: content-creation golang
image: assets/images/gopher.jpg
author: "Manuel Castellin"
permalink: "/golang-background-task-cancellation"
excerpt: >-
  In this article, we'll learn how to run tasks in the background using Go and implement
  graceful termination.
---

## 1. Overview
Task cancellation is straightforward for iterative background tasks that run inside a `for` loop,
though long-running one-time operations can be trickier.

The main issue with one-shot operations is that they are blocking and don't provide any chance to
bail out prematurely.

#### Example of long-running operation

Let's take a look at this implementation:
```go
// mockComplexOp represents a long-running, uninterruptible operation
// like a complex computation, a database transaction or an HTTP request
type mockComplexOp struct {
	Duration time.Duration
	timer    *time.Timer
}

// Do performs the uninterruptible operation.
// This mock implementation just sleeps for a set Duration
func (op *mockComplexOp) Do() error {
	op.timer = time.NewTimer(op.Duration)
	// reading from timer's channel is uninterruptible
	<-op.timer.C
	return nil
}

// Stop will gracefully terminate the long-running operation
func (op *mockComplexOp) Stop() {
	if op.timer != nil {
		if !op.timer.Stop() {
			<-op.timer.C
		}
	}
}
```
<div class="pre-source"><span>View the full source code <a href="https://github.com/mcastellin/golang-mastery/blob/main/background-task-cancellation/main.go#L9-L36" target="_blank">here</a></span></div>

As simple as the `mockComplexOp` is, it represents a real-world scenario where we need
to perform a certain task that is not interruptible. Examples of these tasks are:
- Complex *oneshot* calculations, like rendering tasks
- I/O operations, like reading from files or completing a database transaction
- HTTP interactions with other web servers

## 2. Background Tasks In Go

The `go` programming language makes it super-easy to run background tasks. In *Golang* they're called
goroutines, and all we need to do to run one is use the `go` keyword, followed by a function call:

```go
func main() {
	op := &mockComplexOp{Duration: time.Second}
	go op.Do()
}
```

One thing to notice is that when we spawn a background goroutine, the Go runtime will take ownership of that task
and we can no longer control its state. The sub-routine will **either run to completion or terminate early
if the main program exits.**

In Go, the only way to interact with a goroutine is by using specific structures called **channels**.

```go
// runOpOnce is just an example of how to execute a long-running operation in the
// background without any option for task cancellation.
func runOpOnce(op longRunningOp, completedCh chan struct{}) {
	op.Do()
	close(completedCh)
}
```
<div class="pre-source"><span>View the full source code <a href="https://github.com/mcastellin/golang-mastery/blob/main/background-task-cancellation/main.go#L43-L52" target="_blank">here</a></span></div>

In this example, `runOnce()` is a simple wrapper function that simply calls the `Do()` method on a `longRunningOp`
interface and notify the caller as soon as the operation is completed.

Of course, there are simpler ways of tracking goroutines completion in go (using `sync.WaitGroup`, for example), but
it's good to understand how we can do this ourselves using channels.

In Go, reading from a channel blocks the program execution until new data is pushed into the channel or the channel
itself is closed. In the function above, this means that when the `completedCh` is closed, all processes that are
reading from `completedCh` will be released:

```go
func main() {
	op := &mockComplexOp{Duration: time.Second}
	completed := make(chan struct{})
	go runOpOnce(op, completed)

	// reading from channel will block until the
	// channel is closed by runOpOnce
	<-completed
	fmt.Println("operation completed")
}
```

## 3. Task Cancellation Using Channels

In the previous section, we learned how **closing a Go channel can be used to send and receive signals between goroutines**.

We can now create a new version of the previous wrapper function that can receive a termination signal on the `cancelCh` channel
and attempt a graceful termination for the operation:

```go
func runOpWithCancelCh(
	op longRunningOp,
	completedCh chan struct{},
	cancelCh chan struct{}) {

	// decouple uninterruptible operation from its wrapper
	// by running in a new sub-routine, allowing this function
	// to handle cancellation logic.
	innerCompletedCh := make(chan struct{})
	go func() {
		op.Do()
		close(innerCompletedCh)
	}()

	select {
	case <-innerCompletedCh:
		// normal program execution, background process completed
		// successfully.

	case <-cancelCh:
		// received cancellation signal before operation could
		// complete. Requesting termination.
		op.Stop()
	}

	// always sending completion signal to avoid blocking callers
	close(completedCh)
}
```
<div class="pre-source"><span>View the full source code <a href="https://github.com/mcastellin/golang-mastery/blob/main/background-task-cancellation/main.go#L66-L96" target="_blank">here</a></span></div>

The first thing this function does is **decouple the long-running operation from the wrapper**. Because the operation is
uninterruptible, we can't handle cancellation if the routine is busy running the operation.

We use the `go` keyword to spawn a new sub-routine and delegate the operation execution. Because this is an *inner
routine*, we also create a dedicated channel to signal the operation completion.

After spawning the sub-routine, we introduced the handling logic for cancellation using the `select-case`.
In this implementation, if the `cancelCh` is closed before the operation sub-routine can complete, we call the `op.Stop()` method
to request graceful termination.


### 3.1. The `select-case` construct in Go

`select-case` is a variation of the `switch-case` construct designed to simplify handling communication over multiple channels.

In essence, every `case` defines a channel interaction, to read/write data from/to a specific channel. The `select` construct
will then activate the `case` that completes the channel interaction first.

Let me explain with an example:

```go
func main() {
	boolCh := make(chan bool)

	b := <-boolCh // permanently blocked!!
	fmt.Printf("Boolean value is %t", b)
}
```

Since nothing is writing data into the `boolCh`, the read operation `case b := <-boolCh` will never complete. As
a result, this program will hang indefinitely.

We can use the `select-case` to implement a timeout on the channel read as follows:

```go
func main() {
	boolCh := make(chan bool)

	select {
	case b := <-boolCh:
		fmt.Printf("Boolean value is %t", b)

	case <-time.After(time.Second):
		// timer will activate first.
		fmt.Println("Operation timed out.")
	}
}
```

In this second example, *the `select` activates the `case` corresponding to the interaction that completes first
(our 1-second timer in this case)* giving us a chance to exit the program if the `boolCh` is inactive for too long.


### 3.2. Cancelling an operation with channel

The last thing we need to do is use the `runOpWithCancelCh` to run a new operation and cancel it before it
can complete:

```go
func TestBackgroundTaskWithChanCancel(t *testing.T) {
	// long-running operation will block for 5 seconds
	op := &mockComplexOp{Duration: 5 * time.Second}

	completedCh := make(chan struct{})
	cancelCh := make(chan struct{})
	go runOpWithCancelCh(op, completedCh, cancelCh)

	// sleep 1 second and close cancelCh to request
	// cancellation. The operation should cancel immediately.
	time.Sleep(time.Second)
	close(cancelCh)

	select {
	case <-completedCh:
		// task execution should cancel immediately and
		// signal goroutine completion

	case <-time.After(time.Second):
		t.Fatal("task execution was not cancelled timely")
	}
} 
```
<div class="pre-source"><span>View the full source code <a href="https://github.com/mcastellin/golang-mastery/blob/main/background-task-cancellation/main_test.go#L38-L60" target="_blank">here</a></span></div>

## 4. Cancellation Using Context

Since version *1.7*, the `context` package has been introduced into Go's *standard library*. It provides **a way to
manage and propagate cancellation signals, deadlines and request-scoped values** across goroutines.

For our purposes, implementing task cancellation using `Context` is not necessarily simpler, though it provides a
nicer interface for the function caller.

Let's get into it:

```go
// runOpWithContext executes the long-running operation and handle cancellation
// when the Context is Done.
func runOpWithContext(
	ctx context.Context,
	op longRunningOp,
	completed chan struct{}) {

	// decouple uninterruptible operation from its wrapper
	fnCompleted := make(chan struct{})
	go func() {
		op.Do()
		close(fnCompleted)
	}()

	select {
	case <-fnCompleted:
		// normal program execution, background process completed
		// successfully.

	case <-ctx.Done():
		// Context timed-out or cancelled before operation could
		// complete. Requesting termination.
		op.Stop()
	}

	// always sending completion signal to avoid blocking callers
	close(completed)
}
```
<div class="pre-source"><span>View the full source code <a href="https://github.com/mcastellin/golang-mastery/blob/main/background-task-cancellation/main.go#L98-L129" target="_blank">here</a></span></div>

The implementation is almost identical, except for the cancellation `case` in the handling logic.
To receive the cancellation signal from a `context.Context` all we have to do is read from the `ctx.Done()` channel.

And lastly, here is how we call the function to handle cancellation with context:

```go
func TestBackgroundTaskWithContext(t *testing.T) {
	// long-running operation will block for 5 seconds
	op := &mockComplexOp{Duration: 5 * time.Second}

	// setup context that times-out in 1 second.
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()

	completedCh := make(chan struct{})
	go runOpWithContext(ctx, op, completedCh)

	select {
	case <-completedCh:
		// task execution should cancel immediately and
		// signal goroutine completion

	case <-time.After(2 * time.Second):
		t.Fatal("task execution was not cancelled timely")
	}
} 
```
<div class="pre-source"><span>View the full source code <a href="https://github.com/mcastellin/golang-mastery/blob/main/background-task-cancellation/main_test.go#L62-L82" target="_blank">here</a></span></div>

## 5. Conclusion

In this article, we learned different ways to gracefully cancel long-running operations running Go subroutines.

As always, all examples used in this post and more are available
<a href="https://github.com/mcastellin/golang-mastery/tree/main/background-task-cancellation" target="_blank">over on GitHub</a>


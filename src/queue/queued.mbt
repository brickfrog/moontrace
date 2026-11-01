///|
/// A bounded queue between synchronous logging and a slow async sink. Built by
/// `queued`.
pub struct QueuedSubscriber {
  priv sink : async (Array[@moontrace.Event]) -> Unit
  priv queue : @aqueue.Queue[@moontrace.Event]
  priv max_batch : Int32
  priv mut enqueued : Int64
  priv mut delivered : Int64
  priv mut failed : Int64
  priv mut dropped : Int64
  priv mut closing : Bool
  priv mut worker_running : Bool
}

///|
/// Wrap an async `sink` that receives batches of events.
///
/// `subscriber()` never blocks: it copies the event and enqueues it, or drops
/// and counts it when `capacity` events are already waiting or the queue is
/// shutting down. Spawn `run()` in your task group to deliver batches of up to
/// `max_batch` events. `flush()` waits for every event accepted before the
/// call, and `shutdown()` stops intake, drains, and ends the worker. Both drain
/// in the calling task when no worker is running. A batch whose sink raises is
/// counted in `failed()` and the worker continues. Nonpositive sizes clamp to
/// one. No tasks are started by construction or logging.
pub fn queued(
  sink : async (Array[@moontrace.Event]) -> Unit,
  capacity~ : Int32 = 1024,
  max_batch~ : Int32 = 128,
) -> QueuedSubscriber {
  {
    sink,
    queue: @aqueue.Queue(kind=Blocking(if capacity < 1 { 1 } else { capacity })),
    max_batch: if max_batch < 1 {
      1
    } else {
      max_batch
    },
    enqueued: 0L,
    delivered: 0L,
    failed: 0L,
    dropped: 0L,
    closing: false,
    worker_running: false,
  }
}

///|
pub fn QueuedSubscriber::subscriber(
  self : QueuedSubscriber,
) -> (@moontrace.Event) -> Unit {
  event => {
    if self.closing {
      self.dropped += 1L
      return
    }
    let copy = { ..event, fields: event.fields.copy(), }
    let accepted = self.queue.try_put(copy) catch { _ => false }
    if accepted {
      self.enqueued += 1L
    } else {
      self.dropped += 1L
    }
  }
}

///|
/// Events accepted into the queue.
pub fn QueuedSubscriber::enqueued(self : QueuedSubscriber) -> Int64 {
  self.enqueued
}

///|
/// Events handed to the sink in batches that completed.
pub fn QueuedSubscriber::delivered(self : QueuedSubscriber) -> Int64 {
  self.delivered
}

///|
/// Events in batches whose sink raised or was cancelled.
pub fn QueuedSubscriber::failed(self : QueuedSubscriber) -> Int64 {
  self.failed
}

///|
/// Events refused because the queue was full or shutting down.
pub fn QueuedSubscriber::dropped(self : QueuedSubscriber) -> Int64 {
  self.dropped
}

///|
fn QueuedSubscriber::settled(self : QueuedSubscriber) -> Int64 {
  self.delivered + self.failed
}

///|
fn QueuedSubscriber::take_batch(
  self : QueuedSubscriber,
  first : @moontrace.Event,
) -> Array[@moontrace.Event] {
  let batch = [first]
  while batch.length() < self.max_batch {
    let next = self.queue.try_get() catch { _ => None }
    match next {
      Some(event) => batch.push(event)
      None => break
    }
  }
  batch
}

///|
/// Deliver one batch, counting it as failed if the sink raises or the task is
/// cancelled during delivery.
async fn QueuedSubscriber::deliver(
  self : QueuedSubscriber,
  batch : Array[@moontrace.Event],
) -> Unit {
  let count = batch.length().to_int64()
  let mut settled = false
  defer (if !settled { self.failed += count })
  (self.sink)(batch) catch {
    _ => {
      self.failed += count
      settled = true
      return
    }
  }
  self.delivered += count
  settled = true
}

///|
/// Deliver queued events until `shutdown()` closes the queue. Only one worker
/// may run at a time.
pub async fn QueuedSubscriber::run(self : QueuedSubscriber) -> Unit {
  if self.worker_running {
    fail("moontrace queued subscriber worker is already running")
  }
  self.worker_running = true
  defer {
    self.worker_running = false
  }
  while true {
    let first = self.queue.get() catch {
      @aqueue.QueueAlreadyClosed => return
      err => raise err
    }
    self.deliver(self.take_batch(first))
    @async.pause()
  }
}

///|
async fn QueuedSubscriber::drain_here(self : QueuedSubscriber) -> Unit {
  while true {
    let next = self.queue.try_get() catch { _ => None }
    match next {
      Some(first) => self.deliver(self.take_batch(first))
      None => return
    }
  }
}

///|
/// Wait until every event accepted before this call is delivered or failed.
pub async fn QueuedSubscriber::flush(self : QueuedSubscriber) -> Unit {
  let target = self.enqueued
  while self.settled() < target {
    if self.worker_running {
      @async.pause()
    } else {
      self.drain_here()
      if self.settled() < target && !self.worker_running {
        // Remaining events are in a batch held by a stopped worker's
        // cancelled delivery; nothing more can settle them.
        return
      }
    }
  }
}

///|
/// Stop intake, deliver everything already accepted, and end the worker.
/// Safe to call more than once.
pub async fn QueuedSubscriber::shutdown(self : QueuedSubscriber) -> Unit {
  self.closing = true
  self.flush()
  self.queue.close()
  while self.worker_running {
    @async.pause()
  }
}

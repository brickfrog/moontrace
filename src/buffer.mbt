///|
pub(all) struct EventBuffer {
  mut events : Array[Event]
  capacity : Int
  inner : (Event) -> Unit
}

///|
pub fn buffer(inner : (Event) -> Unit, capacity? : Int = 10) -> EventBuffer {
  { events: [], capacity: if capacity < 1 { 1 } else { capacity }, inner }
}

///|
pub fn EventBuffer::subscriber(self : EventBuffer) -> (Event) -> Unit {
  fn(event) {
    self.events.push(event)
    if self.events.length() >= self.capacity {
      self.flush()
    }
  }
}

///|
pub fn EventBuffer::flush(self : EventBuffer) -> Unit {
  let eventsToFlush = self.events
  self.events = []
  eventsToFlush.each(fn(e) { (self.inner)(e) })
}

///|
pub fn EventBuffer::len(self : EventBuffer) -> Int {
  self.events.length()
}

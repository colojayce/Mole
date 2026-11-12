import Testing
@testable import MoleKit

@Suite struct RingBufferTests {
    @Test func keepsInsertionOrderBelowCapacity() {
        var buffer = RingBuffer<Int>(capacity: 3)
        buffer.append(1)
        buffer.append(2)
        #expect(buffer.elements == [1, 2])
        #expect(buffer.count == 2)
        #expect(buffer.last == 2)
    }

    @Test func dropsOldestWhenFull() {
        var buffer = RingBuffer<Int>(capacity: 3)
        buffer.append(contentsOf: [1, 2, 3, 4, 5])
        #expect(buffer.elements == [3, 4, 5])
        #expect(buffer.count == 3)
        #expect(buffer.last == 5)
    }

    @Test func emptyBufferHasNoLast() {
        let buffer = RingBuffer<Double>(capacity: 2)
        #expect(buffer.last == nil)
        #expect(buffer.elements.isEmpty)
    }
}

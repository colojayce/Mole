import Testing
@testable import MoleKit

@Suite struct FormatTests {
    @Test func bytesUseBinaryStepsWithMoleLabels() {
        #expect(Format.bytes(0) == "0 B")
        #expect(Format.bytes(1023) == "1023 B")
        #expect(Format.bytes(1024) == "1.0 KB")
        #expect(Format.bytes(38_654_705_664) == "36.0 GB")
        #expect(Format.bytes(494_384_795_648) == "460.4 GB")
    }

    @Test func sizeThatRoundsToAFullUnitReadsAsTheNextUnit() {
        #expect(Format.bytes(1_073_741_823) == "1.0 GB")
        #expect(Format.bytes(1_048_575) == "1.0 MB")
    }

    @Test func bytesPartsSplitNumberAndUnit() {
        let parts = Format.bytesParts(27_892_318_208)
        #expect(parts.number == "26.0")
        #expect(parts.unit == "GB")
    }

    @Test func rateConvertsMegabytesPerSecond() {
        #expect(Format.rate(mbPerSecond: 0) == "0 B/s")
        #expect(Format.rate(mbPerSecond: 0.0216) == "22.1 KB/s")
        #expect(Format.rate(mbPerSecond: -.infinity) == "0 B/s")
    }

    @Test func scalarFormats() {
        #expect(Format.percent(91.84) == "91.8%")
        #expect(Format.percent(7.0, digits: 0) == "7%")
        #expect(Format.decimal(10.704, digits: 2) == "10.70")
        #expect(Format.celsius(0) == "—")
        #expect(Format.celsius(31.79) == "31.8°C")
        #expect(Format.watts(0) == "—")
        #expect(Format.watts(11.241) == "11.2 W")
    }

    @Test func elapsedPadsMinutesAndShowsHoursOnlyWhenNeeded() {
        #expect(Format.elapsed(12) == "00:12")
        #expect(Format.elapsed(3723) == "1:02:03")
        #expect(Format.elapsed(-5) == "00:00")
    }
}

import XCTest

import CertScanTests

var tests = [XCTestCaseEntry]()
tests += CertScanTests.allTests()
XCTMain(tests)
import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testBackupExclusionForSensitiveFiles() {
    let appDelegate = AppDelegate()
    
    // Create temporary database and rules files
    let tempDir = FileManager.default.temporaryDirectory
    let dbUrl = tempDir.appendingPathComponent("attention_os.db")
    let rulesUrl = tempDir.appendingPathComponent("rlhf_rules.json")
    
    try? "dummy db".write(to: dbUrl, atomically: true, encoding: .utf8)
    try? "[]".write(to: rulesUrl, atomically: true, encoding: .utf8)
    
    defer {
      try? FileManager.default.removeItem(at: dbUrl)
      try? FileManager.default.removeItem(at: rulesUrl)
    }
    
    let dbExcluded = appDelegate.excludeFileFromBackup(fileName: "attention_os.db", filePath: dbUrl.path)
    let rulesExcluded = appDelegate.excludeFileFromBackup(fileName: "rlhf_rules.json", filePath: rulesUrl.path)
    
    XCTAssertTrue(dbExcluded, "attention_os.db should be successfully excluded from backup")
    XCTAssertTrue(rulesExcluded, "rlhf_rules.json should be successfully excluded from backup")
    
    let dbValues = try? dbUrl.resourceValues(forKeys: [.isExcludedFromBackupKey])
    let rulesValues = try? rulesUrl.resourceValues(forKeys: [.isExcludedFromBackupKey])
    
    XCTAssertEqual(dbValues?.isExcludedFromBackup, true, "NSURLIsExcludedFromBackupKey should be true for attention_os.db")
    XCTAssertEqual(rulesValues?.isExcludedFromBackup, true, "NSURLIsExcludedFromBackupKey should be true for rlhf_rules.json")
  }

}

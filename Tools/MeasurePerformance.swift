import AppKit
import Foundation
@main struct MeasurePerformance {
 static func time(_ action: () throws -> Void) rethrows -> Double { let t = DispatchTime.now().uptimeNanoseconds; try action(); return Double(DispatchTime.now().uptimeNanoseconds-t)/1_000_000 }
 static func measure(_ name: String, n: Int = 40, _ action: () throws -> Void) rethrows { var samples:[Double] = []; for _ in 0..<n { samples.append(try time(action)) }; samples.sort(); print("\(name): median=\(String(format:"%.3f",samples[n/2]))ms p95=\(String(format:"%.3f",samples[Int(Double(n)*0.95)]))ms") }
 static func main() throws {
  let root = URL(fileURLWithPath: CommandLine.arguments[1]); let db = try HistoryDatabase(url:root.appendingPathComponent("history.sqlite"))
  if try db.records().isEmpty {
   for i in 0..<4999 { let text = "Copie de vérification \(i) — café et idée à retrouver.\n" + String(repeating:"Une ligne de contenu de test. ",count:64); _ = try db.save(Capture(kind:.text,text:text,title:"Copie de vérification \(i)",parts:[PastePart(representations:["public.utf8-plain-text":Data(text.utf8)])],sourceName:"TextEdit",sourceBundle:"com.apple.TextEdit"),at:Date(timeIntervalSince1970:Double(i))) }
   let text=String(repeating:"Grand texte de test avec accents : café.\n",count:50_000)
   _ = try db.save(Capture(kind:.text,text:text,title:"Grand texte de vérification",parts:[PastePart(representations:["public.utf8-plain-text":Data(text.utf8)])],sourceName:"TextEdit",sourceBundle:"com.apple.TextEdit"))
  }
  let all=try db.records(); print("Synthetic records: \(all.count)")
  try measure("snapshot all + aggregate counts") { _ = try db.snapshot() }
  try measure("search + aggregate counts") { _ = try db.snapshot(query:"cafe 491") }
  let largeID = all.first { $0.title == "Grand texte de vérification" }!.id
  try measure("large text selection without decoding archive") { _ = try db.text(largeID) }
 }
}

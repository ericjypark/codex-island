import Foundation

// Integration test for Gemini usage API.
// Run with: swift scripts/gemini_test.swift

func testGeminiUsage() async {
    print("🚀 Testing Gemini Usage API...")
    
    let path = NSString("~/.gemini/oauth_creds.json").expandingTildeInPath
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let token = json["access_token"] as? String else {
        print("❌ Error: Could not read ~/.gemini/oauth_creds.json")
        exit(1)
    }
    
    let url = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")!
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    let body = ["project": "-"]
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    
    do {
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        
        if status != 200 {
            print("❌ HTTP Error: \(status)")
            if let err = String(data: data, encoding: .utf8) {
                print("Body: \(err)")
            }
            exit(1)
        }
        
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let buckets = obj["buckets"] as? [[String: Any]] else {
            print("❌ Parse Error: Could not parse response JSON")
            exit(1)
        }
        
        print("✅ Success! Found \(buckets.count) buckets:")
        for bucket in buckets {
            let model = bucket["modelId"] as? String ?? "unknown"
            let remaining = bucket["remainingFraction"] as? Double ?? 0
            let reset = bucket["resetTime"] as? String ?? "unknown"
            print("  - \(model): \(( (1.0 - remaining) * 100).formatted(.number.precision(.fractionLength(1))))% used, resets at \(reset)")
        }
        
    } catch {
        print("❌ Request Error: \(error.localizedDescription)")
        exit(1)
    }
}

let semaphore = DispatchSemaphore(value: 0)
Task {
    await testGeminiUsage()
    semaphore.signal()
}
semaphore.wait()

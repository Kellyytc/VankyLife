//
//  KellyLifeIntents.swift
//  KellyLifeIntents
//
//  Created by Kelly on 10/28/26.
//

import AppIntents

struct KellyLifeIntents: AppIntent {
    static var title: LocalizedStringResource { "KellyLifeIntents" }
    
    func perform() async throws -> some IntentResult {
        return .result()
    }
}

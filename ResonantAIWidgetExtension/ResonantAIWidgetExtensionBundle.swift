//
//  ResonantAIWidgetExtensionBundle.swift
//  ResonantAIWidgetExtension
//
//  Created by Abhijeet gajjar on 7/1/25.
//

import WidgetKit
import SwiftUI

@main
struct ResonantAIWidgetExtensionBundle: WidgetBundle {
    var body: some Widget {
        ResonantAIWidgetExtension()
        RecordingLiveActivityWidget()
    }
}

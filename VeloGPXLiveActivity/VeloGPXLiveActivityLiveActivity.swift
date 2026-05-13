//
//  VeloGPXLiveActivityLiveActivity.swift
//  VeloGPXLiveActivity
//
//  Created by J on 2026-05-12.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct VeloGPXLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct VeloGPXLiveActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VeloGPXLiveActivityAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension VeloGPXLiveActivityAttributes {
    fileprivate static var preview: VeloGPXLiveActivityAttributes {
        VeloGPXLiveActivityAttributes(name: "World")
    }
}

extension VeloGPXLiveActivityAttributes.ContentState {
    fileprivate static var smiley: VeloGPXLiveActivityAttributes.ContentState {
        VeloGPXLiveActivityAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: VeloGPXLiveActivityAttributes.ContentState {
         VeloGPXLiveActivityAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: VeloGPXLiveActivityAttributes.preview) {
   VeloGPXLiveActivityLiveActivity()
} contentStates: {
    VeloGPXLiveActivityAttributes.ContentState.smiley
    VeloGPXLiveActivityAttributes.ContentState.starEyes
}

//
//  RouteNoticeView.swift
//  VeloGPX
//
//  Displays road closure and restriction notices returned by
//  MKDirections.Response on iOS 26+.
//

import SwiftUI

struct RouteNoticeView: View {
    let notices: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(notices.enumerated()), id: \.offset) { index, notice in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(width: 20)
                        .padding(.top, 1)
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                if index < notices.count - 1 {
                    Divider().padding(.leading, 44)
                }
            }
        }
    }
}

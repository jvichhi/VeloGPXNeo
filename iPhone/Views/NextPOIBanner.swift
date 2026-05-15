import SwiftUI
import MapKit

struct NextPOIBanner: View {
    let item: MKMapItem
    let distance: CLLocationDistance
    let category: POICategory?

    var body: some View {
        HStack {
            Image(systemName: category?.systemImage ?? "mappin.circle.fill")
                .foregroundStyle(.blue)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name ?? "POI")
                    .font(.subheadline).bold()
                Text(String(format: "%.1f km ahead", distance / 1000))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

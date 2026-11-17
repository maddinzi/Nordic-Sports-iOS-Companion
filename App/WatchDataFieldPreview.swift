import SwiftUI
import NordicSportsShared

/// One recording page as the round watch draws it (Android `WatchPagePreview`, Watch `ScreenLayout.mc`): the left and
/// right field in a light-blue frame (31-57 % of the height, columns 27/73 %), the large field below from 58 %.
/// Tapping a field calls [onTap] with its menu position (0 left, 1 right, 2 bottom); [selected] is outlined.
struct WatchPagePreview: View {
    /// The page's slots in menu order: left, right, bottom.
    let slots: [DataFieldSlotView]
    let selected: Int?
    let accessibilityName: String
    var diameter: CGFloat = 200
    let onTap: (Int) -> Void

    private static let label = Color(white: 0xAA / 255.0)
    private static let divider = Color(red: 0x55 / 255.0, green: 0xAA / 255.0, blue: 1)

    /// A typical value per field, so the preview reads like a page during a session. The watch shows no units.
    private static let samples: [String: String] = [
        "timer": "42:15", "distance": "8.42", "speed": "14.2", "pace": "4:13", "heartRate": "152",
        "cadence": "62", "calories": "512", "grade": "4", "altitude": "1540", "totalAscent": "312",
        "totalDescent": "298", "timeOfDay": "10:24", "lapTime": "6:12", "lapDistance": "1.20",
        "lapSpeed": "13.8", "lapPace": "4:21", "lapNumber": "3", "temperature": "-4",
        "verticalSpeed": "12", "lapCadence": "60", "lapHeartRate": "148", "distancePerStroke": "8.1",
        "gap": "4:05", "gapSpeed": "14.7",
    ]

    var body: some View {
        let d = diameter
        ZStack(alignment: .topLeading) {
            Circle().fill(Color.black)
            Canvas { context, size in
                let w = size.width, h = size.height
                let top = h * 0.31, bottom = h * 0.57
                var path = Path()
                path.move(to: CGPoint(x: w * 0.13, y: top)); path.addLine(to: CGPoint(x: w * 0.87, y: top))
                path.move(to: CGPoint(x: w * 0.08, y: bottom)); path.addLine(to: CGPoint(x: w * 0.92, y: bottom))
                path.move(to: CGPoint(x: w / 2, y: top)); path.addLine(to: CGPoint(x: w / 2, y: bottom))
                context.stroke(path, with: .color(Self.divider), lineWidth: 1.5)
            }
            if slots.count > 0 { slot(0, x: 0.12, y: 0.31, w: 0.37, h: 0.26, value: 0.12) }
            if slots.count > 1 { slot(1, x: 0.51, y: 0.31, w: 0.37, h: 0.26, value: 0.12) }
            if slots.count > 2 { slot(2, x: 0.15, y: 0.58, w: 0.70, h: 0.32, value: 0.20) }
        }
        .frame(width: d, height: d)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color(white: 0x3A / 255.0), lineWidth: 6))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(accessibilityName))
    }

    private func slot(_ position: Int, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, value: CGFloat) -> some View {
        let d = diameter
        let s = slots[position]
        // Text sizes as a share of the watch, so they follow the drawing and not the phone's text size.
        return Button { onTap(position) } label: {
            VStack(spacing: 0) {
                Text(s.fieldName).font(.system(size: d * 0.05)).foregroundStyle(Self.label).lineLimit(1)
                Text(Self.samples[s.catalogKey] ?? "--").font(.system(size: d * value, weight: .semibold))
                    .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
            }
            .frame(width: d * w, height: d * h, alignment: .top)
            .contentShape(Rectangle())
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected == position ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(s.label): \(s.fieldName)"))
        .offset(x: d * x, y: d * y)
    }
}

import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import LegacyComponents
import ChatTitleActivityNode

private let compactNameFont = Font.regular(28)
private let regularNameFont = Font.regular(28)

private let compactStatusFont = Font.regular(16)
private let regularStatusFont = Font.regular(16)

enum CallControllerStatusValue: Equatable {
    case text(string: String, displayLogo: Bool)
    case timer((String, Bool) -> String, Double)
    case endTime(Double)

    static func ==(lhs: CallControllerStatusValue, rhs: CallControllerStatusValue) -> Bool {
        switch lhs {
            case let .text(text, displayLogo):
                if case .text(text, displayLogo) = rhs {
                    return true
                } else {
                    return false
                }
            case let .timer(_, referenceTime):
                if case .timer(_, referenceTime) = rhs {
                    return true
                } else {
                    return false
                }
            case let .endTime(timestamp):
                if case .endTime(timestamp) = rhs {
                    return true
                } else {
                    return false
                }
        }
    }
}

final class CallControllerStatusNode: ASDisplayNode {
    private let titleNode: TextNode
    private let statusContainerNode: ASDisplayNode
    private let statusNode: TextNode
    private let statusMeasureNode: TextNode
    private let receptionNode: CallControllerReceptionNode
    private let logoNode: ASImageNode
    private let activityNode: ChatTypingActivityIndicatorNode

    private let titleActivateAreaNode: AccessibilityAreaNode
    private let statusActivateAreaNode: AccessibilityAreaNode

    private var endTimestamp: Double?

    var title: String = ""
    var subtitle: String = ""
    var status: CallControllerStatusValue = .text(string: "", displayLogo: false) {
        didSet {

            if case .endTime = status, endTimestamp == nil {
                endTimestamp = CFAbsoluteTimeGetCurrent()
            }

            if self.status != oldValue {
                self.statusTimer?.invalidate()

                if let snapshotView = self.statusContainerNode.view.snapshotView(afterScreenUpdates: false) {
                    snapshotView.frame = self.statusContainerNode.frame
                    self.view.insertSubview(snapshotView, belowSubview: self.statusContainerNode.view)

                    snapshotView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3, removeOnCompletion: false, completion: { [weak snapshotView] _ in
                        snapshotView?.removeFromSuperview()
                    })
                    snapshotView.layer.animateScale(from: 1.0, to: 0.3, duration: 0.3, removeOnCompletion: false)
                    snapshotView.layer.animatePosition(from: CGPoint(), to: CGPoint(x: 0.0, y: snapshotView.frame.height / 2.0), duration: 0.3, delay: 0.0, removeOnCompletion: false, additive: true)

                    self.statusContainerNode.layer.animateScale(from: 0.3, to: 1.0, duration: 0.3)
                    self.statusContainerNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3)
                    self.statusContainerNode.layer.animatePosition(from: CGPoint(x: 0.0, y: -snapshotView.frame.height / 2.0), to: CGPoint(), duration: 0.3, delay: 0.0, additive: true)
                }

                if case .timer = self.status {
                    self.statusTimer = SwiftSignalKit.Timer(timeout: 0.5, repeat: true, completion: { [weak self] in
                        if let strongSelf = self, let validLayoutWidth = strongSelf.validLayoutWidth {
                            let _ = strongSelf.updateLayout(constrainedWidth: validLayoutWidth, transition: .immediate)
                        }
                    }, queue: Queue.mainQueue())
                    self.statusTimer?.start()
                } else {
                    if let validLayoutWidth = self.validLayoutWidth {
                        let _ = self.updateLayout(constrainedWidth: validLayoutWidth, transition: .immediate)
                    }
                }
            }
        }
    }
    var reception: Int32? {
        didSet {
            if self.reception != oldValue {
                if let reception = self.reception {
                    self.receptionNode.reception = reception

                    if oldValue == nil {
                        let transition = ContainedViewLayoutTransition.animated(duration: 0.3, curve: .spring)
                        transition.updateAlpha(node: self.receptionNode, alpha: 1.0)
                    }
                } else if self.reception == nil, oldValue != nil {
                    let transition = ContainedViewLayoutTransition.animated(duration: 0.3, curve: .spring)
                    transition.updateAlpha(node: self.receptionNode, alpha: 0.0)
                }

                if (oldValue == nil) != (self.reception != nil) {
                    if let validLayoutWidth = self.validLayoutWidth {
                        let _ = self.updateLayout(constrainedWidth: validLayoutWidth, transition: .immediate)
                    }
                }
            }
        }
    }

    private var statusTimer: SwiftSignalKit.Timer?
    private var validLayoutWidth: CGFloat?

    override init() {
        self.titleNode = TextNode()
        self.statusContainerNode = ASDisplayNode()
        self.statusNode = TextNode()
        self.statusNode.displaysAsynchronously = false
        self.statusMeasureNode = TextNode()
        self.activityNode = ChatTypingActivityIndicatorNode(color: .white)

        self.receptionNode = CallControllerReceptionNode()
        self.receptionNode.alpha = 0.0

        self.logoNode = ASImageNode()
        self.logoNode.image = generateTintedImage(image: UIImage(bundleImageName: "Call/CallTitleLogo"), color: .white)
        self.logoNode.isHidden = true

        self.titleActivateAreaNode = AccessibilityAreaNode()
        self.titleActivateAreaNode.accessibilityTraits = .staticText

        self.statusActivateAreaNode = AccessibilityAreaNode()
        self.statusActivateAreaNode.accessibilityTraits = [.staticText, .updatesFrequently]

        super.init()

        self.isUserInteractionEnabled = false

        self.addSubnode(self.titleNode)
        self.addSubnode(self.statusContainerNode)
        self.statusContainerNode.addSubnode(self.statusNode)
        self.statusContainerNode.addSubnode(self.receptionNode)
        self.statusContainerNode.addSubnode(self.logoNode)
        self.statusContainerNode.addSubnode(activityNode)

        self.addSubnode(self.titleActivateAreaNode)
        self.addSubnode(self.statusActivateAreaNode)
    }

    deinit {
        self.statusTimer?.invalidate()
    }

    func setVisible(_ visible: Bool, transition: ContainedViewLayoutTransition) {
        let alpha: CGFloat = visible ? 1.0 : 0.0
        transition.updateAlpha(node: self.titleNode, alpha: alpha)
        transition.updateAlpha(node: self.statusContainerNode, alpha: alpha)
    }

    func updateLayout(constrainedWidth: CGFloat, transition: ContainedViewLayoutTransition) -> CGFloat {
        validLayoutWidth = constrainedWidth

        let nameFont = regularNameFont
        let statusFont = regularStatusFont
        var statusOffset: CGFloat = 0
        let statusText: String
        let statusMeasureText: String
        var statusDisplayLogo = false
        var hasIndicator = false

        switch self.status {
        case let .text(text, hasIndicatorValue):
            if text.hasSuffix("...") {
                statusText = String(text.dropLast(3))
            } else {
                statusText = text
            }
            statusMeasureText = text
            hasIndicator = hasIndicatorValue
        case let .timer(format, referenceTime):
            let duration = Int32(CFAbsoluteTimeGetCurrent() - referenceTime)
            let durationString: String
            let measureDurationString: String
            if duration > 60 * 60 {
                durationString = String(format: "%02d:%02d:%02d", arguments: [duration / 3600, (duration / 60) % 60, duration % 60])
                measureDurationString = "00:00:00"
            } else {
                durationString = String(format: "%02d:%02d", arguments: [(duration / 60) % 60, duration % 60])
                measureDurationString = "00:00"
            }
            statusText = format(durationString, false)
            statusMeasureText = format(measureDurationString, true)
            if self.reception != nil {
                statusOffset += 8.0
            }
        case let .endTime(timestamp):
            guard let endTimestamp else {
                statusText = "00:00"
                statusMeasureText = "00:00"
                break
            }
            let duration = Int32(endTimestamp - timestamp)
            let durationString: String
            let measureDurationString: String
            if duration > 60 * 60 {
                durationString = String(format: "%02d:%02d:%02d", arguments: [duration / 3600, (duration / 60) % 60, duration % 60])
                measureDurationString = "00:00:00"
            } else {
                durationString = String(format: "%02d:%02d", arguments: [(duration / 60) % 60, duration % 60])
                measureDurationString = "00:00"
            }
            statusText = durationString
            statusMeasureText = measureDurationString
            statusDisplayLogo = true
            logoNode.image = generateTintedImage(image: UIImage(bundleImageName: "Call/CallDeclineButton2"), color: .white)
            statusOffset += 8.0
        }

        let (titleLayout, titleApply) = TextNode.asyncLayout(titleNode)(TextNodeLayoutArguments(attributedString: NSAttributedString(string: title, font: nameFont, textColor: .white), backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: constrainedWidth - 20, height: 33), alignment: .natural, cutout: nil, insets: .zero))
        let (statusMeasureLayout, statusMeasureApply) = TextNode.asyncLayout(statusMeasureNode)(TextNodeLayoutArguments(attributedString: NSAttributedString(string: statusMeasureText, font: statusFont, textColor: .white), backgroundColor: nil, maximumNumberOfLines: 0, truncationType: .end, constrainedSize: CGSize(width: constrainedWidth - 20, height: 20), alignment: .center, cutout: nil, insets: .zero))
        let (statusLayout, statusApply) = TextNode.asyncLayout(statusNode)(TextNodeLayoutArguments(attributedString: NSAttributedString(string: statusText, font: statusFont, textColor: .white), backgroundColor: nil, maximumNumberOfLines: 0, truncationType: .end, constrainedSize: CGSize(width: constrainedWidth - 20, height: 20), alignment: .center, cutout: nil, insets: .zero))

        let _ = titleApply()
        let _ = statusApply()
        let _ = statusMeasureApply()

        titleActivateAreaNode.accessibilityLabel = title
        statusActivateAreaNode.accessibilityLabel = statusText

        titleNode.frame = CGRect(
            origin: CGPoint(x: floor((constrainedWidth - titleLayout.size.width) / 2), y: 0),
            size: CGSize(width: titleLayout.size.width, height: 33))
        statusContainerNode.frame = CGRect(
            origin: CGPoint(x: 0, y: 37),
            size: CGSize(width: constrainedWidth, height: 20))
        statusNode.frame = CGRect(
            origin: CGPoint(x: floor((constrainedWidth - statusMeasureLayout.size.width) / 2.0) + statusOffset, y: 0),
            size: CGSize(width: statusLayout.size.width, height: 20))
        receptionNode.frame = CGRect(
            origin: CGPoint(x: statusNode.frame.minX - receptionNodeSize.width - 6, y: 0),
            size: receptionNodeSize)
        logoNode.isHidden = !statusDisplayLogo
        if logoNode.image != nil {
            logoNode.frame = CGRect(
                origin: CGPoint(x: statusNode.frame.minX - 20 - 6, y: 0),
                size: CGSize(width: 20, height: 20))
        }
        activityNode.isHidden = !hasIndicator
        if hasIndicator {
            statusNode.frame.origin.x = (constrainedWidth - statusLayout.size.width - 3 - 24) / 2
            activityNode.frame = CGRect(
                origin: CGPoint(x: statusNode.frame.maxX + 3, y: 2),
                size: CGSize(width: 24, height: 16))
        }

        self.titleActivateAreaNode.frame = self.titleNode.frame
        self.statusActivateAreaNode.frame = self.statusContainerNode.frame

        return 57
    }
}


private final class CallControllerReceptionNodeParameters: NSObject {
    let reception: Int32

    init(reception: Int32) {
        self.reception = reception
    }
}

private let receptionNodeSize = CGSize(width: 20, height: 20)

final class CallControllerReceptionNode : ASDisplayNode {
    var reception: Int32 = 4 {
        didSet {
            self.setNeedsDisplay()
        }
    }

    override init() {
        super.init()

        self.isOpaque = false
        self.isLayerBacked = true
    }

    override func drawParameters(forAsyncLayer layer: _ASDisplayLayer) -> NSObjectProtocol? {
        return CallControllerReceptionNodeParameters(reception: self.reception)
    }

    @objc override class func draw(_ bounds: CGRect, withParameters parameters: Any?, isCancelled: () -> Bool, isRasterizing: Bool) {
        let context = UIGraphicsGetCurrentContext()!
        context.setFillColor(UIColor.white.cgColor)

        if let parameters = parameters as? CallControllerReceptionNodeParameters{
            let width: CGFloat = 3
            let spacing: CGFloat = 2

            for i in 0 ..< 4 {
                let height = 3 + 3 * CGFloat(i)
                let rect = CGRect(
                    x: 1 + CGFloat(i) * (width + spacing),
                    y: receptionNodeSize.height - height - 4,
                    width: width,
                    height: height)

                if i >= parameters.reception {
                    context.setAlpha(0.4)
                }

                let path = UIBezierPath(roundedRect: rect, cornerRadius: 1)
                context.addPath(path.cgPath)
                context.fillPath()
            }
        }
    }
}

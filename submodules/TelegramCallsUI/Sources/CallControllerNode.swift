import Foundation
import UIKit
import Display
import AsyncDisplayKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramPresentationData
import TelegramUIPreferences
import TelegramAudio
import AccountContext
import LocalizedPeerData
import PhotoResources
import CallsEmoji
import TooltipUI
import AlertUI
import PresentationDataUtils
import DeviceAccess
import ContextUI
import AppBundle
import Lottie
import GradientBackground
import WallpaperBackgroundNode
import ReactionImageComponent
import ComponentFlow
import DeviceProximity

enum CallBackgroundGradientStyle: CaseIterable {
    case violet
    case green
    case orange

    var colors: [UIColor] {
        switch self {
        case .violet:
            return [
                UIColor(rgb: 0x5295D6),
                UIColor(rgb: 0x7261DA),
                UIColor(rgb: 0xAC65D4),
                UIColor(rgb: 0x616AD5),
            ]
        case .green:
            return [
                UIColor(rgb: 0xBAC05D),
                UIColor(rgb: 0x398D6F),
                UIColor(rgb: 0x53A6DE),
                UIColor(rgb: 0x3C9C8F),
            ]
        case .orange:
            return [
                UIColor(rgb: 0xB84498),
                UIColor(rgb: 0xFF7E46),
                UIColor(rgb: 0xC94986),
                UIColor(rgb: 0xF4992E),
            ]
        }
    }
}

private func interpolateFrame(from fromValue: CGRect, to toValue: CGRect, t: CGFloat) -> CGRect {
    return CGRect(x: floorToScreenPixels(toValue.origin.x * t + fromValue.origin.x * (1.0 - t)), y: floorToScreenPixels(toValue.origin.y * t + fromValue.origin.y * (1.0 - t)), width: floorToScreenPixels(toValue.size.width * t + fromValue.size.width * (1.0 - t)), height: floorToScreenPixels(toValue.size.height * t + fromValue.size.height * (1.0 - t)))
}

private func interpolate(from: CGFloat, to: CGFloat, value: CGFloat) -> CGFloat {
    return (1.0 - value) * from + value * to
}

private final class CallVideoNode: ASDisplayNode, PreviewVideoNode {
    private let videoTransformContainer: ASDisplayNode
    private let videoView: PresentationCallVideoView
    
    private var effectView: UIVisualEffectView?
    private let videoPausedNode: ImmediateTextNode
    
    private var isBlurred: Bool = false
    private var currentCornerRadius: CGFloat = 0.0
    
    private let isReadyUpdated: () -> Void
    private(set) var isReady: Bool = false
    private var isReadyTimer: SwiftSignalKit.Timer?
    
    private let readyPromise = ValuePromise(false)
    var ready: Signal<Bool, NoError> {
        return self.readyPromise.get()
    }
    
    private let isFlippedUpdated: (CallVideoNode) -> Void
    
    private(set) var currentOrientation: PresentationCallVideoView.Orientation
    private(set) var currentAspect: CGFloat = 0.0
    
    private var previousVideoHeight: CGFloat?
    
    init(videoView: PresentationCallVideoView, disabledText: String?, assumeReadyAfterTimeout: Bool, isReadyUpdated: @escaping () -> Void, orientationUpdated: @escaping () -> Void, isFlippedUpdated: @escaping (CallVideoNode) -> Void) {
        self.isReadyUpdated = isReadyUpdated
        self.isFlippedUpdated = isFlippedUpdated
        
        self.videoTransformContainer = ASDisplayNode()
        self.videoView = videoView
        videoView.view.clipsToBounds = true
        videoView.view.backgroundColor = .black
        
        self.currentOrientation = videoView.getOrientation()
        self.currentAspect = videoView.getAspect()
        
        self.videoPausedNode = ImmediateTextNode()
        self.videoPausedNode.alpha = 0.0
        self.videoPausedNode.maximumNumberOfLines = 3
        
        super.init()
        
        self.backgroundColor = .black
        self.clipsToBounds = true
        
        if #available(iOS 13.0, *) {
            self.layer.cornerCurve = .continuous
        }
        
        self.videoTransformContainer.view.addSubview(self.videoView.view)
        self.addSubnode(self.videoTransformContainer)
        
        if let disabledText = disabledText {
            self.videoPausedNode.attributedText = NSAttributedString(string: disabledText, font: Font.regular(17.0), textColor: .white)
            self.addSubnode(self.videoPausedNode)
        }
        
        self.videoView.setOnFirstFrameReceived { [weak self] aspectRatio in
            Queue.mainQueue().async {
                guard let strongSelf = self else {
                    return
                }
                if !strongSelf.isReady {
                    strongSelf.isReady = true
                    strongSelf.readyPromise.set(true)
                    strongSelf.isReadyTimer?.invalidate()
                    strongSelf.isReadyUpdated()
                }
            }
        }
        
        self.videoView.setOnOrientationUpdated { [weak self] orientation, aspect in
            Queue.mainQueue().async {
                guard let strongSelf = self else {
                    return
                }
                if strongSelf.currentOrientation != orientation || strongSelf.currentAspect != aspect {
                    strongSelf.currentOrientation = orientation
                    strongSelf.currentAspect = aspect
                    orientationUpdated()
                }
            }
        }
        
        self.videoView.setOnIsMirroredUpdated { [weak self] _ in
            Queue.mainQueue().async {
                guard let strongSelf = self else {
                    return
                }
                strongSelf.isFlippedUpdated(strongSelf)
            }
        }
        
        if assumeReadyAfterTimeout {
            self.isReadyTimer = SwiftSignalKit.Timer(timeout: 3.0, repeat: false, completion: { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                if !strongSelf.isReady {
                    strongSelf.isReady = true
                    strongSelf.readyPromise.set(true)
                    strongSelf.isReadyUpdated()
                }
            }, queue: .mainQueue())
        }
        self.isReadyTimer?.start()
    }
    
    deinit {
        self.isReadyTimer?.invalidate()
    }
    
    override func didLoad() {
        super.didLoad()
        
        if #available(iOS 13.0, *) {
            self.layer.cornerCurve = .continuous
        }
    }
    
    func animateRadialMask(from fromRect: CGRect, to toRect: CGRect, completion: (() -> Void)? = nil) {
        let maskLayer = CAShapeLayer()
        maskLayer.frame = fromRect
        
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(origin: CGPoint(), size: fromRect.size))
        maskLayer.path = path
        
        self.layer.mask = maskLayer
        
        let topLeft = CGPoint(x: 0.0, y: 0.0)
        let topRight = CGPoint(x: self.bounds.width, y: 0.0)
        let bottomLeft = CGPoint(x: 0.0, y: self.bounds.height)
        let bottomRight = CGPoint(x: self.bounds.width, y: self.bounds.height)
        
        func distance(_ v1: CGPoint, _ v2: CGPoint) -> CGFloat {
            let dx = v1.x - v2.x
            let dy = v1.y - v2.y
            return sqrt(dx * dx + dy * dy)
        }
        
        var maxRadius = distance(toRect.center, topLeft)
        maxRadius = max(maxRadius, distance(toRect.center, topRight))
        maxRadius = max(maxRadius, distance(toRect.center, bottomLeft))
        maxRadius = max(maxRadius, distance(toRect.center, bottomRight))
        maxRadius = ceil(maxRadius)
        
        let targetFrame = CGRect(origin: CGPoint(x: toRect.center.x - maxRadius, y: toRect.center.y - maxRadius), size: CGSize(width: maxRadius * 2.0, height: maxRadius * 2.0))
        
        let transition: ContainedViewLayoutTransition = .animated(duration: 0.3, curve: .easeInOut)
        transition.updatePosition(layer: maskLayer, position: targetFrame.center)
        transition.updateTransformScale(layer: maskLayer, scale: maxRadius * 2.0 / fromRect.width, completion: { [weak self] _ in
            self?.layer.mask = nil
            completion?()
        })
    }

    func animateRadialMaskToSmall(from fromRect: CGRect, to toRect: CGRect, completion: (() -> Void)? = nil) {

        let topLeft = CGPoint(x: 0.0, y: 0.0)
        let topRight = CGPoint(x: self.bounds.width, y: 0.0)
        let bottomLeft = CGPoint(x: 0.0, y: self.bounds.height)
        let bottomRight = CGPoint(x: self.bounds.width, y: self.bounds.height)

        func distance(_ v1: CGPoint, _ v2: CGPoint) -> CGFloat {
            let dx = v1.x - v2.x
            let dy = v1.y - v2.y
            return sqrt(dx * dx + dy * dy)
        }

        var maxRadius = distance(fromRect.center, topLeft)
        maxRadius = max(maxRadius, distance(toRect.center, topRight))
        maxRadius = max(maxRadius, distance(toRect.center, bottomLeft))
        maxRadius = max(maxRadius, distance(toRect.center, bottomRight))
        maxRadius = ceil(maxRadius)

        let sourceFrame = CGRect(origin: CGPoint(x: fromRect.center.x - maxRadius, y: fromRect.center.y - maxRadius), size: CGSize(width: maxRadius * 2.0, height: maxRadius * 2.0))

        let maskLayer = CAShapeLayer()
        maskLayer.frame = sourceFrame

        let path = CGMutablePath()
        path.addEllipse(in: CGRect(origin: CGPoint(), size: sourceFrame.size))
        maskLayer.path = path

        self.layer.mask = maskLayer

        let transition: ContainedViewLayoutTransition = .animated(duration: 0.3, curve: .easeInOut)
        transition.updatePosition(layer: maskLayer, position: toRect.center)
        transition.updateTransformScale(layer: maskLayer, scale: toRect.width / (maxRadius * 2), completion: { [weak self] _ in
            self?.layer.mask = nil
            completion?()
        })
    }

    func animateMask(from fromRect: CGRect, fromCornerRadius: CGFloat, to toRect: CGRect, toCornerRadius: CGFloat, completion: (() -> Void)? = nil) {
        let maskLayer = CALayer()
        maskLayer.backgroundColor = UIColor.white.cgColor
        maskLayer.frame = fromRect
        maskLayer.cornerRadius = fromCornerRadius

        layer.mask = maskLayer

        let transition: ContainedViewLayoutTransition = .animated(duration: 0.3, curve: .linear)
        transition.updateFrame(layer: maskLayer, frame: toRect)
        transition.updateCornerRadius(layer: maskLayer, cornerRadius: toCornerRadius) { _ in
            completion?()
        }
    }
    
    func updateLayout(size: CGSize, layoutMode: VideoNodeLayoutMode, transition: ContainedViewLayoutTransition) {
        self.updateLayout(size: size, cornerRadius: self.currentCornerRadius, isOutgoing: true, deviceOrientation: .portrait, isCompactLayout: false, transition: transition)
    }
    
    func updateLayout(size: CGSize, cornerRadius: CGFloat, isOutgoing: Bool, deviceOrientation: UIDeviceOrientation, isCompactLayout: Bool, transition: ContainedViewLayoutTransition) {
        self.currentCornerRadius = cornerRadius
        
        var rotationAngle: CGFloat
        if false && isOutgoing && isCompactLayout {
            rotationAngle = CGFloat.pi / 2.0
        } else {
            switch self.currentOrientation {
            case .rotation0:
                rotationAngle = 0.0
            case .rotation90:
                rotationAngle = CGFloat.pi / 2.0
            case .rotation180:
                rotationAngle = CGFloat.pi
            case .rotation270:
                rotationAngle = -CGFloat.pi / 2.0
            }
            
            var additionalAngle: CGFloat = 0.0
            switch deviceOrientation {
            case .portrait:
                additionalAngle = 0.0
            case .landscapeLeft:
                additionalAngle = CGFloat.pi / 2.0
            case .landscapeRight:
                additionalAngle = -CGFloat.pi / 2.0
            case .portraitUpsideDown:
                rotationAngle = CGFloat.pi
            default:
                additionalAngle = 0.0
            }
            rotationAngle += additionalAngle
            if abs(rotationAngle - CGFloat.pi * 3.0 / 2.0) < 0.01 {
                rotationAngle = -CGFloat.pi / 2.0
            }
            if abs(rotationAngle - (-CGFloat.pi)) < 0.01 {
                rotationAngle = -CGFloat.pi + 0.001
            }
        }
        
        let rotateFrame = abs(rotationAngle.remainder(dividingBy: CGFloat.pi)) > 1.0
        let fittingSize: CGSize
        if rotateFrame {
            fittingSize = CGSize(width: size.height, height: size.width)
        } else {
            fittingSize = size
        }
        
        let unboundVideoSize = CGSize(width: self.currentAspect * 10000.0, height: 10000.0)
        
        var fittedVideoSize = unboundVideoSize.fitted(fittingSize)
        if fittedVideoSize.width < fittingSize.width || fittedVideoSize.height < fittingSize.height {
            let isVideoPortrait = unboundVideoSize.width < unboundVideoSize.height
            let isFittingSizePortrait = fittingSize.width < fittingSize.height
            
            if isCompactLayout && isVideoPortrait == isFittingSizePortrait {
                fittedVideoSize = unboundVideoSize.aspectFilled(fittingSize)
            } else {
                let maxFittingEdgeDistance: CGFloat
                if isCompactLayout {
                    maxFittingEdgeDistance = 200.0
                } else {
                    maxFittingEdgeDistance = 400.0
                }
                if fittedVideoSize.width > fittingSize.width - maxFittingEdgeDistance && fittedVideoSize.height > fittingSize.height - maxFittingEdgeDistance {
                    fittedVideoSize = unboundVideoSize.aspectFilled(fittingSize)
                }
            }
        }
        
        let rotatedVideoHeight: CGFloat = max(fittedVideoSize.height, fittedVideoSize.width)
        
        let videoFrame: CGRect = CGRect(origin: CGPoint(), size: fittedVideoSize)
        
        let videoPausedSize = self.videoPausedNode.updateLayout(CGSize(width: size.width - 16.0, height: 100.0))
        transition.updateFrame(node: self.videoPausedNode, frame: CGRect(origin: CGPoint(x: floor((size.width - videoPausedSize.width) / 2.0), y: floor((size.height - videoPausedSize.height) / 2.0)), size: videoPausedSize))
        
        self.videoTransformContainer.bounds = CGRect(origin: CGPoint(), size: videoFrame.size)
        if transition.isAnimated && !videoFrame.height.isZero, let previousVideoHeight = self.previousVideoHeight, !previousVideoHeight.isZero {
            let scaleDifference = previousVideoHeight / rotatedVideoHeight
            if abs(scaleDifference - 1.0) > 0.001 {
                transition.animateTransformScale(node: self.videoTransformContainer, from: scaleDifference, additive: true)
            }
        }
        self.previousVideoHeight = rotatedVideoHeight
        transition.updatePosition(node: self.videoTransformContainer, position: CGPoint(x: size.width / 2.0, y: size.height / 2.0))
        transition.updateTransformRotation(view: self.videoTransformContainer.view, angle: rotationAngle)
        
        let localVideoFrame = CGRect(origin: CGPoint(), size: videoFrame.size)
        self.videoView.view.bounds = localVideoFrame
        self.videoView.view.center = localVideoFrame.center
        // TODO: properly fix the issue
        // On iOS 13 and later metal layer transformation is broken if the layer does not require compositing
        self.videoView.view.alpha = 0.995
        
        if let effectView = self.effectView {
            transition.updateFrame(view: effectView, frame: localVideoFrame)
        }
        
        transition.updateCornerRadius(layer: self.layer, cornerRadius: self.currentCornerRadius)
    }
    
    func updateIsBlurred(isBlurred: Bool, light: Bool = false, animated: Bool = true) {
        if self.hasScheduledUnblur {
            self.hasScheduledUnblur = false
        }
        if self.isBlurred == isBlurred {
            return
        }
        self.isBlurred = isBlurred
        
        if isBlurred {
            if self.effectView == nil {
                let effectView = UIVisualEffectView()
                self.effectView = effectView
                effectView.frame = self.videoTransformContainer.bounds
                self.videoTransformContainer.view.addSubview(effectView)
            }
            if animated {
                UIView.animate(withDuration: 0.3, animations: {
                    self.videoPausedNode.alpha = 1.0
                    self.effectView?.effect = UIBlurEffect(style: light ? .light : .dark)
                })
            } else {
                self.effectView?.effect = UIBlurEffect(style: light ? .light : .dark)
            }
        } else if let effectView = self.effectView {
            self.effectView = nil
            UIView.animate(withDuration: 0.3, animations: {
                self.videoPausedNode.alpha = 0.0
                effectView.effect = nil
            }, completion: { [weak effectView] _ in
                effectView?.removeFromSuperview()
            })
        }
    }
    
    private var hasScheduledUnblur = false
    func flip(withBackground: Bool) {
        if withBackground {
            self.backgroundColor = .black
        }
        UIView.transition(with: withBackground ? self.videoTransformContainer.view : self.view, duration: 0.4, options: [.transitionFlipFromLeft, .curveEaseOut], animations: {
            UIView.performWithoutAnimation {
                self.updateIsBlurred(isBlurred: true, light: false, animated: false)
            }
        }) { finished in
            self.backgroundColor = nil
            self.hasScheduledUnblur = true
            Queue.mainQueue().after(0.5) {
                if self.hasScheduledUnblur {
                    self.updateIsBlurred(isBlurred: false)
                }
            }
        }
    }
}

final class CallControllerNode: ViewControllerTracingNode, CallControllerNodeProtocol {
    private enum VideoNodeCorner {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }
    
    private let sharedContext: SharedAccountContext
    private let account: Account
    
    private let statusBar: StatusBar
    
    private var presentationData: PresentationData
    private var peer: Peer?
    private let debugInfo: Signal<(String, String), NoError>
    private var forceReportRating = false
    private let easyDebugAccess: Bool
    private let call: PresentationCall
    
    private let containerTransformationNode: ASDisplayNode
    private let containerNode: ASDisplayNode
    private let videoContainerNode: PinchSourceContainerNode

    private let mediumBlobView: BlobView
    private let bigBlobView: BlobView
    private let imageNode: TransformImageNode
    
    private var candidateIncomingVideoNodeValue: CallVideoNode?
    private var incomingVideoNodeValue: CallVideoNode?
    private var incomingVideoViewRequested: Bool = false
    private var candidateOutgoingVideoNodeValue: CallVideoNode?
    private var outgoingVideoNodeValue: CallVideoNode?
    private var outgoingVideoViewRequested: Bool = false
    
    private var removedMinimizedVideoNodeValue: CallVideoNode?
    private var removedExpandedVideoNodeValue: CallVideoNode?
    
    private var isRequestingVideo: Bool = false
    private var animateOutgoingVideoOnce: Bool = false
    private var animateIncomingVideoOnce: Bool = false
    
    private var hiddenUIForActiveVideoCallOnce: Bool = false
    private var hideUIForActiveVideoCallTimer: SwiftSignalKit.Timer?
    
    private var displayedCameraConfirmation: Bool = false
    private var displayedCameraTooltip: Bool = false
        
    private var expandedVideoNode: CallVideoNode?
    private var minimizedVideoNode: CallVideoNode?
    private var disableAnimationForExpandedVideoOnce: Bool = false
    private var animationForExpandedVideoSnapshotView: UIView? = nil
    private var isRemovedExpandedIncomingNode = false
    
    private var outgoingVideoNodeCorner: VideoNodeCorner = .bottomRight
    private let backButtonArrowNode: ASImageNode
    private let backButtonNode: HighlightableButtonNode
    private let statusNode: CallControllerStatusNode
    private var callEndedStatusNode: CallControllerStatusNode?
    private let toastNode: CallControllerToastContainerNode
    private let buttonsNode: CallControllerButtonsNode
    private var keyPreviewNode: CallControllerKeyPreviewNode?
    private var ratingNode: CallControllerRatingNode?
    private var closeRatingButtonNode: CallControllerCloseRatingButtonNode?
    private var currentGradientBackgroundNode: GradientBackgroundNode?
    private var gradientBackgroundNodes: [CallBackgroundGradientStyle: GradientBackgroundNode]
    private var keyTooltip: TooltipScreen?

    private var currentBackgroundGradientStyle: CallBackgroundGradientStyle = .violet

    private var isUpdateBackgroundAnimationInProgress = false
    private var isBackgroundAnimationStarted = false
    private var isRatingShown = false
    private var isCloseRatingButtonShown = false

    private var currentCallID: CallId?
    
    private var debugNode: CallDebugNode?
    
    private var keyTextData: (Data, String)?
    private let keyButtonNode: CallControllerKeyButton
    
    private var validLayout: (ContainerViewLayout, CGFloat)?
    private var disableActionsUntilTimestamp: Double = 0.0
    
    private var displayedVersionOutdatedAlert: Bool = false
    
    var isMuted: Bool = false {
        didSet {
            self.buttonsNode.isMuted = self.isMuted
            self.updateToastContent()
            if let (layout, navigationBarHeight) = self.validLayout {
                self.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .animated(duration: 0.3, curve: .easeInOut))
            }
        }
    }
    
    private var shouldStayHiddenUntilConnection: Bool = false
    
    private var audioOutputState: ([AudioSessionOutput], currentOutput: AudioSessionOutput?)?
    private var callState: PresentationCallState?
    
    var toggleMute: (() -> Void)?
    var setCurrentAudioOutput: ((AudioSessionOutput) -> Void)?
    var beginAudioOuputSelection: ((Bool) -> Void)?
    var acceptCall: (() -> Void)?
    var endCall: (() -> Void)?
    var back: (() -> Void)?
    var presentCallRating: ((CallId, Bool) -> Void)?
    var callEnded: ((Bool) -> Void)?
    var dismissedInteractively: (() -> Void)?
    var present: ((ViewController) -> Void)?
    var dismissAllTooltips: (() -> Void)?
    
    private var toastContent: CallControllerToastContent?
    private var displayToastsAfterTimestamp: Double?
    
    private var buttonsMode: CallControllerButtonsMode?
    
    private var isUIHidden: Bool = false
    private var isVideoPaused: Bool = false
    private var isVideoPinched: Bool = false
    
    private enum PictureInPictureGestureState {
        case none
        case collapsing(didSelectCorner: Bool)
        case dragging(initialPosition: CGPoint, draggingPosition: CGPoint)
    }
    
    private var pictureInPictureGestureState: PictureInPictureGestureState = .none
    private var pictureInPictureCorner: VideoNodeCorner = .topRight
    private var pictureInPictureTransitionFraction: CGFloat = 0.0
    
    private var deviceOrientation: UIDeviceOrientation = .portrait
    private var orientationDidChangeObserver: NSObjectProtocol?
    
    private var currentRequestedAspect: CGFloat?

    private var isKeyTooltipShown = false

    private var isInterfaceAnimationInProgress = false
    private var isCallStateActive = false
    private var interfaceAnimationTimer: Foundation.Timer?

    private var proximityManagerIndex: Int?
    private var audioLevelsDisposable: Disposable?
    
    init(sharedContext: SharedAccountContext, account: Account, presentationData: PresentationData, statusBar: StatusBar, debugInfo: Signal<(String, String), NoError>, shouldStayHiddenUntilConnection: Bool = false, easyDebugAccess: Bool, call: PresentationCall) {
        self.sharedContext = sharedContext
        self.account = account
        self.presentationData = presentationData
        self.statusBar = statusBar
        self.debugInfo = debugInfo
        self.shouldStayHiddenUntilConnection = shouldStayHiddenUntilConnection
        self.easyDebugAccess = easyDebugAccess
        self.call = call
        
        self.containerTransformationNode = ASDisplayNode()
        self.containerTransformationNode.clipsToBounds = true
        
        self.containerNode = ASDisplayNode()
        
        self.videoContainerNode = PinchSourceContainerNode()

        gradientBackgroundNodes = [:]
        for style in CallBackgroundGradientStyle.allCases {
            gradientBackgroundNodes[style] = createGradientBackgroundNode(
                colors: style.colors,
                useSharedAnimationPhase: true)
        }
        currentGradientBackgroundNode = gradientBackgroundNodes[.violet]

        self.mediumBlobView = BlobView(
            pointsCount: 8,
            minRandomness: 1,
            maxRandomness: 1,
            minSpeed: 0.9,
            maxSpeed: 4.0,
            minScale: 0.69,
            maxScale: 0.87)

        self.bigBlobView = BlobView(
            pointsCount: 8,
            minRandomness: 1,
            maxRandomness: 1,
            minSpeed: 1.0,
            maxSpeed: 4.4,
            minScale: 0.71,
            maxScale: 1.0)
        
        self.imageNode = TransformImageNode()
        self.imageNode.contentAnimations = [.subsequentUpdates]
        
        self.backButtonArrowNode = ASImageNode()
        self.backButtonArrowNode.displayWithoutProcessing = true
        self.backButtonArrowNode.displaysAsynchronously = false
        self.backButtonArrowNode.image = NavigationBarTheme.generateBackArrowImage(color: .white)
        self.backButtonNode = HighlightableButtonNode()
        
        self.statusNode = CallControllerStatusNode()
        
        self.buttonsNode = CallControllerButtonsNode(strings: self.presentationData.strings)
        self.toastNode = CallControllerToastContainerNode(strings: self.presentationData.strings)
        self.keyButtonNode = CallControllerKeyButton(
            account: self.account,
            animatedEmojiStickers: self.call.context.animatedEmojiStickers,
            forceStatic: true)
        self.keyButtonNode.accessibilityElementsHidden = false
        
        super.init()
        
        self.containerNode.backgroundColor = .white
        
        self.addSubnode(self.containerTransformationNode)
        self.containerTransformationNode.addSubnode(self.containerNode)
        
        self.backButtonNode.setTitle(presentationData.strings.Common_Back, with: Font.regular(17.0), with: .white, for: [])
        self.backButtonNode.accessibilityLabel = presentationData.strings.Call_VoiceOver_Minimize
        self.backButtonNode.accessibilityTraits = [.button]
        self.backButtonNode.hitTestSlop = UIEdgeInsets(top: -8.0, left: -20.0, bottom: -8.0, right: -8.0)
        self.backButtonNode.highligthedChanged = { [weak self] highlighted in
            if let strongSelf = self {
                if highlighted {
                    strongSelf.backButtonNode.layer.removeAnimation(forKey: "opacity")
                    strongSelf.backButtonArrowNode.layer.removeAnimation(forKey: "opacity")
                    strongSelf.backButtonNode.alpha = 0.4
                    strongSelf.backButtonArrowNode.alpha = 0.4
                } else {
                    strongSelf.backButtonNode.alpha = 1.0
                    strongSelf.backButtonArrowNode.alpha = 1.0
                    strongSelf.backButtonNode.layer.animateAlpha(from: 0.4, to: 1.0, duration: 0.2)
                    strongSelf.backButtonArrowNode.layer.animateAlpha(from: 0.4, to: 1.0, duration: 0.2)
                }
            }
        }

        if let currentGradientBackgroundNode {
            self.containerNode.addSubnode(currentGradientBackgroundNode)
        }

        self.containerNode.view.addSubview(mediumBlobView)
        self.containerNode.view.addSubview(bigBlobView)

        self.containerNode.addSubnode(self.imageNode)
        self.containerNode.addSubnode(self.videoContainerNode)
        self.containerNode.addSubnode(self.statusNode)
        self.containerNode.addSubnode(self.buttonsNode)
        self.containerNode.addSubnode(self.toastNode)
        self.containerNode.addSubnode(self.keyButtonNode)
        self.containerNode.addSubnode(self.backButtonArrowNode)
        self.containerNode.addSubnode(self.backButtonNode)

        self.mediumBlobView.setColor(UIColor.white.withAlphaComponent(0.2))
        self.bigBlobView.setColor(UIColor.white.withAlphaComponent(0.1))

        self.proximityManagerIndex = DeviceProximityManager.shared().add { _ in
        }
        
        self.buttonsNode.mute = { [weak self] in
            self?.startInterfaceAnimation()
            self?.startInterfaceAnimationTimer()
            self?.toggleMute?()
            self?.cancelScheduledUIHiding()
        }
        
        self.buttonsNode.speaker = { [weak self] in
            self?.startInterfaceAnimation()
            self?.startInterfaceAnimationTimer()
            guard let strongSelf = self else {
                return
            }
            strongSelf.beginAudioOuputSelection?(strongSelf.hasVideoNodes)
            strongSelf.cancelScheduledUIHiding()
        }
                
        self.buttonsNode.acceptOrEnd = { [weak self] in
            self?.startInterfaceAnimation()
            self?.startInterfaceAnimationTimer()
            guard let strongSelf = self, let callState = strongSelf.callState else {
                return
            }
            switch callState.state {
            case .active, .connecting, .reconnecting:
                strongSelf.endCall?()
                strongSelf.cancelScheduledUIHiding()
            case .requesting:
                strongSelf.endCall?()
            case .ringing:
                strongSelf.acceptCall?()
            default:
                break
            }
        }
        
        self.buttonsNode.decline = { [weak self] in
            self?.startInterfaceAnimation()
            self?.startInterfaceAnimationTimer()
            self?.endCall?()
        }
        
        self.buttonsNode.toggleVideo = { [weak self] in
            self?.startInterfaceAnimation()
            self?.startInterfaceAnimationTimer()
            self?.keyTooltip?.dismiss()
            guard let strongSelf = self, let callState = strongSelf.callState else {
                return
            }
            switch callState.state {
            case .active:
                var isScreencastActive = false
                switch callState.videoState {
                case .active(true), .paused(true):
                    isScreencastActive = true
                default:
                    break
                }

                if isScreencastActive {
                    (strongSelf.call as! PresentationCallImpl).disableScreencast()
                } else if strongSelf.outgoingVideoNodeValue == nil {
                    DeviceAccess.authorizeAccess(to: .camera(.videoCall), onlyCheck: true, presentationData: strongSelf.presentationData, present: { [weak self] c, a in
                        if let strongSelf = self {
                            strongSelf.present?(c)
                        }
                    }, openSettings: { [weak self] in
                        self?.sharedContext.applicationBindings.openSettings()
                    }, _: { [weak self] ready in
                        guard let strongSelf = self, ready else {
                            return
                        }
                        let proceed = {
                            strongSelf.displayedCameraConfirmation = true
                            switch callState.videoState {
                            case .inactive:
                                strongSelf.isRequestingVideo = true
                                strongSelf.updateButtonsMode()
                            default:
                                break
                            }
                            strongSelf.call.requestVideo()
                        }
                        
                        strongSelf.call.makeOutgoingVideoView(completion: { [weak self] outgoingVideoView in
                            guard let strongSelf = self else {
                                return
                            }
                            
                            if let outgoingVideoView = outgoingVideoView {
                                outgoingVideoView.view.backgroundColor = .black
                                outgoingVideoView.view.clipsToBounds = true
                                
                                var updateLayoutImpl: ((ContainerViewLayout, CGFloat) -> Void)?
                                
                                let outgoingVideoNode = CallVideoNode(videoView: outgoingVideoView, disabledText: nil, assumeReadyAfterTimeout: true, isReadyUpdated: {
                                    guard let strongSelf = self, let (layout, navigationBarHeight) = strongSelf.validLayout else {
                                        return
                                    }
                                    updateLayoutImpl?(layout, navigationBarHeight)
                                }, orientationUpdated: {
                                    guard let strongSelf = self, let (layout, navigationBarHeight) = strongSelf.validLayout else {
                                        return
                                    }
                                    updateLayoutImpl?(layout, navigationBarHeight)
                                }, isFlippedUpdated: { _ in
                                    guard let strongSelf = self, let (layout, navigationBarHeight) = strongSelf.validLayout else {
                                        return
                                    }
                                    updateLayoutImpl?(layout, navigationBarHeight)
                                })
                                
                                let controller = CallCameraPreviewController(sharedContext: strongSelf.sharedContext, cameraNode: outgoingVideoNode, shareCamera: { _, _ in
                                    proceed()
                                }, switchCamera: { [weak self] in
                                    Queue.mainQueue().after(0.1) {
                                        self?.call.switchVideoCamera()
                                    }
                                })
                                strongSelf.present?(controller)
                                
                                updateLayoutImpl = { [weak controller] layout, navigationBarHeight in
                                    controller?.containerLayoutUpdated(layout, transition: .immediate)
                                }
                            }
                        })
                    })
                } else {
                    strongSelf.call.disableVideo()
                    strongSelf.cancelScheduledUIHiding()
                }
            default:
                break
            }
        }
        
        self.buttonsNode.rotateCamera = { [weak self] in
            self?.startInterfaceAnimation()
            self?.startInterfaceAnimationTimer()
            guard let strongSelf = self, !strongSelf.areUserActionsDisabledNow() else {
                return
            }
            strongSelf.disableActionsUntilTimestamp = CACurrentMediaTime() + 1.0
            if let outgoingVideoNode = strongSelf.outgoingVideoNodeValue {
                outgoingVideoNode.flip(withBackground: outgoingVideoNode !== strongSelf.minimizedVideoNode)
            }
            strongSelf.call.switchVideoCamera()
            if let _ = strongSelf.outgoingVideoNodeValue {
                if let (layout, navigationBarHeight) = strongSelf.validLayout {
                    strongSelf.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .immediate)
                }
            }
            strongSelf.cancelScheduledUIHiding()
        }
        
        self.keyButtonNode.addTarget(self, action: #selector(self.keyPressed), forControlEvents: .touchUpInside)
        
        self.backButtonNode.addTarget(self, action: #selector(self.backPressed), forControlEvents: .touchUpInside)
        
        if shouldStayHiddenUntilConnection {
            self.containerNode.alpha = 0.0
            Queue.mainQueue().after(3.0, { [weak self] in
                self?.containerNode.alpha = 1.0
                self?.animateIn()
            })
        } else if call.isVideo && call.isOutgoing {
            self.containerNode.alpha = 0.0
            Queue.mainQueue().after(1.0, { [weak self] in
                self?.containerNode.alpha = 1.0
                self?.animateIn()
            })
        }
        
        self.orientationDidChangeObserver = NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: nil, using: { [weak self] _ in
            guard let strongSelf = self else {
                return
            }
            let deviceOrientation = UIDevice.current.orientation
            if strongSelf.deviceOrientation != deviceOrientation {
                strongSelf.deviceOrientation = deviceOrientation
                if let (layout, navigationBarHeight) = strongSelf.validLayout {
                    strongSelf.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .animated(duration: 0.3, curve: .easeInOut))
                }
            }
        })
        
        self.videoContainerNode.activate = { [weak self] sourceNode in
            guard let strongSelf = self else {
                return
            }
            let pinchController = PinchController(sourceNode: sourceNode, getContentAreaInScreenSpace: {
                return UIScreen.main.bounds
            })
            strongSelf.sharedContext.mainWindow?.presentInGlobalOverlay(pinchController)
            strongSelf.isVideoPinched = true
            
            strongSelf.videoContainerNode.contentNode.clipsToBounds = true
            strongSelf.videoContainerNode.backgroundColor = .black
            
            if let (layout, navigationBarHeight) = strongSelf.validLayout {
                strongSelf.videoContainerNode.contentNode.cornerRadius = layout.deviceMetrics.screenCornerRadius
                
                strongSelf.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .immediate)
            }
        }
        
        self.videoContainerNode.animatedOut = { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.isVideoPinched = false
            
            strongSelf.videoContainerNode.backgroundColor = .clear
            strongSelf.videoContainerNode.contentNode.cornerRadius = 0.0
            
            if let (layout, navigationBarHeight) = strongSelf.validLayout {
                strongSelf.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .animated(duration: 0.3, curve: .easeInOut))
            }
        }

        self.audioLevelsDisposable = (self.call.audioLevel
        |> deliverOnMainQueue).start(next: { [weak self] level in
            guard let self else {
                return
            }

            let scale: CGFloat = 1 + CGFloat(level) * 0.07
            let transition: ContainedViewLayoutTransition = .animated(duration: 0.2, curve: .easeInOut)
            transition.updateSublayerTransformScale(
                layer: self.bigBlobView.layer,
                scale: CGPoint(x: scale, y: scale),
                beginWithCurrentState: true)
            transition.updateSublayerTransformScale(
                layer: self.mediumBlobView.layer,
                scale: CGPoint(x: scale, y: scale),
                beginWithCurrentState: true)
        })

        DeviceProximityManager.shared().proximityChanged = { [weak self] value in
            if value {
                self?.stopInterfaceAnimation(force: true)
            } else {
                self?.startInterfaceAnimation()
                self?.startInterfaceAnimationTimer()
            }
        }
    }
    
    deinit {
        if let orientationDidChangeObserver = self.orientationDidChangeObserver {
            NotificationCenter.default.removeObserver(orientationDidChangeObserver)
        }
        if let proximityManagerIndex {
            DeviceProximityManager.shared().remove(proximityManagerIndex)
        }
        audioLevelsDisposable?.dispose()
    }

    private func startInterfaceAnimation() {
        guard !isInterfaceAnimationInProgress else {
            return
        }
        isInterfaceAnimationInProgress = true
        startBackgroundAnimation()
        bigBlobView.startAnimating()
        mediumBlobView.startAnimating()

        let transition = ContainedViewLayoutTransition.animated(duration: 1, curve: .linear)
        transition.updateAlpha(layer: bigBlobView.layer, alpha: 1)
        transition.updateAlpha(layer: mediumBlobView.layer, alpha: 1)
    }

    private func stopInterfaceAnimation(force: Bool) {
        if case .active = callState?.state {
        } else if force {
        } else {
            return
        }

        isInterfaceAnimationInProgress = false
        bigBlobView.stopAnimating()
        mediumBlobView.stopAnimating()
        interfaceAnimationTimer?.invalidate()
        interfaceAnimationTimer = nil

        let transition = ContainedViewLayoutTransition.animated(duration: 1, curve: .linear)
        transition.updateAlpha(layer: bigBlobView.layer, alpha: 0)
        transition.updateAlpha(layer: mediumBlobView.layer, alpha: 0) { [weak bigBlobView, weak mediumBlobView] _ in
            bigBlobView?.stopAnimating()
            mediumBlobView?.stopAnimating()
        }
    }

    private func startInterfaceAnimationTimer() {
        guard case .active = callState?.state else {
            return
        }
        interfaceAnimationTimer?.invalidate()
        interfaceAnimationTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            self?.stopInterfaceAnimation(force: false)
        }
    }

    private func showAvatarAnimation() {
        self.bigBlobView.setColor(UIColor.white.withAlphaComponent(0.1))
        self.bigBlobView.layer.animateAlpha(from: 0, to: 1, duration: 0.2)
        self.bigBlobView.layer.animateScale(from: 0, to: 1, duration: 0.2)

        self.mediumBlobView.setColor(UIColor.white.withAlphaComponent(0.2))
        self.mediumBlobView.layer.animateAlpha(from: 0, to: 1, duration: 0.2)
        self.mediumBlobView.layer.animateScale(from: 0, to: 1, duration: 0.2)

        self.imageNode.alpha = 1
        self.imageNode.layer.animateAlpha(from: 0, to: 1, duration: 0.2)
        self.imageNode.layer.animateScale(from: 0, to: 1, duration: 0.2)
    }

    private func hideAvatarAnimation() {
        self.bigBlobView.setColor(UIColor.white.withAlphaComponent(0))
        self.bigBlobView.layer.animateAlpha(from: 1, to: 0, duration: 0.2)
        self.bigBlobView.layer.animateScale(from: 1, to: 0, duration: 0.2)

        self.mediumBlobView.setColor(UIColor.white.withAlphaComponent(0))
        self.mediumBlobView.layer.animateAlpha(from: 1, to: 0, duration: 0.2)
        self.mediumBlobView.layer.animateScale(from: 1, to: 0, duration: 0.2)

        self.imageNode.alpha = 0
        self.imageNode.layer.animateAlpha(from: 1, to: 0, duration: 0.2)
        self.imageNode.layer.animateScale(from: 1, to: 0, duration: 0.2)
    }

    func startBackgroundAnimation() {
        guard isInterfaceAnimationInProgress else {
            return
        }
        currentGradientBackgroundNode?.animateEvent(
            transition: .animated(duration: 1, curve: .linear),
            extendAnimation: false,
            backwards: false) { [weak self] in
                self?.startBackgroundAnimation()
            }
    }
    
    override func didLoad() {
        super.didLoad()
        
        let panRecognizer = CallPanGestureRecognizer(target: self, action: #selector(self.panGesture(_:)))
        panRecognizer.shouldBegin = { [weak self] _ in
            guard let strongSelf = self else {
                return false
            }
            if strongSelf.areUserActionsDisabledNow() {
                return false
            }
            return true
        }
        self.view.addGestureRecognizer(panRecognizer)
        
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.tapGesture(_:)))
        self.view.addGestureRecognizer(tapRecognizer)
    }
    
    func updatePeer(accountPeer: Peer, peer: Peer, hasOther: Bool) {
        if !arePeersEqual(self.peer, peer) {
            self.peer = peer
            if let peerReference = PeerReference(peer), !peer.profileImageRepresentations.isEmpty {
                let representations: [ImageRepresentationWithReference] = peer.profileImageRepresentations.map({ ImageRepresentationWithReference(representation: $0, reference: .avatar(peer: peerReference, resource: $0.resource)) })
                self.imageNode.setSignal(chatAvatarGalleryPhoto(account: self.account, representations: representations, immediateThumbnailData: nil, autoFetchFullSize: true))
            } else {
                self.imageNode.setSignal(callDefaultBackground())
            }
            
            self.toastNode.title = EnginePeer(peer).compactDisplayTitle
            self.statusNode.title = EnginePeer(peer).displayTitle(strings: self.presentationData.strings, displayOrder: self.presentationData.nameDisplayOrder)
            if hasOther {
                self.statusNode.subtitle = self.presentationData.strings.Call_AnsweringWithAccount(EnginePeer(accountPeer).displayTitle(strings: self.presentationData.strings, displayOrder: self.presentationData.nameDisplayOrder)).string
                
                if let callState = self.callState {
                    self.updateCallState(callState)
                }
            }
            
            if let (layout, navigationBarHeight) = self.validLayout {
                self.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .immediate)
            }
        }
    }
    
    func updateAudioOutputs(availableOutputs: [AudioSessionOutput], currentOutput: AudioSessionOutput?) {
        if self.audioOutputState?.0 != availableOutputs || self.audioOutputState?.1 != currentOutput {
            self.audioOutputState = (availableOutputs, currentOutput)
            self.updateButtonsMode()
            
            self.setupAudioOutputs()
        }
    }
    
    private func setupAudioOutputs() {
        if self.outgoingVideoNodeValue != nil || self.incomingVideoNodeValue != nil || self.candidateOutgoingVideoNodeValue != nil || self.candidateIncomingVideoNodeValue != nil {
            if let audioOutputState = self.audioOutputState, let currentOutput = audioOutputState.currentOutput {
                switch currentOutput {
                case .headphones, .speaker:
                    break
                case let .port(port) where port.type == .bluetooth || port.type == .wired:
                    break
                default:
                    self.setCurrentAudioOutput?(.speaker)
                }
            }
        }
    }
    
    func updateCallState(_ callState: PresentationCallState) {
        self.callState = callState
        
        let statusValue: CallControllerStatusValue
        var statusReception: Int32?

        switch callState.state {
        case .terminated, .terminating:
            isRemovedExpandedIncomingNode = expandedVideoNode === incomingVideoNodeValue
            removedMinimizedVideoNodeValue = minimizedVideoNode
            removedExpandedVideoNodeValue = expandedVideoNode
            minimizedVideoNode = nil
            expandedVideoNode = nil
        default:
            break
        }
        
        switch callState.remoteVideoState {
        case .active, .paused:
            keyTooltip?.dismiss()
            keyTooltip = nil

            if !self.incomingVideoViewRequested {
                self.incomingVideoViewRequested = true
                let delayUntilInitialized = true
                self.call.makeIncomingVideoView(completion: { [weak self] incomingVideoView in
                    guard let strongSelf = self else {
                        return
                    }
                    if let incomingVideoView = incomingVideoView {
                        incomingVideoView.view.backgroundColor = .black
                        incomingVideoView.view.clipsToBounds = true
                        
                        let applyNode: () -> Void = {
                            guard let strongSelf = self, let incomingVideoNode = strongSelf.candidateIncomingVideoNodeValue else {
                                return
                            }
                            strongSelf.candidateIncomingVideoNodeValue = nil
                            
                            strongSelf.incomingVideoNodeValue = incomingVideoNode
                            strongSelf.animateIncomingVideoOnce = true
                            if let expandedVideoNode = strongSelf.expandedVideoNode {
                                strongSelf.minimizedVideoNode = expandedVideoNode
                                strongSelf.videoContainerNode.contentNode.insertSubnode(incomingVideoNode, belowSubnode: expandedVideoNode)
                            } else {
                                strongSelf.videoContainerNode.contentNode.addSubnode(incomingVideoNode)
                            }
                            strongSelf.expandedVideoNode = incomingVideoNode
                            strongSelf.updateButtonsMode(transition: .animated(duration: 0.4, curve: .spring))

                            strongSelf.maybeScheduleUIHidingForActiveVideoCall()
                        }
                        
                        let incomingVideoNode = CallVideoNode(videoView: incomingVideoView, disabledText: strongSelf.presentationData.strings.Call_RemoteVideoPaused(strongSelf.peer.flatMap(EnginePeer.init)?.compactDisplayTitle ?? "").string, assumeReadyAfterTimeout: false, isReadyUpdated: {
                            if delayUntilInitialized {
                                Queue.mainQueue().after(0.1, {
                                    applyNode()
                                })
                            }
                        }, orientationUpdated: {
                            guard let strongSelf = self else {
                                return
                            }
                            if let (layout, navigationBarHeight) = strongSelf.validLayout {
                                strongSelf.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .animated(duration: 0.3, curve: .easeInOut))
                            }
                        }, isFlippedUpdated: { _ in
                        })
                        strongSelf.candidateIncomingVideoNodeValue = incomingVideoNode
                        strongSelf.setupAudioOutputs()
                        
                        if !delayUntilInitialized {
                            applyNode()
                        }
                    }
                })
            }
        case .inactive:
            self.candidateIncomingVideoNodeValue = nil
            if let incomingVideoNodeValue = self.incomingVideoNodeValue {
                if self.minimizedVideoNode == incomingVideoNodeValue {
                    self.minimizedVideoNode = nil
                    self.removedMinimizedVideoNodeValue = incomingVideoNodeValue
                }
                if self.expandedVideoNode == incomingVideoNodeValue {
                    self.expandedVideoNode = nil
                    isRemovedExpandedIncomingNode = true
                    self.removedExpandedVideoNodeValue = incomingVideoNodeValue
                    
                    if let minimizedVideoNode = self.minimizedVideoNode {
                        self.expandedVideoNode = minimizedVideoNode
                        self.minimizedVideoNode = nil
                    }
                }
                self.incomingVideoNodeValue = nil
                self.incomingVideoViewRequested = false
            }
        }
        
        switch callState.videoState {
        case .active(false), .paused(false):
            keyTooltip?.dismiss()
            keyTooltip = nil

            if !self.outgoingVideoViewRequested {
                self.outgoingVideoViewRequested = true
                let delayUntilInitialized = self.isRequestingVideo
                self.call.makeOutgoingVideoView(completion: { [weak self] outgoingVideoView in
                    guard let strongSelf = self else {
                        return
                    }
                    
                    if let outgoingVideoView = outgoingVideoView {
                        outgoingVideoView.view.backgroundColor = .black
                        outgoingVideoView.view.clipsToBounds = true
                        
                        let applyNode: () -> Void = {
                            guard let strongSelf = self, let outgoingVideoNode = strongSelf.candidateOutgoingVideoNodeValue else {
                                return
                            }
                            strongSelf.candidateOutgoingVideoNodeValue = nil
                            
                            if strongSelf.isRequestingVideo {
                                strongSelf.isRequestingVideo = false
                                strongSelf.animateOutgoingVideoOnce = true
                            }
                            
                            strongSelf.outgoingVideoNodeValue = outgoingVideoNode
                            if let expandedVideoNode = strongSelf.expandedVideoNode {
                                strongSelf.minimizedVideoNode = outgoingVideoNode
                                strongSelf.videoContainerNode.contentNode.insertSubnode(outgoingVideoNode, aboveSubnode: expandedVideoNode)
                            } else {
                                strongSelf.expandedVideoNode = outgoingVideoNode
                                strongSelf.videoContainerNode.contentNode.addSubnode(outgoingVideoNode)
                            }
                            strongSelf.updateButtonsMode(transition: .animated(duration: 0.4, curve: .spring))
                            
                            strongSelf.maybeScheduleUIHidingForActiveVideoCall()
                        }
                        
                        let outgoingVideoNode = CallVideoNode(videoView: outgoingVideoView, disabledText: nil, assumeReadyAfterTimeout: true, isReadyUpdated: {
                            if delayUntilInitialized {
                                Queue.mainQueue().after(0.4, {
                                    applyNode()
                                })
                            }
                        }, orientationUpdated: {
                            guard let strongSelf = self else {
                                return
                            }
                            if let (layout, navigationBarHeight) = strongSelf.validLayout {
                                strongSelf.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .animated(duration: 0.3, curve: .easeInOut))
                            }
                        }, isFlippedUpdated: { videoNode in
                            guard let _ = self else {
                                return
                            }
                            /*if videoNode === strongSelf.minimizedVideoNode, let tempView = videoNode.view.snapshotView(afterScreenUpdates: true) {
                                videoNode.view.superview?.insertSubview(tempView, aboveSubview: videoNode.view)
                                videoNode.view.frame = videoNode.frame
                                let transitionOptions: UIView.AnimationOptions = [.transitionFlipFromRight, .showHideTransitionViews]

                                UIView.transition(with: tempView, duration: 1.0, options: transitionOptions, animations: {
                                    tempView.isHidden = true
                                }, completion: { [weak tempView] _ in
                                    tempView?.removeFromSuperview()
                                })

                                videoNode.view.isHidden = true
                                UIView.transition(with: videoNode.view, duration: 1.0, options: transitionOptions, animations: {
                                    videoNode.view.isHidden = false
                                })
                            }*/
                        })
                        
                        strongSelf.candidateOutgoingVideoNodeValue = outgoingVideoNode
                        strongSelf.setupAudioOutputs()
                        
                        if !delayUntilInitialized {
                            applyNode()
                        }
                    }
                })
            }
        default:
            self.candidateOutgoingVideoNodeValue = nil
            if let outgoingVideoNodeValue = self.outgoingVideoNodeValue {
                if self.minimizedVideoNode == outgoingVideoNodeValue {
                    self.minimizedVideoNode = nil
                    self.removedMinimizedVideoNodeValue = outgoingVideoNodeValue
                }
                if self.expandedVideoNode == self.outgoingVideoNodeValue {
                    self.expandedVideoNode = nil
                    isRemovedExpandedIncomingNode = false
                    self.removedExpandedVideoNodeValue = outgoingVideoNodeValue
                    
                    if let minimizedVideoNode = self.minimizedVideoNode {
                        self.expandedVideoNode = minimizedVideoNode
                        self.minimizedVideoNode = nil
                    }
                }
                self.outgoingVideoNodeValue = nil
                self.outgoingVideoViewRequested = false
            }
        }
        
        if let incomingVideoNode = self.incomingVideoNodeValue {
            switch callState.state {
            case .terminating, .terminated:
                break
            default:
                let isActive: Bool
                switch callState.remoteVideoState {
                case .inactive, .paused:
                    isActive = false
                case .active:
                    isActive = true
                }
                incomingVideoNode.updateIsBlurred(isBlurred: !isActive)
            }
        }

        let backgroundGradientStyle: CallBackgroundGradientStyle
        switch callState.state {
        case .active(_, let reception, _), .reconnecting(_, let reception, _):
            if let reception = reception, reception < 2 {
                backgroundGradientStyle = .orange
            } else {
                backgroundGradientStyle = .green
            }
        default:
            backgroundGradientStyle = .violet
        }

        updateBackgroundGradient(backgroundGradientStyle)
                
        switch callState.state {
            case .waiting, .connecting:
                statusValue = .text(string: self.presentationData.strings.Call_StatusConnecting, displayLogo: true)
            case let .requesting(ringing):
                if ringing {
                    statusValue = .text(string: self.presentationData.strings.Call_StatusRinging, displayLogo: true)
                } else {
                    statusValue = .text(string: self.presentationData.strings.Call_StatusRequesting, displayLogo: true)
                }
            case .terminating:
            statusReception = statusNode.reception
            statusValue = statusNode.status
            case let .terminated(_, _, reason, _):
                if let reason = reason {
                    switch reason {
                        case let .ended(type):
                            switch type {
                                case .busy:
                                    statusValue = .text(string: self.presentationData.strings.Call_StatusBusy, displayLogo: false)
                                case .hungUp, .missed:
                                    statusValue = .text(string: self.presentationData.strings.Call_StatusEnded, displayLogo: false)
                            }
                        case let .error(error):
                            let text = self.presentationData.strings.Call_StatusFailed
                            switch error {
                            case let .notSupportedByPeer(isVideo):
                                if !self.displayedVersionOutdatedAlert, let peer = self.peer {
                                    self.displayedVersionOutdatedAlert = true
                                    
                                    let text: String
                                    if isVideo {
                                        text = self.presentationData.strings.Call_ParticipantVideoVersionOutdatedError(EnginePeer(peer).displayTitle(strings: self.presentationData.strings, displayOrder: self.presentationData.nameDisplayOrder)).string
                                    } else {
                                        text = self.presentationData.strings.Call_ParticipantVersionOutdatedError(EnginePeer(peer).displayTitle(strings: self.presentationData.strings, displayOrder: self.presentationData.nameDisplayOrder)).string
                                    }
                                    
                                    self.present?(textAlertController(sharedContext: self.sharedContext, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: self.presentationData.strings.Common_OK, action: {
                                    })]))
                                }
                            default:
                                break
                            }
                            statusValue = .text(string: text, displayLogo: false)
                    }
                } else {
                    statusValue = .text(string: self.presentationData.strings.Call_StatusEnded, displayLogo: false)
                }
            case .ringing:
                var text: String
                if self.call.isVideo {
                    text = self.presentationData.strings.Call_IncomingVideoCall
                } else {
                    text = self.presentationData.strings.Call_IncomingVoiceCall
                }
                if !self.statusNode.subtitle.isEmpty {
                    text += "\n\(self.statusNode.subtitle)"
                }
                statusValue = .text(string: text, displayLogo: false)
            case .active(let timestamp, let reception, let keyVisualHash), .reconnecting(let timestamp, let reception, let keyVisualHash):
                let strings = self.presentationData.strings
                var isReconnecting = false
                if case .reconnecting = callState.state {
                    isReconnecting = true
                }
                if self.keyTextData?.0 != keyVisualHash {
                    let text = stringForEmojiHashOfData(keyVisualHash, 4)!
                    self.keyTextData = (keyVisualHash, text)

                    self.keyButtonNode.key = text
                    
                    self.keyButtonNode.frame = CGRect(
                        origin: self.keyButtonNode.frame.origin,
                        size: self.keyButtonNode.measure(.zero))
                    
                    if !isKeyTooltipShown, expandedVideoNode == nil, UserDefaults.standard.bool(forKey: "isKeyPreviewShown") != true {
                        isKeyTooltipShown = true

                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
                            let keyTooltip = TooltipScreen(
                                account: account,
                                text: "Encryption key of this call",
                                style: .light,
                                icon: nil,
                                location: .point(keyButtonNode.frame.offsetBy(dx: 0, dy: 5), .top),
                                displayDuration: .custom(5)) { _ in
                                    return .dismiss(consume: false)
                                }
                            present?(keyTooltip)
                            self.keyTooltip = keyTooltip
                        }
                    }
                    
                    if let (layout, navigationBarHeight) = self.validLayout {
                        self.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .immediate)
                    }
                }
                
                statusValue = .timer({ value, measure in
                    if isReconnecting || (self.outgoingVideoViewRequested && value == "00:00" && !measure) {
                        return strings.Call_StatusConnecting
                    } else {
                        return value
                    }
                }, timestamp)
                if case .active = callState.state {
                    statusReception = reception
                }
        }
        if self.shouldStayHiddenUntilConnection {
            switch callState.state {
                case .connecting, .active:
                    self.containerNode.alpha = 1.0
                default:
                    break
            }
        }

        switch callState.state {
        case let .terminating(timestamp, _):
            setupCallEndedStatusNode(timestamp: timestamp)

            let ratingNode = CallControllerRatingNode() { [weak self] rating in
                guard let self else {
                    return
                }

                guard let currentCallID = self.currentCallID else {
                    self.back?()
                    return
                }
                if rating < 4 {
                    self.present?(callFeedbackController(sharedContext: self.sharedContext, account: self.account, callId: currentCallID, rating: rating, userInitiated: false, isVideo: self.call.isVideo))
                } else {
                    let _ = rateCallAndSendLogs(engine: TelegramEngine(account: self.account), callId: currentCallID, starsCount: rating, comment: "", userInitiated: false, includeLogs: false).start()
                }
                self.back?()
            }
            self.containerNode.addSubnode(ratingNode)
            self.ratingNode = ratingNode

            let closeRatingButtonNode = CallControllerCloseRatingButtonNode() { [weak self] in
                self?.back?()
            }
            self.containerNode.addSubnode(closeRatingButtonNode)
            self.closeRatingButtonNode = closeRatingButtonNode

        case let .terminated(_, callID, _, _):
            currentCallID = callID
            callEnded?(false)
        default:
            statusNode.status = statusValue
            statusNode.reception = statusReception
        }
        
        if let callState = self.callState {
            switch callState.state {
            case .active, .connecting, .reconnecting:
                break
            default:
                self.isUIHidden = false
            }
        }
        
        self.updateToastContent()
        self.updateButtonsMode()
        
        if self.incomingVideoViewRequested || self.outgoingVideoViewRequested {
            if self.incomingVideoViewRequested && self.outgoingVideoViewRequested {
                self.displayedCameraTooltip = true
            }
            self.displayedCameraConfirmation = true
        }
        
        if let (layout, navigationBarHeight) = self.validLayout {
            self.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .animated(duration: 0.3, curve: .linear))
        }
        
        let hasIncomingVideoNode = self.incomingVideoNodeValue != nil && self.expandedVideoNode === self.incomingVideoNodeValue
        self.videoContainerNode.isPinchGestureEnabled = hasIncomingVideoNode

        if case .active = callState.state {
            if !isCallStateActive {
                startInterfaceAnimationTimer()
            }
            isCallStateActive = true
        } else {
            isCallStateActive = false
            interfaceAnimationTimer?.invalidate()
            interfaceAnimationTimer = nil
        }
    }

    private func setupCallEndedStatusNode(timestamp: Double) {
        let node = CallControllerStatusNode()
        node.title = "Call Ended"
        node.status = .endTime(timestamp)
        node.alpha = 0
        containerNode.insertSubnode(node, aboveSubnode: statusNode)
        callEndedStatusNode = node
    }
    
    private func updateToastContent() {
        guard let callState = self.callState else {
            return
        }
        if case .terminating = callState.state {
        } else if case .terminated = callState.state {
        } else {
            var toastContent: CallControllerToastContent = []
            if case .active = callState.state {
                if let displayToastsAfterTimestamp = self.displayToastsAfterTimestamp {
                    if CACurrentMediaTime() > displayToastsAfterTimestamp {
                        if case .inactive = callState.remoteVideoState, self.hasVideoNodes {
                            toastContent.insert(.camera)
                        }
                        if case .muted = callState.remoteAudioState {
                            toastContent.insert(.microphone)
                        }
                        if case .low = callState.remoteBatteryLevel {
                            toastContent.insert(.battery)
                        }
                    }
                } else {
                    self.displayToastsAfterTimestamp = CACurrentMediaTime() + 1.5
                }
            }
            if self.isMuted, let (availableOutputs, _) = self.audioOutputState, availableOutputs.count > 2 {
                toastContent.insert(.mute)
            }
            self.toastContent = toastContent
        }
    }
    
    private func maybeScheduleUIHidingForActiveVideoCall() {
        guard let callState = self.callState, case .active = callState.state, self.incomingVideoNodeValue != nil && self.outgoingVideoNodeValue != nil, !self.hiddenUIForActiveVideoCallOnce && self.keyPreviewNode == nil else {
            return
        }
        
        let timer = SwiftSignalKit.Timer(timeout: 3.0, repeat: false, completion: { [weak self] in
            if let strongSelf = self {
                var updated = false
                if let callState = strongSelf.callState, !strongSelf.isUIHidden {
                    switch callState.state {
                        case .active, .connecting, .reconnecting:
                            strongSelf.isUIHidden = true
                            updated = true
                        default:
                            break
                    }
                }
                if updated, let (layout, navigationBarHeight) = strongSelf.validLayout {
                    strongSelf.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .animated(duration: 0.3, curve: .easeInOut))
                }
                strongSelf.hideUIForActiveVideoCallTimer = nil
            }
        }, queue: Queue.mainQueue())
        timer.start()
        self.hideUIForActiveVideoCallTimer = timer
        self.hiddenUIForActiveVideoCallOnce = true
    }
    
    private func cancelScheduledUIHiding() {
        self.hideUIForActiveVideoCallTimer?.invalidate()
        self.hideUIForActiveVideoCallTimer = nil
    }
    
    private var buttonsTerminationMode: CallControllerButtonsMode?
    
    private func updateButtonsMode(transition: ContainedViewLayoutTransition = .animated(duration: 0.3, curve: .spring)) {
        guard let callState = self.callState else {
            return
        }
        
        var mode: CallControllerButtonsSpeakerMode = .none
        var hasAudioRouteMenu: Bool = false
        if let (availableOutputs, maybeCurrentOutput) = self.audioOutputState, let currentOutput = maybeCurrentOutput {
            hasAudioRouteMenu = availableOutputs.count > 2
            switch currentOutput {
                case .builtin:
                    mode = .builtin
                case .speaker:
                    mode = .speaker
                case .headphones:
                    mode = .headphones
                case let .port(port):
                    var type: CallControllerButtonsSpeakerMode.BluetoothType = .generic
                    let portName = port.name.lowercased()
                    if portName.contains("airpods pro") {
                        type = .airpodsPro
                    } else if portName.contains("airpods") {
                        type = .airpods
                    }
                    mode = .bluetooth(type)
            }
            if availableOutputs.count <= 1 {
                mode = .none
            }
        }
        var mappedVideoState = CallControllerButtonsMode.VideoState(isAvailable: false, isCameraActive: self.outgoingVideoNodeValue != nil, isScreencastActive: false, canChangeStatus: false, hasVideo: self.outgoingVideoNodeValue != nil || self.incomingVideoNodeValue != nil, isInitializingCamera: self.isRequestingVideo)
        switch callState.videoState {
        case .notAvailable:
            break
        case .inactive:
            mappedVideoState.isAvailable = true
            mappedVideoState.canChangeStatus = true
        case .active(let isScreencast), .paused(let isScreencast):
            mappedVideoState.isAvailable = true
            mappedVideoState.canChangeStatus = true
            if isScreencast {
                mappedVideoState.isScreencastActive = true
                mappedVideoState.hasVideo = true
            }
        }
        
        switch callState.state {
        case .ringing:
            self.buttonsMode = .incoming(speakerMode: mode, hasAudioRouteMenu: hasAudioRouteMenu, videoState: mappedVideoState)
            self.buttonsTerminationMode = buttonsMode
        case .waiting, .requesting:
            self.buttonsMode = .outgoingRinging(speakerMode: mode, hasAudioRouteMenu: hasAudioRouteMenu, videoState: mappedVideoState)
            self.buttonsTerminationMode = buttonsMode
        case .active, .connecting, .reconnecting:
            self.buttonsMode = .active(speakerMode: mode, hasAudioRouteMenu: hasAudioRouteMenu, videoState: mappedVideoState)
            self.buttonsTerminationMode = buttonsMode
        case .terminating, .terminated:
            if let buttonsTerminationMode = self.buttonsTerminationMode {
                self.buttonsMode = buttonsTerminationMode
            } else {
                self.buttonsMode = .active(speakerMode: mode, hasAudioRouteMenu: hasAudioRouteMenu, videoState: mappedVideoState)
            }
        }
                
        if let (layout, navigationHeight) = self.validLayout {
            self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: transition)
        }
    }
    
    func animateIn() {
        if !self.containerNode.alpha.isZero {
            var bounds = self.bounds
            bounds.origin = CGPoint()
            self.bounds = bounds
            self.layer.removeAnimation(forKey: "bounds")
            self.statusBar.layer.removeAnimation(forKey: "opacity")
            self.containerNode.layer.removeAnimation(forKey: "opacity")
            self.containerNode.layer.removeAnimation(forKey: "scale")
            self.statusBar.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3)
            if !self.shouldStayHiddenUntilConnection {
                self.containerNode.layer.animateScale(from: 1.04, to: 1.0, duration: 0.3)
                self.containerNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
            }
        }

        self.mediumBlobView.startAnimating()
        self.mediumBlobView.updateSpeedLevel(to: 2)
        self.mediumBlobView.level = 2

        self.bigBlobView.startAnimating()
        self.bigBlobView.updateSpeedLevel(to: 2)
        self.bigBlobView.level = 2
    }
    
    func animateOut(completion: @escaping () -> Void) {
        self.statusBar.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3, removeOnCompletion: false)
        if !self.shouldStayHiddenUntilConnection || self.containerNode.alpha > 0.0 {
            self.containerNode.layer.allowsGroupOpacity = true
            self.containerNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3, removeOnCompletion: false, completion: { [weak self] _ in
                self?.containerNode.layer.allowsGroupOpacity = false
            })
            self.containerNode.layer.animateScale(from: 1.0, to: 1.04, duration: 0.3, removeOnCompletion: false, completion: { _ in
                completion()
            })
        } else {
            completion()
        }
    }
    
    func expandFromPipIfPossible() {
        if self.pictureInPictureTransitionFraction.isEqual(to: 1.0), let (layout, navigationHeight) = self.validLayout {
            self.pictureInPictureTransitionFraction = 0.0
            
            self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: .animated(duration: 0.4, curve: .spring))
        }
    }

    private func updateBackgroundGradient(_ style: CallBackgroundGradientStyle) {
        guard !isUpdateBackgroundAnimationInProgress,
              style != currentBackgroundGradientStyle,
              let currentGradientBackgroundNode,
              let nextGradientBackgroundNode = gradientBackgroundNodes[style]
        else {
            return
        }
        self.isUpdateBackgroundAnimationInProgress = true
        self.currentBackgroundGradientStyle = style
        self.currentGradientBackgroundNode = nextGradientBackgroundNode

        nextGradientBackgroundNode.alpha = 0
        containerNode.insertSubnode(nextGradientBackgroundNode, aboveSubnode: currentGradientBackgroundNode)

        let transition = ContainedViewLayoutTransition.animated(duration: 0.3, curve: .linear)
        transition.updateAlpha(node: nextGradientBackgroundNode, alpha: 1) { [weak currentGradientBackgroundNode, weak self] _ in
            self?.isUpdateBackgroundAnimationInProgress = false
            currentGradientBackgroundNode?.removeFromSupernode()
        }
    }
    
    private func calculatePreviewVideoRect(layout: ContainerViewLayout, navigationHeight: CGFloat) -> CGRect {
        let buttonsHeight: CGFloat = self.buttonsNode.bounds.height
        let toastHeight: CGFloat = self.toastNode.bounds.height
        let toastInset = (toastHeight > 0.0 ? toastHeight + 22.0 : 0.0)
        
        var fullInsets = layout.insets(options: .statusBar)
    
        var cleanInsets = fullInsets
        cleanInsets.bottom = max(layout.intrinsicInsets.bottom, 20.0) + toastInset
        cleanInsets.left = 20.0
        cleanInsets.right = 20.0
        
        fullInsets.top += 44.0 + 8.0
        fullInsets.bottom = buttonsHeight + 22.0 + toastInset
        fullInsets.left = 20.0
        fullInsets.right = 20.0
        
        var insets: UIEdgeInsets = self.isUIHidden ? cleanInsets : fullInsets
        
        let expandedInset: CGFloat = 16.0
        
        insets.top = interpolate(from: expandedInset, to: insets.top, value: 1.0 - self.pictureInPictureTransitionFraction)
        insets.bottom = interpolate(from: expandedInset, to: insets.bottom, value: 1.0 - self.pictureInPictureTransitionFraction)
        insets.left = interpolate(from: expandedInset, to: insets.left, value: 1.0 - self.pictureInPictureTransitionFraction)
        insets.right = interpolate(from: expandedInset, to: insets.right, value: 1.0 - self.pictureInPictureTransitionFraction)
        
        let previewVideoSide = interpolate(from: 300.0, to: 150.0, value: 1.0 - self.pictureInPictureTransitionFraction)
        var previewVideoSize = layout.size.aspectFitted(CGSize(width: previewVideoSide, height: previewVideoSide))
        previewVideoSize = CGSize(width: 30.0, height: 45.0).aspectFitted(previewVideoSize)
        if let minimizedVideoNode = self.minimizedVideoNode {
            var aspect = minimizedVideoNode.currentAspect
            var rotationCount = 0
            if minimizedVideoNode === self.outgoingVideoNodeValue {
                aspect = 3.0 / 4.0
            } else {
                if aspect < 1.0 {
                    aspect = 3.0 / 4.0
                } else {
                    aspect = 4.0 / 3.0
                }
                
                switch minimizedVideoNode.currentOrientation {
                case .rotation90, .rotation270:
                    rotationCount += 1
                default:
                    break
                }
                
                var mappedDeviceOrientation = self.deviceOrientation
                if case .regular = layout.metrics.widthClass, case .regular = layout.metrics.heightClass {
                    mappedDeviceOrientation = .portrait
                }
                
                switch mappedDeviceOrientation {
                case .landscapeLeft, .landscapeRight:
                    rotationCount += 1
                default:
                    break
                }
                
                if rotationCount % 2 != 0 {
                    aspect = 1.0 / aspect
                }
            }
            
            let unboundVideoSize = CGSize(width: aspect * 10000.0, height: 10000.0)
            
            previewVideoSize = unboundVideoSize.aspectFitted(CGSize(width: previewVideoSide, height: previewVideoSide))
        }
        let previewVideoY: CGFloat
        let previewVideoX: CGFloat
        
        switch self.outgoingVideoNodeCorner {
        case .topLeft:
            previewVideoX = insets.left
            previewVideoY = insets.top
        case .topRight:
            previewVideoX = layout.size.width - previewVideoSize.width - insets.right
            previewVideoY = insets.top
        case .bottomLeft:
            previewVideoX = insets.left
            previewVideoY = layout.size.height - insets.bottom - previewVideoSize.height
        case .bottomRight:
            previewVideoX = layout.size.width - previewVideoSize.width - insets.right
            previewVideoY = layout.size.height - insets.bottom - previewVideoSize.height
        }
        
        return CGRect(origin: CGPoint(x: previewVideoX, y: previewVideoY), size: previewVideoSize)
    }
    
    private func calculatePictureInPictureContainerRect(layout: ContainerViewLayout, navigationHeight: CGFloat) -> CGRect {
        let pictureInPictureTopInset: CGFloat = layout.insets(options: .statusBar).top + 44.0 + 8.0
        let pictureInPictureSideInset: CGFloat = 8.0
        let pictureInPictureSize = layout.size.fitted(CGSize(width: 240.0, height: 240.0))
        let pictureInPictureBottomInset: CGFloat = layout.insets(options: .input).bottom + 44.0 + 8.0
        
        let containerPictureInPictureFrame: CGRect
        switch self.pictureInPictureCorner {
        case .topLeft:
            containerPictureInPictureFrame = CGRect(origin: CGPoint(x: pictureInPictureSideInset, y: pictureInPictureTopInset), size: pictureInPictureSize)
        case .topRight:
            containerPictureInPictureFrame = CGRect(origin: CGPoint(x: layout.size.width -  pictureInPictureSideInset - pictureInPictureSize.width, y: pictureInPictureTopInset), size: pictureInPictureSize)
        case .bottomLeft:
            containerPictureInPictureFrame = CGRect(origin: CGPoint(x: pictureInPictureSideInset, y: layout.size.height - pictureInPictureBottomInset - pictureInPictureSize.height), size: pictureInPictureSize)
        case .bottomRight:
            containerPictureInPictureFrame = CGRect(origin: CGPoint(x: layout.size.width -  pictureInPictureSideInset - pictureInPictureSize.width, y: layout.size.height - pictureInPictureBottomInset - pictureInPictureSize.height), size: pictureInPictureSize)
        }
        return containerPictureInPictureFrame
    }

    private func backgroundLayoutUpdated(_ layout: ContainerViewLayout) {
        for style in CallBackgroundGradientStyle.allCases {
            gradientBackgroundNodes[style]?.frame = CGRect(origin: .zero, size: layout.size)
            gradientBackgroundNodes[style]?.updateLayout(size: layout.size, transition: .immediate, extendAnimation: false, backwards: false, completion: {})
        }

        if !isBackgroundAnimationStarted {
            isBackgroundAnimationStarted = true
            startInterfaceAnimation()
        }
    }

    private func backButtonLayoutUpdated(
        _ layout: ContainerViewLayout,
        transition: ContainedViewLayoutTransition,
        uiDisplayTransition: CGFloat
    ) {
        let size = backButtonNode.measure(CGSize(width: 320, height: 100))
        let navigationOffset: CGFloat = max(20, layout.safeInsets.top)
        let originY = interpolate(from: -size.height, to: navigationOffset + 11, value: uiDisplayTransition)
        if let image = backButtonArrowNode.image {
            transition.updateFrame(
                node: backButtonArrowNode,
                frame: CGRect(
                    origin: CGPoint(x: 10, y: originY),
                    size: image.size))
        }
        transition.updateFrame(
            node: backButtonNode,
            frame: CGRect(
                origin: CGPoint(x: 29, y: originY),
                size: size))
    }

    private func keyButtonLayoutUpdated(
        _ layout: ContainerViewLayout,
        transition: ContainedViewLayoutTransition,
        uiDisplayTransition: CGFloat
    ) {
        let navigationOffset: CGFloat = max(20, layout.safeInsets.top)
        let originY = interpolate(from: -keyButtonNode.frame.size.height, to: navigationOffset + 8, value: uiDisplayTransition)
        transition.updateFrame(
            node: keyButtonNode,
            frame: CGRect(
                origin: CGPoint(
                    x: layout.size.width - keyButtonNode.frame.size.width - 8,
                    y: originY),
                size: keyButtonNode.frame.size))

        switch callState?.state {
        case .terminating:
            transition.updateAlpha(node: keyButtonNode, alpha: 0)
        default:
            break
        }
    }

    private func avatarLayoutUpdated(
        _ layout: ContainerViewLayout,
        transition: ContainedViewLayoutTransition
    ) {

        var originY: CGFloat = layout.size.height > 736 ? 222 : 202

        if callEndedStatusNode != nil, layout.size.height < 736 {
            originY -= 60
        }

        let size = layout.size.height > 736
            ? CGSize(width: 136, height: 136)
            : CGSize(width: 124, height: 124)

        transition.updateFrame(
            node: imageNode,
            frame: CGRect(
                origin: CGPoint(x: (layout.size.width - size.width) / 2, y: originY),
                size: size))
        imageNode.cornerRadius = size.width / 2
        imageNode.clipsToBounds = true

        let mediumSide = floor(size.width * 1.09)
        transition.updateFrame(
            view: mediumBlobView,
            frame: CGRect(
                x: (layout.size.width - mediumSide) / 2,
                y: originY - (mediumSide - size.width) / 2,
                width: mediumSide,
                height: mediumSide))

        let bigSide = floor(size.width * 0.97)
        transition.updateFrame(
            view: bigBlobView,
            frame: CGRect(
                x: (layout.size.width - bigSide) / 2,
                y: originY + (size.width - bigSide) / 2,
                width: floor(size.width * 0.97),
                height: floor(size.height * 0.97)))

        imageNode.asyncLayout()(TransformImageArguments(
            corners: ImageCorners(radius: size.width / 2),
            imageSize: CGSize(width: 640, height: 640).aspectFilled(size),
            boundingSize: size, intrinsicInsets: UIEdgeInsets()))()

        switch callState?.state {
        case .terminating:
            transition.updateAlpha(layer: mediumBlobView.layer, alpha: 0)
            transition.updateAlpha(layer: bigBlobView.layer, alpha: 0)
        default:
            break
        }
    }

    private func statusLayoutUpdated(
        _ layout: ContainerViewLayout,
        transition: ContainedViewLayoutTransition,
        uiDisplayTransition: CGFloat
    ) {
        if expandedVideoNode == nil {
            let height = statusNode.updateLayout(constrainedWidth: layout.size.width, transition: transition)
            transition.updateTransformScale(node: statusNode, scale: 1)
            transition.updateFrame(
                node: statusNode,
                frame: CGRect(
                    origin: CGPoint(x: 0, y: imageNode.frame.maxY + 40),
                    size: CGSize(width: layout.size.width, height: height)))
        } else {
            let navigationOffset: CGFloat = max(20, layout.safeInsets.top)
            let originY = interpolate(from: -statusNode.frame.size.height, to: navigationOffset + 36, value: uiDisplayTransition)
            transition.updateTransformScale(node: statusNode, scale: 0.8)
            transition.updateFrame(
                node: statusNode,
                frame: CGRect(
                    x: (layout.size.width - statusNode.frame.width) / 2,
                    y: originY,
                    width: statusNode.frame.width,
                    height: statusNode.frame.height))
        }

        if let callEndedStatusNode {
            _ = callEndedStatusNode.updateLayout(constrainedWidth: layout.size.width, transition: .immediate)
            callEndedStatusNode.frame = statusNode.frame
            transition.updateAlpha(node: statusNode, alpha: 0)
            transition.updateAlpha(node: callEndedStatusNode, alpha: 1)

            if layout.size.height < 736 {
                callEndedStatusNode.frame.origin.y += 60
                transition.updateFrame(
                    node: callEndedStatusNode,
                    frame: CGRect(
                        origin: CGPoint(x: statusNode.frame.minX, y: statusNode.frame.minY),
                        size: statusNode.frame.size))
            }
        }
    }

    private func buttonsLayoutUpdated(
        _ layout: ContainerViewLayout,
        transition: ContainedViewLayoutTransition,
        uiDisplayTransition: CGFloat
    ) {
        let height: CGFloat
        if let buttonsMode = buttonsMode {
            height = buttonsNode.updateLayout(strings: presentationData.strings, mode: buttonsMode, constrainedWidth: layout.size.width, bottomInset: layout.intrinsicInsets.bottom, transition: transition)
        } else {
            height = 0
        }

        let buttonsCollapsedOriginY = pictureInPictureTransitionFraction > 0
            ? layout.size.height + 30
            : layout.size.height + 10
        let buttonsOriginY = interpolate(
            from: buttonsCollapsedOriginY,
            to: layout.size.height - height,
            value: uiDisplayTransition)

        transition.updateFrame(
            node: buttonsNode,
            frame: CGRect(
                origin: CGPoint(x: 0, y: buttonsOriginY),
                size: CGSize(width: layout.size.width, height: height)))

        switch self.callState?.state {
        case .terminating:
            transition.updateAlpha(node: buttonsNode, alpha: 0)
        default:
            break
        }

        if expandedVideoNode == nil {
            buttonsNode.updateStyle(.light)
        } else {
            buttonsNode.updateStyle(.dark)
        }
    }

    private func toastLayoutUpdated(
        _ layout: ContainerViewLayout,
        transition: ContainedViewLayoutTransition,
        uiDisplayTransition: CGFloat
    ) {
        let height = toastNode.updateLayout(strings: presentationData.strings, content: toastContent, constrainedWidth: layout.size.width, bottomInset: layout.intrinsicInsets.bottom + buttonsNode.frame.height, transition: transition)

        let toastCollapsedOriginY = pictureInPictureTransitionFraction > 0
            ? layout.size.height
            : layout.size.height - max(layout.intrinsicInsets.bottom, 20) - height
        let toastOriginY = interpolate(
            from: toastCollapsedOriginY,
            to: buttonsNode.frame.minY - 22 - height,
            value: uiDisplayTransition)

        transition.updateFrame(
            node: toastNode,
            frame: CGRect(
                origin: CGPoint(x: 0.0, y: toastOriginY),
                size: CGSize(width: layout.size.width, height: height)))

        switch self.callState?.state {
        case .terminating:
            transition.updateAlpha(node: toastNode, alpha: 0)
        default:
            break
        }
    }

    private func keyPreviewLayoutUpdated(
        _ layout: ContainerViewLayout,
        transition: ContainedViewLayoutTransition
    ) {
        if let keyPreviewNode {
            let size = keyPreviewNode.updateLayout(transition: .immediate)
            transition.updateFrame(
                node: keyPreviewNode,
                frame: CGRect(
                    origin: CGPoint(x: (layout.size.width - size.width) / 2, y: 136),
                    size: size))

            if expandedVideoNode == nil {
                keyPreviewNode.updateStyle(.light)
            } else {
                keyPreviewNode.updateStyle(.dark)
            }

            switch callState?.state {
            case .terminating:
                transition.updateAlpha(node: keyPreviewNode, alpha: 0)
            default:
                break
            }
        }

        if callEndedStatusNode != nil, keyPreviewNode != nil {
            backPressed()
        }
    }

    private func ratingLayoutUpdated(
        _ layout: ContainerViewLayout,
        transition: ContainedViewLayoutTransition
    ) {
        if let closeRatingButtonNode, let ratingNode {
            let closeRatingButtonSize = closeRatingButtonNode.updateLayout(transition: .immediate)
            closeRatingButtonNode.frame = CGRect(
                origin: CGPoint(
                    x: (layout.size.width - closeRatingButtonSize.width) / 2,
                    y: buttonsNode.frame.minY + (buttonsNode.frame.height - closeRatingButtonSize.height) / 2),
                size: closeRatingButtonSize)

            if !isCloseRatingButtonShown {
                isCloseRatingButtonShown = true
                closeRatingButtonNode.animateIn()
            }

            let ratingSize = ratingNode.updateLayout(transition: .immediate)
            ratingNode.frame = CGRect(
                origin: CGPoint(
                    x: (layout.size.width - ratingSize.width) / 2,
                    y: closeRatingButtonNode.frame.minY - 66 - ratingSize.height),
                size: ratingSize)

            if !isRatingShown {
                isRatingShown = true
                ratingNode.animateIn()
            }
        }
    }

    private func videoLayoutUpdated(
        _ layout: ContainerViewLayout,
        navigationBarHeight: CGFloat,
        transition: ContainedViewLayoutTransition,
        mappedDeviceOrientation: UIDeviceOrientation,
        isCompactLayout: Bool
    ) {
        let fullScreenFrame = CGRect(origin: CGPoint(), size: layout.size)
        let previewVideoFrame = calculatePreviewVideoRect(layout: layout, navigationHeight: navigationBarHeight)

        transition.updateFrame(node: videoContainerNode, frame: fullScreenFrame)
        videoContainerNode.update(size: fullScreenFrame.size, transition: transition)

        if let removedMinimizedVideoNodeValue {
            self.removedMinimizedVideoNodeValue = nil

            if transition.isAnimated {
                removedMinimizedVideoNodeValue.layer.animateScale(from: 1.0, to: 0.1, duration: 0.3, removeOnCompletion: false) { [weak removedMinimizedVideoNodeValue] _ in
                    removedMinimizedVideoNodeValue?.removeFromSupernode()
                }
                removedMinimizedVideoNodeValue.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false)
            } else {
                removedMinimizedVideoNodeValue.removeFromSupernode()
            }
        }

        if let expandedVideoNode {
            var expandedVideoTransition = transition
            if expandedVideoNode.frame.isEmpty || disableAnimationForExpandedVideoOnce {
                expandedVideoTransition = .immediate
                disableAnimationForExpandedVideoOnce = false
            }

            if let removedExpandedVideoNodeValue {
                self.removedExpandedVideoNodeValue = nil

                expandedVideoTransition.updateFrame(node: expandedVideoNode, frame: fullScreenFrame, completion: { [weak removedExpandedVideoNodeValue] _ in
                    removedExpandedVideoNodeValue?.removeFromSupernode()
                })
            } else {
                expandedVideoTransition.updateFrame(node: expandedVideoNode, frame: fullScreenFrame)
            }

            expandedVideoNode.updateLayout(
                size: expandedVideoNode.frame.size,
                cornerRadius: 0,
                isOutgoing: expandedVideoNode === self.outgoingVideoNodeValue,
                deviceOrientation: mappedDeviceOrientation,
                isCompactLayout: isCompactLayout,
                transition: expandedVideoTransition)

            if expandedVideoNode === outgoingVideoNodeValue, animateOutgoingVideoOnce {
                animateOutgoingVideoOnce = false

                let videoButtonFrame = buttonsNode.videoButtonFrame().flatMap { frame -> CGRect in
                    return buttonsNode.view.convert(frame, to: view)
                }

                if let videoButtonFrame = videoButtonFrame {
                    expandedVideoNode.animateRadialMask(
                        from: videoButtonFrame,
                        to: fullScreenFrame)
                }
            } else if expandedVideoNode === incomingVideoNodeValue, animateIncomingVideoOnce {
                animateIncomingVideoOnce = false

                if minimizedVideoNode == nil {
                    let transform = ContainedViewLayoutTransition.animated(duration: 0.1, curve: .linear)
                    expandedVideoNode.alpha = 0
                    transform.updateAlpha(node: expandedVideoNode, alpha: 1)
                    expandedVideoNode.animateMask(
                        from: imageNode.frame,
                        fromCornerRadius: imageNode.frame.width / 2,
                        to: fullScreenFrame,
                        toCornerRadius: 0)
                }
            } else {
                transition.updateAlpha(node: expandedVideoNode, alpha: 1)
            }
        } else if let removedExpandedVideoNodeValue {
            self.removedExpandedVideoNodeValue = nil

            if isRemovedExpandedIncomingNode {

                let transform = ContainedViewLayoutTransition.animated(duration: 0.1, curve: .linear)
                transform.updateAlpha(node: removedExpandedVideoNodeValue, alpha: 0, delay: 0.2)
                removedExpandedVideoNodeValue.animateMask(
                    from: fullScreenFrame,
                    fromCornerRadius: 0,
                    to: imageNode.frame,
                    toCornerRadius: imageNode.frame.width / 2
                ) { [weak removedExpandedVideoNodeValue] in
                    removedExpandedVideoNodeValue?.removeFromSupernode()
                }
            } else {
                if let videoButtonFrame = buttonsNode.videoButtonFrame().flatMap({ frame -> CGRect in
                    return buttonsNode.view.convert(frame, to: view)
                }) {
                    removedExpandedVideoNodeValue.animateRadialMaskToSmall(from: fullScreenFrame, to: videoButtonFrame) { [weak removedExpandedVideoNodeValue] in
                        removedExpandedVideoNodeValue?.removeFromSupernode()
                    }
                }
            }
        }

        if let minimizedVideoNode {
            var minimizedVideoTransition = transition
            var didAppear = false
            if minimizedVideoNode.frame.isEmpty {
                minimizedVideoTransition = .immediate
                didAppear = true
            }

            if minimizedVideoDraggingPosition == nil {
                if let animationForExpandedVideoSnapshotView {
                    self.animationForExpandedVideoSnapshotView = nil

                    containerNode.view.addSubview(animationForExpandedVideoSnapshotView)
                    transition.updateAlpha(layer: animationForExpandedVideoSnapshotView.layer, alpha: 0, completion: { [weak animationForExpandedVideoSnapshotView] _ in
                        animationForExpandedVideoSnapshotView?.removeFromSuperview()
                    })
                    transition.updateTransformScale(layer: animationForExpandedVideoSnapshotView.layer, scale: previewVideoFrame.width / fullScreenFrame.width)
                    transition.updatePosition(
                        layer: animationForExpandedVideoSnapshotView.layer,
                        position: CGPoint(
                            x: previewVideoFrame.minX + previewVideoFrame.center.x /  fullScreenFrame.width * previewVideoFrame.width,
                            y: previewVideoFrame.minY + previewVideoFrame.center.y / fullScreenFrame.height * previewVideoFrame.height))
                }
                minimizedVideoTransition.updateFrame(node: minimizedVideoNode, frame: previewVideoFrame)
                minimizedVideoNode.updateLayout(
                    size: previewVideoFrame.size,
                    cornerRadius: interpolate(from: 14, to: 24, value: pictureInPictureTransitionFraction),
                    isOutgoing: minimizedVideoNode === self.outgoingVideoNodeValue,
                    deviceOrientation: mappedDeviceOrientation,
                    isCompactLayout: layout.metrics.widthClass == .compact,
                    transition: minimizedVideoTransition)
                if transition.isAnimated && didAppear {
                    minimizedVideoNode.layer.animateSpring(from: 0.1 as NSNumber, to: 1 as NSNumber, keyPath: "transform.scale", duration: 0.5)
                }
            }

            animationForExpandedVideoSnapshotView = nil
            animateOutgoingVideoOnce = false
            animateIncomingVideoOnce = false
        }
    }
    
    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        self.validLayout = (layout, navigationBarHeight)
        
        var mappedDeviceOrientation = self.deviceOrientation
        var isCompactLayout = true
        if case .regular = layout.metrics.widthClass, case .regular = layout.metrics.heightClass {
            mappedDeviceOrientation = .portrait
            isCompactLayout = false
        }
        
        if !self.hasVideoNodes {
            self.isUIHidden = false
        }
        
        var isUIHidden = self.isUIHidden
        switch self.callState?.state {
        case .terminated, .terminating:
            isUIHidden = false
        default:
            break
        }
        
        var uiDisplayTransition: CGFloat = isUIHidden ? 0 : 1
        let pipTransitionAlpha = 1 - pictureInPictureTransitionFraction
        uiDisplayTransition *= pipTransitionAlpha
        
        let containerFullScreenFrame = CGRect(origin: CGPoint(), size: layout.size)
        let containerPictureInPictureFrame = self.calculatePictureInPictureContainerRect(layout: layout, navigationHeight: navigationBarHeight)
        
        let containerFrame = interpolateFrame(from: containerFullScreenFrame, to: containerPictureInPictureFrame, t: self.pictureInPictureTransitionFraction)
        
        transition.updateFrame(node: self.containerTransformationNode, frame: containerFrame)
        transition.updateSublayerTransformScale(node: self.containerTransformationNode, scale: min(1.0, containerFrame.width / layout.size.width * 1.01))
        transition.updateCornerRadius(layer: self.containerTransformationNode.layer, cornerRadius: self.pictureInPictureTransitionFraction * 10.0)
        
        transition.updateFrame(node: self.containerNode, frame: CGRect(origin: CGPoint(x: (containerFrame.width - layout.size.width) / 2.0, y: floor(containerFrame.height - layout.size.height) / 2.0), size: layout.size))
        
        if let debugNode = self.debugNode {
            transition.updateFrame(node: debugNode, frame: CGRect(origin: CGPoint(), size: layout.size))
        }

        backgroundLayoutUpdated(layout)
        backButtonLayoutUpdated(layout, transition: transition, uiDisplayTransition: uiDisplayTransition)
        keyButtonLayoutUpdated(layout, transition: transition, uiDisplayTransition: uiDisplayTransition)
        avatarLayoutUpdated(layout, transition: transition)
        statusLayoutUpdated(layout, transition: transition, uiDisplayTransition: uiDisplayTransition)
        buttonsLayoutUpdated(layout, transition: transition, uiDisplayTransition: uiDisplayTransition)
        toastLayoutUpdated(layout, transition: transition, uiDisplayTransition: uiDisplayTransition)
        keyPreviewLayoutUpdated(layout, transition: transition)
        ratingLayoutUpdated(layout, transition: transition)
        videoLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: transition, mappedDeviceOrientation: mappedDeviceOrientation, isCompactLayout: isCompactLayout)
        
        let requestedAspect: CGFloat
        if case .compact = layout.metrics.widthClass, case .compact = layout.metrics.heightClass {
            var isIncomingVideoRotated = false
            var rotationCount = 0
            
            switch mappedDeviceOrientation {
            case .portrait:
                break
            case .landscapeLeft:
                rotationCount += 1
            case .landscapeRight:
                rotationCount += 1
            case .portraitUpsideDown:
                 break
            default:
                break
            }
            
            if rotationCount % 2 != 0 {
                isIncomingVideoRotated = true
            }
            
            if !isIncomingVideoRotated {
                requestedAspect = layout.size.width / layout.size.height
            } else {
                requestedAspect = 0.0
            }
        } else {
            requestedAspect = 0.0
        }
        if self.currentRequestedAspect != requestedAspect {
            self.currentRequestedAspect = requestedAspect
            if !self.sharedContext.immediateExperimentalUISettings.disableVideoAspectScaling {
                self.call.setRequestedVideoAspect(Float(requestedAspect))
            }
        }
    }
    
    @objc func keyPressed() {
        if self.keyPreviewNode == nil, let keyText = self.keyTextData?.1, let peer = self.peer {
            UserDefaults.standard.set(true, forKey: "isKeyPreviewShown")
            let keyPreviewNode = CallControllerKeyPreviewNode(
                account: self.account,
                animatedEmojiStickers: self.call.context.animatedEmojiStickers,
                keyText: keyText,
                titleText: "This call is end-to end encrypted",
                infoText: self.presentationData.strings.Call_EmojiDescription(EnginePeer(peer).compactDisplayTitle).string.replacingOccurrences(of: "%%", with: "%"),
                style: expandedVideoNode == nil ? .light : .dark
            ) { [weak self] in
                if let _ = self?.keyPreviewNode {
                    self?.backPressed()
                }
            }

            self.containerNode.insertSubnode(keyPreviewNode, belowSubnode: self.statusNode)
            self.keyPreviewNode = keyPreviewNode

            if let keyPreviewNode = self.keyPreviewNode, let (layout, navigationBarHeight) = self.validLayout {
                self.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .immediate)
                keyPreviewNode.animateIn(
                    from: self.keyButtonNode.frame,
                    fromNode: self.keyButtonNode)
                self.hideAvatarAnimation()
            }

            self.keyButtonNode.isHidden = true
        }
    }
    
    @objc func backPressed() {
        if let keyPreviewNode = self.keyPreviewNode {
            self.keyPreviewNode = nil
            keyPreviewNode.alpha = 0.0
            keyPreviewNode.animateOut(to: self.keyButtonNode.frame, toNode: self.keyButtonNode, completion: { [weak self, weak keyPreviewNode] in
                self?.keyButtonNode.isHidden = false
                keyPreviewNode?.removeFromSupernode()
            })
            self.showAvatarAnimation()
        } else if self.hasVideoNodes {
            if let (layout, navigationHeight) = self.validLayout {
                self.pictureInPictureTransitionFraction = 1.0
                self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: .animated(duration: 0.4, curve: .spring))
            }
        } else {
            self.back?()
        }
    }
    
    private var hasVideoNodes: Bool {
        return self.expandedVideoNode != nil || self.minimizedVideoNode != nil
    }
    
    private var debugTapCounter: (Double, Int) = (0.0, 0)
    
    private func areUserActionsDisabledNow() -> Bool {
        return CACurrentMediaTime() < self.disableActionsUntilTimestamp
    }
    
    @objc func tapGesture(_ recognizer: UITapGestureRecognizer) {
        startInterfaceAnimation()
        startInterfaceAnimationTimer()
        if case .ended = recognizer.state {
            if !self.pictureInPictureTransitionFraction.isZero {
                self.view.window?.endEditing(true)
                
                if let (layout, navigationHeight) = self.validLayout {
                    self.pictureInPictureTransitionFraction = 0.0
                    
                    self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: .animated(duration: 0.4, curve: .spring))
                }
            } else if let _ = self.keyPreviewNode {
                self.backPressed()
            } else {
                if self.hasVideoNodes {
                    let point = recognizer.location(in: recognizer.view)
                    if let expandedVideoNode = self.expandedVideoNode, let minimizedVideoNode = self.minimizedVideoNode, minimizedVideoNode.frame.contains(point) {
                        if !self.areUserActionsDisabledNow() {
                            let copyView = minimizedVideoNode.view.snapshotView(afterScreenUpdates: false)
                            copyView?.frame = minimizedVideoNode.frame
                            self.expandedVideoNode = minimizedVideoNode
                            self.minimizedVideoNode = expandedVideoNode
                            if let supernode = expandedVideoNode.supernode {
                                supernode.insertSubnode(expandedVideoNode, aboveSubnode: minimizedVideoNode)
                            }
                            self.disableActionsUntilTimestamp = CACurrentMediaTime() + 0.3
                            if let (layout, navigationBarHeight) = self.validLayout {
                                self.disableAnimationForExpandedVideoOnce = true
                                self.animationForExpandedVideoSnapshotView = copyView
                                self.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .animated(duration: 0.3, curve: .easeInOut))
                            }
                        }
                    } else {
                        var updated = false
                        if let callState = self.callState {
                            switch callState.state {
                            case .active, .connecting, .reconnecting:
                                self.isUIHidden = !self.isUIHidden
                                updated = true
                            default:
                                break
                            }
                        }
                        if updated, let (layout, navigationBarHeight) = self.validLayout {
                            self.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .animated(duration: 0.3, curve: .easeInOut))
                        }
                    }
                } else {
                    let point = recognizer.location(in: recognizer.view)
                    if self.statusNode.frame.contains(point) {
                        if self.easyDebugAccess {
                            self.presentDebugNode()
                        } else {
                            let timestamp = CACurrentMediaTime()
                            if self.debugTapCounter.0 < timestamp - 0.75 {
                                self.debugTapCounter.0 = timestamp
                                self.debugTapCounter.1 = 0
                            }
                            
                            if self.debugTapCounter.0 >= timestamp - 0.75 {
                                self.debugTapCounter.0 = timestamp
                                self.debugTapCounter.1 += 1
                            }
                            
                            if self.debugTapCounter.1 >= 10 {
                                self.debugTapCounter.1 = 0
                                
                                self.presentDebugNode()
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func presentDebugNode() {
        guard self.debugNode == nil else {
            return
        }
        
        self.forceReportRating = true
        
        let debugNode = CallDebugNode(signal: self.debugInfo)
        debugNode.dismiss = { [weak self] in
            if let strongSelf = self {
                strongSelf.debugNode?.removeFromSupernode()
                strongSelf.debugNode = nil
            }
        }
        self.addSubnode(debugNode)
        self.debugNode = debugNode
        
        if let (layout, navigationBarHeight) = self.validLayout {
            self.containerLayoutUpdated(layout, navigationBarHeight: navigationBarHeight, transition: .immediate)
        }
    }
    
    private var minimizedVideoInitialPosition: CGPoint?
    private var minimizedVideoDraggingPosition: CGPoint?
    
    private func nodeLocationForPosition(layout: ContainerViewLayout, position: CGPoint, velocity: CGPoint) -> VideoNodeCorner {
        let layoutInsets = UIEdgeInsets()
        var result = CGPoint()
        if position.x < layout.size.width / 2.0 {
            result.x = 0.0
        } else {
            result.x = 1.0
        }
        if position.y < layoutInsets.top + (layout.size.height - layoutInsets.bottom - layoutInsets.top) / 2.0 {
            result.y = 0.0
        } else {
            result.y = 1.0
        }
        
        let currentPosition = result
        
        let angleEpsilon: CGFloat = 30.0
        var shouldHide = false
        
        if (velocity.x * velocity.x + velocity.y * velocity.y) >= 500.0 * 500.0 {
            let x = velocity.x
            let y = velocity.y
            
            var angle = atan2(y, x) * 180.0 / CGFloat.pi * -1.0
            if angle < 0.0 {
                angle += 360.0
            }
            
            if currentPosition.x.isZero && currentPosition.y.isZero {
                if ((angle > 0 && angle < 90 - angleEpsilon) || angle > 360 - angleEpsilon) {
                    result.x = 1.0
                    result.y = 0.0
                } else if (angle > 180 + angleEpsilon && angle < 270 + angleEpsilon) {
                    result.x = 0.0
                    result.y = 1.0
                } else if (angle > 270 + angleEpsilon && angle < 360 - angleEpsilon) {
                    result.x = 1.0
                    result.y = 1.0
                } else {
                    shouldHide = true
                }
            } else if !currentPosition.x.isZero && currentPosition.y.isZero {
                if (angle > 90 + angleEpsilon && angle < 180 + angleEpsilon) {
                    result.x = 0.0
                    result.y = 0.0
                }
                else if (angle > 270 - angleEpsilon && angle < 360 - angleEpsilon) {
                    result.x = 1.0
                    result.y = 1.0
                }
                else if (angle > 180 + angleEpsilon && angle < 270 - angleEpsilon) {
                    result.x = 0.0
                    result.y = 1.0
                }
                else {
                    shouldHide = true
                }
            } else if currentPosition.x.isZero && !currentPosition.y.isZero {
                if (angle > 90 - angleEpsilon && angle < 180 - angleEpsilon) {
                    result.x = 0.0
                    result.y = 0.0
                }
                else if (angle < angleEpsilon || angle > 270 + angleEpsilon) {
                    result.x = 1.0
                    result.y = 1.0
                }
                else if (angle > angleEpsilon && angle < 90 - angleEpsilon) {
                    result.x = 1.0
                    result.y = 0.0
                }
                else if (!shouldHide) {
                    shouldHide = true
                }
            } else if !currentPosition.x.isZero && !currentPosition.y.isZero {
                if (angle > angleEpsilon && angle < 90 + angleEpsilon) {
                    result.x = 1.0
                    result.y = 0.0
                }
                else if (angle > 180 - angleEpsilon && angle < 270 - angleEpsilon) {
                    result.x = 0.0
                    result.y = 1.0
                }
                else if (angle > 90 + angleEpsilon && angle < 180 - angleEpsilon) {
                    result.x = 0.0
                    result.y = 0.0
                }
                else if (!shouldHide) {
                    shouldHide = true
                }
            }
        }
        
        if result.x.isZero {
            if result.y.isZero {
                return .topLeft
            } else {
                return .bottomLeft
            }
        } else {
            if result.y.isZero {
                return .topRight
            } else {
                return .bottomRight
            }
        }
    }
    
    @objc private func panGesture(_ recognizer: CallPanGestureRecognizer) {
        startInterfaceAnimation()
        startInterfaceAnimationTimer()
        switch recognizer.state {
            case .began:
                guard let location = recognizer.firstLocation else {
                    return
                }
                if self.pictureInPictureTransitionFraction.isZero, let expandedVideoNode = self.expandedVideoNode, let minimizedVideoNode = self.minimizedVideoNode, minimizedVideoNode.frame.contains(location), expandedVideoNode.frame != minimizedVideoNode.frame {
                    self.minimizedVideoInitialPosition = minimizedVideoNode.position
                } else if self.hasVideoNodes {
                    self.minimizedVideoInitialPosition = nil
                    if !self.pictureInPictureTransitionFraction.isZero {
                        self.pictureInPictureGestureState = .dragging(initialPosition: self.containerTransformationNode.position, draggingPosition: self.containerTransformationNode.position)
                    } else {
                        self.pictureInPictureGestureState = .collapsing(didSelectCorner: false)
                    }
                } else {
                    self.pictureInPictureGestureState = .none
                }
                self.dismissAllTooltips?()
            case .changed:
                if let minimizedVideoNode = self.minimizedVideoNode, let minimizedVideoInitialPosition = self.minimizedVideoInitialPosition {
                    let translation = recognizer.translation(in: self.view)
                    let minimizedVideoDraggingPosition = CGPoint(x: minimizedVideoInitialPosition.x + translation.x, y: minimizedVideoInitialPosition.y + translation.y)
                    self.minimizedVideoDraggingPosition = minimizedVideoDraggingPosition
                    minimizedVideoNode.position = minimizedVideoDraggingPosition
                } else {
                    switch self.pictureInPictureGestureState {
                    case .none:
                        let offset = recognizer.translation(in: self.view).y
                        var bounds = self.bounds
                        bounds.origin.y = -offset
                        self.bounds = bounds
                    case let .collapsing(didSelectCorner):
                        if let (layout, navigationHeight) = self.validLayout {
                            let offset = recognizer.translation(in: self.view)
                            if !didSelectCorner {
                                self.pictureInPictureGestureState = .collapsing(didSelectCorner: true)
                                if offset.x < 0.0 {
                                    self.pictureInPictureCorner = .topLeft
                                } else {
                                    self.pictureInPictureCorner = .topRight
                                }
                            }
                            let maxOffset: CGFloat = min(300.0, layout.size.height / 2.0)
                            
                            let offsetTransition = max(0.0, min(1.0, abs(offset.y) / maxOffset))
                            self.pictureInPictureTransitionFraction = offsetTransition
                            switch self.pictureInPictureCorner {
                            case .topRight, .bottomRight:
                                self.pictureInPictureCorner = offset.y < 0.0 ? .topRight : .bottomRight
                            case .topLeft, .bottomLeft:
                                self.pictureInPictureCorner = offset.y < 0.0 ? .topLeft : .bottomLeft
                            }
                            
                            self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: .immediate)
                        }
                    case .dragging(let initialPosition, var draggingPosition):
                        let translation = recognizer.translation(in: self.view)
                        draggingPosition.x = initialPosition.x + translation.x
                        draggingPosition.y = initialPosition.y + translation.y
                        self.pictureInPictureGestureState = .dragging(initialPosition: initialPosition, draggingPosition: draggingPosition)
                        self.containerTransformationNode.position = draggingPosition
                    }
                }
            case .cancelled, .ended:
                if let minimizedVideoNode = self.minimizedVideoNode, let _ = self.minimizedVideoInitialPosition, let minimizedVideoDraggingPosition = self.minimizedVideoDraggingPosition {
                    self.minimizedVideoInitialPosition = nil
                    self.minimizedVideoDraggingPosition = nil
                    
                    if let (layout, navigationHeight) = self.validLayout {
                        self.outgoingVideoNodeCorner = self.nodeLocationForPosition(layout: layout, position: minimizedVideoDraggingPosition, velocity: recognizer.velocity(in: self.view))
                        
                        let videoFrame = self.calculatePreviewVideoRect(layout: layout, navigationHeight: navigationHeight)
                        minimizedVideoNode.frame = videoFrame
                        minimizedVideoNode.layer.animateSpring(from: NSValue(cgPoint: CGPoint(x: minimizedVideoDraggingPosition.x - videoFrame.midX, y: minimizedVideoDraggingPosition.y - videoFrame.midY)), to: NSValue(cgPoint: CGPoint()), keyPath: "position", duration: 0.5, delay: 0.0, initialVelocity: 0.0, damping: 110.0, removeOnCompletion: true, additive: true, completion: nil)
                    }
                } else {
                    switch self.pictureInPictureGestureState {
                    case .none:
                        let velocity = recognizer.velocity(in: self.view).y
                        if abs(velocity) < 100.0 {
                            var bounds = self.bounds
                            let previous = bounds
                            bounds.origin = CGPoint()
                            self.bounds = bounds
                            self.layer.animateBounds(from: previous, to: bounds, duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring)
                        } else {
                            var bounds = self.bounds
                            let previous = bounds
                            bounds.origin = CGPoint(x: 0.0, y: velocity > 0.0 ? -bounds.height: bounds.height)
                            self.bounds = bounds
                            self.layer.animateBounds(from: previous, to: bounds, duration: 0.15, timingFunction: CAMediaTimingFunctionName.easeOut.rawValue, completion: { [weak self] _ in
                                self?.dismissedInteractively?()
                            })
                        }
                    case .collapsing:
                        self.pictureInPictureGestureState = .none
                        let velocity = recognizer.velocity(in: self.view).y
                        if abs(velocity) < 100.0 && self.pictureInPictureTransitionFraction < 0.5 {
                            if let (layout, navigationHeight) = self.validLayout {
                                self.pictureInPictureTransitionFraction = 0.0
                                
                                self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: .animated(duration: 0.4, curve: .spring))
                            }
                        } else {
                            if let (layout, navigationHeight) = self.validLayout {
                                self.pictureInPictureTransitionFraction = 1.0
                                
                                self.containerLayoutUpdated(layout, navigationBarHeight: navigationHeight, transition: .animated(duration: 0.4, curve: .spring))
                            }
                        }
                    case let .dragging(initialPosition, _):
                        self.pictureInPictureGestureState = .none
                        if let (layout, navigationHeight) = self.validLayout {
                            let translation = recognizer.translation(in: self.view)
                            let draggingPosition = CGPoint(x: initialPosition.x + translation.x, y: initialPosition.y + translation.y)
                            self.pictureInPictureCorner = self.nodeLocationForPosition(layout: layout, position: draggingPosition, velocity: recognizer.velocity(in: self.view))
                            
                            let containerFrame = self.calculatePictureInPictureContainerRect(layout: layout, navigationHeight: navigationHeight)
                            self.containerTransformationNode.frame = containerFrame
                            containerTransformationNode.layer.animateSpring(from: NSValue(cgPoint: CGPoint(x: draggingPosition.x - containerFrame.midX, y: draggingPosition.y - containerFrame.midY)), to: NSValue(cgPoint: CGPoint()), keyPath: "position", duration: 0.5, delay: 0.0, initialVelocity: 0.0, damping: 110.0, removeOnCompletion: true, additive: true, completion: nil)
                        }
                    }
                }
            default:
                break
        }
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if self.debugNode != nil {
            return super.hitTest(point, with: event)
        }
        if self.containerTransformationNode.frame.contains(point) {
            return self.containerTransformationNode.view.hitTest(self.view.convert(point, to: self.containerTransformationNode.view), with: event)
        }
        return nil
    }
}

final class CallPanGestureRecognizer: UIPanGestureRecognizer {
    private(set) var firstLocation: CGPoint?
    
    public var shouldBegin: ((CGPoint) -> Bool)?
    
    override public init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        
        self.maximumNumberOfTouches = 1
    }
    
    override public func reset() {
        super.reset()
        
        self.firstLocation = nil
    }
    
    override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        
        let touch = touches.first!
        let point = touch.location(in: self.view)
        if let shouldBegin = self.shouldBegin, !shouldBegin(point) {
            self.state = .failed
            return
        }
        
        self.firstLocation = point
    }
    
    override public func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
    }
}

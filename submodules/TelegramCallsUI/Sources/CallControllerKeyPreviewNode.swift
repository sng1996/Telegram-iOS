import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import LegacyComponents
import AnimatedStickerComponent
import TelegramCore

private let emojiFont = Font.regular(28.0)
private let textFont = Font.regular(15.0)

final class CallControllerKeyPreviewNode: ASDisplayNode {

    enum Style {
        case light
        case dark

        var backgroundColor: UIColor {
            switch self {
            case .light:
                return UIColor.white.withAlphaComponent(0.25)
            case .dark:
                return UIColor.black.withAlphaComponent(0.5)
            }
        }
    }

    private let contentNode: ASDisplayNode
    private let contentEffectView: UIVisualEffectView
    private let keyButtonNode: CallControllerKeyButton
    private let titleTextNode: ASTextNode
    private let infoTextNode: ASTextNode
    private let buttonNode: ASButtonNode
    private let buttonEffectView: UIVisualEffectView
    private let buttonContentNode: ASDisplayNode

    private let dismiss: () -> Void
    
    init(
        account: Account,
        animatedEmojiStickers: [String: [StickerPackItem]?],
        keyText: String,
        titleText: String,
        infoText: String,
        style: UIBlurEffect.Style,
        dismiss: @escaping () -> Void
    ) {
        self.contentNode = ASDisplayNode()
        self.contentEffectView = UIVisualEffectView(effect: UIBlurEffect(style: style))
        self.keyButtonNode = CallControllerKeyButton(
            account: account,
            animatedEmojiStickers: animatedEmojiStickers,
            scale: 2)
        self.titleTextNode = ASTextNode()
        self.infoTextNode = ASTextNode()
        self.buttonNode = ASButtonNode()
        self.buttonEffectView = UIVisualEffectView(effect: UIBlurEffect(style: style))
        self.buttonContentNode = ASDisplayNode()
        self.dismiss = dismiss

        super.init()

        contentEffectView.layer.cornerRadius = 20
        contentEffectView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        contentEffectView.layer.masksToBounds = true

        keyButtonNode.key = keyText

        titleTextNode.attributedText = NSAttributedString(string: titleText, font: .systemFont(ofSize: 16, weight: .semibold), textColor: UIColor.white, paragraphAlignment: .center)

        infoTextNode.attributedText = NSAttributedString(string: infoText, font: Font.regular(16.0), textColor: UIColor.white, paragraphAlignment: .center)

        buttonNode.setTitle("OK", with: Font.regular(20.0), with: .white, for: .normal)
        buttonEffectView.layer.cornerRadius = 20
        buttonEffectView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        buttonEffectView.layer.masksToBounds = true
        buttonEffectView.isUserInteractionEnabled = false

        addSubnode(contentNode)
        contentNode.view.addSubview(contentEffectView)
        addSubnode(keyButtonNode)
        addSubnode(titleTextNode)
        addSubnode(infoTextNode)
        addSubnode(buttonContentNode)
        buttonContentNode.view.addSubview(buttonEffectView)
        buttonContentNode.addSubnode(buttonNode)
    }
    
    override func didLoad() {
        super.didLoad()
        self.buttonNode.addTarget(self, action: #selector(tapGesture), forControlEvents: .touchUpInside)
    }

    func updateStyle(_ style: UIBlurEffect.Style) {
        contentEffectView.effect = UIBlurEffect(style: style)
        buttonEffectView.effect = UIBlurEffect(style: style)
    }
    
    func updateLayout(transition: ContainedViewLayoutTransition) -> CGSize {
        let width: CGFloat = 304
        let keyButtonNodeSize = self.keyButtonNode.measure(.zero)
        transition.updateFrame(
            node: self.keyButtonNode,
            frame: CGRect(
                origin: CGPoint(x: (width - keyButtonNodeSize.width) / 2, y: 20),
                size: keyButtonNodeSize))

        let titleTextSize = self.titleTextNode.measure(CGSize(width: width - 32.0, height: CGFloat.greatestFiniteMagnitude))
        transition.updateFrame(
            node: self.titleTextNode,
            frame: CGRect(
                origin: CGPoint(x: (width - titleTextSize.width) / 2, y: self.keyButtonNode.frame.maxY + 10),
                size: titleTextSize))

        let infoTextSize = self.infoTextNode.measure(CGSize(width: width - 32.0, height: CGFloat.greatestFiniteMagnitude))
        transition.updateFrame(
            node: self.infoTextNode,
            frame: CGRect(
                origin: CGPoint(x: (width - infoTextSize.width) / 2, y: self.titleTextNode.frame.maxY + 10),
                size: infoTextSize))

        transition.updateFrame(
            node: self.contentNode,
            frame: CGRect(
                origin: .zero,
                size: CGSize(width: width, height: self.infoTextNode.frame.maxY + 20)))

        transition.updateFrame(
            view: self.contentEffectView,
            frame: CGRect(
                origin: .zero,
                size: CGSize(width: width, height: self.infoTextNode.frame.maxY + 20)))

        transition.updateFrame(
            node: self.buttonContentNode,
            frame: CGRect(
                origin: CGPoint(x: .zero, y: contentNode.frame.maxY + 1),
                size: CGSize(width: width, height: 56)))

        transition.updateFrame(
            view: self.buttonEffectView,
            frame: CGRect(
                origin: CGPoint(x: .zero, y: 0),
                size: CGSize(width: width, height: 56)))

        transition.updateFrame(
            node: self.buttonNode,
            frame: CGRect(
                origin: CGPoint(x: .zero, y: 0),
                size: CGSize(width: width, height: 56)))

        return CGSize(width: width, height: self.buttonNode.frame.maxY)
    }

    func animateIn(from rect: CGRect, fromNode: ASDisplayNode) {

        guard let supernode = fromNode.supernode else {
            return
        }

        self.keyButtonNode.layer.animatePosition(
            from: supernode.view.convert(CGPoint(x: rect.midX, y: rect.midY), to: self.view),
            to: self.keyButtonNode.layer.position,
            duration: 0.3,
            timingFunction: kCAMediaTimingFunctionSpring)

        self.keyButtonNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.1)

        self.keyButtonNode.layer.animateScale(
            from: rect.size.width / self.keyButtonNode.frame.size.width,
            to: 1.0,
            duration: 0.3,
            timingFunction: kCAMediaTimingFunctionSpring)

        if let transitionView = fromNode.view.snapshotView(afterScreenUpdates: false) {
            supernode.view.addSubview(transitionView)
            transitionView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.1, removeOnCompletion: false)
            transitionView.layer.animatePosition(
                from: CGPoint(x: rect.midX, y: rect.midY),
                to: self.view.convert(self.keyButtonNode.layer.position, to: supernode.view),
                duration: 0.3,
                timingFunction: kCAMediaTimingFunctionSpring,
                removeOnCompletion: false
            ) { [weak transitionView] _ in
                transitionView?.removeFromSuperview()
            }
            transitionView.layer.animateScale(
                from: 1.0,
                to: self.keyButtonNode.frame.size.width / rect.size.width,
                duration: 0.3,
                timingFunction: kCAMediaTimingFunctionSpring,
                removeOnCompletion: false)
        }

        self.layer.animatePosition(
            from: CGPoint(x: self.frame.maxX, y: self.frame.minY),
            to: self.position,
            duration: 0.3,
            timingFunction: kCAMediaTimingFunctionSpring)

        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.15)

        self.layer.animateScale(
            from: 0,
            to: 1.0,
            duration: 0.3,
            timingFunction: kCAMediaTimingFunctionSpring)
    }

    func animateOut(to rect: CGRect, toNode: ASDisplayNode, completion: @escaping () -> Void) {
        guard let supernode = toNode.supernode else {
            return
        }

        self.keyButtonNode.layer.animatePosition(
            from: self.keyButtonNode.layer.position,
            to: supernode.view.convert(CGPoint(x: rect.midX, y: rect.midY), to: self.view),
            duration: 0.3,
            timingFunction: kCAMediaTimingFunctionSpring)

        self.keyButtonNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.1)

        self.keyButtonNode.layer.animateScale(
            from: 1.0,
            to: rect.size.width / self.keyButtonNode.frame.size.width,
            duration: 0.3,
            timingFunction: kCAMediaTimingFunctionSpring)

        toNode.view.isHidden = false
        toNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.1, removeOnCompletion: false)
        toNode.layer.animatePosition(
            from: self.view.convert(self.keyButtonNode.layer.position, to: supernode.view),
            to: CGPoint(x: rect.midX, y: rect.midY),
            duration: 0.3,
            timingFunction: kCAMediaTimingFunctionSpring,
            removeOnCompletion: false)
        toNode.layer.animateScale(
            from: self.keyButtonNode.frame.size.width / rect.size.width,
            to: 1.0,
            duration: 0.3,
            timingFunction: kCAMediaTimingFunctionSpring,
            removeOnCompletion: false)

        self.layer.animatePosition(
            from: self.position,
            to: CGPoint(x: self.frame.maxX, y: self.frame.minY),
            duration: 0.3,
            timingFunction: kCAMediaTimingFunctionSpring)

        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15)

        self.layer.animateScale(
            from: 1,
            to: 0,
            duration: 0.3,
            timingFunction: kCAMediaTimingFunctionSpring
        ) { _ in
            completion()
        }
    }

    @objc func tapGesture() {
        self.dismiss()
    }
}


import Foundation
import UIKit
import Display
import AsyncDisplayKit
import CallsEmoji
import AnimatedStickerComponent
import TelegramCore
import ComponentFlow

private class EmojiSlotNode: ASDisplayNode {

    private(set) var isReadyToAnimate = false

    var emoji: (value: String, isAnimated: Bool) = ("", false) {
        didSet {
            guard emoji != oldValue else {
                return
            }

            self.isReadyToAnimate = false
            self.animatedView?.removeFromSuperview()
            self.animatedComponent = nil
            self.animatedView = nil
            self.staticNode.isHidden = false

            if emoji.isAnimated,
               let stickerPackItem = self.animatedEmojiStickers[emoji.value]??.first {
                startAnimationLoading(file: stickerPackItem.file)

                let animatedComponent = AnimatedStickerComponent(
                    account: self.account,
                    animation: .init(source: .file(media: stickerPackItem.file), loop: true),
                    tintColor: nil,
                    isAnimating: true,
                    size: size)
                let view = animatedComponent.makeView()
                self.animatedComponent = animatedComponent
                self.animatedView = view
                self.view.addSubview(view)
                view.isHidden = true
            }

            self.staticNode.attributedText = NSAttributedString(
                string: emoji.value,
                font: font,
                textColor: .black)

            updateLayout()
        }
    }
    
    var readyToAnimateAction: (() -> Void)?

    private let account: Account
    private let animatedEmojiStickers: [String: [StickerPackItem]?]
    private let size: CGSize
    private let font: UIFont

    private let staticNode: ImmediateTextNode
    private var animatedComponent: AnimatedStickerComponent?
    private var animatedView: AnimatedStickerComponent.View?
    
    init(
        account: Account,
        animatedEmojiStickers: [String: [StickerPackItem]?],
        size: CGSize,
        font: UIFont
    ) {
        self.account = account
        self.animatedEmojiStickers = animatedEmojiStickers
        self.size = size
        self.font = font
        self.staticNode = ImmediateTextNode()
        super.init()

        self.addSubnode(self.staticNode)
    }
    
    override func layout() {
        super.layout()
        self.staticNode.frame = self.bounds
    }

    func showAnimation() {
        self.staticNode.isHidden = true
        self.animatedView?.isHidden = false
    }

    private func updateLayout() {
        if let animatedView, let animatedComponent {
            let _ = animatedComponent.update(
                view: animatedView,
                availableSize: self.size,
                state: EmptyComponentState(),
                environment: .init(),
                transition: Transition(.immediate))

            animatedView.animationNode?.started = { [weak self] in
                self?.isReadyToAnimate = true
                self?.readyToAnimateAction?()
            }

            animatedView.frame = self.bounds
        }
        let _ = self.staticNode.updateLayout(CGSize(width: 100.0, height: 100.0))
        self.staticNode.frame = self.bounds
    }

    private func startAnimationLoading(file: TelegramMediaFile) {
        let resourceReference = MediaResourceReference.media(
            media: .standalone(media: file),
            resource: file.resource)

        _ = fetchedMediaResource(
            mediaBox: account.postbox.mediaBox,
            userLocation: .other,
            userContentType: .sticker,
            reference: resourceReference
        ).start(next: { _ in })
    }
}

final class CallControllerKeyButton: HighlightableButtonNode {

    private let nodes: [EmojiSlotNode]
    private let animatedEmojiStickers: [String: [StickerPackItem]?]
    private let nodeSize: CGSize
    private let spacing: CGFloat
    private let forceStatic: Bool

    var key: String = "" {
        didSet {

            guard key != oldValue else {
                return
            }

            var isAnimated = true
            for emoji in key {
                if animatedEmojiStickers[String(emoji)]??.first == nil {
                    isAnimated = false
                    break
                }
            }

            var index = 0
            for emoji in key {
                guard index < 4 else {
                    return
                }
                self.nodes[index].emoji = (String(emoji), isAnimated)
                index += 1
            }
        }
    }

    init(
        account: Account,
        animatedEmojiStickers: [String: [StickerPackItem]?],
        scale: CGFloat = 1,
        forceStatic: Bool = false
    ) {
        let nodeSize = CGSize(width: 24 * scale, height: 24 * scale)
        let font = scale == 1 ? Font.regular(22) : Font.regular(44)

        self.animatedEmojiStickers = animatedEmojiStickers
        self.nodes = (0 ..< 4).map { _ in
            EmojiSlotNode(
                account: account,
                animatedEmojiStickers: animatedEmojiStickers,
                size: nodeSize,
                font: font)
        }
        self.nodeSize = nodeSize
        self.spacing = 3 * scale
        self.forceStatic = forceStatic

        super.init(pointerStyle: nil)

        self.nodes.forEach({ self.addSubnode($0) })

        if !forceStatic {
            self.nodes.forEach {
                $0.readyToAnimateAction = { [weak self] in
                    if self?.nodes.contains(where: { !$0.isReadyToAnimate }) == false {
                        self?.nodes.forEach { $0.showAnimation() }
                    }
                }
            }
        }
    }

    override func measure(_ constrainedSize: CGSize) -> CGSize {
        return CGSize(width: self.nodeSize.width * 4 + self.spacing * 3, height: self.nodeSize.height)
    }

    override func layout() {
        super.layout()

        var index = 0
        for node in self.nodes {
            node.frame = CGRect(
                origin: CGPoint(x: CGFloat(index) * (self.nodeSize.width + self.spacing), y: 0.0),
                size: self.nodeSize)
            index += 1
        }
    }
}

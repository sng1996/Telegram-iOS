import Foundation
import UIKit
import Display
import AsyncDisplayKit
import AppBundle
import Lottie

final class CallControllerRatingNode: ASDisplayNode {
    private let applyAction: (Int) -> Void

    private let titleTextNode: ASTextNode
    private let infoTextNode: ASTextNode
    private var starContainerNode: ASDisplayNode
    private let starNodes: [ASButtonNode]

    init(applyAction: @escaping (Int) -> Void) {
        self.applyAction = applyAction
        self.titleTextNode = ASTextNode()
        self.infoTextNode = ASTextNode()
        self.starContainerNode = ASDisplayNode()

        var starNodes: [ASButtonNode] = []
        for _ in 0 ..< 5 {
            starNodes.append(ASButtonNode())
        }
        self.starNodes = starNodes

        super.init()

        self.addSubnode(titleTextNode)
        self.addSubnode(infoTextNode)
        self.addSubnode(starContainerNode)

        for node in self.starNodes {
            node.addTarget(self, action: #selector(self.didTapStar(_:)), forControlEvents: .touchUpInside)
            self.starContainerNode.addSubnode(node)
        }

        self.cornerRadius = 20
        self.backgroundColor = UIColor.white.withAlphaComponent(0.25)

        self.titleTextNode.attributedText = NSAttributedString(
            string: "Rate This Call",
            font: .systemFont(ofSize: 16, weight: .semibold),
            textColor: .white,
            paragraphAlignment: .center)

        self.infoTextNode.attributedText = NSAttributedString(
            string: "Please rate the quality of this call.",
            font: .systemFont(ofSize: 16, weight: .regular),
            textColor: .white,
            paragraphAlignment: .center)

        for node in self.starNodes {
            node.setImage(
                generateTintedImage(
                    image: UIImage(bundleImageName: "Call/Star"),
                    color: .white),
                for: [])
            node.setImage(
                generateTintedImage(
                    image: UIImage(bundleImageName: "Call/StarHighlighted"),
                    color: .white),
                for: [.selected])
            node.setImage(
                generateTintedImage(
                    image: UIImage(bundleImageName: "Call/StarHighlighted"),
                    color: .white),
                for: [.selected, .highlighted])
        }
    }

    func animateIn() {
        layer.animateAlpha(from: 0, to: 1, duration: 0.3)
        layer.animateScale(from: 0, to: 1, duration: 0.3)
    }

    func updateLayout(transition: ContainedViewLayoutTransition) -> CGSize {
        let width: CGFloat = 304
        let horizontalInset: CGFloat = 16

        let titleTextNodeSize = titleTextNode.measure(CGSize(
            width: width - 2 * horizontalInset,
            height: CGFloat.greatestFiniteMagnitude))

        transition.updateFrame(
            node: titleTextNode,
            frame: CGRect(
                origin: CGPoint(x: (width - titleTextNodeSize.width) / 2, y: 20),
                size: titleTextNodeSize))

        let infoTextNodeSize = infoTextNode.measure(CGSize(
            width: width - 2 * horizontalInset,
            height: CGFloat.greatestFiniteMagnitude))

        transition.updateFrame(
            node: infoTextNode,
            frame: CGRect(
                origin: CGPoint(
                    x: (width - infoTextNodeSize.width) / 2,
                    y: titleTextNode.frame.maxY + 10),
                size: infoTextNodeSize))

        let starSize = CGSize(width: 42, height: 42)
        let starSpacing: CGFloat = 4
        let starContainerNodeSize = CGSize(
            width: 5 * starSize.width + starSpacing * 4,
            height: starSize.height)

        transition.updateFrame(
            node: starContainerNode,
            frame: CGRect(
                origin: CGPoint(
                    x: (width - starContainerNodeSize.width) / 2,
                    y: infoTextNode.frame.maxY + 10),
                size: starContainerNodeSize))

        for i in 0 ..< starNodes.count {
            let node = starNodes[i]
            transition.updateFrame(
                node: node,
                frame: CGRect(
                    origin: CGPoint(x: (starSize.width + starSpacing) * CGFloat(i), y: 0),
                    size: starSize))
        }

        return CGSize(width: width, height: starContainerNode.frame.maxY + 20)
    }

    @objc private func didTapStar(_ sender: ASButtonNode) {
        if let index = starNodes.firstIndex(of: sender) {
            for i in 0 ..< starNodes.count {
                let node = starNodes[i]
                node.isSelected = i <= index
            }

            if index > 2 {
                showAnimation(rect: sender.frame) { [weak self] in
                    self?.applyAction(index + 1)
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.applyAction(index + 1)
                }
            }
        }
    }

    private func showAnimation(rect: CGRect, completion: @escaping () -> Void) {
        if let url = getAppBundle().url(forResource: "AnimatedSticker", withExtension: "tgs"),
           let effectData = try? Data(contentsOf: url),
           let composition = try? Animation.from(data: effectData)
        {
            let animationView = AnimationView(animation: composition, configuration: LottieConfiguration(renderingEngine: .mainThread, decodingStrategy: .codable))
            animationView.animationSpeed = 1.0
            self.starContainerNode.view.addSubview(animationView)
            animationView.frame = CGRect(
                x: rect.center.x - 50,
                y: rect.center.y - 50,
                width: 100,
                height: 100)
            animationView.play { _ in
                animationView.removeFromSuperview()
                completion()
            }
        }
    }
}

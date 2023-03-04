import Foundation
import UIKit
import Display
import AsyncDisplayKit

final class CallControllerCloseRatingButtonNode: ASButtonNode {
    private let action: () -> Void

    private let topNode: ASDisplayNode
    private let titleTextNode: ASTextNode

    init(action: @escaping () -> Void) {
        self.action = action
        self.topNode = ASDisplayNode()
        self.titleTextNode = ASTextNode()

        super.init()

        self.addSubnode(topNode)
        self.topNode.addSubnode(titleTextNode)

        self.addTarget(self, action: #selector(didTap), forControlEvents: .touchUpInside)
        self.cornerRadius = 14
        self.clipsToBounds = true
        self.backgroundColor = UIColor.white.withAlphaComponent(0.25)
        self.setTitle(
            "Close",
            with: .systemFont(ofSize: 17, weight: .semibold),
            with: .white,
            for: .normal)

        self.topNode.cornerRadius = 10
        self.topNode.clipsToBounds = true
        self.topNode.backgroundColor = .white

        self.titleTextNode.verticalAlignment = .middle
        self.titleTextNode.attributedText = NSAttributedString(
            string: "Close",
            font: .systemFont(ofSize: 17, weight: .semibold),
            textColor: UIColor(red: 163 / 255, green: 128 / 255, blue: 219 / 255, alpha: 1),
            paragraphAlignment: .center)
    }

    func updateLayout(transition: ContainedViewLayoutTransition) -> CGSize {
        let size = CGSize(width: 304, height: 50)

        transition.updateFrame(
            node: topNode,
            frame: CGRect(origin: .zero, size: size))

        transition.updateFrame(
            node: titleTextNode,
            frame: CGRect(origin: .zero, size: size))

        return size
    }

    func animateIn() {
        layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3) { [weak self] _ in
            self?.startProgressAnimation()
        }

        layer.animateFrame(
            from: CGRect(
                origin: CGPoint(x: frame.maxX, y: frame.minY),
                size: CGSize(width: 0, height: frame.height)),
            to: frame,
            duration: 0.3)
    }

    @objc private func didTap() {
        action()
    }

    private func startProgressAnimation() {
        topNode.layer.animateFrame(
            from: topNode.frame,
            to: CGRect(
                x: topNode.frame.maxX,
                y: topNode.frame.minY,
                width: 0,
                height: topNode.frame.height),
            duration: 5
        ) { [weak self] _ in
            self?.action()
        }

        titleTextNode.layer.animateFrame(
            from: titleTextNode.frame,
            to: CGRect(
                x: -titleTextNode.frame.width,
                y: topNode.frame.minY,
                width: titleTextNode.frame.width,
                height: titleTextNode.frame.height),
            duration: 5)
    }
}


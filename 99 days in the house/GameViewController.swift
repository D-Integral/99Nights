//
//  GameViewController.swift
//  99 days in the house
//
//  Created by Dmytro Skorokhod on 29.06.2026.
//

import UIKit
import SceneKit

/// SCNView that opts out of the UIKit focus engine.
///
/// On iPad (and any setup with a keyboard/pointer), the focus engine treats
/// SpriteKit overlay nodes as focus environments. When SpriteKit removes such a
/// node during the SceneKit render pass (our floating texts / banners end with
/// `SKAction.removeFromParent()`), it schedules a focus update in an invalid
/// context and crashes with EXC_BAD_ACCESS in `_focusEnvironmentWillDisappear`.
/// Making the hosting view non-focusable keeps the focus engine out of our
/// SpriteKit overlay entirely and avoids the crash.
final class GameSCNView: SCNView {
    override var canBecomeFocused: Bool { false }
}

class GameViewController: UIViewController {

    private var scnView: GameSCNView!
    private var world: GameWorld?

    // The single touch currently driving the movement joystick (if any).
    private weak var joystickTouch: UITouch?

    override func viewDidLoad() {
        super.viewDidLoad()

        scnView = GameSCNView(frame: view.bounds)
        scnView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scnView.backgroundColor = .black
        scnView.antialiasingMode = .multisampling2X
        scnView.isPlaying = true
        scnView.rendersContinuously = true
        scnView.isMultipleTouchEnabled = true
        view.addSubview(scnView)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard world == nil else { return }

        let game = GameWorld(viewSize: scnView.bounds.size)
        scnView.scene = game.scene
        scnView.overlaySKScene = game.hud
        world = game
    }

    // MARK: - Focus engine opt-out
    override func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool { false }

    // MARK: - Touch handling (joystick + taps)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let world = world else { return }
        for touch in touches {
            let point = touch.location(in: scnView)
            if joystickTouch == nil && world.joystickContains(viewPoint: point) {
                joystickTouch = touch
                world.joystickBegin(viewPoint: point)
            } else {
                world.handleTap(at: point, in: scnView)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let world = world else { return }
        for touch in touches where touch == joystickTouch {
            world.joystickMove(viewPoint: touch.location(in: scnView))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        endJoystickIfNeeded(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        endJoystickIfNeeded(touches)
    }

    private func endJoystickIfNeeded(_ touches: Set<UITouch>) {
        for touch in touches where touch == joystickTouch {
            joystickTouch = nil
            world?.joystickEnd()
        }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .allButUpsideDown
        } else {
            return .all
        }
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }
}

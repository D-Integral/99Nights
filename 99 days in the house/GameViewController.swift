//
//  GameViewController.swift
//  99 days in the house
//
//  Created by Dmytro Skorokhod on 29.06.2026.
//

import UIKit
import SceneKit

class GameViewController: UIViewController {

    private var scnView: SCNView!
    private var world: GameWorld?

    // The single touch currently driving the movement joystick (if any).
    private weak var joystickTouch: UITouch?

    override func viewDidLoad() {
        super.viewDidLoad()

        scnView = SCNView(frame: view.bounds)
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

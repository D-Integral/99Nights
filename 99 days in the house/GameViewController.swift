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

    override func viewDidLoad() {
        super.viewDidLoad()

        scnView = SCNView(frame: view.bounds)
        scnView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scnView.backgroundColor = .black
        scnView.antialiasingMode = .multisampling2X
        scnView.isPlaying = true              // keep the render loop running
        scnView.rendersContinuously = true
        view.addSubview(scnView)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard world == nil else { return }

        let game = GameWorld(viewSize: scnView.bounds.size)
        scnView.scene = game.scene
        scnView.overlaySKScene = game.hud
        world = game

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        scnView.addGestureRecognizer(tap)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: scnView)
        world?.handleTap(at: point, in: scnView)
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

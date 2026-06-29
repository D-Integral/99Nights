//
//  GameScene.swift
//  99 days in the house
//
//  Created by Dmytro Skorokhod on 29.06.2026.
//
//  3D game (SceneKit). Survive 99 days.
//  - DAY: hunt outside. Tap bunnies (food) and wolves (more food). Wolves that
//    reach the house bite you.
//  - NIGHT: the Red God walks toward your house. Tap it to repel it before it
//    breaks in. Each night you eat 1 food or starve.
//
//  Everything is built from SceneKit primitives, so no 3D model assets are
//  needed. A SpriteKit scene is used as an overlay for the HUD / menus.
//

import SceneKit
import SpriteKit
import UIKit

enum GamePhase {
    case title
    case day
    case night
    case gameOver
    case win
}

final class GameWorld: NSObject {

    // MARK: - Tunables
    private let maxDays = 99
    private let maxHealth = 5
    private let dayDuration: TimeInterval = 18
    private let nightDuration: TimeInterval = 14
    private let redGodMaxHP = 6

    private let houseZ: Float = 12
    private let frontZ: Float = 8.5     // where things reach the house
    private let spawnZ: Float = -18

    // MARK: - Public scene objects
    let scene = SCNScene()
    let hud: SKScene

    // MARK: - State
    private(set) var phase: GamePhase = .title
    private var day = 1
    private var health = 5
    private var food = 3

    private var phaseTimeRemaining: TimeInterval = 0
    private var lastTick = Date()
    private var timer: Timer?

    // MARK: - 3D nodes
    private let cameraNode = SCNNode()
    private let sunLight = SCNLight()
    private let ambientLight = SCNLight()
    private var groundMaterial: SCNMaterial?
    private var houseNode: SCNNode?
    private weak var redGod: SCNNode?
    private var redGodHP = 0

    // MARK: - HUD nodes
    private let hudDay = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let hudStats = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let hudPhase = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let hudTimer = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let overlay = SKNode()
    private let overlayTitle = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private let overlaySub = SKLabelNode(fontNamed: "AvenirNext-Medium")
    private var damageFlash: SKShapeNode?
    private var viewSize: CGSize

    // MARK: - Init
    init(viewSize: CGSize) {
        self.viewSize = viewSize
        self.hud = SKScene(size: viewSize)
        super.init()

        buildWorld()
        buildHUD()
        showTitle()
        startTimer()
    }

    deinit { timer?.invalidate() }

    // MARK: - World construction
    private func buildWorld() {
        // Camera looking out over the field toward the spawn line.
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 60
        cameraNode.camera?.zFar = 200
        cameraNode.position = SCNVector3(0, 15, 30)
        let focus = SCNNode()
        focus.position = SCNVector3(0, 1, 0)
        scene.rootNode.addChildNode(focus)
        let look = SCNLookAtConstraint(target: focus)
        look.isGimbalLockEnabled = true
        cameraNode.constraints = [look]
        scene.rootNode.addChildNode(cameraNode)

        // Lights.
        sunLight.type = .directional
        sunLight.color = UIColor.white
        sunLight.intensity = 1000
        let sunNode = SCNNode()
        sunNode.light = sunLight
        sunNode.position = SCNVector3(10, 20, 10)
        sunNode.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 5, 0)
        scene.rootNode.addChildNode(sunNode)

        ambientLight.type = .ambient
        ambientLight.color = UIColor(white: 0.6, alpha: 1)
        ambientLight.intensity = 600
        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)

        // Ground.
        let ground = SCNPlane(width: 80, height: 80)
        let gMat = SCNMaterial()
        gMat.diffuse.contents = UIColor(red: 0.30, green: 0.55, blue: 0.25, alpha: 1)
        ground.materials = [gMat]
        groundMaterial = gMat
        let groundNode = SCNNode(geometry: ground)
        groundNode.eulerAngles.x = -Float.pi / 2
        scene.rootNode.addChildNode(groundNode)

        scene.background.contents = UIColor(red: 0.53, green: 0.81, blue: 0.92, alpha: 1)

        buildHouse()
    }

    private func buildHouse() {
        let house = SCNNode()

        let body = SCNBox(width: 6, height: 4, length: 5, chamferRadius: 0.2)
        body.firstMaterial?.diffuse.contents = UIColor(red: 0.62, green: 0.45, blue: 0.32, alpha: 1)
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, 2, 0)
        house.addChildNode(bodyNode)

        let roof = SCNPyramid(width: 7, height: 3, length: 6)
        roof.firstMaterial?.diffuse.contents = UIColor(red: 0.45, green: 0.18, blue: 0.15, alpha: 1)
        let roofNode = SCNNode(geometry: roof)
        roofNode.position = SCNVector3(0, 4, 0)
        house.addChildNode(roofNode)

        let door = SCNBox(width: 1.4, height: 2.2, length: 0.2, chamferRadius: 0)
        door.firstMaterial?.diffuse.contents = UIColor(red: 0.30, green: 0.20, blue: 0.12, alpha: 1)
        let doorNode = SCNNode(geometry: door)
        doorNode.position = SCNVector3(0, 1.1, -2.55)   // facing the field
        house.addChildNode(doorNode)

        house.position = SCNVector3(0, 0, houseZ)
        scene.rootNode.addChildNode(house)
        houseNode = house
    }

    // MARK: - Animal / enemy builders
    private func makeBunny() -> SCNNode {
        let group = SCNNode()
        group.name = "bunny"
        let white = UIColor(white: 0.95, alpha: 1)

        let body = SCNSphere(radius: 0.55)
        body.firstMaterial?.diffuse.contents = white
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, 0.55, 0)
        bodyNode.scale = SCNVector3(1, 0.9, 1.3)
        group.addChildNode(bodyNode)

        let head = SCNSphere(radius: 0.35)
        head.firstMaterial?.diffuse.contents = white
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, 0.75, 0.6)
        group.addChildNode(headNode)

        for dx in [Float(-0.13), 0.13] {
            let ear = SCNCapsule(capRadius: 0.07, height: 0.55)
            ear.firstMaterial?.diffuse.contents = white
            let earNode = SCNNode(geometry: ear)
            earNode.position = SCNVector3(dx, 1.15, 0.55)
            group.addChildNode(earNode)
        }
        return group
    }

    private func makeWolf() -> SCNNode {
        let group = SCNNode()
        group.name = "wolf"
        let grey = UIColor(red: 0.42, green: 0.43, blue: 0.47, alpha: 1)

        let body = SCNBox(width: 0.8, height: 0.7, length: 1.6, chamferRadius: 0.15)
        body.firstMaterial?.diffuse.contents = grey
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, 0.7, 0)
        group.addChildNode(bodyNode)

        let head = SCNBox(width: 0.55, height: 0.55, length: 0.6, chamferRadius: 0.1)
        head.firstMaterial?.diffuse.contents = grey
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, 0.85, 0.95)
        group.addChildNode(headNode)

        for dx in [Float(-0.18), 0.18] {
            let ear = SCNPyramid(width: 0.18, height: 0.25, length: 0.18)
            ear.firstMaterial?.diffuse.contents = grey
            let earNode = SCNNode(geometry: ear)
            earNode.position = SCNVector3(dx, 1.2, 0.95)
            group.addChildNode(earNode)
        }

        for dx in [Float(-0.25), 0.25] {
            let eye = SCNSphere(radius: 0.07)
            eye.firstMaterial?.diffuse.contents = UIColor.yellow
            eye.firstMaterial?.emission.contents = UIColor.yellow
            let eyeNode = SCNNode(geometry: eye)
            eyeNode.position = SCNVector3(dx, 0.95, 1.25)
            group.addChildNode(eyeNode)
        }

        for (dx, dz) in [(Float(-0.3), Float(0.5)), (0.3, 0.5), (-0.3, -0.5), (0.3, -0.5)] {
            let leg = SCNBox(width: 0.18, height: 0.5, length: 0.18, chamferRadius: 0)
            leg.firstMaterial?.diffuse.contents = grey
            let legNode = SCNNode(geometry: leg)
            legNode.position = SCNVector3(dx, 0.25, dz)
            group.addChildNode(legNode)
        }
        return group
    }

    private func makeRedGod() -> SCNNode {
        let group = SCNNode()
        group.name = "redgod"
        let red = UIColor(red: 0.85, green: 0.10, blue: 0.10, alpha: 1)

        let body = SCNBox(width: 1.8, height: 2.6, length: 1.2, chamferRadius: 0.2)
        let bMat = SCNMaterial()
        bMat.diffuse.contents = red
        bMat.emission.contents = UIColor(red: 0.4, green: 0, blue: 0, alpha: 1)
        body.materials = [bMat]
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, 1.8, 0)
        group.addChildNode(bodyNode)

        let head = SCNSphere(radius: 0.9)
        let hMat = SCNMaterial()
        hMat.diffuse.contents = red
        hMat.emission.contents = UIColor(red: 0.5, green: 0, blue: 0, alpha: 1)
        head.materials = [hMat]
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, 3.6, 0)
        group.addChildNode(headNode)

        for dx in [Float(-0.35), 0.35] {
            let eye = SCNSphere(radius: 0.18)
            let eMat = SCNMaterial()
            eMat.diffuse.contents = UIColor.yellow
            eMat.emission.contents = UIColor.yellow
            eye.materials = [eMat]
            let eyeNode = SCNNode(geometry: eye)
            eyeNode.position = SCNVector3(dx, 3.75, 0.8)
            group.addChildNode(eyeNode)
        }

        for dx in [Float(-0.55), 0.55] {
            let horn = SCNPyramid(width: 0.3, height: 0.8, length: 0.3)
            let hornMat = SCNMaterial()
            hornMat.diffuse.contents = UIColor(red: 0.3, green: 0, blue: 0, alpha: 1)
            horn.materials = [hornMat]
            let hornNode = SCNNode(geometry: horn)
            hornNode.position = SCNVector3(dx, 4.4, 0)
            group.addChildNode(hornNode)
        }

        for dx in [Float(-1.2), 1.2] {
            let arm = SCNBox(width: 0.4, height: 1.8, length: 0.4, chamferRadius: 0.1)
            arm.materials = [bMat]
            let armNode = SCNNode(geometry: arm)
            armNode.position = SCNVector3(dx, 2.0, 0)
            group.addChildNode(armNode)
        }
        return group
    }

    // MARK: - HUD
    private func buildHUD() {
        hud.scaleMode = .resizeFill
        hud.anchorPoint = CGPoint(x: 0, y: 0)
        hud.backgroundColor = .clear
        hud.isUserInteractionEnabled = false

        let top = viewSize.height - 30

        configureLabel(hudDay, size: 22, align: .left,
                       at: CGPoint(x: 16, y: top - 24))
        configureLabel(hudStats, size: 22, align: .right,
                       at: CGPoint(x: viewSize.width - 16, y: top - 24))
        configureLabel(hudPhase, size: 17, align: .left,
                       at: CGPoint(x: 16, y: top - 50))
        configureLabel(hudTimer, size: 17, align: .right,
                       at: CGPoint(x: viewSize.width - 16, y: top - 50))

        let flash = SKShapeNode(rect: CGRect(origin: .zero, size: viewSize))
        flash.fillColor = .red
        flash.strokeColor = .clear
        flash.alpha = 0
        flash.zPosition = 90
        hud.addChild(flash)
        damageFlash = flash

        overlay.zPosition = 200
        let dim = SKShapeNode(rect: CGRect(origin: .zero, size: viewSize))
        dim.fillColor = SKColor(white: 0, alpha: 0.65)
        dim.strokeColor = .clear
        overlay.addChild(dim)

        overlayTitle.fontSize = 40
        overlayTitle.fontColor = .white
        overlayTitle.horizontalAlignmentMode = .center
        overlayTitle.numberOfLines = 0
        overlayTitle.preferredMaxLayoutWidth = viewSize.width - 60
        overlayTitle.position = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2 + 30)
        overlay.addChild(overlayTitle)

        overlaySub.fontSize = 20
        overlaySub.fontColor = SKColor(white: 0.85, alpha: 1)
        overlaySub.horizontalAlignmentMode = .center
        overlaySub.numberOfLines = 0
        overlaySub.preferredMaxLayoutWidth = viewSize.width - 60
        overlaySub.position = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2 - 70)
        overlay.addChild(overlaySub)

        hud.addChild(overlay)
        updateHUD()
    }

    private func configureLabel(_ label: SKLabelNode, size: CGFloat,
                                align: SKLabelHorizontalAlignmentMode, at pos: CGPoint) {
        label.fontSize = size
        label.fontColor = .white
        label.horizontalAlignmentMode = align
        label.position = pos
        label.zPosition = 100
        hud.addChild(label)
    }

    private func updateHUD() {
        hudDay.text = "Day \(day)/\(maxDays)"
        let hearts = String(repeating: "❤️", count: max(0, health))
            + String(repeating: "🖤", count: max(0, maxHealth - health))
        hudStats.text = "\(hearts)  🍖\(food)"
        switch phase {
        case .day:
            hudPhase.text = "☀️ DAY — Hunt for food"
            hudTimer.text = String(format: "⏱ %.0fs", max(0, phaseTimeRemaining))
        case .night:
            hudPhase.text = "🌙 NIGHT — The Red God comes"
            hudTimer.text = String(format: "⏱ %.0fs", max(0, phaseTimeRemaining))
        default:
            hudPhase.text = ""
            hudTimer.text = ""
        }
    }

    // MARK: - Screens
    private func showTitle() {
        phase = .title
        overlay.isHidden = false
        overlayTitle.text = "99 DAYS\nIN THE HOUSE"
        overlaySub.text = "☀️ Tap bunnies & wolves by day for food.\n🌙 Survive the Red God by night.\n\nTap to begin."
        updateHUD()
    }

    private func startGame() {
        day = 1
        health = maxHealth
        food = 3
        overlay.isHidden = true
        startDay()
    }

    private func restartGame() {
        removeAllAnimals()
        redGod?.removeFromParentNode(); redGod = nil
        startGame()
    }

    // MARK: - Day phase
    private func startDay() {
        phase = .day
        phaseTimeRemaining = dayDuration
        applyDayLighting()
        flashBanner("☀️ Day \(day)", color: .white)
        updateHUD()
        scheduleSpawn()
    }

    private func applyDayLighting() {
        sunLight.color = UIColor.white
        sunLight.intensity = 1000
        ambientLight.color = UIColor(white: 0.6, alpha: 1)
        ambientLight.intensity = 600
        scene.background.contents = UIColor(red: 0.53, green: 0.81, blue: 0.92, alpha: 1)
        groundMaterial?.diffuse.contents = UIColor(red: 0.30, green: 0.55, blue: 0.25, alpha: 1)
    }

    private func scheduleSpawn() {
        guard phase == .day else { return }
        let wait = SCNAction.wait(duration: Double.random(in: 0.6...1.4))
        let run = SCNAction.run { [weak self] _ in
            self?.spawnAnimal()
            self?.scheduleSpawn()
        }
        scene.rootNode.runAction(SCNAction.sequence([wait, run]), forKey: "daySpawn")
    }

    private func spawnAnimal() {
        guard phase == .day else { return }
        let isWolf = Int.random(in: 0...2) == 0
        let node = isWolf ? makeWolf() : makeBunny()
        let x = Float.random(in: -11...11)
        node.position = SCNVector3(x, 0, spawnZ)
        scene.rootNode.addChildNode(node)

        let speed: TimeInterval = isWolf ? Double.random(in: 4.0...5.5)
                                         : Double.random(in: 3.0...4.5)
        let move = SCNAction.move(to: SCNVector3(x, 0, frontZ), duration: speed)
        move.timingMode = .linear

        if isWolf {
            let bite = SCNAction.run { [weak self] _ in self?.changeHealth(-1) }
            node.runAction(SCNAction.sequence([move, bite, .removeFromParentNode()]))
        } else {
            node.runAction(SCNAction.sequence([move, .removeFromParentNode()]))
        }
    }

    private func removeAllAnimals() {
        for n in scene.rootNode.childNodes where n.name == "bunny" || n.name == "wolf" || n.name == "dead" {
            n.removeFromParentNode()
        }
    }

    private func killAnimal(_ node: SCNNode) {
        let isWolf = node.name == "wolf"
        node.removeAllActions()
        node.name = "dead"
        food += isWolf ? 2 : 1
        floatText(isWolf ? "+2🍖" : "+1🍖", color: .green)
        let pop = SCNAction.sequence([
            SCNAction.group([
                SCNAction.scale(to: 1.6, duration: 0.12),
                SCNAction.fadeOut(duration: 0.12)
            ]),
            SCNAction.removeFromParentNode()
        ])
        node.runAction(pop)
        updateHUD()
    }

    private func endDay() {
        scene.rootNode.removeAction(forKey: "daySpawn")
        removeAllAnimals()
        startNight()
    }

    // MARK: - Night phase
    private func startNight() {
        phase = .night
        phaseTimeRemaining = nightDuration
        applyNightLighting()

        if food > 0 {
            food -= 1
            flashBanner("🌙 Night \(day) — you eat to survive", color: .white)
        } else {
            changeHealth(-1)
            flashBanner("🌙 Night \(day) — STARVING!", color: .red)
        }
        updateHUD()
        guard phase == .night else { return }
        spawnRedGod()
    }

    private func applyNightLighting() {
        sunLight.color = UIColor(red: 0.7, green: 0.2, blue: 0.2, alpha: 1)
        sunLight.intensity = 350
        ambientLight.color = UIColor(red: 0.2, green: 0.1, blue: 0.2, alpha: 1)
        ambientLight.intensity = 200
        scene.background.contents = UIColor(red: 0.08, green: 0.02, blue: 0.06, alpha: 1)
        groundMaterial?.diffuse.contents = UIColor(red: 0.12, green: 0.10, blue: 0.10, alpha: 1)
    }

    private func spawnRedGod() {
        guard phase == .night else { return }
        let god = makeRedGod()
        let x = Float.random(in: -8...8)
        god.position = SCNVector3(x, 0, spawnZ)
        scene.rootNode.addChildNode(god)
        redGod = god
        redGodHP = redGodMaxHP

        let pulse = SCNAction.repeatForever(SCNAction.sequence([
            SCNAction.scale(to: 1.1, duration: 0.5),
            SCNAction.scale(to: 1.0, duration: 0.5)
        ]))
        god.runAction(pulse, forKey: "pulse")

        descendRedGod()
    }

    private func descendRedGod() {
        guard let god = redGod else { return }
        let from = god.position
        let target = SCNVector3(0, 0, frontZ)
        let dx = target.x - from.x
        let dz = target.z - from.z
        let dist = max(1, sqrt(dx * dx + dz * dz))
        let speed: Float = 2.6   // units per second
        let duration = TimeInterval(dist / speed)

        let move = SCNAction.move(to: target, duration: duration)
        move.timingMode = .linear
        let strike = SCNAction.run { [weak self] _ in self?.redGodReachesHouse() }
        god.runAction(SCNAction.sequence([move, strike]), forKey: "descend")
    }

    private func hitRedGod(_ god: SCNNode) {
        redGodHP -= 1
        floatText("-1", color: .orange)
        god.runAction(SCNAction.sequence([
            SCNAction.scale(to: 0.85, duration: 0.05),
            SCNAction.scale(to: 1.0, duration: 0.05)
        ]))
        if redGodHP <= 0 {
            god.removeAllActions()
            redGod = nil
            floatText("REPELLED!", color: .green)
            god.runAction(SCNAction.sequence([
                SCNAction.group([
                    SCNAction.scale(to: 1.8, duration: 0.2),
                    SCNAction.fadeOut(duration: 0.2)
                ]),
                SCNAction.removeFromParentNode()
            ]))
            scene.rootNode.runAction(SCNAction.sequence([
                SCNAction.wait(duration: 1.2),
                SCNAction.run { [weak self] _ in self?.spawnRedGod() }
            ]), forKey: "redGodRespawn")
        }
    }

    private func redGodReachesHouse() {
        guard phase == .night else { return }
        changeHealth(-1)
        floatText("BREACH!", color: .red)
        redGod?.removeFromParentNode()
        redGod = nil
        guard phase == .night else { return }
        scene.rootNode.runAction(SCNAction.sequence([
            SCNAction.wait(duration: 0.8),
            SCNAction.run { [weak self] _ in self?.spawnRedGod() }
        ]))
    }

    private func endNight() {
        scene.rootNode.removeAction(forKey: "redGodRespawn")
        redGod?.removeFromParentNode()
        redGod = nil
        if day >= maxDays {
            win()
            return
        }
        day += 1
        startDay()
    }

    // MARK: - Health / win / lose
    private func changeHealth(_ delta: Int) {
        health = min(maxHealth, health + delta)
        if delta < 0 { flashDamage() }
        updateHUD()
        if health <= 0 { gameOver() }
    }

    private func gameOver() {
        guard phase != .gameOver else { return }
        phase = .gameOver
        scene.rootNode.removeAction(forKey: "daySpawn")
        scene.rootNode.removeAction(forKey: "redGodRespawn")
        removeAllAnimals()
        redGod?.removeFromParentNode(); redGod = nil
        updateHUD()
        overlay.isHidden = false
        overlayTitle.text = "YOU DIED"
        overlaySub.text = "The house fell on day \(day).\n\nTap to try again."
    }

    private func win() {
        phase = .win
        updateHUD()
        overlay.isHidden = false
        overlayTitle.text = "YOU SURVIVED!"
        overlaySub.text = "99 days. The Red God is defeated.\n\nTap to play again."
    }

    // MARK: - HUD effects
    private func flashBanner(_ text: String, color: SKColor) {
        let banner = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        banner.text = text
        banner.fontSize = 28
        banner.fontColor = color
        banner.position = CGPoint(x: viewSize.width / 2, y: viewSize.height * 0.62)
        banner.zPosition = 150
        banner.setScale(0.6)
        hud.addChild(banner)
        banner.run(SKAction.sequence([
            SKAction.group([SKAction.scale(to: 1.0, duration: 0.25),
                            SKAction.fadeIn(withDuration: 0.2)]),
            SKAction.wait(forDuration: 0.8),
            SKAction.fadeOut(withDuration: 0.4),
            SKAction.removeFromParent()
        ]))
    }

    private func floatText(_ text: String, color: SKColor) {
        let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.text = text
        label.fontSize = 24
        label.fontColor = color
        label.position = CGPoint(x: viewSize.width / 2, y: viewSize.height * 0.4)
        label.zPosition = 120
        hud.addChild(label)
        label.run(SKAction.sequence([
            SKAction.group([SKAction.moveBy(x: 0, y: 60, duration: 0.6),
                            SKAction.fadeOut(withDuration: 0.6)]),
            SKAction.removeFromParent()
        ]))
    }

    private func flashDamage() {
        damageFlash?.removeAllActions()
        damageFlash?.alpha = 0
        damageFlash?.run(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.45, duration: 0.06),
            SKAction.fadeAlpha(to: 0, duration: 0.25)
        ]))
    }

    // MARK: - Game loop (main-thread timer)
    private func startTimer() {
        lastTick = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now

        guard phase == .day || phase == .night else { return }
        phaseTimeRemaining -= dt
        updateHUD()
        if phaseTimeRemaining <= 0 {
            if phase == .day { endDay() }
            else if phase == .night { endNight() }
        }
    }

    // MARK: - Input (called by the view controller)
    func handleTap(at point: CGPoint, in view: SCNView) {
        switch phase {
        case .title:
            startGame()
        case .gameOver, .win:
            restartGame()
        case .day:
            if let target = gameNode(from: view.hitTest(point, options: nil)),
               target.name == "bunny" || target.name == "wolf" {
                killAnimal(target)
            }
        case .night:
            if let target = gameNode(from: view.hitTest(point, options: nil)),
               target.name == "redgod" {
                hitRedGod(target)
            }
        }
    }

    private func gameNode(from hits: [SCNHitTestResult]) -> SCNNode? {
        for hit in hits {
            var node: SCNNode? = hit.node
            while let cur = node {
                if let name = cur.name,
                   name == "bunny" || name == "wolf" || name == "redgod" {
                    return cur
                }
                node = cur.parent
            }
        }
        return nil
    }
}

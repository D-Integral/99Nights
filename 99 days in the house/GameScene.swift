//
//  GameScene.swift
//  99 days in the house
//
//  Created by Dmytro Skorokhod on 29.06.2026.
//
//  3D game (SceneKit). Survive 99 days.
//
//  CONTROLS
//  - Left joystick: run around the field.
//  - Tap a tree (stand close): chop wood 🪵.
//  - Tap the campfire (stand close): feed wood to evolve it 🔥.
//  - Tap the crafting table (stand close): open the crafting menu.
//  - Tap bunnies / wolves by day for food 🍖.
//  - Tap the Red God / demons by night to drive them back.
//
//  DAY (2:00): roam, hunt, chop wood, craft. WOLVES that reach the house bite.
//  NIGHT (1:30): the Red God comes. On RAID nights little demons swarm the house.
//  A bigger campfire burns nearby enemies. Each night you eat 1 food or starve.
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

struct DifficultyConfig {
    let name: String
    let blurb: String
    let maxHealth: Int
    let startFood: Int
    let startWood: Int
    let attackPower: Int
    let redGodHP: Int
    let demonHP: Int
    let enemySpeedMultiplier: Float
    let wolfDamage: Int
    let campfireDamage: Int
    let dayDuration: TimeInterval
    let nightDuration: TimeInterval
    let animalSpawn: ClosedRange<Double>
    let demonSpawn: ClosedRange<Double>
    let redGodRespawnDelay: TimeInterval
}

enum Difficulty: Int, CaseIterable {
    case easy, medium, difficult, insane, king

    var config: DifficultyConfig {
        switch self {
        case .easy:
            return DifficultyConfig(
                name: "Easy", blurb: "relaxed, lots of food",
                maxHealth: 7, startFood: 6, startWood: 10, attackPower: 2,
                redGodHP: 4, demonHP: 1, enemySpeedMultiplier: 0.75,
                wolfDamage: 1, campfireDamage: 2,
                dayDuration: 130, nightDuration: 70,
                animalSpawn: 0.9...1.8, demonSpawn: 4.5...7.0,
                redGodRespawnDelay: 3.0)
        case .medium:
            return DifficultyConfig(
                name: "Medium", blurb: "a fair fight",
                maxHealth: 5, startFood: 3, startWood: 4, attackPower: 1,
                redGodHP: 6, demonHP: 2, enemySpeedMultiplier: 1.0,
                wolfDamage: 1, campfireDamage: 1,
                dayDuration: 120, nightDuration: 90,
                animalSpawn: 1.2...2.4, demonSpawn: 3.0...5.0,
                redGodRespawnDelay: 1.8)
        case .difficult:
            return DifficultyConfig(
                name: "Difficult", blurb: "tough enemies",
                maxHealth: 5, startFood: 2, startWood: 2, attackPower: 1,
                redGodHP: 8, demonHP: 3, enemySpeedMultiplier: 1.2,
                wolfDamage: 1, campfireDamage: 1,
                dayDuration: 110, nightDuration: 95,
                animalSpawn: 1.6...3.0, demonSpawn: 2.2...3.8,
                redGodRespawnDelay: 1.3)
        case .insane:
            return DifficultyConfig(
                name: "Insane", blurb: "brutal",
                maxHealth: 4, startFood: 1, startWood: 0, attackPower: 1,
                redGodHP: 10, demonHP: 3, enemySpeedMultiplier: 1.4,
                wolfDamage: 1, campfireDamage: 1,
                dayDuration: 100, nightDuration: 100,
                animalSpawn: 2.0...3.6, demonSpawn: 1.6...2.8,
                redGodRespawnDelay: 1.0)
        case .king:
            return DifficultyConfig(
                name: "King", blurb: "nearly impossible",
                maxHealth: 3, startFood: 1, startWood: 0, attackPower: 1,
                redGodHP: 12, demonHP: 4, enemySpeedMultiplier: 1.65,
                wolfDamage: 2, campfireDamage: 1,
                dayDuration: 95, nightDuration: 110,
                animalSpawn: 2.5...4.2, demonSpawn: 1.1...2.2,
                redGodRespawnDelay: 0.8)
        }
    }
}

final class GameWorld: NSObject {

    // MARK: - Tunables
    private let maxDays = 99
    private var config = Difficulty.medium.config
    private var maxHealth = 5
    private var dayDuration: TimeInterval = 120     // 2:00
    private var nightDuration: TimeInterval = 90    // 1:30
    private var redGodMaxHP = 6
    private var demonMaxHP = 2

    // Nights where little demons raid the house.
    private let raidNights: Set<Int> = [3, 11, 24, 46, 50, 55, 61, 77, 89, 99]

    private let houseZ: Float = 12
    private let frontZ: Float = 8.5     // where enemies reach the house
    private let spawnZ: Float = -18

    // Field bounds the player can run within.
    private let minX: Float = -13, maxX: Float = 13
    private let minZ: Float = -15, maxZ: Float = 10

    private let interactRange: Float = 4.0
    private let playerSpeed: Float = 8.5

    // MARK: - Public scene objects
    let scene = SCNScene()
    let hud: SKScene

    // MARK: - State
    private(set) var phase: GamePhase = .title
    private var day = 1
    private var health = 5
    private var food = 3
    private var wood = 0
    private var attackPower = 1
    private var campfireLevel = 1
    private let maxCampfireLevel = 6

    private var phaseTimeRemaining: TimeInterval = 0
    private var lastTick = Date()
    private var timer: Timer?
    private var campfireAoeAccumulator: TimeInterval = 0

    // MARK: - 3D nodes
    private let cameraNode = SCNNode()
    private let sunLight = SCNLight()
    private let ambientLight = SCNLight()
    private var groundMaterial: SCNMaterial?
    private var houseNode: SCNNode?
    private let playerNode = SCNNode()
    private var campfireNode: SCNNode?
    private var flameNode: SCNNode?
    private var campLight: SCNLight?
    private var craftTableNode: SCNNode?

    private var enemyHP: [SCNNode: Int] = [:]
    private var treeChops: [SCNNode: Int] = [:]

    // MARK: - Input state
    private var moveVec = CGVector(dx: 0, dy: 0)
    private let joystickCenter = CGPoint(x: 95, y: 95)   // HUD coords (origin bottom-left)
    private let joystickRadius: CGFloat = 60
    private let joystickActivation: CGFloat = 100
    private var craftingMenuOpen = false

    // MARK: - HUD nodes
    private let hudDay = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let hudRes = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let hudStats = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let hudPhase = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let hudTimer = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let overlay = SKNode()
    private let overlayTitle = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private let overlaySub = SKLabelNode(fontNamed: "AvenirNext-Medium")
    private var damageFlash: SKShapeNode?
    private let joystickBase = SKShapeNode(circleOfRadius: 60)
    private let joystickKnob = SKShapeNode(circleOfRadius: 28)
    private let craftMenu = SKNode()
    private let craftSpearLabel = SKLabelNode(fontNamed: "AvenirNext-Medium")
    private let craftReinforceLabel = SKLabelNode(fontNamed: "AvenirNext-Medium")
    private let difficultyButtons = SKNode()
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
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 62
        cameraNode.camera?.zFar = 200
        cameraNode.position = SCNVector3(0, 20, 33)
        let focus = SCNNode()
        focus.position = SCNVector3(0, 1, -1)
        scene.rootNode.addChildNode(focus)
        let look = SCNLookAtConstraint(target: focus)
        look.isGimbalLockEnabled = true
        cameraNode.constraints = [look]
        scene.rootNode.addChildNode(cameraNode)

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

        let ground = SCNPlane(width: 90, height: 90)
        let gMat = SCNMaterial()
        gMat.diffuse.contents = UIColor(red: 0.30, green: 0.55, blue: 0.25, alpha: 1)
        ground.materials = [gMat]
        groundMaterial = gMat
        let groundNode = SCNNode(geometry: ground)
        groundNode.eulerAngles.x = -Float.pi / 2
        scene.rootNode.addChildNode(groundNode)

        scene.background.contents = UIColor(red: 0.53, green: 0.81, blue: 0.92, alpha: 1)

        buildHouse()
        buildCampfire()
        buildCraftTable()
        buildTrees()
        buildPlayer()
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
        doorNode.position = SCNVector3(0, 1.1, -2.55)
        house.addChildNode(doorNode)

        house.position = SCNVector3(0, 0, houseZ)
        scene.rootNode.addChildNode(house)
        houseNode = house
    }

    private func buildCampfire() {
        let fire = SCNNode()
        fire.name = "campfire"

        for i in 0..<8 {
            let angle = Float(i) / 8 * 2 * .pi
            let stone = SCNSphere(radius: 0.22)
            stone.firstMaterial?.diffuse.contents = UIColor(white: 0.5, alpha: 1)
            let s = SCNNode(geometry: stone)
            s.position = SCNVector3(cos(angle) * 0.9, 0.1, sin(angle) * 0.9)
            fire.addChildNode(s)
        }
        for (dx, rot) in [(Float(-0.2), Float(0.4)), (0.25, -0.5)] {
            let log = SCNBox(width: 1.2, height: 0.18, length: 0.18, chamferRadius: 0.05)
            log.firstMaterial?.diffuse.contents = UIColor(red: 0.4, green: 0.26, blue: 0.14, alpha: 1)
            let l = SCNNode(geometry: log)
            l.position = SCNVector3(dx, 0.18, 0)
            l.eulerAngles.y = rot
            fire.addChildNode(l)
        }

        let flameGeo = SCNCone(topRadius: 0, bottomRadius: 0.55, height: 1.3)
        let fMat = SCNMaterial()
        fMat.diffuse.contents = UIColor.orange
        fMat.emission.contents = UIColor.orange
        flameGeo.materials = [fMat]
        let flame = SCNNode(geometry: flameGeo)
        flame.position = SCNVector3(0, 0.7, 0)
        flame.runAction(.repeatForever(.sequence([
            .scale(to: 1.15, duration: 0.25),
            .scale(to: 0.9, duration: 0.25)
        ])))
        fire.addChildNode(flame)
        flameNode = flame

        let light = SCNLight()
        light.type = .omni
        light.color = UIColor.orange
        light.intensity = 300
        light.attenuationEndDistance = 14
        let lightNode = SCNNode()
        lightNode.light = light
        lightNode.position = SCNVector3(0, 2, 0)
        fire.addChildNode(lightNode)
        campLight = light

        fire.position = SCNVector3(4.5, 0, 6)
        scene.rootNode.addChildNode(fire)
        campfireNode = fire
        updateCampfireVisual()
    }

    private func buildCraftTable() {
        let table = SCNNode()
        table.name = "crafttable"
        let top = SCNBox(width: 2.0, height: 0.25, length: 1.3, chamferRadius: 0.05)
        top.firstMaterial?.diffuse.contents = UIColor(red: 0.5, green: 0.35, blue: 0.2, alpha: 1)
        let topNode = SCNNode(geometry: top)
        topNode.position = SCNVector3(0, 1.0, 0)
        table.addChildNode(topNode)
        for (dx, dz) in [(Float(-0.8), Float(0.5)), (0.8, 0.5), (-0.8, -0.5), (0.8, -0.5)] {
            let leg = SCNBox(width: 0.18, height: 1.0, length: 0.18, chamferRadius: 0)
            leg.firstMaterial?.diffuse.contents = UIColor(red: 0.4, green: 0.27, blue: 0.15, alpha: 1)
            let legNode = SCNNode(geometry: leg)
            legNode.position = SCNVector3(dx, 0.5, dz)
            table.addChildNode(legNode)
        }
        // A little anvil-ish block on top so it reads as a workbench.
        let tool = SCNBox(width: 0.5, height: 0.4, length: 0.4, chamferRadius: 0.05)
        tool.firstMaterial?.diffuse.contents = UIColor(white: 0.35, alpha: 1)
        let toolNode = SCNNode(geometry: tool)
        toolNode.position = SCNVector3(0.4, 1.35, 0)
        table.addChildNode(toolNode)

        table.position = SCNVector3(-4.5, 0, 6)
        scene.rootNode.addChildNode(table)
        craftTableNode = table
    }

    private func buildTrees() {
        let positions: [(Float, Float)] = [
            (-11, -2), (-8, -9), (-3, -12), (3, -11), (9, -8),
            (12, -1), (10, 4), (-12, 5), (-6, 1), (6, 2)
        ]
        for (x, z) in positions {
            let tree = makeTree()
            tree.position = SCNVector3(x, 0, z)
            scene.rootNode.addChildNode(tree)
            treeChops[tree] = 4
        }
    }

    private func makeTree() -> SCNNode {
        let tree = SCNNode()
        tree.name = "tree"
        let trunk = SCNCylinder(radius: 0.35, height: 2.2)
        trunk.firstMaterial?.diffuse.contents = UIColor(red: 0.42, green: 0.28, blue: 0.16, alpha: 1)
        let trunkNode = SCNNode(geometry: trunk)
        trunkNode.position = SCNVector3(0, 1.1, 0)
        tree.addChildNode(trunkNode)
        for (y, r) in [(Float(2.4), Float(1.4)), (3.3, 1.1), (4.0, 0.75)] {
            let leaves = SCNCone(topRadius: 0, bottomRadius: CGFloat(r), height: 1.4)
            leaves.firstMaterial?.diffuse.contents = UIColor(red: 0.16, green: 0.45, blue: 0.20, alpha: 1)
            let lNode = SCNNode(geometry: leaves)
            lNode.position = SCNVector3(0, y, 0)
            tree.addChildNode(lNode)
        }
        return tree
    }

    private func buildPlayer() {
        let skin = UIColor(red: 0.95, green: 0.78, blue: 0.6, alpha: 1)
        let shirt = UIColor(red: 0.15, green: 0.5, blue: 0.75, alpha: 1)
        let pants = UIColor(red: 0.2, green: 0.22, blue: 0.28, alpha: 1)

        let body = SCNBox(width: 0.7, height: 0.9, length: 0.4, chamferRadius: 0.1)
        body.firstMaterial?.diffuse.contents = shirt
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, 1.15, 0)
        playerNode.addChildNode(bodyNode)

        let head = SCNSphere(radius: 0.32)
        head.firstMaterial?.diffuse.contents = skin
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, 1.95, 0)
        playerNode.addChildNode(headNode)

        for dx in [Float(-0.18), 0.18] {
            let leg = SCNBox(width: 0.22, height: 0.8, length: 0.25, chamferRadius: 0.05)
            leg.firstMaterial?.diffuse.contents = pants
            let legNode = SCNNode(geometry: leg)
            legNode.position = SCNVector3(dx, 0.4, 0)
            playerNode.addChildNode(legNode)
        }
        for dx in [Float(-0.5), 0.5] {
            let arm = SCNBox(width: 0.18, height: 0.75, length: 0.22, chamferRadius: 0.05)
            arm.firstMaterial?.diffuse.contents = shirt
            let armNode = SCNNode(geometry: arm)
            armNode.position = SCNVector3(dx, 1.15, 0)
            playerNode.addChildNode(armNode)
        }
        // Tiny eyes so the front is clear (model faces -z).
        for dx in [Float(-0.12), 0.12] {
            let eye = SCNSphere(radius: 0.05)
            eye.firstMaterial?.diffuse.contents = UIColor.black
            let eyeNode = SCNNode(geometry: eye)
            eyeNode.position = SCNVector3(dx, 1.98, -0.28)
            playerNode.addChildNode(eyeNode)
        }

        playerNode.position = SCNVector3(0, 0, 4)
        scene.rootNode.addChildNode(playerNode)
    }

    // MARK: - Enemy builders
    private func makeRedGod() -> SCNNode {
        let group = SCNNode()
        group.name = "redgod"
        let red = UIColor(red: 0.85, green: 0.10, blue: 0.10, alpha: 1)
        let bMat = SCNMaterial()
        bMat.diffuse.contents = red
        bMat.emission.contents = UIColor(red: 0.4, green: 0, blue: 0, alpha: 1)

        let body = SCNBox(width: 1.8, height: 2.6, length: 1.2, chamferRadius: 0.2)
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

    private func makeDemon() -> SCNNode {
        let group = SCNNode()
        group.name = "demon"
        let maroon = UIColor(red: 0.55, green: 0.08, blue: 0.12, alpha: 1)
        let mat = SCNMaterial()
        mat.diffuse.contents = maroon
        mat.emission.contents = UIColor(red: 0.25, green: 0, blue: 0, alpha: 1)

        let body = SCNBox(width: 0.6, height: 0.9, length: 0.45, chamferRadius: 0.1)
        body.materials = [mat]
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, 0.85, 0)
        group.addChildNode(bodyNode)

        let head = SCNSphere(radius: 0.35)
        head.materials = [mat]
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, 1.5, 0)
        group.addChildNode(headNode)

        for dx in [Float(-0.13), 0.13] {
            let eye = SCNSphere(radius: 0.07)
            let eMat = SCNMaterial()
            eMat.diffuse.contents = UIColor.orange
            eMat.emission.contents = UIColor.orange
            eye.materials = [eMat]
            let eyeNode = SCNNode(geometry: eye)
            eyeNode.position = SCNVector3(dx, 1.55, 0.3)
            group.addChildNode(eyeNode)
        }
        for dx in [Float(-0.18), 0.18] {
            let horn = SCNPyramid(width: 0.12, height: 0.3, length: 0.12)
            horn.materials = [mat]
            let hornNode = SCNNode(geometry: horn)
            hornNode.position = SCNVector3(dx, 1.8, 0)
            group.addChildNode(hornNode)
        }
        for dx in [Float(-0.18), 0.18] {
            let leg = SCNBox(width: 0.18, height: 0.5, length: 0.2, chamferRadius: 0.04)
            leg.materials = [mat]
            let legNode = SCNNode(geometry: leg)
            legNode.position = SCNVector3(dx, 0.25, 0)
            group.addChildNode(legNode)
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
        configureLabel(hudDay, size: 20, align: .left, at: CGPoint(x: 16, y: top - 22))
        configureLabel(hudRes, size: 17, align: .left, at: CGPoint(x: 16, y: top - 46))
        configureLabel(hudPhase, size: 16, align: .left, at: CGPoint(x: 16, y: top - 68))
        configureLabel(hudStats, size: 20, align: .right, at: CGPoint(x: viewSize.width - 16, y: top - 22))
        configureLabel(hudTimer, size: 17, align: .right, at: CGPoint(x: viewSize.width - 16, y: top - 46))

        let flash = SKShapeNode(rect: CGRect(origin: .zero, size: viewSize))
        flash.fillColor = .red
        flash.strokeColor = .clear
        flash.alpha = 0
        flash.zPosition = 90
        hud.addChild(flash)
        damageFlash = flash

        buildJoystick()
        buildCraftMenu()
        buildMenuOverlay()
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

    private func buildJoystick() {
        joystickBase.fillColor = SKColor(white: 1, alpha: 0.12)
        joystickBase.strokeColor = SKColor(white: 1, alpha: 0.35)
        joystickBase.lineWidth = 2
        joystickBase.position = joystickCenter
        joystickBase.zPosition = 95
        hud.addChild(joystickBase)

        joystickKnob.fillColor = SKColor(white: 1, alpha: 0.4)
        joystickKnob.strokeColor = SKColor(white: 1, alpha: 0.7)
        joystickKnob.position = joystickCenter
        joystickKnob.zPosition = 96
        hud.addChild(joystickKnob)

        setJoystickVisible(false)
    }

    private func setJoystickVisible(_ visible: Bool) {
        let a: CGFloat = visible ? 1 : 0
        joystickBase.alpha = a
        joystickKnob.alpha = a
    }

    private func buildCraftMenu() {
        craftMenu.zPosition = 210
        craftMenu.isHidden = true

        let dim = SKShapeNode(rect: CGRect(origin: .zero, size: viewSize))
        dim.fillColor = SKColor(white: 0, alpha: 0.55)
        dim.strokeColor = .clear
        craftMenu.addChild(dim)

        let title = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        title.text = "CRAFTING TABLE"
        title.fontSize = 28
        title.fontColor = .white
        title.position = CGPoint(x: viewSize.width / 2, y: viewSize.height * 0.66)
        craftMenu.addChild(title)

        let spearBtn = makeButton(name: "craft_spear",
                                  at: CGPoint(x: viewSize.width / 2, y: viewSize.height * 0.52),
                                  label: craftSpearLabel)
        let reinforceBtn = makeButton(name: "craft_reinforce",
                                      at: CGPoint(x: viewSize.width / 2, y: viewSize.height * 0.40),
                                      label: craftReinforceLabel)
        craftMenu.addChild(spearBtn)
        craftMenu.addChild(reinforceBtn)

        let close = makeButton(name: "craft_close",
                               at: CGPoint(x: viewSize.width / 2, y: viewSize.height * 0.26),
                               label: nil)
        if let lbl = close.childNode(withName: "label") as? SKLabelNode { lbl.text = "Close" }
        craftMenu.addChild(close)

        hud.addChild(craftMenu)
    }

    private func makeButton(name: String, at pos: CGPoint, label: SKLabelNode?) -> SKNode {
        let btn = SKShapeNode(rectOf: CGSize(width: viewSize.width * 0.7, height: 54), cornerRadius: 12)
        btn.name = name
        btn.fillColor = SKColor(red: 0.2, green: 0.22, blue: 0.3, alpha: 0.95)
        btn.strokeColor = SKColor(white: 1, alpha: 0.5)
        btn.position = pos
        let text = label ?? SKLabelNode(fontNamed: "AvenirNext-Medium")
        text.name = "label"
        text.fontSize = 19
        text.fontColor = .white
        text.verticalAlignmentMode = .center
        text.horizontalAlignmentMode = .center
        text.position = .zero
        btn.addChild(text)
        return btn
    }

    private func buildMenuOverlay() {
        overlay.zPosition = 200
        let dim = SKShapeNode(rect: CGRect(origin: .zero, size: viewSize))
        dim.fillColor = SKColor(white: 0, alpha: 0.65)
        dim.strokeColor = .clear
        overlay.addChild(dim)

        overlayTitle.fontSize = 38
        overlayTitle.fontColor = .white
        overlayTitle.horizontalAlignmentMode = .center
        overlayTitle.numberOfLines = 0
        overlayTitle.preferredMaxLayoutWidth = viewSize.width - 60
        overlayTitle.position = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2 + 40)
        overlay.addChild(overlayTitle)

        overlaySub.fontSize = 18
        overlaySub.fontColor = SKColor(white: 0.85, alpha: 1)
        overlaySub.horizontalAlignmentMode = .center
        overlaySub.numberOfLines = 0
        overlaySub.preferredMaxLayoutWidth = viewSize.width - 60
        overlaySub.position = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2 - 80)
        overlay.addChild(overlaySub)

        buildDifficultyButtons()
        overlay.addChild(difficultyButtons)

        hud.addChild(overlay)
    }

    private func buildDifficultyButtons() {
        let cases = Difficulty.allCases
        let topY = viewSize.height * 0.60
        let step = viewSize.height * 0.095
        for (i, diff) in cases.enumerated() {
            let c = diff.config
            let y = topY - CGFloat(i) * step
            let btn = makeButton(name: "diff_\(diff.rawValue)",
                                 at: CGPoint(x: viewSize.width / 2, y: y), label: nil)
            if let lbl = btn.childNode(withName: "label") as? SKLabelNode {
                lbl.text = "\(c.name) — \(c.blurb)"
            }
            difficultyButtons.addChild(btn)
        }
    }

    private func updateHUD() {
        hudDay.text = "Day \(day)/\(maxDays)"
        hudRes.text = "🪵\(wood)  🔥\(campfireLevel)  🗡\(attackPower)"
        let hearts = String(repeating: "❤️", count: max(0, health))
            + String(repeating: "🖤", count: max(0, maxHealth - health))
        hudStats.text = "\(hearts)  🍖\(food)"
        switch phase {
        case .day:
            hudPhase.text = "☀️ DAY — Hunt, chop wood, craft"
            hudTimer.text = timeString(phaseTimeRemaining)
        case .night:
            hudPhase.text = isRaidNight(day) ? "🌙 RAID NIGHT — Demons!" : "🌙 NIGHT — The Red God"
            hudTimer.text = timeString(phaseTimeRemaining)
        default:
            hudPhase.text = ""
            hudTimer.text = ""
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded()))
        return String(format: "⏱ %d:%02d", s / 60, s % 60)
    }

    private func updateCraftLabels() {
        craftSpearLabel.text = "🗡 Sharper Spear (10🪵) — atk \(attackPower)→\(min(4, attackPower + 1))"
        craftReinforceLabel.text = "🛡 Reinforce House (8🪵) — heal + max ❤️"
    }

    // MARK: - Screens
    private func showTitle() {
        phase = .title
        overlay.isHidden = false
        difficultyButtons.isHidden = false
        setJoystickVisible(false)
        overlayTitle.text = "99 DAYS IN THE HOUSE"
        overlayTitle.fontSize = 28
        overlayTitle.position = CGPoint(x: viewSize.width / 2, y: viewSize.height * 0.86)
        overlaySub.text = "Joystick to run · chop 🪵 · evolve 🔥 · craft 🛠\nHunt 🍖 by day, fight by night.\n\nChoose your difficulty:"
        overlaySub.position = CGPoint(x: viewSize.width / 2, y: viewSize.height * 0.72)
        updateHUD()
    }

    private func startGame(_ difficulty: Difficulty) {
        config = difficulty.config
        maxHealth = config.maxHealth
        dayDuration = config.dayDuration
        nightDuration = config.nightDuration
        redGodMaxHP = config.redGodHP
        demonMaxHP = config.demonHP

        day = 1
        health = maxHealth
        food = config.startFood
        wood = config.startWood
        attackPower = config.attackPower
        campfireLevel = 1
        updateCampfireVisual()

        clearEnemies()
        removeAllAnimals()
        regrowAllTrees()
        closeCraftMenu()
        playerNode.position = SCNVector3(0, 0, 4)

        overlay.isHidden = true
        difficultyButtons.isHidden = true
        setJoystickVisible(true)
        startDay()
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
        updateCampfireVisual()
    }

    private func scheduleSpawn() {
        guard phase == .day else { return }
        let wait = SCNAction.wait(duration: Double.random(in: config.animalSpawn))
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
        let x = Float.random(in: minX...maxX)
        node.position = SCNVector3(x, 0, spawnZ)
        scene.rootNode.addChildNode(node)

        let speed: TimeInterval = isWolf ? Double.random(in: 5.0...7.0)
                                         : Double.random(in: 4.0...6.0)
        let move = SCNAction.move(to: SCNVector3(x, 0, frontZ), duration: speed)
        move.timingMode = .linear
        if isWolf {
            let dmg = config.wolfDamage
            let bite = SCNAction.run { [weak self] _ in self?.changeHealth(-dmg) }
            node.runAction(SCNAction.sequence([move, bite, .removeFromParentNode()]))
        } else {
            node.runAction(SCNAction.sequence([move, .removeFromParentNode()]))
        }
    }

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
        node.runAction(SCNAction.sequence([
            SCNAction.group([SCNAction.scale(to: 1.6, duration: 0.12),
                             SCNAction.fadeOut(duration: 0.12)]),
            SCNAction.removeFromParentNode()
        ]))
        updateHUD()
    }

    private func endDay() {
        scene.rootNode.removeAction(forKey: "daySpawn")
        removeAllAnimals()
        startNight()
    }

    // MARK: - Night phase
    private func isRaidNight(_ d: Int) -> Bool { raidNights.contains(d) }

    private func startNight() {
        phase = .night
        phaseTimeRemaining = nightDuration
        campfireAoeAccumulator = 0
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
        if isRaidNight(day) {
            flashBanner("⚠️ RAID! Demons are coming!", color: .orange)
            scheduleDemonSpawn()
        }
    }

    private func applyNightLighting() {
        sunLight.color = UIColor(red: 0.7, green: 0.2, blue: 0.2, alpha: 1)
        sunLight.intensity = 300
        ambientLight.color = UIColor(red: 0.2, green: 0.1, blue: 0.2, alpha: 1)
        ambientLight.intensity = 180
        scene.background.contents = UIColor(red: 0.08, green: 0.02, blue: 0.06, alpha: 1)
        groundMaterial?.diffuse.contents = UIColor(red: 0.12, green: 0.10, blue: 0.10, alpha: 1)
        updateCampfireVisual()
    }

    // MARK: - Enemies
    private func spawnRedGod() {
        guard phase == .night else { return }
        let god = makeRedGod()
        let x = Float.random(in: -8...8)
        god.position = SCNVector3(x, 0, spawnZ)
        scene.rootNode.addChildNode(god)
        enemyHP[god] = redGodMaxHP
        god.runAction(.repeatForever(.sequence([
            .scale(to: 1.1, duration: 0.5),
            .scale(to: 1.0, duration: 0.5)
        ])), forKey: "pulse")
        marchEnemy(god, speed: 2.6 * config.enemySpeedMultiplier)
    }

    private func scheduleDemonSpawn() {
        guard phase == .night, isRaidNight(day) else { return }
        let wait = SCNAction.wait(duration: Double.random(in: config.demonSpawn))
        let run = SCNAction.run { [weak self] _ in
            self?.spawnDemon()
            self?.scheduleDemonSpawn()
        }
        scene.rootNode.runAction(SCNAction.sequence([wait, run]), forKey: "demonSpawn")
    }

    private func spawnDemon() {
        guard phase == .night else { return }
        let demon = makeDemon()
        let x = Float.random(in: minX...maxX)
        demon.position = SCNVector3(x, 0, spawnZ)
        scene.rootNode.addChildNode(demon)
        enemyHP[demon] = demonMaxHP
        marchEnemy(demon, speed: Float.random(in: 3.2...4.2) * config.enemySpeedMultiplier)
    }

    private func marchEnemy(_ node: SCNNode, speed: Float) {
        let from = node.position
        let target = SCNVector3(from.x * 0.3, 0, frontZ)
        let dx = target.x - from.x
        let dz = target.z - from.z
        let dist = max(1, sqrt(dx * dx + dz * dz))
        let move = SCNAction.move(to: target, duration: TimeInterval(dist / speed))
        move.timingMode = .linear
        let strike = SCNAction.run { [weak self] n in self?.enemyReachesHouse(n) }
        node.runAction(SCNAction.sequence([move, strike]), forKey: "march")
    }

    private func hitEnemy(_ node: SCNNode) {
        guard let hp = enemyHP[node] else { return }
        let newHP = hp - attackPower
        enemyHP[node] = newHP
        node.runAction(SCNAction.sequence([
            SCNAction.scale(to: 0.85, duration: 0.05),
            SCNAction.scale(to: 1.0, duration: 0.05)
        ]))
        if newHP <= 0 { killEnemy(node, byPlayer: true) }
    }

    private func killEnemy(_ node: SCNNode, byPlayer: Bool) {
        guard enemyHP[node] != nil else { return }
        enemyHP[node] = nil
        let isRedGod = node.name == "redgod"
        node.removeAllActions()
        node.name = "dead"

        if isRedGod {
            floatText("REPELLED!", color: .green)
            if phase == .night {
                scene.rootNode.runAction(SCNAction.sequence([
                    SCNAction.wait(duration: config.redGodRespawnDelay),
                    SCNAction.run { [weak self] _ in self?.spawnRedGod() }
                ]))
            }
        } else if byPlayer {
            food += 1
            floatText("+1🍖", color: .green)
            updateHUD()
        }
        node.runAction(SCNAction.sequence([
            SCNAction.group([SCNAction.scale(to: 1.6, duration: 0.18),
                             SCNAction.fadeOut(duration: 0.18)]),
            SCNAction.removeFromParentNode()
        ]))
    }

    private func enemyReachesHouse(_ node: SCNNode) {
        guard enemyHP[node] != nil, phase == .night else { return }
        let isRedGod = node.name == "redgod"
        enemyHP[node] = nil
        node.removeAllActions()
        changeHealth(-1)
        floatText("BREACH!", color: .red)
        node.removeFromParentNode()
        if isRedGod && phase == .night {
            scene.rootNode.runAction(SCNAction.sequence([
                SCNAction.wait(duration: config.redGodRespawnDelay),
                SCNAction.run { [weak self] _ in self?.spawnRedGod() }
            ]))
        }
    }

    private func clearEnemies() {
        scene.rootNode.removeAction(forKey: "demonSpawn")
        for (node, _) in enemyHP { node.removeFromParentNode() }
        enemyHP.removeAll()
        for n in scene.rootNode.childNodes where n.name == "dead" { n.removeFromParentNode() }
    }

    private func campfireTick(_ dt: TimeInterval) {
        guard phase == .night, let fire = campfireNode else { return }
        campfireAoeAccumulator += dt
        guard campfireAoeAccumulator >= 1.0 else { return }
        campfireAoeAccumulator = 0
        let radius = 3.0 + Float(campfireLevel) * 1.3
        for (node, _) in enemyHP {
            if xzDistance(node.position, fire.position) <= radius {
                hitEnemyFromFire(node)
            }
        }
    }

    private func hitEnemyFromFire(_ node: SCNNode) {
        guard let hp = enemyHP[node] else { return }
        let newHP = hp - config.campfireDamage
        enemyHP[node] = newHP
        if newHP <= 0 { killEnemy(node, byPlayer: false) }
    }

    private func endNight() {
        clearEnemies()
        if day >= maxDays {
            win()
            return
        }
        day += 1
        startDay()
    }

    // MARK: - Trees / wood
    private func chopTree(_ tree: SCNNode) {
        guard let remaining = treeChops[tree], remaining > 0 else { return }
        wood += 1
        let left = remaining - 1
        treeChops[tree] = left
        floatText("+1🪵", color: SKColor(red: 0.8, green: 0.6, blue: 0.3, alpha: 1))
        tree.runAction(SCNAction.sequence([
            SCNAction.rotateBy(x: 0, y: 0, z: 0.12, duration: 0.05),
            SCNAction.rotateBy(x: 0, y: 0, z: -0.12, duration: 0.05)
        ]))
        updateHUD()
        if left <= 0 { fellTree(tree) }
    }

    private func fellTree(_ tree: SCNNode) {
        tree.runAction(SCNAction.sequence([
            SCNAction.group([SCNAction.scale(to: 0.05, duration: 0.3),
                             SCNAction.rotateBy(x: 0.6, y: 0, z: 0, duration: 0.3)]),
            SCNAction.run { n in
                n.isHidden = true
            },
            SCNAction.wait(duration: 18.0),
            SCNAction.run { [weak self] n in
                n.isHidden = false
                n.scale = SCNVector3(1, 1, 1)
                n.eulerAngles = SCNVector3Zero
                self?.treeChops[n] = 4
            }
        ]))
    }

    private func regrowAllTrees() {
        for (tree, _) in treeChops {
            tree.removeAllActions()
            tree.isHidden = false
            tree.scale = SCNVector3(1, 1, 1)
            tree.eulerAngles = SCNVector3Zero
            treeChops[tree] = 4
        }
    }

    // MARK: - Campfire
    private func updateCampfireVisual() {
        let s = 0.7 + Float(campfireLevel) * 0.28
        flameNode?.scale = SCNVector3(s, s, s)
        let base: CGFloat = phase == .night ? 350 : 120
        campLight?.intensity = base + CGFloat(campfireLevel) * 220
        campLight?.attenuationEndDistance = CGFloat(8 + campfireLevel * 3)
    }

    private func feedCampfire() {
        if campfireLevel >= maxCampfireLevel {
            floatText("Fire maxed!", color: .orange)
            return
        }
        let cost = campfireLevel * 4
        if wood >= cost {
            wood -= cost
            campfireLevel += 1
            updateCampfireVisual()
            floatText("🔥 Fire Lv \(campfireLevel)!", color: .orange)
            if let fire = campfireNode {
                fire.runAction(SCNAction.sequence([
                    SCNAction.scale(to: 1.2, duration: 0.12),
                    SCNAction.scale(to: 1.0, duration: 0.12)
                ]))
            }
            updateHUD()
        } else {
            floatText("Need \(cost)🪵 (lvl up)", color: .red)
        }
    }

    // MARK: - Crafting
    private func openCraftMenu() {
        craftingMenuOpen = true
        updateCraftLabels()
        craftMenu.isHidden = false
        moveVec = .zero
        resetJoystickKnob()
    }

    private func closeCraftMenu() {
        craftingMenuOpen = false
        craftMenu.isHidden = true
    }

    private func craftSpear() {
        let cost = 10
        if attackPower >= 4 { floatText("Spear maxed!", color: .orange); return }
        if wood >= cost {
            wood -= cost
            attackPower += 1
            floatText("🗡 Attack \(attackPower)!", color: .green)
            updateHUD(); updateCraftLabels()
        } else {
            floatText("Need \(cost)🪵", color: .red)
        }
    }

    private func craftReinforce() {
        let cost = 8
        if wood >= cost {
            wood -= cost
            maxHealth = min(8, maxHealth + 1)
            health = maxHealth
            floatText("🛡 House reinforced!", color: .green)
            updateHUD(); updateCraftLabels()
        } else {
            floatText("Need \(cost)🪵", color: .red)
        }
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
        removeAllAnimals()
        clearEnemies()
        closeCraftMenu()
        setJoystickVisible(false)
        updateHUD()
        overlay.isHidden = false
        difficultyButtons.isHidden = true
        overlayTitle.fontSize = 38
        overlayTitle.position = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2 + 40)
        overlayTitle.text = "YOU DIED"
        overlaySub.position = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2 - 80)
        overlaySub.text = "The house fell on day \(day) (\(config.name)).\n\nTap to choose difficulty."
    }

    private func win() {
        phase = .win
        setJoystickVisible(false)
        updateHUD()
        overlay.isHidden = false
        difficultyButtons.isHidden = true
        overlayTitle.fontSize = 38
        overlayTitle.position = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2 + 40)
        overlayTitle.text = "YOU SURVIVED!"
        overlaySub.position = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2 - 80)
        overlaySub.text = "99 days on \(config.name)! The Red God is defeated.\n\nTap to play again."
    }

    // MARK: - HUD effects
    private func flashBanner(_ text: String, color: SKColor) {
        let banner = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        banner.text = text
        banner.fontSize = 26
        banner.fontColor = color
        banner.position = CGPoint(x: viewSize.width / 2, y: viewSize.height * 0.64)
        banner.zPosition = 150
        banner.setScale(0.6)
        hud.addChild(banner)
        banner.run(SKAction.sequence([
            SKAction.group([SKAction.scale(to: 1.0, duration: 0.25),
                            SKAction.fadeIn(withDuration: 0.2)]),
            SKAction.wait(forDuration: 1.0),
            SKAction.fadeOut(withDuration: 0.4),
            SKAction.removeFromParent()
        ]))
    }

    private func floatText(_ text: String, color: SKColor) {
        let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.text = text
        label.fontSize = 22
        label.fontColor = color
        label.position = CGPoint(x: viewSize.width / 2, y: viewSize.height * 0.42)
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

    // MARK: - Game loop
    private func startTimer() {
        lastTick = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now

        guard phase == .day || phase == .night else { return }

        updatePlayer(dt)
        campfireTick(dt)

        phaseTimeRemaining -= dt
        updateHUD()
        if phaseTimeRemaining <= 0 {
            if phase == .day { endDay() }
            else if phase == .night { endNight() }
        }
    }

    private func updatePlayer(_ dt: TimeInterval) {
        guard !craftingMenuOpen else { return }
        let vx = Float(moveVec.dx) * playerSpeed
        let vz = -Float(moveVec.dy) * playerSpeed
        if abs(vx) < 0.001 && abs(vz) < 0.001 { return }
        var p = playerNode.position
        p.x = min(maxX, max(minX, p.x + vx * Float(dt)))
        p.z = min(maxZ, max(minZ, p.z + vz * Float(dt)))
        playerNode.position = p
        playerNode.eulerAngles.y = atan2(vx, vz)
    }

    // MARK: - Input
    func joystickContains(viewPoint: CGPoint) -> Bool {
        let p = hud.convertPoint(fromView: viewPoint)
        return hypot(p.x - joystickCenter.x, p.y - joystickCenter.y) <= joystickActivation
    }

    func joystickBegin(viewPoint: CGPoint) { joystickMove(viewPoint: viewPoint) }

    func joystickMove(viewPoint: CGPoint) {
        let p = hud.convertPoint(fromView: viewPoint)
        var dx = p.x - joystickCenter.x
        var dy = p.y - joystickCenter.y
        let dist = hypot(dx, dy)
        if dist > joystickRadius {
            dx = dx / dist * joystickRadius
            dy = dy / dist * joystickRadius
        }
        joystickKnob.position = CGPoint(x: joystickCenter.x + dx, y: joystickCenter.y + dy)
        moveVec = CGVector(dx: dx / joystickRadius, dy: dy / joystickRadius)
    }

    func joystickEnd() {
        moveVec = .zero
        resetJoystickKnob()
    }

    private func resetJoystickKnob() {
        joystickKnob.position = joystickCenter
    }

    func handleTap(at viewPoint: CGPoint, in view: SCNView) {
        switch phase {
        case .title:
            let hp = hud.convertPoint(fromView: viewPoint)
            for node in hud.nodes(at: hp) {
                if let name = node.name, name.hasPrefix("diff_"),
                   let raw = Int(name.dropFirst(5)),
                   let diff = Difficulty(rawValue: raw) {
                    startGame(diff)
                    return
                }
            }
            return
        case .gameOver, .win:
            showTitle()
            return
        case .day, .night:
            break
        }

        if craftingMenuOpen {
            let hp = hud.convertPoint(fromView: viewPoint)
            for node in hud.nodes(at: hp) {
                switch node.name {
                case "craft_spear": craftSpear(); return
                case "craft_reinforce": craftReinforce(); return
                case "craft_close": closeCraftMenu(); return
                default: break
                }
            }
            return
        }

        guard let target = gameNode(from: view.hitTest(viewPoint, options: nil)) else { return }
        switch target.name {
        case "bunny", "wolf":
            killAnimal(target)
        case "redgod", "demon":
            hitEnemy(target)
        case "tree":
            if isNearPlayer(target) { chopTree(target) }
            else { floatText("Too far from tree", color: .white) }
        case "campfire":
            if isNearPlayer(target) { feedCampfire() }
            else { floatText("Too far from fire", color: .white) }
        case "crafttable":
            if isNearPlayer(target) { openCraftMenu() }
            else { floatText("Too far from table", color: .white) }
        default:
            break
        }
    }

    private func gameNode(from hits: [SCNHitTestResult]) -> SCNNode? {
        let names: Set<String> = ["bunny", "wolf", "redgod", "demon", "tree", "campfire", "crafttable"]
        for hit in hits {
            var node: SCNNode? = hit.node
            while let cur = node {
                if let name = cur.name, names.contains(name) { return cur }
                node = cur.parent
            }
        }
        return nil
    }

    private func isNearPlayer(_ node: SCNNode) -> Bool {
        xzDistance(node.position, playerNode.position) <= interactRange
    }

    private func xzDistance(_ a: SCNVector3, _ b: SCNVector3) -> Float {
        let dx = a.x - b.x
        let dz = a.z - b.z
        return sqrt(dx * dx + dz * dz)
    }
}
